import Foundation
import UIKit
import UniformTypeIdentifiers
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import Display
import ContextUI
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

// ============================================================================
// MediaTok Wave 17 — UI Glass Studio, Local Premium Emoji, Anti-Telemetry & .mediatok Backup:
//   #297/#298/#308 / .uistudio    — Bubble Radius (0-26pt), Glass Bubbles & Panel Blur (0-100%)
//   #283 / .localemoji            — Local-only Premium Emoji toggle & picker (no zero-width noise)
//   #277 / .hideservice           — Hide noisy join/leave/pin service messages toggle
//   #232 / .antitelemetry         — Anti-Telemetry & Silent Channel Views toggle
//   #334 / .backup                — Export/Import full MediaTok config into a single .mediatok file
// ============================================================================

public struct MTUiStudioConfig: Codable, Equatable {
    public var bubbleRadiusPt: Double      // 0...26
    public var glassBubblesEnabled: Bool
    public var panelBlurPercent: Int       // 0...100
    public var localPremiumEmoji: Bool     // #283 local-only
    public var hideServiceMessages: Bool   // #277
    public var antiTelemetryEnabled: Bool  // #232

    private enum CodingKeys: String, CodingKey {
        case bubbleRadiusPt
        case glassBubblesEnabled
        case panelBlurPercent
        case localPremiumEmoji
        case hideServiceMessages
        case antiTelemetryEnabled
    }

    public static let `default` = MTUiStudioConfig(
        bubbleRadiusPt: 18.0,
        glassBubblesEnabled: false,
        panelBlurPercent: 80,
        localPremiumEmoji: true,
        hideServiceMessages: false,
        antiTelemetryEnabled: true
    )
}

public enum MTMediaTokWave17Tools {
    private static let uiConfigKey = "mediatok.wave17.ui_studio.v1"
    private static let dmMuteRulesKey = "mediatok.wave13.dm_mute_rules.v1"
    private static let hideServiceLock = NSLock()
    private static var cachedHideService: Bool = false
    private static var activeBackupCoordinator: MTBackupDocumentCoordinator?

    private static var isHideServiceMessagesActive: Bool {
        hideServiceLock.lock()
        let v = cachedHideService
        hideServiceLock.unlock()
        return v
    }

    private static func setCachedHideService(_ enabled: Bool) {
        hideServiceLock.lock()
        cachedHideService = enabled
        hideServiceLock.unlock()
    }

