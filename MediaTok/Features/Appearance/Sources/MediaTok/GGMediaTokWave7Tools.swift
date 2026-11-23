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
import GGCore
import GGHooks
import GGSettingsUI
import GGAppearanceSettings

/// MediaTok Wave 7 (Roadmap Wave 1 — Foundation, Stability & UX):
/// - #493 Safe Mode (automatic crash-streak guard + manual Safe Mode reset)
/// - #416 Force Reconnect (instant Telegram MTProto network reset)
/// - #490 Spotlight Command Palette (universal searchable MediaTok launcher)
/// - #371 Synced LRC Lyrics (`lrclib.net` real-time karaoke lyrics synced to Telegram music player)
/// - #379 Confirm Before Sending Voice Message (`mediatok.voice.confirm_send.v1`)
/// - #377 Optional Fake Voice Duration (`mediatok.voice.fake_duration.v1`: 0:00, 1:00, 59:59, 99:59, custom)
/// - #491 "What's New" Screen (`b3775`) + #492 "Report Bug / Idea" Diagnostics
public enum GGMediaTokWave7Tools {
    public static let currentBuildNumber = "3779"

    private static let safeModeStreakKey = "mediatok.safemode.streak.v1"
    private static let whatsNewLastSeenKey = "mediatok.whatsnew.last_seen_build.v1"
    public static let voiceConfirmSendKey = "mediatok.voice.confirm_send.v1"
    public static let voiceFakeDurationKey = "mediatok.voice.fake_duration.v1"

    public private(set) static var safeModeActivatedOnLaunch = false
    private static var hasCheckedSafeMode = false

