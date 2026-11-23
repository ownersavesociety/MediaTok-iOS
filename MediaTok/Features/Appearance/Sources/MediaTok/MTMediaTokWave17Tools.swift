import Foundation
import UIKit
import UniformTypeIdentifiers
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import Display
import ItemListUI
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
        return MTModalPresenter.topmostViewController()
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
        let vc = mtMakeNativeUiStudioController(context: context)
        mtPushNativeController(vc, context: context)
    }

    public static func presentFullBackupManager(context: AccountContext) {
        mtPresentNativeActionSheet(
            context: context,
            title: "Бэкап конфигурации (.mediatok)",
            buttons: [
                (title: "Экспортировать .mediatok файл", isDestructive: false, action: {
                    guard let top = topViewController() else { return }
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
                }),
                (title: "Импортировать .mediatok из Файлов", isDestructive: false, action: {
                    guard let host = topViewController() else { return }
                    let coordinator = MTBackupDocumentCoordinator(context: context) {
                        activeBackupCoordinator = nil
                    }
                    activeBackupCoordinator = coordinator
                    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data, UTType.json])
                    picker.delegate = coordinator
                    host.present(picker, animated: true)
                }),
                (title: "Импортировать из буфера обмена", isDestructive: false, action: {
                    guard let raw = UIPasteboard.general.string,
                          let data = raw.data(using: .utf8),
                          applyBackupData(data, context: context) else {
                        mtPresentNativeToast(context: context, text: "В буфере обмена нет корректного .mediatok бэкапа")
                        return
                    }
                })
            ]
        )
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

private func mtMakeNativeUiStudioController(context: AccountContext) -> ItemListController {
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revCount = 0
    let bump: () -> Void = {
        revCount += 1
        revision.set(revCount)
    }

    weak var weakController: ItemListController?
    let radiusChoices: [Int] = [6, 12, 16, 18, 22, 26]

    let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let cfg = MTMediaTokWave17Tools.loadConfig()
        var screen = MTNativeScreenModel(title: "Пузыри и Приватность")

        screen.sections.append([
            MTNativeRow(id: "ui.b.h", kind: .header("Пузыри сообщений")),
            MTNativeRow(id: "ui.radius", kind: .disclosure(title: "Радиус скругления углов", label: "\(Int(cfg.bubbleRadiusPt.rounded())) pt", icon: nil, enabled: true)),
            MTNativeRow(id: "ui.glass", kind: .toggle(title: "Полупрозрачные пузыри", value: cfg.glassBubblesEnabled, enabled: true))
        ])

        screen.tap["ui.radius"] = {
            let btns: [(title: String, isDestructive: Bool, action: () -> Void)] = radiusChoices.map { r in
                return (title: "\(r) pt", isDestructive: false, action: {
                    var next = MTMediaTokWave17Tools.loadConfig()
                    next.bubbleRadiusPt = Double(r)
                    next.panelBlurPercent = 0
                    MTMediaTokWave17Tools.saveConfig(next)
                    MTMediaTokWave17Tools.applyUiStudioAppearanceSettings(next)
                    bump()
                })
            }
            mtPresentNativeActionSheet(context: context, from: weakController, title: "Радиус скругления пузырей", buttons: btns)
        }

        screen.toggle["ui.glass"] = { isOn in
            var next = MTMediaTokWave17Tools.loadConfig()
            next.glassBubblesEnabled = isOn
            next.panelBlurPercent = 0
            MTMediaTokWave17Tools.saveConfig(next)
            MTMediaTokWave17Tools.applyUiStudioAppearanceSettings(next)
            bump()
        }

        screen.sections.append([
            MTNativeRow(id: "ui.p.h", kind: .header("Эмодзи, Чат и Телеметрия")),
            MTNativeRow(id: "ui.emoji", kind: .toggle(title: "Локальные Премиум-эмодзи", value: cfg.localPremiumEmoji, enabled: true)),
            MTNativeRow(id: "ui.service", kind: .toggle(title: "Скрывать сервисные сообщения", value: cfg.hideServiceMessages, enabled: true)),
            MTNativeRow(id: "ui.telemetry", kind: .toggle(title: "Блокировка внутренней телеметрии", value: cfg.antiTelemetryEnabled, enabled: true)),
            MTNativeRow(id: "ui.backup", kind: .action(title: "Бэкап и перенос настроек (.mediatok)", destructive: false, enabled: true))
        ])

        screen.toggle["ui.emoji"] = { isOn in
            var next = MTMediaTokWave17Tools.loadConfig()
            next.localPremiumEmoji = isOn
            MTMediaTokWave17Tools.saveConfig(next)
            bump()
        }
        screen.toggle["ui.service"] = { isOn in
            var next = MTMediaTokWave17Tools.loadConfig()
            next.hideServiceMessages = isOn
            MTMediaTokWave17Tools.saveConfig(next)
            bump()
        }
        screen.toggle["ui.telemetry"] = { isOn in
            var next = MTMediaTokWave17Tools.loadConfig()
            next.antiTelemetryEnabled = isOn
            MTMediaTokWave17Tools.saveConfig(next)
            bump()
        }
        screen.tap["ui.backup"] = {
            MTMediaTokWave17Tools.presentFullBackupManager(context: context)
        }

        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}
