import Foundation
import UIKit
import QuartzCore
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import Display
import ContextUI
import UniversalMediaPlayer
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

/// MediaTok Wave 7 (Roadmap Wave 1 — Foundation, Stability & UX):
/// - #493 Safe Mode (automatic crash-streak guard + manual Safe Mode reset)
/// - #416 Force Reconnect (instant Telegram MTProto network reset)
/// - #490 Spotlight Command Palette (universal searchable MediaTok launcher)
/// - #371 Synced LRC Lyrics (`lrclib.net` real-time karaoke lyrics synced to Telegram music player)
/// - #379 Confirm Before Sending Voice Message (`mediatok.voice.confirm_send.v1`)
/// - #377 Optional Fake Voice Duration (`mediatok.voice.fake_duration.v1`: 0:00, 1:00, 59:59, 99:59, custom)
/// - #491 "What's New" Screen (`b3775`) + #492 "Report Bug / Idea" Diagnostics
public enum MTMediaTokWave7Tools {
    public static let currentBuildNumber = "3801"

    private static let safeModeStreakKey = "mediatok.safemode.streak.v1"
    private static let whatsNewLastSeenKey = "mediatok.whatsnew.last_seen_build.v1"
    public static let voiceConfirmSendKey = "mediatok.voice.confirm_send.v1"
    public static let voiceFakeDurationKey = "mediatok.voice.fake_duration.v1"

    public private(set) static var safeModeActivatedOnLaunch = false
    private static var hasCheckedSafeMode = false