    public static var isVoiceConfirmEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: GGMediaTokWave7Tools.voiceConfirmSendKey) }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave7Tools.voiceConfirmSendKey) }
    }

    /// 0 = off, -1 = fake 0:00, >0 = custom duration in seconds (e.g. 5999 = 99:59).
    public static var fakeVoiceDurationSeconds: Int {
        get { return UserDefaults.standard.integer(forKey: GGMediaTokWave7Tools.voiceFakeDurationKey) }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave7Tools.voiceFakeDurationKey) }
    }

    public static var fakeVoiceDurationLabel: String {
        let val = GGMediaTokWave7Tools.fakeVoiceDurationSeconds
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
        let confirmPart = GGMediaTokWave7Tools.isVoiceConfirmEnabled ? "✓" : ""
        let fakePart = GGMediaTokWave7Tools.fakeVoiceDurationSeconds != 0 ? GGMediaTokWave7Tools.fakeVoiceDurationLabel : ""
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
        GGMediaTokWave7Tools.runStartupSafeModeGuard()

        // Chat inline commands: .cmd / .spot (Spotlight), .lyrics (LRC Lyrics), .reconnect (Force Reconnect), .whatsnew
        GGChatScreenHooks.willSendText.register({ request, _ in
            return GGMediaTokWave7Tools.interceptCommands(request)
        }, order: 26)

        // Send button long-press menu: Spotlight, LRC Lyrics, Force Reconnect, Voice Settings
        GGChatScreenHooks.sendMenuItems.register({ sendContext in
            return GGMediaTokWave7Tools.sendMenuItems(sendContext)
        }, order: 78)
    }

    // MARK: - #493 Safe Mode

    private static func runStartupSafeModeGuard() {
        guard !GGMediaTokWave7Tools.hasCheckedSafeMode else { return }
        GGMediaTokWave7Tools.hasCheckedSafeMode = true

        let defaults = UserDefaults.standard
        let streak = defaults.integer(forKey: GGMediaTokWave7Tools.safeModeStreakKey) + 1
        if streak >= 3 {
            GGMediaTokWave7Tools.safeModeActivatedOnLaunch = true
            GGMediaTokWave7Tools.applySafeModeVisualReset()
            defaults.set(0, forKey: GGMediaTokWave7Tools.safeModeStreakKey)
        } else {
            defaults.set(streak, forKey: GGMediaTokWave7Tools.safeModeStreakKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
                UserDefaults.standard.set(0, forKey: GGMediaTokWave7Tools.safeModeStreakKey)
            }
        }
    }

    public static func applySafeModeVisualReset() {
        GGAppearanceSettings.fontFamily.set("system")
        GGAppearanceSettings.chatTextFont.set("")
        GGAppearanceSettings.edgeStyle.set(GGEdgeStyle.off.rawValue)
        GGAppearanceSettings.chatBackground.set(false)
        GGAppearanceSettings.profileBackground.set(false)
        GGAppearanceSettings.snow.set(false)
        GGAppearanceSettings.bubbleEditor.set(false)
    }

    public static func presentSafeModeConfirmation(context: AccountContext) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "🛡️ Безопасный режим (Safe Mode)",
                message: "Сбросит кастомный шрифт на системный SF Pro и отключит видео-обои чата/профиля, снег и редактор пузырей. Ваши чаты, подарки и стикеры не пострадают.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Сбросить визуал (Safe Mode)", style: .destructive, handler: { _ in
                GGMediaTokWave7Tools.applySafeModeVisualReset()
                UserDefaults.standard.set(0, forKey: GGMediaTokWave7Tools.safeModeStreakKey)
                GGMediaTokWave5Tools.showToast(context: context, text: "🛡️ Safe Mode применён: шрифт и видео-обои сброшены")
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            GGMediaTokWave5Tools.presentOnRoot(alert)
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
        GGMediaTokWave5Tools.showToast(context: context, text: "🔄 Переподключение к серверам Telegram...")
    }

    // MARK: - #379 Confirm Voice Send & #377 Fake Voice Duration

    public static func presentVoiceToolsSheet(context: AccountContext) {
        DispatchQueue.main.async {
            let confirmState = GGMediaTokWave7Tools.isVoiceConfirmEnabled ? "ВКЛ" : "ВЫКЛ"
            let fakeState = GGMediaTokWave7Tools.fakeVoiceDurationLabel
            let sheet = UIAlertController(
                title: "🎙 Инструменты голосовых (ГС)",
                message: "Подтверждение отправки: \(confirmState)\nФейк-длительность ГС: \(fakeState)",
                preferredStyle: .actionSheet
            )

            let toggleTitle = GGMediaTokWave7Tools.isVoiceConfirmEnabled
                ? "✅ Подтверждать отправку ГС: ВКЛ (выключить)"
                : "☑️ Подтверждать отправку ГС: ВЫКЛ (включить)"
            sheet.addAction(UIAlertAction(title: toggleTitle, style: .default, handler: { _ in
                GGMediaTokWave7Tools.isVoiceConfirmEnabled.toggle()
                let st = GGMediaTokWave7Tools.isVoiceConfirmEnabled ? "ВКЛ" : "ВЫКЛ"
                GGMediaTokWave5Tools.showToast(context: context, text: "🎙 Подтверждение отправки ГС: \(st)")
            }))

            sheet.addAction(UIAlertAction(title: "⏱ Фейк-длительность: Выкл (реальная)", style: .default, handler: { _ in
                GGMediaTokWave7Tools.fakeVoiceDurationSeconds = 0
                GGMediaTokWave5Tools.showToast(context: context, text: "⏱ Фейк-длительность ГС отключена")
            }))
            sheet.addAction(UIAlertAction(title: "⏱ Фейк-длительность: 0:00", style: .default, handler: { _ in
                GGMediaTokWave7Tools.fakeVoiceDurationSeconds = -1
                GGMediaTokWave5Tools.showToast(context: context, text: "⏱ Длительность ГС: 0:00")
            }))
            sheet.addAction(UIAlertAction(title: "⏱ Фейк-длительность: 1:00", style: .default, handler: { _ in
                GGMediaTokWave7Tools.fakeVoiceDurationSeconds = 60
                GGMediaTokWave5Tools.showToast(context: context, text: "⏱ Длительность ГС: 1:00")
            }))
            sheet.addAction(UIAlertAction(title: "⏱ Фейк-длительность: 59:59", style: .default, handler: { _ in
                GGMediaTokWave7Tools.fakeVoiceDurationSeconds = 3599
                GGMediaTokWave5Tools.showToast(context: context, text: "⏱ Длительность ГС: 59:59")
            }))
            sheet.addAction(UIAlertAction(title: "⏱ Фейк-длительность: 99:59", style: .default, handler: { _ in
                GGMediaTokWave7Tools.fakeVoiceDurationSeconds = 5999
                GGMediaTokWave5Tools.showToast(context: context, text: "⏱ Длительность ГС: 99:59")
            }))
            sheet.addAction(UIAlertAction(title: "✏️ Своя длительность (в секундах)...", style: .default, handler: { _ in
                GGMediaTokWave7Tools.presentCustomFakeDurationAlert(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))

            GGMediaTokWave7Tools.configurePopoverIfNeeded(sheet)
            GGMediaTokWave5Tools.presentOnRoot(sheet)
        }
    }

    private static func presentCustomFakeDurationAlert(context: AccountContext) {
        let alert = UIAlertController(
            title: "⏱ Своя длительность ГС",
            message: "Введите число секунд (например: 5999 для 99:59, 0 — выключить):",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.keyboardType = .numberPad
            tf.placeholder = "5999"
            let cur = GGMediaTokWave7Tools.fakeVoiceDurationSeconds
            if cur > 0 {
                tf.text = "\(cur)"
            }
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
            let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let seconds = Int(raw), seconds >= 0 {
                let clamped = min(seconds, 86399)
                GGMediaTokWave7Tools.fakeVoiceDurationSeconds = clamped
                GGMediaTokWave5Tools.showToast(context: context, text: "⏱ Фейк-длительность ГС: \(GGMediaTokWave7Tools.fakeVoiceDurationLabel)")
            } else {
                GGMediaTokWave5Tools.showToast(context: context, text: "Введите корректное число секунд")
            }
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGMediaTokWave5Tools.presentOnRoot(alert)
    }

    // MARK: - #491 What's New & #492 Report Bug / Idea

    public static func presentWhatsNew(context: AccountContext) {
        UserDefaults.standard.set(GGMediaTokWave7Tools.currentBuildNumber, forKey: GGMediaTokWave7Tools.whatsNewLastSeenKey)
        DispatchQueue.main.async {
            let safeBadge = GGMediaTokWave7Tools.safeModeActivatedOnLaunch
                ? "\n⚠️ В этом запуске сработал Safe Mode — проверь шрифт/обои."
                : ""
            let body = """
            MediaTok iOS • Build b\(GGMediaTokWave7Tools.currentBuildNumber) (Волны 1 + 2):

            • 🪞 Примерочная профиля (Sandbox) — живой превью темы, рамки, эффекта, погоды и статуса до сохранения
            • 📱 Красивый градиентный QR-код профиля с бейджем MediaTok
            • 📦 Скачивание любого стикерпака в ZIP-архив (долгое нажатие на стикер)
            • 🔎 Обратный поиск фото (Google Lens / Yandex / SauceNAO) из меню фото
            • 😶‍🌫️ Размытие лиц на фото в 1 тап через Apple Vision AI
            • 📄 Сканер документов → PDF + ✍️ Подпись PDF пальцем
            • 🌤 Живая погода города в профиле (Open-Meteo) + 🔋 Спуфинг батареи
            • 🔍 Spotlight + 🎵 LRC-тексты песен + 🔄 Force Reconnect + 🎙 ГС + 🛡️ Safe Mode\(safeBadge)
            """
            let alert = UIAlertController(title: "✨ Что нового в MediaTok b\(GGMediaTokWave7Tools.currentBuildNumber)", message: body, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "🐛 Сообщить о баге / идее", style: .default, handler: { _ in
                GGMediaTokWave7Tools.presentFeedbackSheet(context: context)
            }))
            alert.addAction(UIAlertAction(title: "Отлично!", style: .cancel))
            GGMediaTokWave5Tools.presentOnRoot(alert)
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
        let stickerCount = GGStickerVaultStore.shared.count
        let e2eCount = GGMediaTokE2E.activeCount
        return """
        --- MediaTok Diagnostics ---
        Build: MediaTok iOS \(appVer) (b\(GGMediaTokWave7Tools.currentBuildNumber))
        Device: \(machine) | iOS \(iosVer) | RAM: \(ramGB) | Battery: \(GGMediaTokWave8Tools.effectiveBatteryDescription)
        SafeModeOnLaunch: \(GGMediaTokWave7Tools.safeModeActivatedOnLaunch)
        VoiceConfirm: \(GGMediaTokWave7Tools.isVoiceConfirmEnabled) | FakeVoice: \(GGMediaTokWave7Tools.fakeVoiceDurationLabel)
        StickerVault: \(stickerCount) | ActiveE2E: \(e2eCount) | AdBlock: \(GGMediaTokWave6Tools.isAdBlockEnabled)
        ----------------------------
        """
    }

    public static func presentFeedbackSheet(context: AccountContext) {
        DispatchQueue.main.async {
            let diag = GGMediaTokWave7Tools.buildDiagnosticsSummary()
            UIPasteboard.general.string = diag
            let alert = UIAlertController(
                title: "🐛 Сообщить о баге / идее",
                message: "Диагностика скопирована в буфер обмена!\n\n\(diag)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "📤 Поделиться диагностикой", style: .default, handler: { _ in
                let share = UIActivityViewController(activityItems: [diag], applicationActivities: nil)
                GGMediaTokWave7Tools.configurePopoverIfNeeded(share)
                GGMediaTokWave5Tools.presentOnRoot(share)
            }))
            alert.addAction(UIAlertAction(title: "Готово", style: .cancel))
            GGMediaTokWave5Tools.presentOnRoot(alert)
        }
    }

    // MARK: - #490 Spotlight Command Palette Launcher

    public static func presentSpotlightPalette(accountContext: AccountContext, menuContext: GGMenuContext? = nil) {
        DispatchQueue.main.async {
            let vc = GGSpotlightPaletteController(accountContext: accountContext, menuContext: menuContext)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            GGMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    // MARK: - #371 Synced LRC Lyrics Launcher

    public static func presentLyricsViewer(context: AccountContext, initialQuery: String? = nil) {
        DispatchQueue.main.async {
            let vc = GGLyricsViewController(context: context, initialQuery: initialQuery)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            GGMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    // MARK: - Quick Tools Sheet (for Settings quick row)

    public static func presentWave7QuickHub(context: GGMenuContext) {
        DispatchQueue.main.async {
            let sheet = UIAlertController(
                title: "⚡ Инструменты MediaTok b\(GGMediaTokWave7Tools.currentBuildNumber)",
                message: "Сеть, голосовые (ГС), тексты песен, диагностика и Safe Mode",
                preferredStyle: .actionSheet
            )
            sheet.addAction(UIAlertAction(title: "🔍 Палитра команд (Spotlight)", style: .default, handler: { _ in
                GGMediaTokWave7Tools.presentSpotlightPalette(accountContext: context.context, menuContext: context)
            }))
            sheet.addAction(UIAlertAction(title: "🎵 Текст песни (LRC)", style: .default, handler: { _ in
                GGMediaTokWave7Tools.presentLyricsViewer(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "🔄 Переподключить сеть (Force Reconnect)", style: .default, handler: { _ in
                GGMediaTokWave7Tools.forceReconnect(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "🎙 Голосовые: Подтверждение / Фейк-длительность", style: .default, handler: { _ in
                GGMediaTokWave7Tools.presentVoiceToolsSheet(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "✨ Что нового в b\(GGMediaTokWave7Tools.currentBuildNumber)", style: .default, handler: { _ in
                GGMediaTokWave7Tools.presentWhatsNew(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "🐛 Сообщить о баге / идее", style: .default, handler: { _ in
                GGMediaTokWave7Tools.presentFeedbackSheet(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "🛡️ Безопасный режим (Safe Mode)", style: .destructive, handler: { _ in
                GGMediaTokWave7Tools.presentSafeModeConfirmation(context: context.context)
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))

            GGMediaTokWave7Tools.configurePopoverIfNeeded(sheet)
            GGMediaTokWave5Tools.presentOnRoot(sheet)
        }
    }

    // MARK: - Inline Commands & Send Menu

    private static func interceptCommands(_ request: GGComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let lower = raw.lowercased()

        if lower == ".cmd" || lower == ".spot" || lower == ".spotlight" {
            request.replace(ChatTextInputState())
            GGMediaTokWave7Tools.presentSpotlightPalette(accountContext: request.context, menuContext: nil)
            return true
        }

        if lower == ".reconnect" || lower == ".reconn" {
            request.replace(ChatTextInputState())
            GGMediaTokWave7Tools.forceReconnect(context: request.context)
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
            GGMediaTokWave7Tools.presentLyricsViewer(context: request.context, initialQuery: (query?.isEmpty ?? true) ? nil : query)
            return true
        }

        if lower == ".whatsnew" {
            request.replace(ChatTextInputState())
            GGMediaTokWave7Tools.presentWhatsNew(context: request.context)
            return true
        }

        return false
    }

    private static func sendMenuItems(_ sendContext: GGSendMenuContext) -> [ContextMenuItem] {
        var entries: [ContextMenuItem] = []
        let ctx = sendContext.context
        let dismiss = sendContext.dismiss

        entries.append(.action(ContextMenuActionItem(
            text: "🔍 Палитра команд MediaTok",
            icon: { theme in
                return UIImage(systemName: "magnifyingglass")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                GGMediaTokWave7Tools.presentSpotlightPalette(accountContext: ctx, menuContext: nil)
            }
        )))

        entries.append(.action(ContextMenuActionItem(
            text: "🎵 Текст песни (LRC)",
            icon: { theme in
                return UIImage(systemName: "music.note.list")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                GGMediaTokWave7Tools.presentLyricsViewer(context: ctx)
            }
        )))

        entries.append(.action(ContextMenuActionItem(
            text: "🔄 Переподключить сеть",
            icon: { theme in
                return UIImage(systemName: "arrow.triangle.2.circlepath")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                GGMediaTokWave7Tools.forceReconnect(context: ctx)
            }
        )))

        entries.append(.action(ContextMenuActionItem(
            text: "🎙 ГС: Подтверждение / 99:59",
            icon: { theme in
                return UIImage(systemName: "mic.badge.plus")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                GGMediaTokWave7Tools.presentVoiceToolsSheet(context: ctx)
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

private struct GGSpotlightCommandItem {
    let icon: String
    let title: String
    let subtitle: String
    let keywords: String
    let action: () -> Void
}

public final class GGSpotlightPaletteController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let accountContext: AccountContext
    private let menuContext: GGMenuContext?
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var allItems: [GGSpotlightCommandItem] = []
    private var filteredItems: [GGSpotlightCommandItem] = []

    public init(accountContext: AccountContext, menuContext: GGMenuContext?) {
        self.accountContext = accountContext
        self.menuContext = menuContext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🔍 MediaTok Spotlight"
        self.view.backgroundColor = UIColor(white: 0.08, alpha: 1.0)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Закрыть",
            style: .done,
            target: self,
            action: #selector(self.closeTapped)
        )

        self.searchBar.placeholder = "Поиск фич: lrc, гс, сеть, nft, эмодзи, safe..."
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.delegate = self
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.searchBar)

        self.tableView.backgroundColor = .clear
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.keyboardDismissMode = .onDrag
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

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.searchBar.becomeFirstResponder()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    private func runAfterDismiss(_ block: @escaping () -> Void) {
        self.dismiss(animated: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                block()
            }
        }
    }

    private func buildItems() {
        let ctx = self.accountContext
        let mCtx = self.menuContext
        var items: [GGSpotlightCommandItem] = []

        items.append(GGSpotlightCommandItem(
            icon: "🕵️‍♂️",
            title: "Призрачный Сейф-Фото (Стеганография)",
            subtitle: "Спрячь или извлеки секретный текст прямо из пикселей PNG (.stego)",
            keywords: "stego стеганография секрет фото png 501",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave12Tools.presentStegoStudio(context: ctx, initialImage: nil)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🎛",
            title: "Голос-Студия FX (Диктор / Рация / Демон)",
            subtitle: "Изменение голоса в реальном времени и рендер .m4a (.vfx)",
            keywords: "vfx voice голос демон рация диктор робот бурундук 502",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave12Tools.presentVoiceFxStudio(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🔥",
            title: "Сгорающая AES-256 записка с PIN и TTL",
            subtitle: "Одноразовый секрет с таймером 10с и самоуничтожением (.burn)",
            keywords: "burn бомба записка pin aes секрет 503",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave12Tools.presentBurnNoteComposer(context: ctx, peerId: nil)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🎬",
            title: "Кино-карточка цитат (1:1 / 9:16 / 16:9)",
            subtitle: "Стеклянная карточка в стиле Apple Keynote / Ray.so в HD PNG (.cinematic)",
            keywords: "cinematic карточка цитата скриншот stories 504",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave12Tools.presentCinematicCard(context: ctx, initialText: nil, author: nil)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🔬",
            title: "OSINT-Рентген (EXIF / GPS / Фишинг-ссылки)",
            subtitle: "Анализ камеры/GPS в фото и проверка редиректов/спуфинга ссылок (.xray)",
            keywords: "xray osint exif gps фишинг ссылка редирект 505",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave12Tools.presentOsintXRay(context: ctx, initialUrl: nil, initialImageData: nil)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🈳",
            title: "Переводчик текста на фото / манге (OCR)",
            subtitle: "Распознавание облачков текста и перевод поверх картинки (.trimg)",
            keywords: "ocr манга перевод фото translate image 479",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave11Tools.presentImageTranslator(context: ctx, initialImage: nil, peerId: nil)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🪄",
            title: "Magic Eraser — умный ластик на фото",
            subtitle: "Стирание лишних объектов и водяных знаков пальцем (.erase)",
            keywords: "eraser ластик стереть объект фото 481",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave11Tools.presentMagicEraser(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "✨",
            title: "4K Upscale & Enhance фото",
            subtitle: "Увеличение разрешения 2×/4× и повышение резкости (.upscale)",
            keywords: "upscale 4k апскейл качество резкость фото 482",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave11Tools.presentUpscaler(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🎮",
            title: "Мини-игры: Крестики-нолики & 2048",
            subtitle: "Синхронизация ходов в чате между клиентами MediaTok (.game)",
            keywords: "игры game крестики нолики 2048 467",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave11Tools.presentMiniGames(context: ctx, peerId: nil, initialTab: 0)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "📰",
            title: "Встроенный RSS-ридер",
            subtitle: "Чтение RSS/Atom лент (Habr, HN, Apple и свои) + репост в чат (.rss)",
            keywords: "rss новости ридер ленты 470",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave11Tools.presentRssReader(context: ctx, peerId: nil)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "📋",
            title: "Общий буфер обмена Телефон ↔ ПК",
            subtitle: "Мгновенная синхронизация текста между iPhone и Windows (.pcclip / .syncclip)",
            keywords: "clipboard буфер пк windows sync pcclip syncclip 419",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave11Tools.presentSharedClipboard(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "⚡️",
            title: "Siri / Команды, Виджеты, iPad-клавиши, Миграция",
            subtitle: "URL-схемы mediatok://, Widget JSON, авто-миграция базы (.shortcuts)",
            keywords: "siri shortcuts команды виджеты клавиатура миграция 487 488 489 494",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave11Tools.presentEcosystemHub(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🎨",
            title: "Конструктор стикерпаков (512×512 PNG)",
            subtitle: "Скруглённый стикер с белой обводкой для @Stickers (.makesticker)",
            keywords: "sticker стикер конструктор 512 png 456",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave10Tools.presentStickerMaker(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🧩",
            title: "Mini Apps Power Pack (#451–#455)",
            subtitle: "Блок fullscreen/вибрации, подмена платформы, мульти-окна, автокликер, DevTools",
            keywords: "miniapps миниапп fullscreen платформа автокликер devtools 451 452 453 454 455",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave10Tools.presentMiniAppsStudio(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🎙",
            title: "Пресеты Voicemod (Экспорт / Импорт)",
            subtitle: "Обмен JSON-пресетами голоса (#380)",
            keywords: "voicemod пресеты голос экспорт импорт 380",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave10Tools.presentVoicemodPresetsSheet(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "📡",
            title: "Спидтест DC1–DC5 и монитор сети",
            subtitle: "Замер пинга дата-центров Telegram, Catbox CDN и ntfy (.dc)",
            keywords: "dc speedtest ping сеть замер пинг датацентр 406 415",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave9Tools.presentDcSpeedtest(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🌐",
            title: "Сеть, VPN-слот, Аккаунты (∞) и Sync v2",
            subtitle: "Split Tunneling, прокси на аккаунт, клонирование, DoH, SHA-256 (.vpn)",
            keywords: "vpn split tunnel proxy прокси аккаунты клон sync doh sha256 401 402 422 423 495 417",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave9Tools.presentWave3NetworkHub(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🪞",
            title: "Примерочная профиля (MediaTok Sandbox)",
            subtitle: "Живой превью темы, рамки, эффекта, статуса и погоды до сохранения (.sandbox)",
            keywords: "sandbox примерочная профиль превью баннер рамка 499",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave8Tools.presentProfileSandbox(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "📱",
            title: "Красивый QR-код профиля",
            subtitle: "Градиентная QR-карточка с бейджем MediaTok (.myqr)",
            keywords: "qr код профиль карточка градиент 466",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave8Tools.presentProfileQR(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "😶‍🌫️",
            title: "Размытие лиц на фото (Apple Vision)",
            subtitle: "Автоматический поиск и размытие лиц в 1 тап (.blurface)",
            keywords: "blur face лица размытие фото приватность 460",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave8Tools.presentFaceBlurPicker(context: ctx, targetPeerId: nil)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "📄",
            title: "Сканер документов → PDF",
            subtitle: "Сканирование камерой в многостраничный PDF (.scanpdf)",
            keywords: "scan pdf скан документ камера 461",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave8Tools.presentDocumentScanner(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "✍️",
            title: "Подписать PDF пальцем",
            subtitle: "Наложение рукописной подписи на любой PDF (.signpdf)",
            keywords: "sign pdf подпись документ 462",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave8Tools.presentPdfFilePickerForSignature(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🌤",
            title: "Живая погода в профиле (Open-Meteo)",
            subtitle: "Подбор эффекта и статуса под погоду твоего города (.weather)",
            keywords: "weather погода город дождь снег солнце 497",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave8Tools.presentWeatherSetup(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🔋",
            title: "Спуфинг батареи и зарядки",
            subtitle: "Подмена процента заряда в системных отчётах MediaTok",
            keywords: "battery spoof батарея зарядка спуфинг 486",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave8Tools.presentBatterySpoofSheet(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🎵",
            title: "Текст песни (LRC Караоке)",
            subtitle: "Синхронизация с плеером Telegram через lrclib.net (.lyrics)",
            keywords: "lyrics lrc музыка текст песни караоке спотифай spotify 371",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave7Tools.presentLyricsViewer(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🔄",
            title: "Переподключить сеть (Force Reconnect)",
            subtitle: "Мгновенный сброс зависшего соединения Telegram (.reconnect)",
            keywords: "reconnect сеть интернет сброс переподключить пинг 416",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave7Tools.forceReconnect(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🎙",
            title: "Голосовые (ГС): Подтверждение и 99:59",
            subtitle: "Подтверждать отправку ГС и настраивать фейк-длительность",
            keywords: "voice гс голосовое подтверждение 99:59 длительность 377 379",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave7Tools.presentVoiceToolsSheet(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "✨",
            title: "Визуальный профиль 4K (Discord Studio)",
            subtitle: "Баннер 4K, рамка аватара, эффекты, музыка, Steam/Roblox",
            keywords: "profile профиль баннер рамка эффект discord 4k музыка",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        GGMediaTokDiscordProfile.presentOwnEditor(context: mCtx)
                    } else {
                        GGMediaTokDiscordProfile.presentEditor(peerId: ctx.account.peerId, isOwn: true, onDone: nil)
                    }
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🎬",
            title: "TikTok-лента каналов",
            subtitle: "Вертикальная свайп-лента видео и кружков из каналов",
            keywords: "tiktok reels shorts лента видео кружки",
            action: { [weak self] in
                self?.runAfterDismiss {
                    let feed = GGTikTokFeedViewController(context: ctx, navigationController: mCtx?.navigationController)
                    GGMediaTokWave5Tools.presentOnRoot(feed)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🎭",
            title: "/stickers — База 10к стикеров + ИИ",
            subtitle: "Быстрый поиск, OCR и загрузка папок по Wi-Fi",
            keywords: "stickers стикеры поиск ии wifi база",
            action: { [weak self] in
                self?.runAfterDismiss {
                    if let mCtx {
                        GGMediaTokStickerVault.presentManagerFromMenu(context: mCtx)
                    } else {
                        GGMediaTokStickerVault.presentPicker(context: ctx, targetPeerId: nil, initialQuery: "")
                    }
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🏆",
            title: "Достижения MediaTok",
            subtitle: "Ранги, бейджи и статистика",
            keywords: "achievements достижения ачивки ранг",
            action: { [weak self] in
                self?.runAfterDismiss {
                    let vc = GGAchievementsViewController()
                    vc.overrideUserInterfaceStyle = .dark
                    let nav = UINavigationController(rootViewController: vc)
                    nav.overrideUserInterfaceStyle = .dark
                    GGMediaTokWave5Tools.presentOnRoot(nav)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "📱",
            title: "Редактор нижнего бара",
            subtitle: "Пресеты таббара, парящий бар, скрыть вкладки",
            keywords: "tabbar таббар бар нижняя панель 110",
            action: { [weak self] in
                self?.runAfterDismiss {
                    let vc = GGBottomBarStudioViewController()
                    vc.overrideUserInterfaceStyle = .dark
                    let nav = UINavigationController(rootViewController: vc)
                    nav.overrideUserInterfaceStyle = .dark
                    GGMediaTokWave5Tools.presentOnRoot(nav)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🔥",
            title: "Огоньки чатов (Топ серий)",
            subtitle: "Активные серии переписок и заморозки",
            keywords: "streaks огоньки серии рейтинг",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave5Tools.presentStreaksLeaderboard(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🎮",
            title: "Мини-игры MediaTok",
            subtitle: "2048, Сапёр 8x8 и аркады без интернета",
            keywords: "games игры 2048 сапер minesweeper",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave5Tools.presentMiniGamesHub()
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "⚡",
            title: "Сниппеты / Макросы (.sn)",
            subtitle: "Сохранённые быстрые шаблоны текста",
            keywords: "snippets сниппеты макросы шаблоны sn",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave6Tools.presentSnippetsSheet(context: ctx, onPick: nil)
                }
            }
        ))

        if let mCtx {
            items.append(GGSpotlightCommandItem(
                icon: "🌟",
                title: "Премиум Эмодзи (без подписки)",
                subtitle: "Клавиатура, отправка в чатах и эмодзи-статус",
                keywords: "emoji premium эмодзи премиум статус",
                action: { [weak self] in
                    self?.runAfterDismiss {
                        GGMediaTokWave5Tools.presentPremiumEmojiSheet(context: mCtx)
                    }
                }
            ))
            items.append(GGSpotlightCommandItem(
                icon: "🧊",
                title: "Liquid Glass / Zero-Bloat / 4K 60fps",
                subtitle: "Стекло iOS 27, компактный чат, стиль галочек, видео 4K",
                keywords: "liquid glass стекло 4k 60fps bloat галочки",
                action: { [weak self] in
                    self?.runAfterDismiss {
                        GGMediaTokLiquidUI.presentStudio(context: mCtx)
                    }
                }
            ))
            items.append(GGSpotlightCommandItem(
                icon: "🌍",
                title: "Студия языков (66+ пакетов)",
                subtitle: "Языковые пакеты и живой редактор всех строк",
                keywords: "lang языки перевод строки редактор",
                action: { [weak self] in
                    self?.runAfterDismiss {
                        GGMediaTokLangs.presentStudio(context: mCtx)
                    }
                }
            ))
            items.append(GGSpotlightCommandItem(
                icon: "🔐",
                title: "E2E Шифрование (AES-256-GCM)",
                subtitle: "Управление ключами шифрования чатов",
                keywords: "e2e aes шифрование ключ приватность",
                action: { [weak self] in
                    self?.runAfterDismiss {
                        GGMediaTokE2E.presentManager(context: mCtx)
                    }
                }
            ))
            items.append(GGSpotlightCommandItem(
                icon: "🔊",
                title: "Anti-Screamer / Фильтр громких звуков",
                subtitle: "Защита от скримеров и резких звуков",
                keywords: "screamer аудио звук защита фильтр",
                action: { [weak self] in
                    self?.runAfterDismiss {
                        GGMediaTokAudioGuard.presentSettings(context: mCtx)
                    }
                }
            ))
            items.append(GGSpotlightCommandItem(
                icon: "🔤",
                title: "Шрифты приложения и чата",
                subtitle: "Кастомные TTF/OTF шрифты и 32 стиля текста",
                keywords: "font шрифт ttf otf стиль текст",
                action: { [weak self] in
                    self?.runAfterDismiss {
                        mCtx.open(tab: GGAppearanceMenu.fontTab)
                    }
                }
            ))
            items.append(GGSpotlightCommandItem(
                icon: "🩺",
                title: "MediaTok Wrapped и Диагностика",
                subtitle: "Итоги статистики, статус модулей и защита от плеча",
                keywords: "wrapped итоги диагностика privacy статистика",
                action: { [weak self] in
                    self?.runAfterDismiss {
                        GGMediaTokWave6Tools.presentWrappedAndDiagnostics(context: mCtx)
                    }
                }
            ))
        }

        items.append(GGSpotlightCommandItem(
            icon: "📞",
            title: "Защита от случайных звонков (Call Guard)",
            subtitle: GGMediaTokWave6Tools.isCallConfirmEnabled ? "Сейчас: ВКЛ — нажми чтобы переключить" : "Сейчас: ВЫКЛ — нажми чтобы переключить",
            keywords: "call guard звонки подтверждение защита",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave6Tools.isCallConfirmEnabled.toggle()
                    let st = GGMediaTokWave6Tools.isCallConfirmEnabled ? "ВКЛ" : "ВЫКЛ"
                    GGMediaTokWave5Tools.showToast(context: ctx, text: "📞 Защита звонков: \(st)")
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🚫",
            title: "Анти-реклама каналов (#188)",
            subtitle: GGMediaTokWave6Tools.isAdBlockEnabled ? "Сейчас: ВКЛ — нажми чтобы переключить" : "Сейчас: ВЫКЛ — нажми чтобы переключить",
            keywords: "adblock реклама erid каналы блок",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave6Tools.isAdBlockEnabled.toggle()
                    let st = GGMediaTokWave6Tools.isAdBlockEnabled ? "ВКЛ" : "ВЫКЛ"
                    GGMediaTokWave5Tools.showToast(context: ctx, text: "🚫 Анти-реклама каналов: \(st)")
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "✨",
            title: "Что нового в MediaTok b\(GGMediaTokWave7Tools.currentBuildNumber)",
            subtitle: "Список изменений текущей сборки",
            keywords: "whatsnew changelog нового обновление билд 491",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave7Tools.presentWhatsNew(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🐛",
            title: "Сообщить о баге / идее",
            subtitle: "Копирует диагностику устройства и сборки",
            keywords: "bug feedback баг идея диагностика репорт 492",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave7Tools.presentFeedbackSheet(context: ctx)
                }
            }
        ))

        items.append(GGSpotlightCommandItem(
            icon: "🛡️",
            title: "Безопасный режим (Safe Mode)",
            subtitle: "Сброс шрифта и видео-обоев без потери данных",
            keywords: "safe mode безопасный режим краш сброс 493",
            action: { [weak self] in
                self?.runAfterDismiss {
                    GGMediaTokWave7Tools.presentSafeModeConfirmation(context: ctx)
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
        let reuseId = "GGSpotlightCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseId)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseId)
        let item = self.filteredItems[indexPath.row]
        cell.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        cell.textLabel?.text = "\(item.icon)  \(item.title)"
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
}

// MARK: - #371 Synced LRC Lyrics (`lrclib.net`)

private struct GGSyncedLrcLine {
    let time: Double
    let text: String
}

private enum GGLrcParser {
    static func parse(_ raw: String) -> [GGSyncedLrcLine] {
        var result: [GGSyncedLrcLine] = []
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
                result.append(GGSyncedLrcLine(time: time, text: display))
            }
        }
        result.sort { $0.time < $1.time }
        return result
    }
}

public final class GGLyricsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let initialQuery: String?

    private let headerLabel = UILabel()
    private let statusLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var playerDisposable: Disposable?
    private var syncTimer: Foundation.Timer?
    private var latestStatus: MediaPlayerStatus?
    private var currentTrackKey: String = ""
    private var syncedLines: [GGSyncedLrcLine] = []
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
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🎵 Текст песни (LRC)"
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
            self.statusLabel.text = "Включи музыку в Telegram или нажми 🔍 для поиска"
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
        }
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func copyTapped() {
        guard !self.rawLyricsText.isEmpty else {
            GGMediaTokWave5Tools.showToast(context: self.context, text: "Текст ещё не загружен")
            return
        }
        UIPasteboard.general.string = self.rawLyricsText
        GGMediaTokWave5Tools.showToast(context: self.context, text: "📋 Текст песни скопирован")
    }

    @objc private func searchTapped() {
        let alert = UIAlertController(
            title: "🔍 Найти текст песни",
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
        req.setValue("MediaTok-iOS/\(GGMediaTokWave7Tools.currentBuildNumber) (https://github.com/ownersavesociety)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
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
                    self.statusLabel.text = "Текст не найден на lrclib.net — попробуй поиск 🔍"
                }
            }
        }.resume()
    }

    private func applyLrclibEntry(_ dict: [String: Any]) -> Bool {
        let trackName = dict["trackName"] as? String ?? ""
        let artistName = dict["artistName"] as? String ?? ""
        if !trackName.isEmpty {
            self.headerLabel.text = artistName.isEmpty ? trackName : "\(artistName) — \(trackName)"
        }

        if let synced = dict["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = GGLrcParser.parse(synced)
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
        let reuseId = "GGLyricsLineCell"
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