    public static func register() {
        let initial = loadConfig()
        UserDefaults.standard.set(initial.antiTelemetryEnabled, forKey: "mediatok.anti_telemetry.enabled")
        setCachedHideService(initial.hideServiceMessages)

        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave17Tools.interceptCommands(request)
        }, order: 39)

        // #277 Wire service message hiding via MTChatScreenHooks.hidesMessage
        MTChatScreenHooks.hidesMessage.register({ message, _, _ in
            guard MTMediaTokWave17Tools.isHideServiceMessagesActive else { return false }
            for media in message.media {
                if let action = media as? TelegramMediaAction {
                    switch action.action {
                    case .addedMembers,
                         .removedMembers,
                         .photoUpdated,
                         .titleUpdated,
                         .pinnedMessageUpdated,
                         .joinedByLink,
                         .joinedByRequest,
                         .joinedChannel,
                         .peerJoined,
                         .channelMigratedFromGroup,
                         .groupMigratedToChannel,
                         .setChatTheme,
                         .setChatWallpaper,
                         .setSameChatWallpaper,
                         .boostsApplied,
                         .historyCleared,
                         .historyScreenshot,
                         .messageAutoremoveTimeoutUpdated:
                        return true
                    default:
                        return false
                    }
                }
            }
            return false
        }, order: 50)
    }

    public static func loadConfig() -> MTUiStudioConfig {
        var cfg: MTUiStudioConfig
        if let data = UserDefaults.standard.data(forKey: uiConfigKey),
           let decoded = try? JSONDecoder().decode(MTUiStudioConfig.self, from: data) {
            cfg = decoded
        } else {
            cfg = .default
        }
        cfg.localPremiumEmoji = MTMediaTokWave5Tools.isPremiumEmojiEnabled
        return cfg
    }

    public static func saveConfig(_ cfg: MTUiStudioConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: uiConfigKey)
        }
        // Mirror anti-telemetry flag to fast UserDefaults key read by TelegramCore
        UserDefaults.standard.set(cfg.antiTelemetryEnabled, forKey: "mediatok.anti_telemetry.enabled")
        // Bidirectional sync with #283 live Premium Emoji toggle
        MTMediaTokWave5Tools.isPremiumEmojiEnabled = cfg.localPremiumEmoji
        // Update fast O(1) cache for #277 service message hiding
        setCachedHideService(cfg.hideServiceMessages)
    }

    public static func applyUiStudioAppearanceSettings(_ cfg: MTUiStudioConfig) {
        let clampedRadius = min(26.0, max(0.0, cfg.bubbleRadiusPt))
        MTAppearanceSettings.bubbleEditor.set(true)
        MTAppearanceSettings.bubbleIncomingRadius.set(clampedRadius)
        MTAppearanceSettings.bubbleOutgoingRadius.set(clampedRadius)
        MTAppearanceSettings.bubbleBackgroundOpacity.set(cfg.glassBubblesEnabled ? 52.0 : 100.0)
        MTAppearanceSettings.bubbleOutlineOpacity.set(cfg.glassBubblesEnabled ? 35.0 : 0.0)

        let clampedBlur = Double(max(0, min(100, cfg.panelBlurPercent)))
        let currentEdgeStyle = MTEdgeStyle(rawValue: MTAppearanceSettings.edgeStyle.value) ?? .off
        if clampedBlur > 0.0 {
            if currentEdgeStyle == .off {
                MTAppearanceSettings.edgeStyle.set(MTEdgeStyle.blur.rawValue)
            }
            MTAppearanceSettings.edgeIntensity.set(clampedBlur)
        } else {
            MTAppearanceSettings.edgeIntensity.set(0.0)
            if currentEdgeStyle == .blur {
                MTAppearanceSettings.edgeStyle.set(MTEdgeStyle.off.rawValue)
            }
        }
        MTThemeHooks.invalidate()
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix(".") else { return false }
        let lower = raw.lowercased()

        if lower == ".uistudio" || lower == ".glass" || lower == ".bubbles" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentUiStudio(context: request.context) }
            return true
        }
        if lower == ".localemoji" {
            request.replace(ChatTextInputState())
            var cfg = loadConfig()
            cfg.localPremiumEmoji.toggle()
            saveConfig(cfg)
            MTMediaTokWave5Tools.showToast(context: request.context, text: "Локальные Премиум-эмодзи: \(cfg.localPremiumEmoji ? "ВКЛ" : "ВЫКЛ")")
            return true
        }
        if lower == ".hideservice" {
            request.replace(ChatTextInputState())
            var cfg = loadConfig()
            cfg.hideServiceMessages.toggle()
            saveConfig(cfg)
            MTMediaTokWave5Tools.showToast(context: request.context, text: "Скрытие сервисных сообщений: \(cfg.hideServiceMessages ? "ВКЛ" : "ВЫКЛ")")
            return true
        }
        if lower == ".antitelemetry" {
            request.replace(ChatTextInputState())
            var cfg = loadConfig()
            cfg.antiTelemetryEnabled.toggle()
            saveConfig(cfg)
            MTMediaTokWave5Tools.showToast(context: request.context, text: "Анти-телеметрия: \(cfg.antiTelemetryEnabled ? "ВКЛ" : "ВЫКЛ")")
            return true
        }
        if lower == ".backup" || lower == ".mediatokbackup" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentFullBackupManager(context: request.context) }
            return true
        }
        return false
    }

    public static func presentUiStudio(context: AccountContext) {
        guard let top = topViewController() else { return }
        let vc = MTUiStudioController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    public static func presentFullBackupManager(context: AccountContext) {
        guard let top = topViewController() else { return }
        let alert = UIAlertController(
            title: "Бэкап конфигурации (.mediatok)",
            message: "Экспорт или импорт всех настроек MediaTok (Профиль FX, NFT, Закладки видео, UI Studio, .mute правила, Защиты Wave 18).",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Экспортировать .mediatok файл", style: .default) { _ in
            let muteArr = Array(MTMediaTokWave13Tools.loadMuteRules().values)
            let bundle: [String: Any] = [
                "version": 2,
                "exportedAt": Int(Date().timeIntervalSince1970),
                "uiStudio": (try? JSONEncoder().encode(loadConfig())).flatMap { String(data: $0, encoding: .utf8) } ?? "{}",
                "profileFx": (try? JSONEncoder().encode(MTMediaTokWave15Tools.loadFxConfig())).flatMap { String(data: $0, encoding: .utf8) } ?? "{}",
                "customNfts": (try? JSONEncoder().encode(MTMediaTokWave15Tools.loadSavedCustomNfts())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]",
                "videoBookmarks": (try? JSONEncoder().encode(MTMediaTokWave16Tools.loadVideoBookmarks())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]",
                "dmMuteRules": (try? JSONEncoder().encode(muteArr)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]",
                "wave18Guards": (try? JSONEncoder().encode(MTMediaTokWave18Tools.loadConfig())).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted]) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("MediaTok_Backup_\(Int(Date().timeIntervalSince1970)).mediatok")
                try? data.write(to: url)
                if let str = String(data: data, encoding: .utf8) {
                    UIPasteboard.general.string = str
                }
                let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                share.completionWithItemsHandler = { _, _, _, _ in
                    try? FileManager.default.removeItem(at: url)
                }
                if let pop = share.popoverPresentationController {
                    pop.sourceView = top.view
                    pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                }
                top.present(share, animated: true)
            }
        })
        alert.addAction(UIAlertAction(title: "Импортировать .mediatok из Файлов", style: .default) { _ in
            guard let host = topViewController() else { return }
            let coordinator = MTBackupDocumentCoordinator(context: context) {
                activeBackupCoordinator = nil
            }
            activeBackupCoordinator = coordinator
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data, UTType.json])
            picker.delegate = coordinator
            host.present(picker, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Импортировать .mediatok из буфера обмена", style: .default) { _ in
            guard let raw = UIPasteboard.general.string,
                  let data = raw.data(using: .utf8) else {
                MTMediaTokWave5Tools.showToast(context: context, text: "В буфере обмена нет корректного .mediatok бэкапа")
                return
            }
            if !applyBackupData(data, context: context) {
                MTMediaTokWave5Tools.showToast(context: context, text: "В буфере обмена нет корректного .mediatok бэкапа")
            }
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        }
        top.present(alert, animated: true)
    }

    @discardableResult
    fileprivate static func applyBackupData(_ data: Data, context: AccountContext) -> Bool {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let uiStr = dict["uiStudio"] as? String, let d = uiStr.data(using: .utf8), let cfg = try? JSONDecoder().decode(MTUiStudioConfig.self, from: d) {
            saveConfig(cfg)
            applyUiStudioAppearanceSettings(cfg)
        }
        if let fxStr = dict["profileFx"] as? String, let d = fxStr.data(using: .utf8), let fx = try? JSONDecoder().decode(MTProfileFxConfig.self, from: d) {
            MTMediaTokWave15Tools.saveFxConfig(fx)
        }
        if let nftStr = dict["customNfts"] as? String, let d = nftStr.data(using: .utf8), let nfts = try? JSONDecoder().decode([MTPortalsCatalogItem].self, from: d) {
            MTMediaTokWave15Tools.replaceSavedCustomNfts(nfts)
        }
        if let bmStr = dict["videoBookmarks"] as? String, let d = bmStr.data(using: .utf8), let bms = try? JSONDecoder().decode([MTVideoBookmarkItem].self, from: d) {
            MTMediaTokWave16Tools.saveVideoBookmarks(bms)
        }
        if let muteStr = dict["dmMuteRules"] as? String, let d = muteStr.data(using: .utf8), let rules = try? JSONDecoder().decode([MTDmMuteRule].self, from: d) {
            if let encoded = try? JSONEncoder().encode(rules) {
                UserDefaults.standard.set(encoded, forKey: dmMuteRulesKey)
            }
            if !rules.isEmpty {
                MTMediaTokWave13Tools.armMuteWatcherIfNeeded(context: context)
            }
        }
        if let w18Str = dict["wave18Guards"] as? String, let d = w18Str.data(using: .utf8), let w18 = try? JSONDecoder().decode(MTWave18GuardsConfig.self, from: d) {
            MTMediaTokWave18Tools.saveConfig(w18)
        }
        MTMediaTokWave5Tools.showToast(context: context, text: "Конфигурация MediaTok успешно восстановлена!")
        return true
    }
}