    public static var isVoiceConfirmEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave7Tools.voiceConfirmSendKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave7Tools.voiceConfirmSendKey) }
    }

    /// 0 = off, -1 = fake 0:00, >0 = custom duration in seconds (e.g. 5999 = 99:59).
    public static var fakeVoiceDurationSeconds: Int {
        get { return UserDefaults.standard.integer(forKey: MTMediaTokWave7Tools.voiceFakeDurationKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave7Tools.voiceFakeDurationKey) }
    }

    public static var fakeVoiceDurationLabel: String {
        let val = MTMediaTokWave7Tools.fakeVoiceDurationSeconds
        if val == 0 {
            return "Выкл"
        }
        if val < 0 {
            return "0:00"
        }
        let mins = val / 60
        let secs = val % 60
        return String(format: "%d:%02d", mins, secs)
    }

    public static var voiceSummaryLabel: String {
        let confirmPart = MTMediaTokWave7Tools.isVoiceConfirmEnabled ? "✓" : ""
        let fakePart = MTMediaTokWave7Tools.fakeVoiceDurationSeconds != 0 ? MTMediaTokWave7Tools.fakeVoiceDurationLabel : ""
        if !confirmPart.isEmpty && !fakePart.isEmpty {
            return "\(confirmPart) \(fakePart)"
        }
        if !confirmPart.isEmpty {
            return "ПОДТВ."
        }
        if !fakePart.isEmpty {
            return fakePart
        }
        return "ГС"
    }

    public static func register() {
        MTMediaTokWave7Tools.runStartupSafeModeGuard()

        // Chat inline commands: .cmd / .spot (Spotlight), .lyrics (LRC Lyrics), .reconnect (Force Reconnect), .whatsnew
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave7Tools.interceptCommands(request)
        }, order: 26)

        // Send button long-press menu: Spotlight, LRC Lyrics, Force Reconnect, Voice Settings
        MTChatScreenHooks.sendMenuItems.register({ sendContext in
            return MTMediaTokWave7Tools.sendMenuItems(sendContext)
        }, order: 78)
    }

    // MARK: - #493 Safe Mode

    private static func runStartupSafeModeGuard() {
        guard !MTMediaTokWave7Tools.hasCheckedSafeMode else { return }
        MTMediaTokWave7Tools.hasCheckedSafeMode = true

        let defaults = UserDefaults.standard
        let streak = defaults.integer(forKey: MTMediaTokWave7Tools.safeModeStreakKey) + 1
        if streak >= 3 {
            MTMediaTokWave7Tools.safeModeActivatedOnLaunch = true
            MTMediaTokWave7Tools.applySafeModeVisualReset()
            defaults.set(0, forKey: MTMediaTokWave7Tools.safeModeStreakKey)
        } else {
            defaults.set(streak, forKey: MTMediaTokWave7Tools.safeModeStreakKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
                UserDefaults.standard.set(0, forKey: MTMediaTokWave7Tools.safeModeStreakKey)
            }
        }
    }

    public static func applySafeModeVisualReset() {
        MTAppearanceSettings.fontFamily.set("system")
        MTAppearanceSettings.chatTextFont.set("")
        MTAppearanceSettings.edgeStyle.set(MTEdgeStyle.off.rawValue)
        MTAppearanceSettings.chatBackground.set(false)
        MTAppearanceSettings.profileBackground.set(false)
        MTAppearanceSettings.snow.set(false)
        MTAppearanceSettings.bubbleEditor.set(false)
    }

    public static func presentSafeModeConfirmation(context: AccountContext) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Безопасный режим (Safe Mode)",
                message: "Сбросит кастомный шрифт на системный SF Pro и отключит видео-обои чата/профиля, снег и редактор пузырей. Ваши чаты, подарки и стикеры не пострадают.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Сбросить визуал (Safe Mode)", style: .destructive, handler: { _ in
                MTMediaTokWave7Tools.applySafeModeVisualReset()
                UserDefaults.standard.set(0, forKey: MTMediaTokWave7Tools.safeModeStreakKey)
                MTMediaTokWave5Tools.showToast(context: context, text: "Safe Mode применён: шрифт и видео-обои сброшены")
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            MTMediaTokWave5Tools.presentOnRoot(alert)
        }
    }

    // MARK: - #416 Force Reconnect

    public static func forceReconnect(context: AccountContext) {
        let account = context.account
        let network = account.network
        network.dropConnectionStatus()
        network.shouldKeepConnection.set(.single(false))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak account] in
            guard let account else { return }
            let shouldBeMaster = combineLatest(account.shouldBeServiceTaskMaster.get(), account.postbox.isMasterClient())
            |> map { [weak account] shouldBeMaster, isMaster -> Bool in
                if shouldBeMaster == .always && !isMaster {
                    account?.postbox.becomeMasterClient()
                }
                return (shouldBeMaster == .now || shouldBeMaster == .always) && isMaster
            }
            |> distinctUntilChanged
            account.network.shouldKeepConnection.set(shouldBeMaster)
            account.resetStateManagement()
        }
        MTMediaTokWave5Tools.showToast(context: context, text: "Переподключение к серверам Telegram...")
    }

    // MARK: - #379 Confirm Voice Send & #377 Fake Voice Duration

    public static func presentVoiceToolsSheet(context: AccountContext) {
        DispatchQueue.main.async {
            let confirmState = MTMediaTokWave7Tools.isVoiceConfirmEnabled ? "ВКЛ" : "ВЫКЛ"
            let fakeState = MTMediaTokWave7Tools.fakeVoiceDurationLabel
            let sheet = UIAlertController(
                title: "Инструменты голосовых (ГС)",
                message: "Подтверждение отправки: \(confirmState)\nФейк-длительность ГС: \(fakeState)",
                preferredStyle: .actionSheet
            )

            let toggleTitle = MTMediaTokWave7Tools.isVoiceConfirmEnabled
                ? "Подтверждать отправку ГС: ВКЛ (выключить)"
                : "Подтверждать отправку ГС: ВЫКЛ (включить)"
            sheet.addAction(UIAlertAction(title: toggleTitle, style: .default, handler: { _ in
                MTMediaTokWave7Tools.isVoiceConfirmEnabled.toggle()
                let st = MTMediaTokWave7Tools.isVoiceConfirmEnabled ? "ВКЛ" : "ВЫКЛ"
                MTMediaTokWave5Tools.showToast(context: context, text: "Подтверждение отправки ГС: \(st)")
            }))

            sheet.addAction(UIAlertAction(title: "Фейк-длительность: Выкл (реальная)", style: .default, handler: { _ in
                MTMediaTokWave7Tools.fakeVoiceDurationSeconds = 0
                MTMediaTokWave5Tools.showToast(context: context, text: "Фейк-длительность ГС отключена")
            }))
            sheet.addAction(UIAlertAction(title: "Фейк-длительность: 0:00", style: .default, handler: { _ in
                MTMediaTokWave7Tools.fakeVoiceDurationSeconds = -1
                MTMediaTokWave5Tools.showToast(context: context, text: "Длительность ГС: 0:00")
            }))
            sheet.addAction(UIAlertAction(title: "Фейк-длительность: 1:00", style: .default, handler: { _ in
                MTMediaTokWave7Tools.fakeVoiceDurationSeconds = 60
                MTMediaTokWave5Tools.showToast(context: context, text: "Длительность ГС: 1:00")
            }))
            sheet.addAction(UIAlertAction(title: "Фейк-длительность: 59:59", style: .default, handler: { _ in
                MTMediaTokWave7Tools.fakeVoiceDurationSeconds = 3599
                MTMediaTokWave5Tools.showToast(context: context, text: "Длительность ГС: 59:59")
            }))
            sheet.addAction(UIAlertAction(title: "Фейк-длительность: 99:59", style: .default, handler: { _ in
                MTMediaTokWave7Tools.fakeVoiceDurationSeconds = 5999
                MTMediaTokWave5Tools.showToast(context: context, text: "Длительность ГС: 99:59")
            }))
            sheet.addAction(UIAlertAction(title: "Своя длительность (в секундах)...", style: .default, handler: { _ in
                MTMediaTokWave7Tools.presentCustomFakeDurationAlert(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))

            MTMediaTokWave7Tools.configurePopoverIfNeeded(sheet)
            MTMediaTokWave5Tools.presentOnRoot(sheet)
        }
    }

    private static func presentCustomFakeDurationAlert(context: AccountContext) {
        let alert = UIAlertController(
            title: "Своя длительность ГС",
            message: "Введите число секунд (например: 5999 для 99:59, 0 — выключить):",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.keyboardType = .numberPad
            tf.placeholder = "5999"
            let cur = MTMediaTokWave7Tools.fakeVoiceDurationSeconds
            if cur > 0 {
                tf.text = "\(cur)"
            }
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
            let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let seconds = Int(raw), seconds >= 0 {
                let clamped = min(seconds, 86399)
                MTMediaTokWave7Tools.fakeVoiceDurationSeconds = clamped
                MTMediaTokWave5Tools.showToast(context: context, text: "Фейк-длительность ГС: \(MTMediaTokWave7Tools.fakeVoiceDurationLabel)")
            } else {
                MTMediaTokWave5Tools.showToast(context: context, text: "Введите корректное число секунд")
            }
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTMediaTokWave5Tools.presentOnRoot(alert)
    }

    // MARK: - #491 What's New & #492 Report Bug / Idea

    public static func presentWhatsNew(context: AccountContext) {
        UserDefaults.standard.set(MTMediaTokWave7Tools.currentBuildNumber, forKey: MTMediaTokWave7Tools.whatsNewLastSeenKey)
        DispatchQueue.main.async {
            let safeBadge = MTMediaTokWave7Tools.safeModeActivatedOnLaunch
                ? "\nВнимание: в этом запуске сработал Safe Mode — проверь шрифт/обои."
                : ""
            let body = """
            MediaTok iOS • Build b\(MTMediaTokWave7Tools.currentBuildNumber) (Волны 1–18):

            • Примерочная профиля (Sandbox) — живой превью темы, рамки, эффекта, погоды и статуса до сохранения
            • Красивый градиентный QR-код профиля с бейджем MediaTok
            • Скачивание любого стикерпака в ZIP-архив (долгое нажатие на стикер)
            • Обратный поиск фото (Google Lens / Yandex / SauceNAO) из меню фото
            • Размытие лиц на фото в 1 тап через Apple Vision AI
            • Сканер документов → PDF + Подпись PDF пальцем
            • Живая погода города в профиле (Open-Meteo) + Спуфинг батареи
            • Spotlight + LRC-тексты песен + Force Reconnect + ГС + Safe Mode\(safeBadge)
            """
            let alert = UIAlertController(title: "Что нового в MediaTok b\(MTMediaTokWave7Tools.currentBuildNumber)", message: body, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Сообщить о баге / идее", style: .default, handler: { _ in
                MTMediaTokWave7Tools.presentFeedbackSheet(context: context)
            }))
            alert.addAction(UIAlertAction(title: "Отлично!", style: .cancel))
            MTMediaTokWave5Tools.presentOnRoot(alert)
        }
    }

    public static func buildDiagnosticsSummary() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) { ptr -> String in
            return ptr.withMemoryRebound(to: CChar.self, capacity: 1) { cStr in
                return String(cString: cStr)
            }
        }
        let ramGB = String(format: "%.1f GB", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0)
        let iosVer = UIDevice.current.systemVersion
        let appVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "13.1.1"
        let stickerCount = MTStickerVaultStore.shared.count
        let e2eCount = MTMediaTokE2E.activeCount
        return """
        --- MediaTok Diagnostics ---
        Build: MediaTok iOS \(appVer) (b\(MTMediaTokWave7Tools.currentBuildNumber))
        Device: \(machine) | iOS \(iosVer) | RAM: \(ramGB) | Battery: \(MTMediaTokWave8Tools.effectiveBatteryDescription)
        SafeModeOnLaunch: \(MTMediaTokWave7Tools.safeModeActivatedOnLaunch)
        VoiceConfirm: \(MTMediaTokWave7Tools.isVoiceConfirmEnabled) | FakeVoice: \(MTMediaTokWave7Tools.fakeVoiceDurationLabel)
        StickerVault: \(stickerCount) | ActiveE2E: \(e2eCount) | AdBlock: \(MTMediaTokWave6Tools.isAdBlockEnabled)
        ----------------------------
        """
    }

    public static func presentFeedbackSheet(context: AccountContext) {
        DispatchQueue.main.async {
            let diag = MTMediaTokWave7Tools.buildDiagnosticsSummary()
            UIPasteboard.general.string = diag
            let alert = UIAlertController(
                title: "Сообщить о баге / идее",
                message: "Диагностика скопирована в буфер обмена!\n\n\(diag)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Поделиться диагностикой", style: .default, handler: { _ in
                let share = UIActivityViewController(activityItems: [diag], applicationActivities: nil)
                MTMediaTokWave7Tools.configurePopoverIfNeeded(share)
                MTMediaTokWave5Tools.presentOnRoot(share)
            }))
            alert.addAction(UIAlertAction(title: "Готово", style: .cancel))
            MTMediaTokWave5Tools.presentOnRoot(alert)
        }
    }

    // MARK: - #490 Spotlight Command Palette Launcher

    public static func presentSpotlightPalette(accountContext: AccountContext, menuContext: MTMenuContext? = nil) {
        DispatchQueue.main.async {
            let vc = MTSpotlightPaletteController(accountContext: accountContext, menuContext: menuContext)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            MTMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    // MARK: - #371 Synced LRC Lyrics Launcher

    public static func presentLyricsViewer(context: AccountContext, initialQuery: String? = nil) {
        DispatchQueue.main.async {
            let vc = MTLyricsViewController(context: context, initialQuery: initialQuery)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            MTMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    // MARK: - Quick Tools Sheet (for Settings quick row)

    public static func presentWave7QuickHub(context: MTMenuContext) {
        DispatchQueue.main.async {
            let sheet = UIAlertController(
                title: "Инструменты MediaTok b\(MTMediaTokWave7Tools.currentBuildNumber)",
                message: "Сеть, голосовые (ГС), тексты песен, диагностика и Safe Mode",
                preferredStyle: .actionSheet
            )
            sheet.addAction(UIAlertAction(title: "Палитра команд (Spotlight)", style: .default, handler: { _ in
                MTMediaTokWave7Tools.presentSpotlightPalette(accountContext: context.context, menuContext: context)
            }))
            sheet.addAction(UIAlertAction(title: "Текст песни (LRC)", style: .default, handler: { _ in
                MTMediaTokWave7Tools.presentLyricsViewer(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "Переподключить сеть (Force Reconnect)", style: .default, handler: { _ in
                MTMediaTokWave7Tools.forceReconnect(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "Голосовые: Подтверждение / Фейк-длительность", style: .default, handler: { _ in
                MTMediaTokWave7Tools.presentVoiceToolsSheet(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "Что нового в b\(MTMediaTokWave7Tools.currentBuildNumber)", style: .default, handler: { _ in
                MTMediaTokWave7Tools.presentWhatsNew(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "Сообщить о баге / идее", style: .default, handler: { _ in
                MTMediaTokWave7Tools.presentFeedbackSheet(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "Безопасный режим (Safe Mode)", style: .destructive, handler: { _ in
                MTMediaTokWave7Tools.presentSafeModeConfirmation(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))

            MTMediaTokWave7Tools.configurePopoverIfNeeded(sheet)
            MTMediaTokWave5Tools.presentOnRoot(sheet)
        }
    }

    // MARK: - Inline Commands & Send Menu

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let lower = raw.lowercased()

        if lower == ".cmd" || lower == ".spot" || lower == ".spotlight" {
            request.replace(ChatTextInputState())
            MTMediaTokWave7Tools.presentSpotlightPalette(accountContext: request.context, menuContext: nil)
            return true
        }

        if lower == ".reconnect" || lower == ".reconn" {
            request.replace(ChatTextInputState())
            MTMediaTokWave7Tools.forceReconnect(context: request.context)
            return true
        }

        if lower == ".lyrics" || lower.hasPrefix(".lyrics ") || lower == ".lrc" || lower.hasPrefix(".lrc ") {
            request.replace(ChatTextInputState())
            let query: String?
            if lower.hasPrefix(".lyrics ") {
                query = String(raw.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lower.hasPrefix(".lrc ") {
                query = String(raw.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                query = nil
            }
            MTMediaTokWave7Tools.presentLyricsViewer(context: request.context, initialQuery: (query?.isEmpty ?? true) ? nil : query)
            return true
        }

        if lower == ".whatsnew" {
            request.replace(ChatTextInputState())
            MTMediaTokWave7Tools.presentWhatsNew(context: request.context)
            return true
        }

        return false
    }

    private static func sendMenuItems(_ sendContext: MTSendMenuContext) -> [ContextMenuItem] {
        var entries: [ContextMenuItem] = []
        let ctx = sendContext.context
        let dismiss = sendContext.dismiss

        entries.append(.action(ContextMenuActionItem(
            text: "Палитра команд MediaTok",
            icon: { theme in
                return UIImage(systemName: "magnifyingglass")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave7Tools.presentSpotlightPalette(accountContext: ctx, menuContext: nil)
            }
        )))

        entries.append(.action(ContextMenuActionItem(
            text: "Текст песни (LRC)",
            icon: { theme in
                return UIImage(systemName: "music.note.list")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave7Tools.presentLyricsViewer(context: ctx)
            }
        )))

        entries.append(.action(ContextMenuActionItem(
            text: "Переподключить сеть",
            icon: { theme in
                return UIImage(systemName: "arrow.triangle.2.circlepath")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave7Tools.forceReconnect(context: ctx)
            }
        )))

        entries.append(.action(ContextMenuActionItem(
            text: "ГС: Подтверждение / 99:59",
            icon: { theme in
                return UIImage(systemName: "mic.badge.plus")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave7Tools.presentVoiceToolsSheet(context: ctx)
            }
        )))

        return entries
    }

    private static func configurePopoverIfNeeded(_ vc: UIViewController) {
        if let pop = vc.popoverPresentationController {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let win = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
            pop.sourceView = win
            if let win {
                pop.sourceRect = CGRect(x: win.bounds.midX, y: win.bounds.midY, width: 1, height: 1)
            }
            pop.permittedArrowDirections = []
        }
    }
}

// MARK: - #490 Spotlight Command Palette UI

private struct MTSpotlightCommandItem {
    let symbol: String
    let tint: UIColor
    let title: String
    let subtitle: String
    let keywords: String
    let action: () -> Void
}

public final class MTSpotlightPaletteController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let accountContext: AccountContext
    private let menuContext: MTMenuContext?
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var allItems: [MTSpotlightCommandItem] = []
    private var filteredItems: [MTSpotlightCommandItem] = []
    private var badgeCache: [String: UIImage] = [:]

    public init(accountContext: AccountContext, menuContext: MTMenuContext?) {
        self.accountContext = accountContext
        self.menuContext = menuContext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [self.tableView]
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.isBeingPresented || self.navigationController?.isBeingPresented == true {
            self.searchBar.resignFirstResponder()
            self.view.endEditing(true)
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "MediaTok Spotlight"
        self.view.backgroundColor = UIColor(white: 0.08, alpha: 1.0)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Закрыть",
            style: .done,
            target: self,
            action: #selector(self.closeTapped)
        )

        self.searchBar.placeholder = "Поиск фич: fish audio, lrc, гс, сеть, safe..."
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.delegate = self
        self.searchBar.returnKeyType = .search
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.searchBar)

        self.tableView.backgroundColor = .clear
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.keyboardDismissMode = .interactive
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.searchBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 4),
            self.searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 8),
            self.searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -8),
            self.tableView.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor, constant: 4),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.buildItems()
        self.filteredItems = self.allItems
        self.tableView.reloadData()
    }

    @objc private func closeTapped() {
        self.searchBar.resignFirstResponder()
        self.dismiss(animated: true)
    }

    private func makeSpotlightBadge(symbol: String, tint: UIColor) -> UIImage {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        let cacheKey = String(format: "%@_%.3f_%.3f_%.3f", symbol, r, g, b)
        if let cached = self.badgeCache[cacheKey] {
            return cached
        }
        let size = CGSize(width: 34, height: 34)
        let renderer = UIGraphicsImageRenderer(size: size)
        let badge = renderer.image { _ in
            let fillPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
            tint.withAlphaComponent(0.20).setFill()
            fillPath.fill()

            let strokeRect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let strokePath = UIBezierPath(roundedRect: strokeRect, cornerRadius: 9)
            strokePath.lineWidth = 1.0
            tint.withAlphaComponent(0.42).setStroke()
            strokePath.stroke()

            let symConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            let rawIcon = UIImage(systemName: symbol, withConfiguration: symConfig)
                ?? UIImage(systemName: "sparkles", withConfiguration: symConfig)
            if let icon = rawIcon?.withTintColor(tint, renderingMode: .alwaysOriginal) {
                let iconOrigin = CGPoint(
                    x: (size.width - icon.size.width) * 0.5,
                    y: (size.height - icon.size.height) * 0.5
                )
                icon.draw(at: iconOrigin)
            }
        }
        let finalBadge = badge.withRenderingMode(.alwaysOriginal)
        self.badgeCache[cacheKey] = finalBadge
        return finalBadge
    }

    private func runAfterDismiss(_ block: @escaping () -> Void) {
        self.searchBar.resignFirstResponder()
        self.dismiss(animated: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                block()
            }
        }
    }

    private func buildItems() {
        let ctx = self.accountContext
        let mCtx = self.menuContext
        var items: [MTSpotlightCommandItem] = []

        items.append(MTSpotlightCommandItem(
            symbol: "waveform.badge.person.crop",
            tint: UIColor(red: 0.96, green: 0.38, blue: 0.68, alpha: 1.0),
            title: "AI Клон голоса (Fish Audio)",
            subtitle: "Клонирование голоса по образцу ГС, войслайна или аниме-персонажа",
            keywords: "fish audio клон голос аниме elevenlabs tts 506",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        mCtx.open(tab: .mediaVoice)
                    } else if let nav = ctx.sharedContext.mainWindow?.viewController as? NavigationController {
                        if let url = URL(string: "mediatok://fishaudio"),
                           MTLifecycleHooks.handleURL(url, context: ctx, navigationController: nav) {
                            return
                        }
                        nav.pushViewController(mtMakeSettingsController(context: ctx))
                        MTMediaTokWave5Tools.showToast(context: ctx, text: "Открой Медиа и звонки › Голос › AI Клон голоса (Fish Audio)")
                    }
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "eye.trianglebadge.exclamationmark.fill",
            tint: UIColor(red: 0.42, green: 0.80, blue: 0.98, alpha: 1.0),
            title: "Призрачный Сейф-Фото (Стеганография)",
            subtitle: "Спрячь или извлеки секретный текст прямо из пикселей PNG (.stego)",
            keywords: "stego стеганография секрет фото png 501",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave12Tools.presentStegoStudio(context: ctx, initialImage: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "slider.horizontal.3",
            tint: UIColor(red: 0.68, green: 0.48, blue: 1.0, alpha: 1.0),
            title: "Голос-Студия FX (Диктор / Рация / Демон)",
            subtitle: "Изменение голоса в реальном времени и рендер .ogg (.vfx)",
            keywords: "vfx voice голос демон рация диктор робот бурундук 502",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave12Tools.presentVoiceFxStudio(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "flame.fill",
            tint: UIColor(red: 1.0, green: 0.42, blue: 0.28, alpha: 1.0),
            title: "Сгорающая AES-256 записка с PIN и TTL",
            subtitle: "Одноразовый секрет с таймером 10с и самоуничтожением (.burn)",
            keywords: "burn бомба записка pin aes секрет 503",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave12Tools.presentBurnNoteComposer(context: ctx, peerId: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "film.stack.fill",
            tint: UIColor(red: 0.98, green: 0.62, blue: 0.24, alpha: 1.0),
            title: "Кино-карточка цитат (1:1 / 9:16 / 16:9)",
            subtitle: "Стеклянная карточка в стиле Apple Keynote / Ray.so в HD PNG (.cinematic)",
            keywords: "cinematic карточка цитата скриншот stories 504",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave12Tools.presentCinematicCard(context: ctx, initialText: nil, author: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "viewfinder.rectangular",
            tint: UIColor(red: 0.22, green: 0.86, blue: 0.66, alpha: 1.0),
            title: "OSINT-Рентген (EXIF / GPS / Фишинг-ссылки)",
            subtitle: "Анализ камеры/GPS в фото и проверка редиректов/спуфинга ссылок (.xray)",
            keywords: "xray osint exif gps фишинг ссылка редирект 505",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave12Tools.presentOsintXRay(context: ctx, initialUrl: nil, initialImageData: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "trash.slash.fill",
            tint: UIColor(red: 0.95, green: 0.28, blue: 0.30, alpha: 1.0),
            title: "Безопасный снос своих сообщений (.delme)",
            subtitle: "FaceID + подтверждение + выбор ЛС, групп или всех чатов (#208)",
            keywords: "delme wipe удалить снос сообщения лс группы 208",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave13Tools.presentDelMeGate(context: ctx, currentPeerId: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "externaldrive.fill.badge.checkmark",
            tint: UIColor(red: 0.25, green: 0.62, blue: 1.0, alpha: 1.0),
            title: "Фильтр тяжёлых медиа по весу (.heavy)",
            subtitle: "Сортировка от самых тяжёлых: >10 / >50 / >100 МБ (#263)",
            keywords: "heavy media фильтр вес размер файлы видео 263",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave13Tools.presentHeavyMediaScreen(context: ctx, initialPeerId: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "lock.shield.fill",
            tint: UIColor(red: 0.98, green: 0.65, blue: 0.18, alpha: 1.0),
            title: MTMediaTokWave13Tools.isReadOnlyLocked ? "Выключить режим «Только чтение» (FaceID)" : "Включить режим «Только чтение» (.readonly)",
            subtitle: "Блокирует отправку сообщений, когда даёшь телефон в чужие руки (#242)",
            keywords: "readonly lock только чтение блокировка защита 242",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave13Tools.toggleReadOnlyLock(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "person.text.rectangle.fill",
            tint: UIColor(red: 0.40, green: 0.56, blue: 1.0, alpha: 1.0),
            title: "OSINT Поиск сообщений юзера (.osintuser)",
            subtitle: "Найти все сообщения автора по общим группам и Anti-Delete (#219)",
            keywords: "osint user сообщения автор поиск группы 219",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave14Tools.presentOsintUserSearch(context: ctx, targetAuthorId: nil, initialQuery: "")
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "clock.arrow.circlepath",
            tint: UIColor(red: 0.96, green: 0.36, blue: 0.44, alpha: 1.0),
            title: "Глобальный журнал удалений и правок (.audit)",
            subtitle: "Все удалённые и изменённые сообщения с поиском (#205 / #244 / #245)",
            keywords: "deleted audit log удалённые изменённые журнал антиделит 205 244 245",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave14Tools.presentGlobalAuditLog(context: ctx, initialPeerId: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "speaker.slash.fill",
            tint: UIColor(red: 0.96, green: 0.34, blue: 0.44, alpha: 1.0),
            title: "Авто-снос входящих в ЛС (.mute / .unmute)",
            subtitle: "Управление активными .mute-правилами и быстрый сброс (#207)",
            keywords: "mute unmute мут автоснос снос входящие лс 207",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave13Tools.presentMuteManager(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "ellipsis.message.fill",
            tint: UIColor(red: 0.32, green: 0.72, blue: 1.0, alpha: 1.0),
            title: "Фейк-статус (.typing / .recvideo / .recvoice / .sticker)",
            subtitle: "Отправка реального MTProto-статуса набора, записи ГС или видео (#249)",
            keywords: "typing recvideo recvoice sticker stoptyping фейк статус печатает гс 249",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTSpotlightPaletteController.presentRecentChatPicker(context: ctx, title: "Выберите чат для фейк-статуса") { peerId, chatTitle in
                        let sheet = UIAlertController(title: "Фейк-статус: \(chatTitle)", message: "Статус будет активен 5 минут (виден в обычном Telegram):", preferredStyle: .actionSheet)
                        sheet.addAction(UIAlertAction(title: "⌨️ Печатает...", style: .default) { _ in
                            MTMediaTokWave13Tools.startFakeActivity(context: ctx, peerId: peerId, activity: .typingText, label: "печатает...", minutes: 5)
                        })
                        sheet.addAction(UIAlertAction(title: "🎥 Записывает видео...", style: .default) { _ in
                            MTMediaTokWave13Tools.startFakeActivity(context: ctx, peerId: peerId, activity: .recordingInstantVideo, label: "записывает видео...", minutes: 5)
                        })
                        sheet.addAction(UIAlertAction(title: "🎙 Записывает ГС...", style: .default) { _ in
                            MTMediaTokWave13Tools.startFakeActivity(context: ctx, peerId: peerId, activity: .recordingVoice, label: "записывает ГС...", minutes: 5)
                        })
                        sheet.addAction(UIAlertAction(title: "🎨 Выбирает стикер...", style: .default) { _ in
                            MTMediaTokWave13Tools.startFakeActivity(context: ctx, peerId: peerId, activity: .choosingSticker, label: "выбирает стикер...", minutes: 5)
                        })
                        sheet.addAction(UIAlertAction(title: "⏹ Остановить фейк-статус", style: .destructive) { _ in
                            MTMediaTokWave13Tools.stopFakeActivity(context: ctx, peerId: peerId)
                        })
                        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                        MTModalPresenter.presentOnTopmost(sheet)
                    }
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "square.and.arrow.up.fill",
            tint: UIColor(red: 0.24, green: 0.78, blue: 0.64, alpha: 1.0),
            title: "Экспорт диалога HTML / JSON / TXT (.exportchat)",
            subtitle: "Автономный архив переписки с поиском в тёмной теме (#272)",
            keywords: "export exportchat html json txt экспорт архив диалог 272",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTSpotlightPaletteController.presentRecentChatPicker(context: ctx, title: "Выберите чат для экспорта") { peerId, _ in
                        MTMediaTokWave14Tools.presentExportFormatPicker(context: ctx, peerId: peerId)
                    }
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "textformat.abc.dottedunderline",
            tint: UIColor(red: 0.42, green: 0.84, blue: 0.56, alpha: 1.0),
            title: "Исправить раскладку и орфографию (.spell / .layoutfix)",
            subtitle: "Офлайн проверка RU/EN + исправление QWERTY-раскладки и пунктуации (#166)",
            keywords: "spell layoutfix autocorrect раскладка орфография текст пунктуация 166",
            action: { [weak self] in
                self?.runAfterDismiss {
                    let alert = UIAlertController(
                        title: "Корректор текста (.spell)",
                        message: "Вставьте текст для исправления раскладки/опечаток (команда в чате: .spell <текст>):",
                        preferredStyle: .alert
                    )
                    alert.addTextField { tf in
                        tf.placeholder = "ghbdtn vbh..."
                        tf.text = UIPasteboard.general.string
                    }
                    alert.addAction(UIAlertAction(title: "Исправить и скопировать", style: .default) { [weak alert] _ in
                        let raw = alert?.textFields?.first?.text ?? ""
                        let fixed = MTMediaTokWave14Tools.fixTextSpellingAndPunctuation(raw)
                        guard !fixed.isEmpty else { return }
                        UIPasteboard.general.string = fixed
                        MTMediaTokWave5Tools.showToast(context: ctx, text: "Исправлено и скопировано: \(fixed.prefix(60))")
                    })
                    alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                    MTModalPresenter.presentOnTopmost(alert)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "eye.slash.circle.fill",
            tint: UIColor(red: 0.62, green: 0.42, blue: 0.98, alpha: 1.0),
            title: "Режим Стримера: Блюр экрана (.streamblur)",
            subtitle: "Плавающая кнопка мгновенного размытия чатов при записи экрана (#225)",
            keywords: "streamblur sblur streamer стрим блюр размытие запись экрана 225",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave14Tools.toggleStreamerBlur(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "flame.fill",
            tint: UIColor(red: 1.0, green: 0.45, blue: 0.20, alpha: 1.0),
            title: "Экстренная очистка кэша (.panicclean)",
            subtitle: "Мгновенная чистка временных файлов и URLCache (#235)",
            keywords: "panic clean cache очистка кэш экстренно 235",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave14Tools.presentPanicCleanAlert(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "sparkles.rectangle.stack.fill",
            tint: UIColor(red: 0.54, green: 0.44, blue: 1.0, alpha: 1.0),
            title: "Студия эффектов профиля + Discord Lanyard (.nickfx)",
            subtitle: "Рамки аватара, свечение/градиент ника и Live-музыка (#3/#6/#7/#8/#10)",
            keywords: "nickfx avatar frame рамка ник градиент музыка lanyard discord 3 6 7 8 10",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave15Tools.presentProfileFxStudio(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "storefront.fill",
            tint: UIColor(red: 0.18, green: 0.72, blue: 0.98, alpha: 1.0),
            title: "Браузер маркета Portals NFT (.portals)",
            subtitle: "Живой поиск RU/EN, фильтры редкости <0.5% / ≤1% / Rare (#51/#52)",
            keywords: "portals nft маркет подарки редкость пепе 51 52",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave15Tools.presentPortalsBrowser(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "dice.fill",
            tint: UIColor(red: 0.96, green: 0.62, blue: 0.18, alpha: 1.0),
            title: "Рулетка апгрейда NFT (.roulette)",
            subtitle: "Бесплатный симулятор апгрейда редких моделей подарков (#82)",
            keywords: "roulette upgrade рулетка апгрейд nft 82",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave15Tools.presentUpgradeRoulette(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "hammer.fill",
            tint: UIColor(red: 0.68, green: 0.36, blue: 0.96, alpha: 1.0),
            title: "Симулятор крафта NFT (.craft)",
            subtitle: "Случайный крафт редких комбинаций Модель+Фон+Узор (#83)",
            keywords: "craft крафт nft подарки 83",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave15Tools.presentCraftSimulator(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "qrcode",
            tint: UIColor(red: 0.22, green: 0.84, blue: 0.56, alpha: 1.0),
            title: "Экспорт/Импорт NFT в JSON и QR (.nftexport)",
            subtitle: "Перенос коллекции JSON и QR-передача NFT (#85/#86)",
            keywords: "nft json qr экспорт импорт 85 86",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave15Tools.presentNftJsonManager(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "moon.stars.fill",
            tint: UIColor(red: 0.36, green: 0.44, blue: 0.92, alpha: 1.0),
            title: "Режим «Ночной кинотеатр» (.cinema)",
            subtitle: "Снижение точки белого и мягкое затемнение экрана ночью (#132)",
            keywords: "cinema night dim ночной кинотеатр затемнение 132",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave16Tools.toggleNightCinemaMode(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "bookmark.circle.fill",
            tint: UIColor(red: 0.98, green: 0.68, blue: 0.22, alpha: 1.0),
            title: "Таймкоды-закладки видео (.vbm)",
            subtitle: "Сохраняй точные секунды и заметки к длинным видео (#134)",
            keywords: "vbm video bookmarks timecode таймкоды закладки 134",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave16Tools.presentVideoBookmarks(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "waveform.path",
            tint: UIColor(red: 0.20, green: 0.78, blue: 0.98, alpha: 1.0),
            title: "Редактор волны ГС — Waveform Art (.waveform)",
            subtitle: "Нарисуй любую форму волны голосового (видно всем!) (#355)",
            keywords: "waveform waveart волна голосовое гс 355",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave16Tools.presentWaveformArtEditor(context: ctx, peerId: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "music.mic",
            tint: UIColor(red: 0.94, green: 0.34, blue: 0.58, alpha: 1.0),
            title: "Аудиофайл → Голосовое сообщение (.atv)",
            subtitle: "Отправка любого .mp3/.m4a/.wav как настоящего ГС с волной (#354)",
            keywords: "atv audiotovoice mp3 voice аудио голосовое 354",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave16Tools.presentAudioToVoicePicker(context: ctx, peerId: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "speaker.wave.3.fill",
            tint: UIColor(red: 0.62, green: 0.42, blue: 0.98, alpha: 1.0),
            title: "Саундпад — Soundboard (.soundboard)",
            subtitle: "Мемные звуки для звонков и мгновенной отправки ГС (#363)",
            keywords: "soundboard sb саундпад мемы звуки звонки 363",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave16Tools.presentSoundboard(context: ctx, peerId: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "slider.horizontal.3",
            tint: UIColor(red: 0.24, green: 0.66, blue: 1.0, alpha: 1.0),
            title: "UI & Glass Студия + Анти-телеметрия (.uistudio)",
            subtitle: "Радиус пузырей 0–26pt, стекло, локальные эмодзи (#297/#298/#308/#283/#232)",
            keywords: "uistudio glass bubbles emoji telemetry пузыри стекло эмодзи 297 298 308 283 232",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave17Tools.presentUiStudio(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "archivebox.fill",
            tint: UIColor(red: 0.24, green: 0.82, blue: 0.52, alpha: 1.0),
            title: "Полный бэкап настроек .mediatok (.backup)",
            subtitle: "Экспорт и импорт всей конфигурации MediaTok в один файл (#334)",
            keywords: "backup mediatok экспорт импорт бэкап конфиг 334",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave17Tools.presentFullBackupManager(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "shazam.logo.fill",
            tint: UIColor(red: 0.16, green: 0.56, blue: 1.0, alpha: 1.0),
            title: "ShazamKit — Распознать трек (.shazam)",
            subtitle: "Определение играющей музыки через микрофон Apple ShazamKit (#124)",
            keywords: "shazam track music шазам трек музыка 124",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave18Tools.presentShazamRecognizer(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "shield.lefthalf.filled.badge.checkmark",
            tint: UIColor(red: 0.96, green: 0.34, blue: 0.36, alpha: 1.0),
            title: "Детектор скама, фишинга и подмен (.scamcheck)",
            subtitle: "Анализ текста/ссылок на IDN-подмены, IP-логгеры и дрейнеры (#157)",
            keywords: "scamcheck phishing скам фишинг ссылка проверка 157",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave18Tools.presentScamReport(context: ctx, text: UIPasteboard.general.string ?? "")
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "key.slash.fill",
            tint: UIColor(red: 0.98, green: 0.56, blue: 0.18, alpha: 1.0),
            title: "Ложный пароль и Паник-режим (.fakepass)",
            subtitle: "Мгновенная маскировка профиля, NFT и правил по паник-коду (#210)",
            keywords: "fakepass panic ложный пароль паник маскировка 210",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave18Tools.presentFakePasscodeManager(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "bell.and.waves.left.and.right.fill",
            tint: UIColor(red: 0.58, green: 0.44, blue: 1.0, alpha: 1.0),
            title: "Защиты от случайных кликов и Звуки (.guards / .sounds)",
            subtitle: "Подтверждение звонков, фильтр рекламы, паки звуков ICQ/Discord (#212/#161/#306)",
            keywords: "guards sounds защита звонки звуки icq discord реклама 212 161 306",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave18Tools.presentGuardsAndSounds(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "bubble.left.and.text.bubble.right.fill",
            tint: UIColor(red: 0.24, green: 0.78, blue: 0.68, alpha: 1.0),
            title: "Конструктор скрин-сообщения (.fakemsg)",
            subtitle: "Локальная карточка сообщения от любого автора и времени в PNG (#227/#228)",
            keywords: "fakemsg fakechat фейк сообщение скриншот 227 228",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave18Tools.presentFakeMessageBuilder(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "character.bubble.fill",
            tint: UIColor(red: 0.32, green: 0.68, blue: 1.0, alpha: 1.0),
            title: "Переводчик текста на фото / манге (OCR)",
            subtitle: "Распознавание облачков текста и перевод поверх картинки (.trimg)",
            keywords: "ocr манга перевод фото translate image 479",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave11Tools.presentImageTranslator(context: ctx, initialImage: nil, peerId: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "wand.and.rays",
            tint: UIColor(red: 0.96, green: 0.44, blue: 0.82, alpha: 1.0),
            title: "Magic Eraser — умный ластик на фото",
            subtitle: "Стирание лишних объектов и водяных знаков пальцем (.erase)",
            keywords: "eraser ластик стереть объект фото 481",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave11Tools.presentMagicEraser(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "sparkles.rectangle.stack.fill",
            tint: UIColor(red: 0.44, green: 0.78, blue: 1.0, alpha: 1.0),
            title: "4K Upscale & Enhance фото",
            subtitle: "Увеличение разрешения 2×/4× и повышение резкости (.upscale)",
            keywords: "upscale 4k апскейл качество резкость фото waifu2x 482",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave11Tools.presentUpscaler(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "gamecontroller.fill",
            tint: UIColor(red: 0.42, green: 0.88, blue: 0.48, alpha: 1.0),
            title: "Мини-игры: Крестики-нолики & 2048",
            subtitle: "Синхронизация ходов в чате между клиентами MediaTok (.game)",
            keywords: "игры game крестики нолики 2048 467",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave11Tools.presentMiniGames(context: ctx, peerId: nil, initialTab: 0)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "newspaper.fill",
            tint: UIColor(red: 1.0, green: 0.58, blue: 0.24, alpha: 1.0),
            title: "Встроенный RSS-ридер",
            subtitle: "Чтение RSS/Atom лент (Habr, HN, Apple и свои) + репост в чат (.rss)",
            keywords: "rss новости ридер ленты 470",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave11Tools.presentRssReader(context: ctx, peerId: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "doc.on.clipboard.fill",
            tint: UIColor(red: 0.36, green: 0.74, blue: 0.98, alpha: 1.0),
            title: "Общий буфер обмена Телефон ↔ ПК",
            subtitle: "Мгновенная синхронизация текста между iPhone и Windows (.pcclip / .syncclip)",
            keywords: "clipboard буфер пк windows sync pcclip syncclip 419",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave11Tools.presentSharedClipboard(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "bolt.fill",
            tint: UIColor(red: 1.0, green: 0.80, blue: 0.22, alpha: 1.0),
            title: "Siri / Команды, Виджеты, iPad-клавиши, Миграция",
            subtitle: "URL-схемы mediatok://, Widget JSON, авто-миграция базы (.shortcuts)",
            keywords: "siri shortcuts команды виджеты клавиатура миграция 487 488 489 494",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave11Tools.presentEcosystemHub(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "paintpalette.fill",
            tint: UIColor(red: 0.98, green: 0.46, blue: 0.64, alpha: 1.0),
            title: "Конструктор стикерпаков (512×512 PNG)",
            subtitle: "Скруглённый стикер с подписью и прямой отправкой в @Stickers (.makesticker)",
            keywords: "sticker стикер конструктор 512 png stickers 456",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave10Tools.presentStickerMaker(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "puzzlepiece.extension.fill",
            tint: UIColor(red: 0.56, green: 0.52, blue: 1.0, alpha: 1.0),
            title: "Mini Apps Power Pack (#451–#455)",
            subtitle: "Блок fullscreen/вибрации, подмена платформы, мульти-окна, автокликер, DevTools",
            keywords: "miniapps миниапп fullscreen платформа автокликер devtools 451 452 453 454 455",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave10Tools.presentMiniAppsStudio(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "waveform.and.mic",
            tint: UIColor(red: 0.34, green: 0.84, blue: 0.78, alpha: 1.0),
            title: "Пресеты Voicemod (Экспорт / Импорт)",
            subtitle: "Обмен JSON-пресетами голоса (#380)",
            keywords: "voicemod пресеты голос экспорт импорт 380",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave10Tools.presentVoicemodPresetsSheet(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "antenna.radiowaves.left.and.right",
            tint: UIColor(red: 0.28, green: 0.82, blue: 0.54, alpha: 1.0),
            title: "Спидтест DC1–DC5 и монитор сети",
            subtitle: "Замер пинга дата-центров Telegram, Catbox CDN и ntfy (.dc)",
            keywords: "dc speedtest ping сеть замер пинг датацентр 406 415",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave9Tools.presentDcSpeedtest(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "network.badge.shield.half.filled",
            tint: UIColor(red: 0.28, green: 0.66, blue: 1.0, alpha: 1.0),
            title: "Сеть, VPN-слот, Аккаунты (∞) и Sync v2",
            subtitle: "Split Tunneling, прокси на аккаунт, клонирование, DoH, SHA-256 (.vpn)",
            keywords: "vpn split tunnel proxy прокси аккаунты клон sync doh sha256 401 402 422 423 495 417",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave9Tools.presentWave3NetworkHub(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "person.crop.rectangle.stack.fill",
            tint: UIColor(red: 0.76, green: 0.48, blue: 0.98, alpha: 1.0),
            title: "Примерочная профиля (MediaTok Sandbox)",
            subtitle: "Живой превью темы, рамки, эффекта, статуса и погоды до сохранения (.sandbox)",
            keywords: "sandbox примерочная профиль превью баннер рамка 499",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave8Tools.presentProfileSandbox(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "qrcode.viewfinder",
            tint: UIColor(red: 0.38, green: 0.78, blue: 1.0, alpha: 1.0),
            title: "Красивый QR-код профиля",
            subtitle: "Градиентная QR-карточка с бейджем MediaTok (.myqr)",
            keywords: "qr код профиль карточка градиент 466",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave8Tools.presentProfileQR(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "face.dashed.fill",
            tint: UIColor(red: 0.98, green: 0.54, blue: 0.38, alpha: 1.0),
            title: "Размытие лиц на фото (Apple Vision)",
            subtitle: "Автоматический поиск и размытие лиц в 1 тап (.blurface)",
            keywords: "blur face лица размытие фото приватность 460",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave8Tools.presentFaceBlurPicker(context: ctx, targetPeerId: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "doc.viewfinder",
            tint: UIColor(red: 0.34, green: 0.74, blue: 0.98, alpha: 1.0),
            title: "Сканер документов → PDF",
            subtitle: "Сканирование камерой в многостраничный PDF (.scanpdf)",
            keywords: "scan pdf скан документ камера 461",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave8Tools.presentDocumentScanner(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "signature",
            tint: UIColor(red: 0.96, green: 0.72, blue: 0.28, alpha: 1.0),
            title: "Подписать PDF пальцем",
            subtitle: "Наложение рукописной подписи на любой PDF (.signpdf)",
            keywords: "sign pdf подпись документ 462",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave8Tools.presentPdfFilePickerForSignature(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "cloud.sun.fill",
            tint: UIColor(red: 0.38, green: 0.82, blue: 0.98, alpha: 1.0),
            title: "Живая погода в профиле (Open-Meteo)",
            subtitle: "Подбор эффекта и статуса под погоду твоего города (.weather)",
            keywords: "weather погода город дождь снег солнце 497",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave8Tools.presentWeatherSetup(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "battery.100.bolt",
            tint: UIColor(red: 0.32, green: 0.88, blue: 0.48, alpha: 1.0),
            title: "Спуфинг батареи и зарядки",
            subtitle: "Подмена процента заряда в системных отчётах MediaTok",
            keywords: "battery spoof батарея зарядка спуфинг 486",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave8Tools.presentBatterySpoofSheet(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "music.note.list",
            tint: UIColor(red: 0.98, green: 0.38, blue: 0.56, alpha: 1.0),
            title: "Текст песни (LRC Караоке)",
            subtitle: "Синхронизация с плеером Telegram через lrclib.net (.lyrics)",
            keywords: "lyrics lrc музыка текст песни караоке спотифай spotify 371",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave7Tools.presentLyricsViewer(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "arrow.triangle.2.circlepath",
            tint: UIColor(red: 0.28, green: 0.72, blue: 1.0, alpha: 1.0),
            title: "Переподключить сеть (Force Reconnect)",
            subtitle: "Мгновенный сброс зависшего соединения Telegram (.reconnect)",
            keywords: "reconnect сеть интернет сброс переподключить пинг 416",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave7Tools.forceReconnect(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "mic.badge.plus",
            tint: UIColor(red: 0.96, green: 0.44, blue: 0.44, alpha: 1.0),
            title: "Голосовые (ГС): Подтверждение и 99:59",
            subtitle: "Подтверждать отправку ГС и настраивать фейк-длительность",
            keywords: "voice гс голосовое подтверждение 99:59 длительность 377 379",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave7Tools.presentVoiceToolsSheet(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "person.crop.circle.badge.sparkles",
            tint: UIColor(red: 0.54, green: 0.52, blue: 1.0, alpha: 1.0),
            title: "Визуальный профиль 4K (Discord Studio)",
            subtitle: "Баннер 4K, рамка аватара, эффекты, музыка, Steam/Roblox",
            keywords: "profile профиль баннер рамка эффект discord 4k музыка",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        MTMediaTokDiscordProfile.presentOwnEditor(context: mCtx)
                    } else {
                        MTMediaTokDiscordProfile.presentEditor(peerId: ctx.account.peerId, isOwn: true, onDone: nil)
                    }
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "play.rectangle.on.rectangle.fill",
            tint: UIColor(red: 0.98, green: 0.34, blue: 0.52, alpha: 1.0),
            title: "TikTok-лента каналов",
            subtitle: "Вертикальная свайп-лента видео и кружков из каналов",
            keywords: "tiktok reels shorts лента видео кружки",
            action: { [weak self] in
                self?.runAfterDismiss {
                    let feed = MTTikTokFeedViewController(context: ctx, navigationController: mCtx?.navigationController)
                    MTMediaTokWave5Tools.presentOnRoot(feed)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "face.smiling.inverse",
            tint: UIColor(red: 1.0, green: 0.72, blue: 0.24, alpha: 1.0),
            title: "/stickers — База 10к стикеров + ИИ",
            subtitle: "Быстрый поиск, OCR и загрузка папок по Wi-Fi",
            keywords: "stickers стикеры поиск ии wifi база",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        MTMediaTokStickerVault.presentManagerFromMenu(context: mCtx)
                    } else {
                        MTMediaTokStickerVault.presentPicker(context: ctx, targetPeerId: nil, initialQuery: "")
                    }
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "trophy.fill",
            tint: UIColor(red: 1.0, green: 0.78, blue: 0.22, alpha: 1.0),
            title: "Достижения MediaTok",
            subtitle: "Ранги, бейджи и статистика",
            keywords: "achievements достижения ачивки ранг",
            action: { [weak self] in
                self?.runAfterDismiss {
                    let vc = MTAchievementsViewController()
                    vc.overrideUserInterfaceStyle = .dark
                    let nav = UINavigationController(rootViewController: vc)
                    nav.overrideUserInterfaceStyle = .dark
                    MTMediaTokWave5Tools.presentOnRoot(nav)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "dock.rectangle",
            tint: UIColor(red: 0.42, green: 0.72, blue: 0.98, alpha: 1.0),
            title: "Редактор нижнего бара",
            subtitle: "Пресеты таббара, парящий бар, скрыть вкладки",
            keywords: "tabbar таббар бар нижняя панель 110",
            action: { [weak self] in
                self?.runAfterDismiss {
                    let vc = MTBottomBarStudioViewController()
                    vc.overrideUserInterfaceStyle = .dark
                    let nav = UINavigationController(rootViewController: vc)
                    nav.overrideUserInterfaceStyle = .dark
                    MTMediaTokWave5Tools.presentOnRoot(nav)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "flame.circle.fill",
            tint: UIColor(red: 1.0, green: 0.48, blue: 0.20, alpha: 1.0),
            title: "Огоньки чатов (Топ серий)",
            subtitle: "Активные серии переписок и заморозки",
            keywords: "streaks огоньки серии рейтинг",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave5Tools.presentStreaksLeaderboard(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "arcade.stick.console.fill",
            tint: UIColor(red: 0.56, green: 0.84, blue: 0.36, alpha: 1.0),
            title: "Мини-игры MediaTok",
            subtitle: "2048, Сапёр 8x8 и аркады без интернета",
            keywords: "games игры 2048 сапер minesweeper",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave5Tools.presentMiniGamesHub()
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "text.badge.plus",
            tint: UIColor(red: 0.98, green: 0.74, blue: 0.26, alpha: 1.0),
            title: "Сниппеты / Макросы (.sn)",
            subtitle: "Сохранённые быстрые шаблоны текста",
            keywords: "snippets сниппеты макросы шаблоны sn",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave6Tools.presentSnippetsSheet(context: ctx, onPick: nil)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "star.circle.fill",
            tint: UIColor(red: 0.72, green: 0.48, blue: 1.0, alpha: 1.0),
            title: "Премиум Эмодзи (без подписки)",
            subtitle: "Клавиатура, отправка в чатах и эмодзи-статус",
            keywords: "emoji premium эмодзи премиум статус",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        MTMediaTokWave5Tools.presentPremiumEmojiSheet(context: mCtx)
                    } else {
                        let enabled = MTMediaTokWave5Tools.isPremiumEmojiEnabled
                        let sheet = UIAlertController(
                            title: "✨ Премиум Эмодзи",
                            message: enabled
                                ? "Включено: все паки Премиум-эмодзи разблокированы в клавиатуре и поиске, отправляются в любые чаты без подписки."
                                : "Выключено: стандартное поведение Telegram для Премиум-эмодзи.",
                            preferredStyle: .actionSheet
                        )
                        sheet.addAction(UIAlertAction(title: enabled ? "Выключить Премиум Эмодзи" : "✨ Включить Премиум Эмодзи", style: .default, handler: { _ in
                            MTMediaTokWave5Tools.isPremiumEmojiEnabled.toggle()
                            MTMediaTokWave5Tools.showToast(context: ctx, text: MTMediaTokWave5Tools.isPremiumEmojiEnabled ? "✨ Премиум Эмодзи включены!" : "Премиум Эмодзи выключены")
                        }))
                        sheet.addAction(UIAlertAction(title: "🧹 Сбросить эмодзи-статус в профиле", style: .destructive, handler: { _ in
                            MTMediaTokWave5Tools.resetPremiumEmojiStatus(context: ctx)
                            MTMediaTokWave5Tools.showToast(context: ctx, text: "Эмодзи-статус профиля сброшен")
                        }))
                        sheet.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
                        MTModalPresenter.presentOnTopmost(sheet)
                    }
                }
            }
        ))
        items.append(MTSpotlightCommandItem(
            symbol: "cube.transparent.fill",
            tint: UIColor(red: 0.42, green: 0.86, blue: 0.98, alpha: 1.0),
            title: "Liquid Glass / Zero-Bloat / 4K 60fps",
            subtitle: "Стекло iOS 27, компактный чат, стиль галочек, видео 4K",
            keywords: "liquid glass стекло 4k 60fps bloat галочки",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        MTMediaTokLiquidUI.presentStudio(context: mCtx)
                    } else if let nav = ctx.sharedContext.mainWindow?.viewController as? NavigationController {
                        nav.pushViewController(mtMakeSettingsController(context: ctx))
                        MTMediaTokWave5Tools.showToast(context: ctx, text: "Открой Оформление › Интерфейс и Видео 4K")
                    }
                }
            }
        ))
        items.append(MTSpotlightCommandItem(
            symbol: "globe",
            tint: UIColor(red: 0.34, green: 0.76, blue: 0.98, alpha: 1.0),
            title: "Студия языков (66+ пакетов)",
            subtitle: "Языковые пакеты и живой редактор всех строк",
            keywords: "lang языки перевод строки редактор",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        MTMediaTokLangs.presentStudio(context: mCtx)
                    } else if let nav = ctx.sharedContext.mainWindow?.viewController as? NavigationController {
                        nav.pushViewController(mtMakeSettingsController(context: ctx))
                        MTMediaTokWave5Tools.showToast(context: ctx, text: "Открой Оформление › Студия языков")
                    }
                }
            }
        ))
        items.append(MTSpotlightCommandItem(
            symbol: "lock.shield.fill",
            tint: UIColor(red: 0.28, green: 0.84, blue: 0.62, alpha: 1.0),
            title: "E2E Шифрование (AES-256-GCM)",
            subtitle: "Управление ключами шифрования чатов",
            keywords: "e2e aes шифрование ключ приватность",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        MTMediaTokE2E.presentManager(context: mCtx)
                    } else {
                        let count = MTMediaTokE2E.activeCount
                        let alert = UIAlertController(
                            title: "E2E-шифрование чатов (AES-256-GCM)",
                            message: "Активно чатов: \(count) (ключи защищены в Keychain + PBKDF2).\n\nВключить E2E для любого чата можно долгим нажатием на «Отправить» или командой .e2e on <пароль>.",
                            preferredStyle: .alert
                        )
                        if count > 0 {
                            alert.addAction(UIAlertAction(title: "Сбросить все E2E-ключи (\(count))", style: .destructive, handler: { _ in
                                MTMediaTokE2E.removeAll()
                                MTMediaTokWave5Tools.showToast(context: ctx, text: "Все E2E-ключи сброшены")
                            }))
                        }
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        MTModalPresenter.presentOnTopmost(alert)
                    }
                }
            }
        ))
        items.append(MTSpotlightCommandItem(
            symbol: "speaker.slash.fill",
            tint: UIColor(red: 0.98, green: 0.46, blue: 0.42, alpha: 1.0),
            title: "Anti-Screamer / Фильтр громких звуков",
            subtitle: "Защита от скримеров и резких звуков",
            keywords: "screamer аудио звук защита фильтр",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        MTMediaTokAudioGuard.presentSettings(context: mCtx)
                    } else {
                        let cur = MTMediaTokAudioGuard.mode
                        let sheet = UIAlertController(
                            title: "🛡 Фильтр громких звуков, скримеров и стонов",
                            message: "MediaTok сканирует ГС (Opus), кружки и видео на резкие перегрузы и глушит резкие частоты (-12 dB).",
                            preferredStyle: .actionSheet
                        )
                        let options: [(Int, String)] = [
                            (1, "Авто-фильтр скримеров и стонов (Рекомендуется)" + (cur == 1 ? " ✓" : "")),
                            (2, "Строгий: всегда глушить резкие частоты без наушников" + (cur == 2 ? " ✓" : "")),
                            (0, "Выключено" + (cur == 0 ? " ✓" : ""))
                        ]
                        for (val, title) in options {
                            sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
                                MTMediaTokAudioGuard.mode = val
                                MTMediaTokWave5Tools.showToast(context: ctx, text: "Фильтр звука: \(MTMediaTokAudioGuard.modeLabel)")
                            }))
                        }
                        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                        MTModalPresenter.presentOnTopmost(sheet)
                    }
                }
            }
        ))
        items.append(MTSpotlightCommandItem(
            symbol: "textformat",
            tint: UIColor(red: 0.84, green: 0.56, blue: 1.0, alpha: 1.0),
            title: "Шрифты приложения и чата",
            subtitle: "Кастомные TTF/OTF шрифты и 32 стиля текста",
            keywords: "font шрифт ttf otf стиль текст",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        mCtx.open(tab: MTAppearanceMenu.fontTab)
                    } else if let nav = ctx.sharedContext.mainWindow?.viewController as? NavigationController {
                        nav.pushViewController(mtMakeSettingsController(context: ctx))
                        MTMediaTokWave5Tools.showToast(context: ctx, text: "Открой Оформление › Шрифт приложения и чата")
                    }
                }
            }
        ))
        items.append(MTSpotlightCommandItem(
            symbol: "waveform.path.ecg.rectangle.fill",
            tint: UIColor(red: 0.36, green: 0.86, blue: 0.76, alpha: 1.0),
            title: "MediaTok Wrapped и Диагностика",
            subtitle: "Итоги статистики, статус модулей и защита от плеча",
            keywords: "wrapped итоги диагностика privacy статистика",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        MTMediaTokWave6Tools.presentWrappedAndDiagnostics(context: mCtx)
                    } else {
                        let diag = MTMediaTokWave7Tools.buildDiagnosticsSummary()
                        let alert = UIAlertController(title: "🩺 Wrapped & Диагностика MediaTok", message: diag, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "☁️ Бэкап MediaTok в Избранное (ТГ)", style: .default, handler: { _ in
                            MTMediaTokWave6Tools.backupMediaTokToSavedMessages(context: ctx)
                        }))
                        alert.addAction(UIAlertAction(title: "🕶️ Защита от плеча", style: .default, handler: { _ in
                            MTMediaTokWave6Tools.togglePrivacyScreen()
                        }))
                        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
                        MTModalPresenter.presentOnTopmost(alert)
                    }
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "phone.down.waves.left.and.right",
            tint: UIColor(red: 0.34, green: 0.82, blue: 0.54, alpha: 1.0),
            title: "Защита от случайных звонков (Call Guard)",
            subtitle: MTMediaTokWave6Tools.isCallConfirmEnabled ? "Сейчас: ВКЛ — нажми чтобы переключить" : "Сейчас: ВЫКЛ — нажми чтобы переключить",
            keywords: "call guard звонки подтверждение защита",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave6Tools.isCallConfirmEnabled.toggle()
                    let st = MTMediaTokWave6Tools.isCallConfirmEnabled ? "ВКЛ" : "ВЫКЛ"
                    MTMediaTokWave5Tools.showToast(context: ctx, text: "Защита звонков: \(st)")
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "nosign",
            tint: UIColor(red: 0.98, green: 0.38, blue: 0.38, alpha: 1.0),
            title: "Анти-реклама каналов (#188)",
            subtitle: MTMediaTokWave6Tools.isAdBlockEnabled ? "Сейчас: ВКЛ — нажми чтобы переключить" : "Сейчас: ВЫКЛ — нажми чтобы переключить",
            keywords: "adblock реклама erid каналы блок",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave6Tools.isAdBlockEnabled.toggle()
                    let st = MTMediaTokWave6Tools.isAdBlockEnabled ? "ВКЛ" : "ВЫКЛ"
                    MTMediaTokWave5Tools.showToast(context: ctx, text: "Анти-реклама каналов: \(st)")
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "sparkles",
            tint: UIColor(red: 0.98, green: 0.78, blue: 0.30, alpha: 1.0),
            title: "Что нового в MediaTok b\(MTMediaTokWave7Tools.currentBuildNumber)",
            subtitle: "Список изменений текущей сборки",
            keywords: "whatsnew changelog нового обновление билд 491",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave7Tools.presentWhatsNew(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "ladybug.fill",
            tint: UIColor(red: 0.96, green: 0.50, blue: 0.34, alpha: 1.0),
            title: "Сообщить о баге / идее",
            subtitle: "Копирует диагностику устройства и сборки",
            keywords: "bug feedback баг идея диагностика репорт 492",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave7Tools.presentFeedbackSheet(context: ctx)
                }
            }
        ))

        items.append(MTSpotlightCommandItem(
            symbol: "checkmark.shield.fill",
            tint: UIColor(red: 0.38, green: 0.78, blue: 1.0, alpha: 1.0),
            title: "Безопасный режим (Safe Mode)",
            subtitle: "Сброс шрифта и видео-обоев без потери данных",
            keywords: "safe mode безопасный режим краш сброс 493",
            action: { [weak self] in
                self?.runAfterDismiss {
                    MTMediaTokWave7Tools.presentSafeModeConfirmation(context: ctx)
                }
            }
        ))

        self.allItems = items
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            self.filteredItems = self.allItems
        } else {
            self.filteredItems = self.allItems.filter { item in
                return item.title.lowercased().contains(q)
                    || item.subtitle.lowercased().contains(q)
                    || item.keywords.lowercased().contains(q)
            }
        }
        self.tableView.reloadData()
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.filteredItems.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseId = "MTSpotlightCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseId)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseId)
        let item = self.filteredItems[indexPath.row]
        cell.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        cell.imageView?.image = self.makeSpotlightBadge(symbol: item.symbol, tint: item.tint)
        cell.textLabel?.text = item.title
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cell.detailTextLabel?.text = item.subtitle
        cell.detailTextLabel?.textColor = UIColor(white: 0.68, alpha: 1.0)
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = self.filteredItems[indexPath.row]
        item.action()
    }

    private static func presentRecentChatPicker(context: AccountContext, title: String, onSelect: @escaping (PeerId, String) -> Void) {
        let _ = (context.account.postbox.transaction { transaction -> [(PeerId, String)] in
            var result: [(PeerId, String)] = []
            for entry in transaction.getTopChatListEntries(groupId: .root, count: 10) {
                let name = entry.peer?.debugDisplayTitle ?? "Чат \(entry.peerId.id._internalGetInt64Value())"
                result.append((entry.peerId, name))
            }
            return result
        } |> deliverOnMainQueue).startStandalone(next: { chats in
            guard !chats.isEmpty else {
                MTMediaTokWave5Tools.showToast(context: context, text: "Список чатов пуст")
                return
            }
            let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
            for (pid, name) in chats {
                sheet.addAction(UIAlertAction(title: name, style: .default) { _ in
                    onSelect(pid, name)
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            MTModalPresenter.presentOnTopmost(sheet)
        })
    }
}

// MARK: - #371 Synced LRC Lyrics (`lrclib.net`)

private struct MTSyncedLrcLine {
    let time: Double
    let text: String
}

private enum MTLrcParser {
    static func parse(_ raw: String) -> [MTSyncedLrcLine] {
        var result: [MTSyncedLrcLine] = []
        let lines = raw.components(separatedBy: .newlines)
        guard let regex = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{2})(?:\\.(\\d{1,3}))?\\]", options: []) else {
            return []
        }
        for line in lines {
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: line, options: [], range: fullRange)
            guard !matches.isEmpty else { continue }

            let lastEnd = matches.last.map { $0.range.location + $0.range.length } ?? 0
            let lyricText = nsLine.substring(from: lastEnd).trimmingCharacters(in: .whitespaces)
            let display = lyricText.isEmpty ? "♪" : lyricText

            for m in matches {
                let minStr = nsLine.substring(with: m.range(at: 1))
                let secStr = nsLine.substring(with: m.range(at: 2))
                let fracRange = m.range(at: 3)
                var frac: Double = 0.0
                if fracRange.location != NSNotFound {
                    let fStr = nsLine.substring(with: fracRange)
                    let fVal = Double(fStr) ?? 0.0
                    if fStr.count == 1 {
                        frac = fVal / 10.0
                    } else if fStr.count == 2 {
                        frac = fVal / 100.0
                    } else {
                        frac = fVal / 1000.0
                    }
                }
                let time = (Double(minStr) ?? 0.0) * 60.0 + (Double(secStr) ?? 0.0) + frac
                result.append(MTSyncedLrcLine(time: time, text: display))
            }
        }
        result.sort { $0.time < $1.time }
        return result
    }
}

public final class MTLyricsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let initialQuery: String?

    private let headerLabel = UILabel()
    private let statusLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var playerDisposable: Disposable?
    private var syncTimer: Foundation.Timer?
    private var currentLyricsTask: URLSessionDataTask?
    private var latestStatus: MediaPlayerStatus?
    private var currentTrackKey: String = ""
    private var syncedLines: [MTSyncedLrcLine] = []
    private var plainLines: [String] = []
    private var activeIndex: Int = -1
    private var rawLyricsText: String = ""

    public init(context: AccountContext, initialQuery: String? = nil) {
        self.context = context
        self.initialQuery = initialQuery
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.playerDisposable?.dispose()
        self.syncTimer?.invalidate()
        self.currentLyricsTask?.cancel()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Текст песни (LRC)"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)

        let searchBtn = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(self.searchTapped))
        let copyBtn = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), style: .plain, target: self, action: #selector(self.copyTapped))
        self.navigationItem.leftBarButtonItems = [searchBtn, copyBtn]
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.closeTapped))

        self.headerLabel.font = .systemFont(ofSize: 18, weight: .bold)
        self.headerLabel.textColor = .white
        self.headerLabel.numberOfLines = 2
        self.headerLabel.textAlignment = .center
        self.headerLabel.translatesAutoresizingMaskIntoConstraints = false

        self.statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        self.statusLabel.textColor = UIColor(white: 0.65, alpha: 1.0)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 2
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        self.spinner.color = .white
        self.spinner.hidesWhenStopped = true
        self.spinner.translatesAutoresizingMaskIntoConstraints = false

        self.tableView.backgroundColor = .clear
        self.tableView.separatorStyle = .none
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.contentInset = UIEdgeInsets(top: 16, left: 0, bottom: 48, right: 0)
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.headerLabel)
        self.view.addSubview(self.statusLabel)
        self.view.addSubview(self.spinner)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.headerLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            self.headerLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.headerLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            self.statusLabel.topAnchor.constraint(equalTo: self.headerLabel.bottomAnchor, constant: 4),
            self.statusLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.statusLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            self.spinner.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.spinner.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 8),
            self.tableView.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 12),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        if let q = self.initialQuery, !q.isEmpty {
            self.headerLabel.text = q
            self.statusLabel.text = "Поиск текста на lrclib.net..."
            self.fetchLyrics(track: nil, artist: nil, query: q)
        } else {
            self.headerLabel.text = "Ожидание трека..."
            self.statusLabel.text = "Включи музыку в Telegram или нажми поиск"
        }

        self.subscribeToMusicPlayer()
        self.syncTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tickPlaybackHighlight()
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if self.isBeingDismissed {
            self.syncTimer?.invalidate()
            self.syncTimer = nil
            self.currentLyricsTask?.cancel()
            self.currentLyricsTask = nil
        }
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func copyTapped() {
        guard !self.rawLyricsText.isEmpty else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Текст ещё не загружен")
            return
        }
        UIPasteboard.general.string = self.rawLyricsText
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Текст песни скопирован")
    }

    @objc private func searchTapped() {
        let alert = UIAlertController(
            title: "Найти текст песни",
            message: "Введи исполнителя и название трека:",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Например: Miyagi - Minor"
        }
        alert.addAction(UIAlertAction(title: "Найти", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let q = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !q.isEmpty else { return }
            self.currentTrackKey = "manual:\(q)"
            self.headerLabel.text = q
            self.statusLabel.text = "Поиск на lrclib.net..."
            self.fetchLyrics(track: nil, artist: nil, query: q)
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.present(alert, animated: true)
    }

    private func subscribeToMusicPlayer() {
        let signal = self.context.sharedContext.mediaManager.musicMediaPlayerState
            |> deliverOnMainQueue
        self.playerDisposable = signal.startStrict(next: { [weak self] state in
            guard let self else { return }
            guard let (_, playbackStateOrLoading, _) = state,
                  case let .state(playbackState) = playbackStateOrLoading else {
                return
            }
            self.latestStatus = playbackState.status

            if case let .music(title, performer, _, _, _) = playbackState.item.displayData {
                let cleanTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanArtist = (performer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let trackKey = "\(cleanArtist)|\(cleanTitle)"
                if !cleanTitle.isEmpty && trackKey != self.currentTrackKey && self.initialQuery == nil {
                    self.currentTrackKey = trackKey
                    self.headerLabel.text = cleanArtist.isEmpty ? cleanTitle : "\(cleanArtist) — \(cleanTitle)"
                    self.statusLabel.text = "Загрузка LRC с lrclib.net..."
                    self.fetchLyrics(track: cleanTitle, artist: cleanArtist.isEmpty ? nil : cleanArtist, query: nil)
                }
            }
        })
    }

    private func fetchLyrics(track: String?, artist: String?, query: String?) {
        self.currentLyricsTask?.cancel()
        self.currentLyricsTask = nil

        self.spinner.startAnimating()
        self.syncedLines = []
        self.plainLines = []
        self.activeIndex = -1
        self.tableView.reloadData()

        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"

        if let track, !track.isEmpty {
            components.path = "/api/get"
            var items = [URLQueryItem(name: "track_name", value: track)]
            if let artist, !artist.isEmpty {
                items.append(URLQueryItem(name: "artist_name", value: artist))
            }
            components.queryItems = items
        } else if let query, !query.isEmpty {
            components.path = "/api/search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        } else {
            self.spinner.stopAnimating()
            return
        }

        guard let url = components.url else {
            self.spinner.stopAnimating()
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 10.0)
        req.setValue("MediaTok-iOS/\(MTMediaTokWave7Tools.currentBuildNumber) (https://github.com/ownersavesociety)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            if let nsErr = error as NSError?, nsErr.domain == NSURLErrorDomain, nsErr.code == NSURLErrorCancelled {
                return
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, error == nil {
                    if let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                       self.applyLrclibEntry(dict) {
                        self.spinner.stopAnimating()
                        return
                    }
                    if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                        let best = arr.first(where: { ($0["syncedLyrics"] as? String)?.isEmpty == false })
                            ?? arr.first(where: { ($0["plainLyrics"] as? String)?.isEmpty == false })
                        if let best, self.applyLrclibEntry(best) {
                            self.spinner.stopAnimating()
                            return
                        }
                    }
                }
                // If exact /api/get missed, automatically fall back to fuzzy /api/search once.
                if let track, !track.isEmpty {
                    let fallbackQuery = [artist, track].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                    self.fetchLyrics(track: nil, artist: nil, query: fallbackQuery)
                } else {
                    self.spinner.stopAnimating()
                    self.statusLabel.text = "Текст не найден на lrclib.net — попробуй поиск"
                }
            }
        }
        self.currentLyricsTask = task
        task.resume()
    }

    private func applyLrclibEntry(_ dict: [String: Any]) -> Bool {
        let trackName = dict["trackName"] as? String ?? ""
        let artistName = dict["artistName"] as? String ?? ""
        if !trackName.isEmpty {
            self.headerLabel.text = artistName.isEmpty ? trackName : "\(artistName) — \(trackName)"
        }

        if let synced = dict["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = MTLrcParser.parse(synced)
            if !parsed.isEmpty {
                self.syncedLines = parsed
                self.plainLines = []
                self.rawLyricsText = parsed.map { $0.text }.joined(separator: "\n")
                self.statusLabel.text = "Синхронизированный LRC (\(parsed.count) строк) • lrclib.net"
                self.tableView.reloadData()
                self.tickPlaybackHighlight()
                return true
            }
        }

        if let plain = dict["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = plain.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if !lines.isEmpty {
                self.syncedLines = []
                self.plainLines = lines
                self.rawLyricsText = plain
                self.statusLabel.text = "Текст песни (без таймкодов) • lrclib.net"
                self.tableView.reloadData()
                return true
            }
        }
        return false
    }

    private func tickPlaybackHighlight() {
        guard !self.syncedLines.isEmpty, let status = self.latestStatus else { return }
        var currentTime = status.timestamp
        if case .playing = status.status {
            let elapsed = max(0.0, CACurrentMediaTime() - status.generationTimestamp)
            currentTime += elapsed * status.baseRate
        }
        var idx = -1
        for (i, line) in self.syncedLines.enumerated() {
            if line.time <= currentTime + 0.15 {
                idx = i
            } else {
                break
            }
        }
        if idx != self.activeIndex && idx >= 0 && idx < self.syncedLines.count {
            let oldIdx = self.activeIndex
            self.activeIndex = idx
            var reload: [IndexPath] = [IndexPath(row: idx, section: 0)]
            if oldIdx >= 0 && oldIdx < self.syncedLines.count {
                reload.append(IndexPath(row: oldIdx, section: 0))
            }
            self.tableView.reloadRows(at: reload, with: .none)
            self.tableView.scrollToRow(at: IndexPath(row: idx, section: 0), at: .middle, animated: true)
        }
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return !self.syncedLines.isEmpty ? self.syncedLines.count : self.plainLines.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseId = "MTLyricsLineCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseId)
            ?? UITableViewCell(style: .default, reuseIdentifier: reuseId)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.textAlignment = .center

        if !self.syncedLines.isEmpty {
            let line = self.syncedLines[indexPath.row]
            let isActive = indexPath.row == self.activeIndex
            cell.textLabel?.text = line.text
            cell.textLabel?.font = .systemFont(ofSize: isActive ? 22 : 17, weight: isActive ? .bold : .medium)
            cell.textLabel?.textColor = isActive ? .white : UIColor(white: 1.0, alpha: 0.42)
        } else {
            cell.textLabel?.text = self.plainLines[indexPath.row]
            cell.textLabel?.font = .systemFont(ofSize: 18, weight: .medium)
            cell.textLabel?.textColor = UIColor(white: 1.0, alpha: 0.88)
        }
        return cell
    }
}