private final class MTBackupDocumentCoordinator: NSObject, UIDocumentPickerDelegate {
    private let context: AccountContext
    private let onComplete: () -> Void

    init(context: AccountContext, onComplete: @escaping () -> Void) {
        self.context = context
        self.onComplete = onComplete
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        defer { self.onComplete() }
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              MTMediaTokWave17Tools.applyBackupData(data, context: self.context) else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Файл не является корректным .mediatok бэкапом")
            return
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.onComplete()
    }
}

// MARK: - #297/#298/#308 UI & Glass Studio Controller

private final class MTUiStudioController: UIViewController {
    private let context: AccountContext
    private var config: MTUiStudioConfig

    private let bubblePreview = UIView()
    private let bubbleLabel = UILabel()
    private let radiusLabel = UILabel()
    private let radiusSlider = UISlider()
    private let blurLabel = UILabel()
    private let blurSlider = UISlider()
    private let glassSwitch = UISwitch()
    private let emojiSwitch = UISwitch()
    private let serviceSwitch = UISwitch()
    private let telemetrySwitch = UISwitch()

    init(context: AccountContext) {
        self.context = context
        self.config = MTMediaTokWave17Tools.loadConfig()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "UI & Glass Студия"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(saveTapped))

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        self.bubblePreview.backgroundColor = UIColor.systemBlue
        self.bubblePreview.layer.cornerCurve = .continuous
        self.bubblePreview.translatesAutoresizingMaskIntoConstraints = false

        self.bubbleLabel.text = "Привет! Вот так выглядят твои пузыри в MediaTok."
        self.bubbleLabel.textColor = .white
        self.bubbleLabel.font = .systemFont(ofSize: 15)
        self.bubbleLabel.numberOfLines = 0
        self.bubbleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.bubblePreview.addSubview(self.bubbleLabel)

        NSLayoutConstraint.activate([
            self.bubbleLabel.topAnchor.constraint(equalTo: self.bubblePreview.topAnchor, constant: 12),
            self.bubbleLabel.bottomAnchor.constraint(equalTo: self.bubblePreview.bottomAnchor, constant: -12),
            self.bubbleLabel.leadingAnchor.constraint(equalTo: self.bubblePreview.leadingAnchor, constant: 16),
            self.bubbleLabel.trailingAnchor.constraint(equalTo: self.bubblePreview.trailingAnchor, constant: -16)
        ])

        self.radiusSlider.minimumValue = 0
        self.radiusSlider.maximumValue = 26
        self.radiusSlider.value = Float(self.config.bubbleRadiusPt)
        self.radiusSlider.addTarget(self, action: #selector(updatePreview), for: .valueChanged)

        self.blurSlider.minimumValue = 0
        self.blurSlider.maximumValue = 100
        self.blurSlider.value = Float(self.config.panelBlurPercent)
        self.blurSlider.addTarget(self, action: #selector(updatePreview), for: .valueChanged)

        self.glassSwitch.isOn = self.config.glassBubblesEnabled
        self.glassSwitch.addTarget(self, action: #selector(updatePreview), for: .valueChanged)

        self.emojiSwitch.isOn = self.config.localPremiumEmoji
        self.serviceSwitch.isOn = self.config.hideServiceMessages
        self.telemetrySwitch.isOn = self.config.antiTelemetryEnabled

        stack.addArrangedSubview(self.bubblePreview)
        stack.addArrangedSubview(self.radiusLabel)
        stack.addArrangedSubview(self.radiusSlider)
        stack.addArrangedSubview(self.blurLabel)
        stack.addArrangedSubview(self.blurSlider)
        stack.addArrangedSubview(makeRow(title: "Стеклянные пузыри сообщений (#298)", toggle: self.glassSwitch))
        stack.addArrangedSubview(makeRow(title: "Локальные Премиум-эмодзи (#283)", toggle: self.emojiSwitch))
        stack.addArrangedSubview(makeRow(title: "Скрывать сервисные сообщения (#277)", toggle: self.serviceSwitch))
        stack.addArrangedSubview(makeRow(title: "Анти-телеметрия и тихие просмотры (#232)", toggle: self.telemetrySwitch))

        self.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16)
        ])

        self.updatePreview()
    }

    private func makeRow(title: String, toggle: UISwitch) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        let lbl = UILabel()
        lbl.text = title
        lbl.font = .systemFont(ofSize: 14)
        lbl.numberOfLines = 0
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(toggle)
        return row
    }

    @objc private func updatePreview() {
        let r = CGFloat(self.radiusSlider.value.rounded())
        let blur = Int(self.blurSlider.value.rounded())
        self.radiusLabel.text = "Радиус углов пузырей (#297): \(Int(r)) pt"
        self.blurLabel.text = "Размытие краёв и панелей (#308): \(blur)%"
        self.bubblePreview.layer.cornerRadius = r
        self.bubblePreview.backgroundColor = self.glassSwitch.isOn
            ? UIColor.systemBlue.withAlphaComponent(0.55)
            : UIColor.systemBlue
    }

    @objc private func saveTapped() {
        self.config.bubbleRadiusPt = Double(self.radiusSlider.value.rounded())
        self.config.panelBlurPercent = Int(self.blurSlider.value.rounded())
        self.config.glassBubblesEnabled = self.glassSwitch.isOn
        self.config.localPremiumEmoji = self.emojiSwitch.isOn
        self.config.hideServiceMessages = self.serviceSwitch.isOn
        self.config.antiTelemetryEnabled = self.telemetrySwitch.isOn
        MTMediaTokWave17Tools.saveConfig(self.config)
        MTMediaTokWave17Tools.applyUiStudioAppearanceSettings(self.config)
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Настройки UI & Glass Студии сохранены")
        self.dismiss(animated: true)
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}
