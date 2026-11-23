import Foundation
import UIKit
import Vision
import CoreImage
import ImageIO
import CryptoKit
import Security
import SafariServices
#if canImport(WidgetKit)
import WidgetKit
#endif
import Photos
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

private final class MTThreadSafeArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element]

    init(repeating value: Element, count: Int) {
        self.storage = Array(repeating: value, count: count)
    }

    func set(_ value: Element, at index: Int) {
        self.lock.lock()
        if index >= 0 && index < self.storage.count {
            self.storage[index] = value
        }
        self.lock.unlock()
    }

    func snapshot() -> [Element] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.storage
    }
}

// ============================================================================
// MediaTok Wave 11 (Roadmap Wave 5 — AI Media, Games, RSS, Clipboard, Ecosystem):
//   #479 — Image / Manga OCR + Translator (Vision + Gemini / GTX overlay)
//   #481 — Magic Eraser (finger mask + CoreImage feathered inpaint)
//   #482 — 4K Upscale & Enhance (Lanczos + UnsharpMask, safe 4096px cap)
//   #467 — Chat-Synced Mini-Games (Tic-Tac-Toe [MT:TTT] + playable 2048)
//   #470 — Built-in RSS / Atom Reader (XMLParser + presets + forward)
//   #419 — Universal Clipboard Phone <-> PC (push/pull + Windows PS snippet)
//   #487 — Widget Data Snapshot Bridge (App Group / UserDefaults JSON)
//   #488 — Siri & Apple Shortcuts URL Actions (mediatok://cmd?action=...)
//   #489 — Hardware Keyboard Shortcuts (iPad / Bluetooth KeyShortcutsController)
//   #494 — Versioned Auto-Migration Engine on Telegram base updates
// ============================================================================

public enum MTMediaTokWave11Tools {
    private static let schemaVersionKey = "mediatok.schema.version.v1"
    private static let currentSchemaVersion = 5
    private static let migrationLogKey = "mediatok.schema.migration_log.v1"
    private static let widgetSnapshotKey = "mediatok.widget.snapshot.v1"
    private static let rssFeedsKey = "mediatok.rss.feeds.v1"
    private static let clipboardTopicKey = "mediatok.clipboard.topic.v1"
    private static let clipboardPassphraseKey = "mediatok.clipboard.passphrase.v1"
    private static let best2048Key = "mediatok.game.2048.best.v1"
    private static let activePhotoFetchDisposable = MetaDisposable()

    public static func register() {
        runSchemaMigrationIfNeeded()
        refreshWidgetSnapshot()

        // Dot commands for Wave 5
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave11Tools.interceptCommands(request)
        }, order: 33)

        // Message context menu: #479 Translate text on photo (OCR + overlay)
        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave11Tools.messageMenuItems(menuContext)
        }, order: 93)

        // #488 Siri & Apple Shortcuts URL routing (mediatok://cmd?action=...) — order 1100 so MTExtrasRoutes (900) and MTTelegramUIHooks (1000) run first
        MTLifecycleHooks.openURL.register({ url, context, _ in
            return MTMediaTokWave11Tools.handleShortcutURL(url, context: context)
        }, order: 1100)

        // #489 Hardware Keyboard Shortcuts (⇧⌘K Spotlight, ⇧⌘R Force Reconnect, ⇧⌘L Lyrics)
        MTLifecycleHooks.keyShortcuts.register({ context in
            return MTMediaTokWave11Tools.keyShortcuts(context: context)
        }, order: 850)
    }

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let trimmed = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(".") else { return false }
        let lower = trimmed.lowercased()
        let peerId = request.chatLocation.peerId
        if lower == ".trimg" || lower == ".manga" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentImageTranslator(context: request.context, initialImage: nil, peerId: peerId) }
            return true
        }
        if lower == ".erase" || lower == ".eraser" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentMagicEraser(context: request.context) }
            return true
        }
        if lower == ".upscale" || lower == ".4k" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentUpscaler(context: request.context) }
            return true
        }
        if lower == ".game" || lower == ".ttt" || lower == ".2048" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentMiniGames(context: request.context, peerId: peerId, initialTab: lower == ".2048" ? 1 : 0) }
            return true
        }
        if lower == ".rss" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentRssReader(context: request.context, peerId: peerId) }
            return true
        }
        if lower == ".pcclip" || lower == ".syncclip" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentSharedClipboard(context: request.context) }
            return true
        }
        if lower == ".shortcuts" || lower == ".siri" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentEcosystemHub(context: request.context) }
            return true
        }
        return false
    }

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        var hasPhoto = false
        for media in message.media {
            if media is TelegramMediaImage {
                hasPhoto = true
                break
            }
        }
        guard hasPhoto else { return [] }
        let context = menuContext.context
        return [
            MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Перевести текст на фото",
                icon: { theme in
                    return UIImage(systemName: "text.viewfinder")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave11Tools.translatePhotoFromMessage(context: context, message: message)
                }
            )))
        ]
    }

    // MARK: - #494 Auto-Migration Engine

    private static func generateSecureClipboardTopic() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var u = UUID().uuid
            bytes = withUnsafeBytes(of: &u) { Array($0) }
        }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "mtclip_\(hex)"
    }

    public static func sanitizedTopic(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12, trimmed.count <= 64 else { return nil }
        let ok = trimmed.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        return ok ? trimmed : nil
    }

    public static var migrationSummary: String {
        let ver = UserDefaults.standard.integer(forKey: schemaVersionKey)
        let log = UserDefaults.standard.string(forKey: migrationLogKey) ?? "Чистая установка v\(ver)"
        return "Схема v\(ver) • \(log)"
    }

    public static func runSchemaMigrationIfNeeded() {
        let ud = UserDefaults.standard
        let oldVersion = ud.integer(forKey: schemaVersionKey)
        guard oldVersion < currentSchemaVersion else { return }

        var notes: [String] = []
        if oldVersion < 2 {
            // Migrate legacy voice confirm key if present
            if ud.object(forKey: "mediatok.voice.confirm") != nil && ud.object(forKey: "mediatok.voice.confirm_send.v1") == nil {
                ud.set(ud.bool(forKey: "mediatok.voice.confirm"), forKey: "mediatok.voice.confirm_send.v1")
                notes.append("voice_confirm")
            }
        }
        if oldVersion < 4 {
            // Ensure default RSS feeds exist on first migration
            if ud.stringArray(forKey: rssFeedsKey) == nil {
                ud.set(defaultRssFeeds, forKey: rssFeedsKey)
                notes.append("rss_defaults")
            }
        }
        if oldVersion < 5 {
            // Ensure 128-bit CSPRNG clipboard topic exists
            let currentTopic = ud.string(forKey: clipboardTopicKey) ?? ""
            if sanitizedTopic(currentTopic) == nil || currentTopic.count < 24 {
                ud.set(generateSecureClipboardTopic(), forKey: clipboardTopicKey)
                notes.append("clip_topic")
            }
        }

        ud.set(currentSchemaVersion, forKey: schemaVersionKey)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let summary = notes.isEmpty ? "v\(oldVersion)->v\(currentSchemaVersion) (\(stamp))" : "v\(oldVersion)->v\(currentSchemaVersion): \(notes.joined(separator: ", "))"
        ud.set(summary, forKey: migrationLogKey)
    }

    // MARK: - #487 Widget Data Snapshot Bridge

    public static func refreshWidgetSnapshot() {
        let work = {
            let ud = UserDefaults.standard
            let snapshot: [String: Any] = [
                "updatedAt": Int64(Date().timeIntervalSince1970),
                "schemaVersion": currentSchemaVersion,
                "weatherCity": MTMediaTokWave8Tools.weatherCity,
                "batteryLabel": MTMediaTokWave8Tools.effectiveBatteryDescription,
                "best2048": ud.integer(forKey: best2048Key),
                "rssFeedCount": savedRssFeeds.count
            ]
            if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: []),
               let json = String(data: data, encoding: .utf8) {
                ud.set(json, forKey: widgetSnapshotKey)
                if let bundleId = Bundle.main.bundleIdentifier,
                   let groupDefaults = UserDefaults(suiteName: "group.\(bundleId)") {
                    groupDefaults.set(json, forKey: widgetSnapshotKey)
                }
                #if canImport(WidgetKit)
                if #available(iOS 14.0, *) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                #endif
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    public static var widgetSnapshotJson: String {
        refreshWidgetSnapshot()
        return UserDefaults.standard.string(forKey: widgetSnapshotKey) ?? "{}"
    }

    // MARK: - #488 Siri & Apple Shortcuts URL Handler

    @discardableResult
    public static func handleShortcutURL(_ url: URL, context: AccountContext) -> Bool {
        guard url.scheme?.lowercased() == "mediatok" else { return false }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let action = (comps?.queryItems?.first(where: { $0.name == "action" })?.value ?? url.host ?? "").lowercased()
        switch action {
        case "reconnect":
            MTMediaTokWave7Tools.forceReconnect(context: context)
            return true
        case "lyrics":
            MTMediaTokWave7Tools.presentLyricsViewer(context: context)
            return true
        case "sandbox":
            MTMediaTokWave8Tools.presentProfileSandbox(context: context)
            return true
        case "vpn":
            MTMediaTokWave9Tools.presentWave3NetworkHub(context: context)
            return true
        case "dc":
            MTMediaTokWave9Tools.presentDcSpeedtest(context: context)
            return true
        case "rss":
            presentRssReader(context: context, peerId: nil)
            return true
        case "clip", "pcclip", "syncclip":
            presentSharedClipboard(context: context)
            return true
        case "game":
            presentMiniGames(context: context, peerId: nil, initialTab: 0)
            return true
        case "trimg":
            presentImageTranslator(context: context, initialImage: nil, peerId: nil)
            return true
        case "erase":
            presentMagicEraser(context: context)
            return true
        case "upscale":
            presentUpscaler(context: context)
            return true
        case "cmd", "spotlight", "menu", "":
            MTMediaTokWave7Tools.presentSpotlightPalette(accountContext: context)
            return true
        default:
            return false
        }
    }

    // MARK: - #489 Hardware Keyboard Shortcuts (iPad / Bluetooth)

    public static func keyShortcuts(context: AccountContext) -> [KeyShortcut] {
        return [
            KeyShortcut(title: "MediaTok Spotlight Palette", input: "K", modifiers: [.command, .shift], action: {
                MTMediaTokWave7Tools.presentSpotlightPalette(accountContext: context)
            }),
            KeyShortcut(title: "MediaTok Force Reconnect", input: "R", modifiers: [.command, .shift], action: {
                MTMediaTokWave7Tools.forceReconnect(context: context)
            }),
            KeyShortcut(title: "MediaTok Караоке-лирика", input: "L", modifiers: [.command, .shift], action: {
                MTMediaTokWave7Tools.presentLyricsViewer(context: context)
            })
        ]
    }

    // MARK: - Persistent Helpers

    public static let defaultRssFeeds: [String] = [
        "https://habr.com/ru/rss/best/daily/",
        "https://hnrss.org/frontpage",
        "https://www.apple.com/newsroom/rss-feed.rss"
    ]

    public static var savedRssFeeds: [String] {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: rssFeedsKey)
            if let stored, !stored.isEmpty { return stored }
            return defaultRssFeeds
        }
        set {
            UserDefaults.standard.set(newValue, forKey: rssFeedsKey)
            refreshWidgetSnapshot()
        }
    }

    public static var clipboardTopic: String {
        get {
            let val = UserDefaults.standard.string(forKey: clipboardTopicKey) ?? ""
            if let clean = sanitizedTopic(val), clean.count >= 12 {
                return clean
            }
            let topic = generateSecureClipboardTopic()
            UserDefaults.standard.set(topic, forKey: clipboardTopicKey)
            return topic
        }
        set {
            if let clean = sanitizedTopic(newValue) {
                UserDefaults.standard.set(clean, forKey: clipboardTopicKey)
            }
        }
    }

    private static let clipboardKeychainService = "org.mediatok.clipboard"
    private static let clipboardKeychainAccount = "passphrase.v1"

    private static let clipboardFallbackDefaultsKey = "mediatok.wave11.clip_pass.fb.v1"

    public static var clipboardPassphrase: String {
        get {
            if let data = MTMediaTokCoreLogic.resilientSecretLoad(
                service: clipboardKeychainService,
                account: clipboardKeychainAccount,
                fallbackKey: clipboardFallbackDefaultsKey
            ),
            let str = String(data: data, encoding: .utf8) {
                return str
            }
            // Migrate legacy UserDefaults passphrase into resilient Keychain / obfuscated fallback
            if let legacy = UserDefaults.standard.string(forKey: clipboardPassphraseKey), !legacy.isEmpty {
                MTMediaTokWave11Tools.saveClipboardPassphraseToKeychain(legacy)
                return legacy
            }
            return ""
        }
        set {
            MTMediaTokWave11Tools.saveClipboardPassphraseToKeychain(newValue)
        }
    }

    private static func saveClipboardPassphraseToKeychain(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.removeObject(forKey: clipboardPassphraseKey)
        MTMediaTokCoreLogic.resilientSecretSave(
            clean.isEmpty ? nil : Data(clean.utf8),
            service: clipboardKeychainService,
            account: clipboardKeychainAccount,
            fallbackKey: clipboardFallbackDefaultsKey
        )
    }

    public static var best2048Score: Int {
        get { UserDefaults.standard.integer(forKey: best2048Key) }
        set {
            if newValue > UserDefaults.standard.integer(forKey: best2048Key) {
                UserDefaults.standard.set(newValue, forKey: best2048Key)
                refreshWidgetSnapshot()
            }
        }
    }

    // MARK: - Presenters

    public static func presentWave5Hub(context: AccountContext, peerId: PeerId? = nil) {
        let modelSignal: Signal<MTNativeScreenModel, NoError> = .single({
            var model = MTNativeScreenModel(title: "AI, Игры, RSS и Экосистема")
            model.sections = [
                [
                    MTNativeRow(id: "ai_hdr", kind: .header("AI-обработка фото")),
                    MTNativeRow(id: "trimg", kind: .disclosure(title: "Переводчик текста на фото / манге", label: ".trimg", icon: nil, enabled: true)),
                    MTNativeRow(id: "erase", kind: .disclosure(title: "Magic Eraser — умный ластик", label: ".erase", icon: nil, enabled: true)),
                    MTNativeRow(id: "upscale", kind: .disclosure(title: "AI Апскейл фото (Real-ESRGAN)", label: ".upscale", icon: nil, enabled: true))
                ],
                [
                    MTNativeRow(id: "tools_hdr", kind: .header("Игры, RSS и кросс-девайс")),
                    MTNativeRow(id: "games", kind: .disclosure(title: "Мини-игры: Крестики-нолики и 2048", label: ".game", icon: nil, enabled: true)),
                    MTNativeRow(id: "rss", kind: .disclosure(title: "Встроенный RSS / Atom ридер", label: ".rss", icon: nil, enabled: true)),
                    MTNativeRow(id: "clip", kind: .disclosure(title: "Общий буфер Телефон ↔ ПК", label: ".pcclip", icon: nil, enabled: true)),
                    MTNativeRow(id: "eco", kind: .disclosure(title: "Siri / Команды, Виджеты, Клавиши", label: ".siri", icon: nil, enabled: true))
                ]
            ]
            model.tap["trimg"] = { presentImageTranslator(context: context, initialImage: nil, peerId: peerId) }
            model.tap["erase"] = { presentMagicEraser(context: context) }
            model.tap["upscale"] = { presentUpscaler(context: context) }
            model.tap["games"] = { presentMiniGames(context: context, peerId: peerId, initialTab: 0) }
            model.tap["rss"] = { presentRssReader(context: context, peerId: peerId) }
            model.tap["clip"] = { presentSharedClipboard(context: context) }
            model.tap["eco"] = { presentEcosystemHub(context: context) }
            return model
        }())
        let vc = mtMakeNativeListController(context: context, model: modelSignal)
        mtPushNativeController(vc, context: context)
    }

    public static func presentImageTranslator(context: AccountContext, initialImage: UIImage?, peerId: PeerId?) {
        let vc = MTImageTranslatorViewController(context: context, initialImage: initialImage, peerId: peerId)
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        MTModalPresenter.presentOnTopmost(nav)
    }

    public static func presentMagicEraser(context: AccountContext) {
        let vc = MTMagicEraserViewController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        MTModalPresenter.presentOnTopmost(nav)
    }

    public static func presentUpscaler(context: AccountContext) {
        let host = MTUpscaleNativeScreenHost(context: context)
        let vc = host.makeController()
        mtPushNativeController(vc, context: context)
    }

    public static func presentMiniGames(context: AccountContext, peerId: PeerId?, initialTab: Int = 0) {
        let host = MTChatMiniGamesNativeScreenHost(context: context, peerId: peerId, initialTab: initialTab)
        let vc = host.makeController()
        mtPushNativeController(vc, context: context)
    }

    public static func presentRssReader(context: AccountContext, peerId: PeerId?) {
        let vc = mtMakeNativeRssReaderController(context: context, peerId: peerId)
        mtPushNativeController(vc, context: context)
    }

    public static func presentSharedClipboard(context: AccountContext) {
        let vc = mtMakeNativeSharedClipboardController(context: context)
        mtPushNativeController(vc, context: context)
    }

    public static func presentEcosystemHub(context: AccountContext) {
        refreshWidgetSnapshot()
        let summary = migrationSummary
        let snapshotJson = widgetSnapshotJson
        let modelSignal: Signal<MTNativeScreenModel, NoError> = .single({
            var model = MTNativeScreenModel(title: "Экосистема MediaTok")
            model.sections = [
                [
                    MTNativeRow(id: "mig_hdr", kind: .header("Авто-миграция схемы")),
                    MTNativeRow(id: "mig_info", kind: .info(summary))
                ],
                [
                    MTNativeRow(id: "siri_hdr", kind: .header("Apple Shortcuts / Siri URL")),
                    MTNativeRow(id: "siri_info", kind: .info("• mediatok://cmd?action=reconnect\n• mediatok://cmd?action=lyrics\n• mediatok://cmd?action=trimg\n• mediatok://cmd?action=clip\n• mediatok://cmd?action=rss")),
                    MTNativeRow(id: "copy_siri", kind: .action(title: "Скопировать URL для Команд (Siri)", destructive: false, enabled: true))
                ],
                [
                    MTNativeRow(id: "kbd_hdr", kind: .header("Клавиатура iPad / Bluetooth")),
                    MTNativeRow(id: "kbd_info", kind: .info("• ⇧⌘K — Spotlight Palette\n• ⇧⌘R — Force Reconnect\n• ⇧⌘L — Караоке-лирика"))
                ],
                [
                    MTNativeRow(id: "wid_hdr", kind: .header("Данные виджета")),
                    MTNativeRow(id: "copy_wid", kind: .action(title: "Скопировать JSON снимка виджета", destructive: false, enabled: true)),
                    MTNativeRow(id: "wid_ftr", kind: .footer("Снимок обновляется автоматически в App Group и UserDefaults."))
                ]
            ]
            model.tap["copy_siri"] = {
                UIPasteboard.general.string = "mediatok://cmd?action=reconnect"
                mtPresentNativeToast(context: context, text: "mediatok://cmd?action=reconnect скопирован")
            }
            model.tap["copy_wid"] = {
                UIPasteboard.general.string = snapshotJson
                mtPresentNativeToast(context: context, text: "Widget JSON скопирован")
            }
            return model
        }())
        let vc = mtMakeNativeListController(context: context, model: modelSignal)
        mtPushNativeController(vc, context: context)
    }

    // MARK: - Chat Photo -> Image Translator (#479)

    private static func translatePhotoFromMessage(context: AccountContext, message: Message) {
        guard let image = message.media.compactMap({ $0 as? TelegramMediaImage }).first,
              let rep = largestImageRepresentation(image.representations) else {
            MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось найти фото в сообщении")
            return
        }
        MTMediaTokWave5Tools.showToast(context: context, text: "🈳 Загружаю фото для OCR-перевода...")
        let combined = DisposableSet()
        let fetchDisp = fetchedMediaResource(
            mediaBox: context.account.postbox.mediaBox,
            userLocation: .other,
            userContentType: .image,
            reference: ImageMediaReference.message(message: MessageReference(message), media: image).resourceReference(rep.resource)
        ).startStandalone()
        combined.add(fetchDisp)

        let dataDisp = (context.account.postbox.mediaBox.resourceData(rep.resource, option: .complete(waitUntilFetchStatus: false))
            |> filter { $0.complete }
            |> take(1)
            |> timeout(20.0, queue: Queue.mainQueue(), alternate: .single(MediaResourceData(path: "", offset: 0, size: 0, complete: false)))
            |> deliverOnMainQueue).startStandalone(next: { data in
                fetchDisp.dispose()
                if data.complete, !data.path.isEmpty, let img = UIImage(contentsOfFile: data.path) {
                    presentImageTranslator(context: context, initialImage: img, peerId: message.id.peerId)
                } else {
                    MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось загрузить или декодировать фото")
                }
            })
        combined.add(dataDisp)
        activePhotoFetchDisposable.set(combined)
    }

    // MARK: - Shared Free Translation Helper (Google Translate GTX)

    fileprivate static func translateText(_ text: String, targetLang: String = "ru", completion: @escaping (String) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async { completion("") }
            return
        }
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        comps?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: targetLang),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = comps?.url else {
            DispatchQueue.main.async { completion(trimmed) }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 15.0)
        req.setValue("Mozilla/5.0 MediaTok/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let sentences = root.first as? [Any] else {
                DispatchQueue.main.async { completion(trimmed) }
                return
            }
            var parts: [String] = []
            for item in sentences {
                if let arr = item as? [Any], let translated = arr.first as? String {
                    parts.append(translated)
                }
            }
            let result = parts.joined()
            DispatchQueue.main.async { completion(result.isEmpty ? trimmed : result) }
        }.resume()
    }
}

// ============================================================================
// #479 — Image / Manga OCR + Translator ViewController
// ============================================================================

private final class MTImageTranslatorViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let context: AccountContext
    private let peerId: PeerId?
    private var sourceImage: UIImage?
    private var renderedImage: UIImage?
    private var lastTranscript: String = ""
    private var targetLang: String = "ru"
    private var translateGeneration: Int = 0

    private let imageView = UIImageView()
    private let statusLabel = UILabel()
    private let langControl = UISegmentedControl(items: ["RU", "EN", "UK", "KZ"])

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    init(context: AccountContext, initialImage: UIImage?, peerId: PeerId?) {
        self.context = context
        self.sourceImage = initialImage
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🈳 Переводчик фото / манги"
        self.view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Фото", style: .done, target: self, action: #selector(pickPhotoTapped))

        self.langControl.selectedSegmentIndex = 0
        self.langControl.translatesAutoresizingMaskIntoConstraints = false
        self.langControl.addTarget(self, action: #selector(langChanged), for: .valueChanged)

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.backgroundColor = UIColor(white: 0.11, alpha: 1.0)
        self.imageView.layer.cornerRadius = 14
        self.imageView.clipsToBounds = true
        self.imageView.translatesAutoresizingMaskIntoConstraints = false

        self.statusLabel.textColor = .secondaryLabel
        self.statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        self.statusLabel.numberOfLines = 3
        self.statusLabel.textAlignment = .center
        self.statusLabel.text = "Выбери фото или страницу манги — Vision OCR найдёт облачка и наложит перевод."
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let translateBtn = makeActionButton(title: "🈳 Распознать и перевести", color: .systemBlue, action: #selector(runTranslateTapped))
        let copyBtn = makeActionButton(title: "📋 Текст", color: UIColor(white: 0.22, alpha: 1.0), action: #selector(copyTextTapped))
        let shareBtn = makeActionButton(title: "📤 Сохранить / Поделиться", color: .systemGreen, action: #selector(shareTapped))

        let btnRow = UIStackView(arrangedSubviews: [copyBtn, shareBtn])
        btnRow.axis = .horizontal
        btnRow.spacing = 10
        btnRow.distribution = .fillEqually
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [self.langControl, self.imageView, self.statusLabel, translateBtn, btnRow])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            translateBtn.heightAnchor.constraint(equalToConstant: 46),
            btnRow.heightAnchor.constraint(equalToConstant: 44)
        ])

        if let img = self.sourceImage {
            self.imageView.image = img
            runTranslateTapped()
        }
    }

    private func makeActionButton(title: String, color: UIColor, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.backgroundColor = color
        btn.layer.cornerRadius = 12
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }

    @objc private func langChanged() {
        let langs = ["ru", "en", "uk", "kk"]
        self.targetLang = langs[max(0, min(self.langControl.selectedSegmentIndex, langs.count - 1))]
    }

    @objc private func pickPhotoTapped() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        self.present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let img = info[.originalImage] as? UIImage {
            self.translateGeneration += 1
            self.sourceImage = img
            self.renderedImage = nil
            self.imageView.image = img
            let w = Int((img.size.width * img.scale).rounded())
            let h = Int((img.size.height * img.scale).rounded())
            self.statusLabel.text = "Фото загружено (\(w)×\(h)). Нажми «Распознать и перевести»."
        }
    }

    @objc private func runTranslateTapped() {
        guard let img = self.sourceImage, let cgImage = img.cgImage else {
            pickPhotoTapped()
            return
        }
        self.translateGeneration += 1
        let currentGen = self.translateGeneration
        self.statusLabel.text = "🔍 Vision OCR сканирует текст..."
        let target = self.targetLang
        let orient = Self.cgOrientation(from: img.imageOrientation)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orient, options: [:])
            try? handler.perform([request])

            let observations = request.results ?? []
            var blocks: [(rect: CGRect, text: String)] = []
            for obs in observations {
                if let top = obs.topCandidates(1).first, !top.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append((rect: obs.boundingBox, text: top.string))
                }
            }

            if blocks.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.translateGeneration == currentGen else { return }
                    self.statusLabel.text = "Текст на изображении не найден."
                }
                return
            }

            let joined = blocks.map(\.text).joined(separator: "\n")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.translateGeneration == currentGen else { return }
                self.statusLabel.text = "🌐 Найдено блоков: \(blocks.count). Перевожу на \(target.uppercased())..."
            }

            let group = DispatchGroup()
            let semaphore = DispatchSemaphore(value: 4)
            let translatedBlocks = MTThreadSafeArray<String>(repeating: "", count: blocks.count)
            for (idx, blk) in blocks.enumerated() {
                semaphore.wait()
                group.enter()
                MTMediaTokWave11Tools.translateText(blk.text, targetLang: target) { tr in
                    translatedBlocks.set(tr, at: idx)
                    semaphore.signal()
                    group.leave()
                }
            }

            group.notify(queue: DispatchQueue.global(qos: .userInitiated)) { [weak self] in
                let translations = translatedBlocks.snapshot()
                let outputImg = Self.renderTranslatedOverlay(base: img, blocks: blocks, translations: translations)
                let transcript = zip(blocks.map(\.text), translations)
                    .map { "• \($0)\n→ \($1)" }
                    .joined(separator: "\n\n")
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.translateGeneration == currentGen else { return }
                    self.renderedImage = outputImg
                    self.imageView.image = outputImg
                    self.lastTranscript = transcript
                    self.statusLabel.text = "✅ Переведено блоков: \(blocks.count) (\(target.uppercased())). Оригинал: \(joined.prefix(40))..."
                }
            }
        }
    }

    private static func renderTranslatedOverlay(base: UIImage, blocks: [(rect: CGRect, text: String)], translations: [String]) -> UIImage {
        let rawW = base.size.width * base.scale
        let rawH = base.size.height * base.scale
        let ratio = min(1.0, 2560.0 / max(1.0, max(rawW, rawH)))
        let size = CGSize(width: max(1, (rawW * ratio).rounded()), height: max(1, (rawH * ratio).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            for (idx, blk) in blocks.enumerated() {
                let text = idx < translations.count ? translations[idx] : blk.text
                let x = blk.rect.origin.x * size.width
                let y = (1.0 - blk.rect.origin.y - blk.rect.height) * size.height
                let w = max(44, blk.rect.width * size.width)
                let h = max(22, blk.rect.height * size.height)
                let box = CGRect(x: x - 4, y: y - 3, width: w + 8, height: h + 6).intersection(CGRect(origin: .zero, size: size))

                let path = UIBezierPath(roundedRect: box, cornerRadius: max(4, min(10, box.height * 0.22)))
                UIColor(white: 0.08, alpha: 0.86).setFill()
                path.fill()

                let fontSize = max(11, min(32, box.height * 0.56))
                let para = NSMutableParagraphStyle()
                para.alignment = .center
                para.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: para
                ]
                let insetBox = box.insetBy(dx: 3, dy: 2)
                (text as NSString).draw(in: insetBox, withAttributes: attrs)
            }
        }
    }

    @objc private func copyTextTapped() {
        guard !self.lastTranscript.isEmpty else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Сначала переведи фото")
            return
        }
        UIPasteboard.general.string = self.lastTranscript
        MTMediaTokWave5Tools.showToast(context: self.context, text: "📋 OCR и перевод скопированы")
    }

    @objc private func shareTapped() {
        guard let img = self.renderedImage ?? self.sourceImage else { return }
        let ac = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        MTModalPresenter.configurePopover(ac, hostView: self.view)
        self.present(ac, animated: true)
    }
}

// ============================================================================
// #481 — Magic Eraser (Finger Mask + Feathered CoreImage Inpaint)
// ============================================================================

private final class MTMagicEraserViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let context: AccountContext
    private let ciContext = CIContext()
    private var originalImage: UIImage?
    private var currentImage: UIImage?
    private var strokes: [[CGPoint]] = []
    private var activeStroke: [CGPoint] = []
    private var brushWidth: CGFloat = 28.0
    private var isProcessing: Bool = false

    private let imageView = UIImageView()
    private let overlayLayer = CAShapeLayer()
    private let brushSlider = UISlider()
    private let hintLabel = UILabel()

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func normalizedImage(_ image: UIImage, maxDimension: CGFloat = 2048.0) -> UIImage {
        let origW = image.size.width * image.scale
        let origH = image.size.height * image.scale
        guard origW > 0, origH > 0 else { return image }
        let ratio = min(1.0, maxDimension / max(origW, origH))
        let targetSize = CGSize(width: max(1, (origW * ratio).rounded()), height: max(1, (origH * ratio).rounded()))
        if image.imageOrientation == .up && ratio == 1.0 && image.scale == 1.0 && image.cgImage != nil {
            return image
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🪄 Magic Eraser"
        self.view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Фото", style: .done, target: self, action: #selector(pickPhotoTapped))

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.backgroundColor = UIColor(white: 0.11, alpha: 1.0)
        self.imageView.layer.cornerRadius = 14
        self.imageView.clipsToBounds = true
        self.imageView.isUserInteractionEnabled = true
        self.imageView.translatesAutoresizingMaskIntoConstraints = false

        self.overlayLayer.strokeColor = UIColor.systemPink.withAlphaComponent(0.65).cgColor
        self.overlayLayer.fillColor = UIColor.clear.cgColor
        self.overlayLayer.lineCap = .round
        self.overlayLayer.lineJoin = .round
        self.overlayLayer.lineWidth = self.brushWidth
        self.imageView.layer.addSublayer(self.overlayLayer)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.imageView.addGestureRecognizer(pan)

        self.hintLabel.text = "Зарисуй пальцем лишний объект или водяной знак, затем нажми «Стереть»."
        self.hintLabel.textColor = .secondaryLabel
        self.hintLabel.font = .systemFont(ofSize: 13)
        self.hintLabel.numberOfLines = 2
        self.hintLabel.textAlignment = .center

        self.brushSlider.minimumValue = 12
        self.brushSlider.maximumValue = 64
        self.brushSlider.value = Float(self.brushWidth)
        self.brushSlider.addTarget(self, action: #selector(brushChanged), for: .valueChanged)

        let eraseBtn = makeBtn("🪄 Стереть выделенное", .systemPink, #selector(applyEraseTapped))
        let undoBtn = makeBtn("↩️ Сброс", UIColor(white: 0.22, alpha: 1.0), #selector(resetTapped))
        let shareBtn = makeBtn("📤 Сохранить", .systemGreen, #selector(shareTapped))

        let row = UIStackView(arrangedSubviews: [undoBtn, shareBtn])
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [self.imageView, self.hintLabel, self.brushSlider, eraseBtn, row])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            eraseBtn.heightAnchor.constraint(equalToConstant: 46),
            row.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func makeBtn(_ title: String, _ bg: UIColor, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.backgroundColor = bg
        b.layer.cornerRadius = 12
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }

    @objc private func pickPhotoTapped() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        self.present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let rawImg = info[.originalImage] as? UIImage {
            let img = normalizedImage(rawImg, maxDimension: 2048.0)
            self.originalImage = img
            self.currentImage = img
            self.imageView.image = img
            self.strokes.removeAll()
            self.overlayLayer.path = nil
        }
    }

    @objc private func brushChanged() {
        self.brushWidth = CGFloat(self.brushSlider.value)
        self.overlayLayer.lineWidth = self.brushWidth
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let pt = gesture.location(in: self.imageView)
        switch gesture.state {
        case .began:
            self.activeStroke = [pt]
        case .changed:
            self.activeStroke.append(pt)
            redrawMaskOverlay()
        case .ended, .cancelled:
            if !self.activeStroke.isEmpty {
                self.strokes.append(self.activeStroke)
                self.activeStroke.removeAll()
                redrawMaskOverlay()
            }
        default:
            break
        }
    }

    private func redrawMaskOverlay() {
        let path = UIBezierPath()
        for stroke in self.strokes + (self.activeStroke.isEmpty ? [] : [self.activeStroke]) {
            guard let first = stroke.first else { continue }
            path.move(to: first)
            for p in stroke.dropFirst() { path.addLine(to: p) }
        }
        self.overlayLayer.path = path.cgPath
    }

    private func imageDisplayRect(for image: UIImage) -> CGRect {
        let bounds = self.imageView.bounds
        guard bounds.width > 0, bounds.height > 0, image.size.width > 0, image.size.height > 0 else { return bounds }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let w = image.size.width * scale
        let h = image.size.height * scale
        return CGRect(x: (bounds.width - w) * 0.5, y: (bounds.height - h) * 0.5, width: w, height: h)
    }

    @objc private func applyEraseTapped() {
        guard !self.isProcessing else { return }
        guard let rawImg = self.currentImage else {
            pickPhotoTapped()
            return
        }
        let img = normalizedImage(rawImg, maxDimension: 2048.0)
        guard let cgImg = img.cgImage else {
            pickPhotoTapped()
            return
        }
        guard !self.strokes.isEmpty else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Сначала зарисуй объект пальцем")
            return
        }
        self.isProcessing = true
        let imgRect = imageDisplayRect(for: img)
        let strokesCopy = self.strokes
        let brushPt = self.brushWidth
        let pixelW = CGFloat(cgImg.width)
        let pixelH = CGFloat(cgImg.height)
        let scaleX = pixelW / max(1, imgRect.width)
        let scaleY = pixelH / max(1, imgRect.height)
        let ciCtx = self.ciContext
        self.hintLabel.text = "⚙️ Обрабатываю..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = true
            format.preferredRange = .standard
            let maskUIImage = UIGraphicsImageRenderer(size: CGSize(width: pixelW, height: pixelH), format: format).image { ctx in
                UIColor.black.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
                let path = UIBezierPath()
                for stroke in strokesCopy {
                    let mapped = stroke.map { CGPoint(x: ($0.x - imgRect.minX) * scaleX, y: ($0.y - imgRect.minY) * scaleY) }
                    guard let first = mapped.first else { continue }
                    path.move(to: first)
                    for p in mapped.dropFirst() { path.addLine(to: p) }
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.lineWidth = brushPt * max(scaleX, scaleY)
                UIColor.white.setStroke()
                path.stroke()
            }

            guard let maskCG = maskUIImage.cgImage else {
                DispatchQueue.main.async { [weak self] in
                    self?.isProcessing = false
                }
                return
            }
            let baseCI = CIImage(cgImage: cgImg)
            let blurRadius = max(6.0, brushPt * max(scaleX, scaleY) * 0.25)
            let maskCI = CIImage(cgImage: maskCG)
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
                .cropped(to: baseCI.extent)

            // Multi-pass feathered surrounding-color fill (morphology + wide blur + soft blend)
            let expanded = baseCI
                .clampedToExtent()
                .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 12.0])
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 28.0])
                .cropped(to: baseCI.extent)

            let blended = expanded.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: baseCI,
                kCIInputMaskImageKey: maskCI
            ])

            let outCG = ciCtx.createCGImage(blended, from: baseCI.extent)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isProcessing = false
                self.hintLabel.text = "Зарисуй пальцем лишний объект или водяной знак, затем нажми «Стереть»."
                if let outCG {
                    let result = UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
                    self.currentImage = result
                    self.imageView.image = result
                    self.strokes.removeAll()
                    self.overlayLayer.path = nil
                    MTMediaTokWave5Tools.showToast(context: self.context, text: "🪄 Объект стёрт!")
                }
            }
        }
    }

    @objc private func resetTapped() {
        self.strokes.removeAll()
        self.overlayLayer.path = nil
        if let orig = self.originalImage {
            self.currentImage = orig
            self.imageView.image = orig
        }
    }

    @objc private func shareTapped() {
        guard let img = self.currentImage else { return }
        let ac = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        MTModalPresenter.configurePopover(ac, hostView: self.view)
        self.present(ac, animated: true)
    }
}

// ============================================================================
// #482 — Neural 4K Upscale (Waifu2x upconv_7 GPU / MPSGraph)
// ============================================================================

private final class MTUpscaleCancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled: Bool = false

    func cancel() {
        self.lock.lock()
        self.cancelled = true
        self.lock.unlock()
    }

    var isCancelled: Bool {
        self.lock.lock()
        let v = self.cancelled
        self.lock.unlock()
        return v
    }
}

private enum MTOnlineUpscalerError: LocalizedError {
    case encodingFailed
    case serverBusy(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Не удалось подготовить изображение для отправки"
        case let .serverBusy(msg):
            return msg
        case .cancelled:
            return "Апскейл отменён"
        }
    }
}

private enum MTOnlineRealESRGAN {
    private struct Mirror {
        let name: String
        let baseURL: String
        let uploadPath: String
        let callPath: String
        let filePrefix: String
        let buildPayload: (_ uploadedPath: String, _ isAnime: Bool, _ factor: Int) -> [String: Any]
    }

    private static let mirrors: [Mirror] = [
        Mirror(
            name: "Real-ESRGAN Cloud #1",
            baseURL: "https://guetlzy-real-esrgan-demo.hf.space",
            uploadPath: "/gradio_api/upload",
            callPath: "/gradio_api/call/enhance",
            filePrefix: "/gradio_api/file=",
            buildPayload: { path, isAnime, factor in
                let model = isAnime ? "RealESRGAN_x4plus_anime_6B" : "RealESRGAN_x4plus"
                return ["data": [
                    ["path": path, "meta": ["_type": "gradio.FileData"]],
                    model,
                    factor,
                    !isAnime
                ]]
            }
        ),
        Mirror(
            name: "Real-ESRGAN Cloud #2",
            baseURL: "https://nick088-real-esrgan-pytorch.hf.space",
            uploadPath: "/upload",
            callPath: "/call/predict",
            filePrefix: "/file=",
            buildPayload: { path, _, factor in
                return ["data": [
                    ["path": path, "meta": ["_type": "gradio.FileData"]],
                    "\(factor)"
                ]]
            }
        )
    ]

    static func upscale(
        image: UIImage,
        isAnime: Bool,
        factor: Int,
        isCancelled: @escaping () -> Bool,
        onProgress: @escaping (Float, String) -> Void
    ) throws -> UIImage {
        let resized = self.downscaleIfHuge(image, maxSide: 1280)
        guard let uploadData = resized.jpegData(compressionQuality: 0.92) ?? resized.pngData() else {
            throw MTOnlineUpscalerError.encodingFailed
        }
        var lastError = "Облачные серверы Real-ESRGAN сейчас заняты — открой iLoveIMG или Bigjpg кнопками ниже."
        for (idx, mirror) in self.mirrors.enumerated() {
            if isCancelled() { throw MTOnlineUpscalerError.cancelled }
            onProgress(0.15 + Float(idx) * 0.1, "Отправка фото на \(mirror.name)...")
            do {
                let result = try self.runOnMirror(mirror, imageData: uploadData, isAnime: isAnime, factor: factor, isCancelled: isCancelled, onProgress: onProgress)
                return result
            } catch let err as MTOnlineUpscalerError {
                if case .cancelled = err { throw err }
                lastError = err.localizedDescription
            } catch {
                lastError = error.localizedDescription
            }
        }
        throw MTOnlineUpscalerError.serverBusy(lastError)
    }

    private static func downscaleIfHuge(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let w = img.size.width * img.scale
        let h = img.size.height * img.scale
        let longest = max(w, h)
        guard longest > maxSide else { return img }
        let ratio = maxSide / longest
        let target = CGSize(width: floor(w * ratio), height: floor(h * ratio))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        return UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?
        private var error: Error?
        private var statusCode: Int = 0

        func store(data: Data?, error: Error?, statusCode: Int) {
            self.lock.lock()
            self.data = data
            self.error = error
            self.statusCode = statusCode
            self.lock.unlock()
        }

        func read() -> (Data?, Error?, Int) {
            self.lock.lock()
            defer { self.lock.unlock() }
            return (self.data, self.error, self.statusCode)
        }
    }

    private static func syncRequest(_ req: URLRequest, timeout: TimeInterval, isCancelled: () -> Bool) throws -> Data {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }
        let sem = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        let task = session.dataTask(with: req) { data, resp, err in
            box.store(data: data, error: err, statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0)
            sem.signal()
        }
        task.resume()
        let deadline = Date().addingTimeInterval(timeout)
        while sem.wait(timeout: .now() + 0.15) == .timedOut {
            if isCancelled() {
                task.cancel()
                throw MTOnlineUpscalerError.cancelled
            }
            if Date() >= deadline {
                task.cancel()
                throw MTOnlineUpscalerError.serverBusy("Превышено время ожидания сервера")
            }
        }
        if isCancelled() { throw MTOnlineUpscalerError.cancelled }
        let (outData, outErr, statusCode) = box.read()
        if let outErr { throw outErr }
        guard statusCode >= 200 && statusCode < 300, let outData else {
            throw MTOnlineUpscalerError.serverBusy("Сервер вернул код \(statusCode)")
        }
        return outData
    }

    private static func runOnMirror(
        _ mirror: Mirror,
        imageData: Data,
        isAnime: Bool,
        factor: Int,
        isCancelled: () -> Bool,
        onProgress: @escaping (Float, String) -> Void
    ) throws -> UIImage {
        let boundary = "----MTUpscale\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"files\"; filename=\"input.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        guard let uploadURL = URL(string: mirror.baseURL + mirror.uploadPath) else {
            throw MTOnlineUpscalerError.serverBusy("Неверный URL")
        }
        var upReq = URLRequest(url: uploadURL)
        upReq.httpMethod = "POST"
        upReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upReq.setValue("MediaTok/1.0", forHTTPHeaderField: "User-Agent")
        upReq.httpBody = body

        let upResp = try self.syncRequest(upReq, timeout: 18, isCancelled: isCancelled)
        guard let paths = (try? JSONSerialization.jsonObject(with: upResp)) as? [String],
              let serverPath = paths.first, !serverPath.isEmpty else {
            throw MTOnlineUpscalerError.serverBusy("Не удалось загрузить фото на \(mirror.name)")
        }

        onProgress(0.42, "Нейросеть \(mirror.name) обрабатывает \(factor)×...")
        guard let callURL = URL(string: mirror.baseURL + mirror.callPath) else {
            throw MTOnlineUpscalerError.serverBusy("Неверный URL вызова")
        }
        var callReq = URLRequest(url: callURL)
        callReq.httpMethod = "POST"
        callReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        callReq.setValue("MediaTok/1.0", forHTTPHeaderField: "User-Agent")
        callReq.httpBody = try JSONSerialization.data(withJSONObject: mirror.buildPayload(serverPath, isAnime, factor))

        let callResp = try self.syncRequest(callReq, timeout: 18, isCancelled: isCancelled)
        guard let callJson = (try? JSONSerialization.jsonObject(with: callResp)) as? [String: Any],
              let eventId = callJson["event_id"] as? String, !eventId.isEmpty else {
            throw MTOnlineUpscalerError.serverBusy("Сервер \(mirror.name) не принял задачу")
        }

        onProgress(0.65, "Рендер Real-ESRGAN \(factor)× в облаке...")
        guard let pollURL = URL(string: "\(mirror.baseURL)\(mirror.callPath)/\(eventId)") else {
            throw MTOnlineUpscalerError.serverBusy("Неверный URL результата")
        }
        var pollReq = URLRequest(url: pollURL)
        pollReq.setValue("MediaTok/1.0", forHTTPHeaderField: "User-Agent")
        let sseData = try self.syncRequest(pollReq, timeout: 45, isCancelled: isCancelled)
        let sseText = String(decoding: sseData, as: UTF8.self)
        guard let resultURLString = self.extractImageURL(fromSSE: sseText, baseURL: mirror.baseURL, filePrefix: mirror.filePrefix),
              let resultURL = URL(string: resultURLString) else {
            throw MTOnlineUpscalerError.serverBusy("Сервер \(mirror.name) занят или спит")
        }

        onProgress(0.88, "Скачивание готового HD-изображения...")
        var dlReq = URLRequest(url: resultURL)
        dlReq.setValue("MediaTok/1.0", forHTTPHeaderField: "User-Agent")
        let imgData = try self.syncRequest(dlReq, timeout: 25, isCancelled: isCancelled)
        guard let finalImage = UIImage(data: imgData) else {
            throw MTOnlineUpscalerError.serverBusy("Не удалось декодировать ответ сервера")
        }
        return finalImage
    }

    private static func extractImageURL(fromSSE text: String, baseURL: String, filePrefix: String) -> String? {
        for line in text.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonPart = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = jsonPart.data(using: .utf8),
                  let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { continue }
            for item in arr {
                if let dict = item as? [String: Any] {
                    if let url = dict["url"] as? String, url.hasPrefix("http") {
                        return url
                    }
                    if let path = dict["path"] as? String, !path.isEmpty {
                        if path.hasPrefix("http") { return path }
                        let prefix = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
                        return "\(prefix)\(filePrefix)\(path)"
                    }
                } else if let str = item as? String, str.hasPrefix("http") {
                    return str
                }
            }
        }
        return nil
    }

    static func normalizeOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private final class MTUpscaleNativeScreenHost: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    struct State: Equatable {
        var isAnime: Bool = false
        var factor: Int = 2
        var isRunning: Bool = false
        var imageLabel: String = "Не выбрано"
        var statusText: String = "Бесплатный облачный Real-ESRGAN (без API-ключа) + быстрый переход в iLoveIMG и Bigjpg."
        var hasImage: Bool = false
        var hasUpscaled: Bool = false
        var revision: Int = 0
    }

    private let context: AccountContext
    weak var controller: ItemListController?
    private var sourceImage: UIImage?
    private var upscaledImage: UIImage?
    private var activeCancelBox: MTUpscaleCancelBox?
    private var stateValue = State()
    private let statePromise: ValuePromise<State>

    init(context: AccountContext) {
        self.context = context
        self.statePromise = ValuePromise(self.stateValue, ignoreRepeated: true)
        super.init()
    }

    deinit {
        self.activeCancelBox?.cancel()
    }

    private func updateState(_ mutate: (inout State) -> Void) {
        mutate(&self.stateValue)
        self.stateValue.revision &+= 1
        self.statePromise.set(self.stateValue)
    }

    func makeController() -> ItemListController {
        let host = self
        let signal: Signal<MTNativeScreenModel, NoError> = self.statePromise.get()
        |> map { state in
            return host.buildModel(state: state)
        }
        let vc = mtMakeNativeListController(context: self.context, model: signal)
        self.controller = vc
        return vc
    }

    private func buildModel(state: State) -> MTNativeScreenModel {
        var model = MTNativeScreenModel(title: "AI Апскейл фото")
        model.rightButton = (
            title: "Фото",
            enabled: !state.isRunning,
            action: { [weak self] in self?.pickPhoto() }
        )

        model.sections = [
            [
                MTNativeRow(id: "img_hdr", kind: .header("Изображение и статус")),
                MTNativeRow(id: "pick_photo", kind: .disclosure(title: "Выбрать фото из галереи", label: state.imageLabel, icon: nil, enabled: !state.isRunning)),
                MTNativeRow(id: "status_info", kind: .info(state.statusText))
            ],
            [
                MTNativeRow(id: "style_hdr", kind: .header("Модель Real-ESRGAN")),
                MTNativeRow(id: "style_photo", kind: .check(title: "Фото (Real-ESRGAN x4plus)", subtitle: "Реалистичные фотографии и портреты", checked: !state.isAnime)),
                MTNativeRow(id: "style_anime", kind: .check(title: "Аниме / Арт (anime_6B)", subtitle: "Иллюстрации, манга и чёткие линии", checked: state.isAnime))
            ],
            [
                MTNativeRow(id: "factor_hdr", kind: .header("Масштаб")),
                MTNativeRow(id: "factor_2x", kind: .check(title: "2× HD", subtitle: "Быстрое двукратное улучшение", checked: state.factor == 2)),
                MTNativeRow(id: "factor_4x", kind: .check(title: "4× Ultra", subtitle: "Максимальная детализация 4K", checked: state.factor == 4))
            ],
            [
                MTNativeRow(id: "act_hdr", kind: .header("Обработка и экспорт")),
                state.isRunning
                    ? MTNativeRow(id: "run_btn", kind: .action(title: "Отменить апскейл", destructive: true, enabled: true))
                    : MTNativeRow(id: "run_btn", kind: .action(title: "Улучшить фото (Онлайн AI)", destructive: false, enabled: true)),
                MTNativeRow(id: "send_saved", kind: .action(title: "Отправить PNG в Избранное (без сжатия)", destructive: false, enabled: state.hasImage && !state.isRunning)),
                MTNativeRow(id: "share_img", kind: .action(title: "Сохранить в Фото / Поделиться...", destructive: false, enabled: state.hasImage && !state.isRunning))
            ],
            [
                MTNativeRow(id: "web_hdr", kind: .header("Внешние веб-сервисы")),
                MTNativeRow(id: "web_iloveimg", kind: .disclosure(title: "Открыть iLoveIMG Upscale", label: "iloveimg.com", icon: nil, enabled: true)),
                MTNativeRow(id: "web_bigjpg", kind: .disclosure(title: "Открыть Bigjpg AI", label: "bigjpg.com", icon: nil, enabled: true)),
                MTNativeRow(id: "web_ftr", kind: .footer("Резервные онлайн-сервисы на случай высокой нагрузки публичных облачных зеркал Real-ESRGAN."))
            ]
        ]

        model.tap["pick_photo"] = { [weak self] in self?.pickPhoto() }
        model.tap["style_photo"] = { [weak self] in
            guard let self, !self.stateValue.isRunning else { return }
            self.updateState { $0.isAnime = false }
        }
        model.tap["style_anime"] = { [weak self] in
            guard let self, !self.stateValue.isRunning else { return }
            self.updateState { $0.isAnime = true }
        }
        model.tap["factor_2x"] = { [weak self] in
            guard let self, !self.stateValue.isRunning else { return }
            self.updateState { $0.factor = 2 }
        }
        model.tap["factor_4x"] = { [weak self] in
            guard let self, !self.stateValue.isRunning else { return }
            self.updateState { $0.factor = 4 }
        }
        model.tap["run_btn"] = { [weak self] in self?.runOrCancelUpscale() }
        model.tap["send_saved"] = { [weak self] in self?.sendToSavedMessages() }
        model.tap["share_img"] = { [weak self] in self?.shareResult() }
        model.tap["web_iloveimg"] = { [weak self] in self?.openSafari("https://www.iloveimg.com/upscale-image") }
        model.tap["web_bigjpg"] = { [weak self] in self?.openSafari("https://bigjpg.com") }
        return model
    }

    private func pickPhoto() {
        guard self.activeCancelBox == nil else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        MTModalPresenter.presentOnTopmost(picker, preferredRoot: self.controller?.view.window?.rootViewController)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let img = info[.originalImage] as? UIImage else { return }
        let normalized = MTOnlineRealESRGAN.normalizeOrientation(img)
        self.sourceImage = normalized
        self.upscaledImage = nil
        let w = Int(normalized.size.width.rounded())
        let h = Int(normalized.size.height.rounded())
        self.updateState { st in
            st.hasImage = true
            st.hasUpscaled = false
            st.imageLabel = "\(w)×\(h) px"
            st.statusText = "Оригинал: \(w)×\(h) px. Выберите параметры и нажмите «Улучшить фото (Онлайн AI)»."
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func runOrCancelUpscale() {
        if let active = self.activeCancelBox {
            active.cancel()
            return
        }
        guard let src = self.sourceImage else {
            self.pickPhoto()
            return
        }
        let isAnime = self.stateValue.isAnime
        let factor = self.stateValue.factor
        let srcW = Int(src.size.width.rounded())
        let srcH = Int(src.size.height.rounded())

        let cancelBox = MTUpscaleCancelBox()
        self.activeCancelBox = cancelBox
        self.updateState { st in
            st.isRunning = true
            st.statusText = "⏳ 8% — Подключение к облачному Real-ESRGAN..."
        }
        let startedAt = CFAbsoluteTimeGetCurrent()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try MTOnlineRealESRGAN.upscale(
                    image: src,
                    isAnime: isAnime,
                    factor: factor,
                    isCancelled: { cancelBox.isCancelled },
                    onProgress: { progress, statusText in
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.activeCancelBox === cancelBox else { return }
                            let pct = max(1, min(99, Int((progress * 100.0).rounded())))
                            self.updateState { st in
                                st.statusText = "⏳ \(pct)% — \(statusText)"
                            }
                        }
                    }
                )
                let elapsed = max(0.05, CFAbsoluteTimeGetCurrent() - startedAt)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.activeCancelBox === cancelBox else { return }
                    self.activeCancelBox = nil
                    self.upscaledImage = result
                    let outW = Int((result.size.width * result.scale).rounded())
                    let outH = Int((result.size.height * result.scale).rounded())
                    self.updateState { st in
                        st.isRunning = false
                        st.hasUpscaled = true
                        st.imageLabel = "\(outW)×\(outH) px"
                        st.statusText = String(format: "✅ Готово за %.1f сек: %d×%d → %d×%d px (Real-ESRGAN Cloud)", elapsed, srcW, srcH, outW, outH)
                    }
                    mtPresentNativeToast(context: self.context, from: self.controller, text: "Фото успешно улучшено до \(outW)×\(outH) px")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.activeCancelBox === cancelBox else { return }
                    self.activeCancelBox = nil
                    self.updateState { st in
                        st.isRunning = false
                        st.statusText = error.localizedDescription
                    }
                }
            }
        }
    }

    private func sendToSavedMessages() {
        guard let img = self.upscaledImage ?? self.sourceImage else {
            self.pickPhoto()
            return
        }
        guard let pngData = img.pngData() else { return }
        let w = Int32((img.size.width * img.scale).rounded())
        let h = Int32((img.size.height * img.scale).rounded())
        let fileId = Int64.random(in: Int64.min ... Int64.max)
        let resource = LocalFileMediaResource(fileId: fileId, size: Int64(pngData.count), isSecretRelated: false)
        self.context.account.postbox.mediaBox.storeResourceData(resource.id, data: pngData, synchronous: true)
        let media = TelegramMediaFile(
            fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: fileId),
            partialReference: nil,
            resource: resource,
            previewRepresentations: [],
            videoThumbnails: [],
            immediateThumbnailData: nil,
            mimeType: "image/png",
            size: Int64(pngData.count),
            attributes: [
                .FileName(fileName: "MediaTok_HD_\(w)x\(h).png"),
                .ImageSize(size: PixelDimensions(width: w, height: h))
            ],
            alternativeRepresentations: []
        )
        _ = enqueueMessages(account: self.context.account, peerId: self.context.account.peerId, messages: [
            .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        ]).startStandalone()
        self.updateState { st in
            st.statusText = "📤 Отправлено без потери качества в Избранное (\(w)×\(h) PNG)"
        }
        mtPresentNativeToast(context: self.context, from: self.controller, text: "PNG \(w)×\(h) отправлен в Избранное без сжатия")
    }

    private func shareResult() {
        guard let img = self.upscaledImage ?? self.sourceImage else {
            self.pickPhoto()
            return
        }
        let ac = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        MTModalPresenter.presentOnTopmost(ac, preferredRoot: self.controller?.view.window?.rootViewController)
    }

    private func openSafari(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let sf = SFSafariViewController(url: url)
        MTModalPresenter.presentOnTopmost(sf, preferredRoot: self.controller?.view.window?.rootViewController)
    }
}

// ============================================================================
// #467 — Chat-Synced Mini-Games (Tic-Tac-Toe [MT:TTT] + Playable 2048)
// ============================================================================

private final class MTChatMiniGamesNativeScreenHost {
    struct State: Equatable {
        var tab: Int
        var tttBoard: [String] = Array(repeating: "", count: 9)
        var tttTurn: String = "X"
        var tttVsAi: Bool = false
        var hasMadeMoveThisTurn: Bool = false
        var grid2048: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        var score2048: Int = 0
        var best2048: Int = 0
    }

    private let context: AccountContext
    private let peerId: PeerId?
    weak var controller: ItemListController?
    private var stateValue: State
    private let statePromise: ValuePromise<State>

    init(context: AccountContext, peerId: PeerId?, initialTab: Int) {
        self.context = context
        self.peerId = peerId
        var initial = State(tab: initialTab == 1 ? 1 : 0, best2048: MTMediaTokWave11Tools.best2048Score)
        Self.spawn2048Tile(in: &initial.grid2048)
        Self.spawn2048Tile(in: &initial.grid2048)
        self.stateValue = initial
        self.statePromise = ValuePromise(initial, ignoreRepeated: true)
    }

    private func updateState(_ mutate: (inout State) -> Void) {
        mutate(&self.stateValue)
        self.statePromise.set(self.stateValue)
    }

    func makeController() -> ItemListController {
        let host = self
        let signal: Signal<MTNativeScreenModel, NoError> = self.statePromise.get()
        |> map { state in
            return host.buildModel(state: state)
        }
        let vc = mtMakeNativeListController(context: self.context, model: signal)
        self.controller = vc
        if self.peerId != nil {
            self.syncTttFromChat()
        }
        return vc
    }

    private static func tttWinner(board: [String]) -> String? {
        let lines = [
            [0, 1, 2], [3, 4, 5], [6, 7, 8],
            [0, 3, 6], [1, 4, 7], [2, 5, 8],
            [0, 4, 8], [2, 4, 6]
        ]
        for l in lines {
            let a = board[l[0]]
            if !a.isEmpty && a == board[l[1]] && a == board[l[2]] {
                return a
            }
        }
        if !board.contains("") { return "DRAW" }
        return nil
    }

    private static func formatTttStatus(board: [String], turn: String) -> String {
        if let w = tttWinner(board: board) {
            return w == "DRAW" ? "🤝 Ничья!" : "🏆 Победил \(w == "X" ? "❌" : "⭕️")!"
        }
        return "Ход: \(turn == "X" ? "❌" : "⭕️")"
    }

    private static func formatTttGrid(board: [String], turn: String) -> String {
        let rows = [0, 3, 6].map { start in
            (start ..< (start + 3)).map { i in
                board[i] == "X" ? "❌" : (board[i] == "O" ? "⭕️" : "⬜️")
            }.joined(separator: "  ")
        }.joined(separator: "\n")
        return "\(rows)\n\n\(formatTttStatus(board: board, turn: turn))"
    }

    private static func format2048Grid(grid: [[Int]], score: Int, best: Int) -> String {
        let gridText = grid.map { row in
            row.map { v in
                let cell = v == 0 ? "·" : "\(v)"
                return cell.padding(toLength: 5, withPad: " ", startingAt: 0)
            }.joined(separator: " ")
        }.joined(separator: "\n")
        return "Счёт: \(score)  •  Рекорд: \(best)\n\n\(gridText)"
    }

    private func buildModel(state: State) -> MTNativeScreenModel {
        var model = MTNativeScreenModel(title: "Мини-игры")
        if self.peerId != nil && state.tab == 0 {
            model.rightButton = (
                title: "Синхр.",
                enabled: true,
                action: { [weak self] in self?.syncTttFromChat() }
            )
        }

        let modeSection: [MTNativeRow] = [
            MTNativeRow(id: "mode_hdr", kind: .header("Выбор игры")),
            MTNativeRow(id: "tab_ttt", kind: .check(title: "Крестики-нолики ([MT:TTT])", subtitle: "Синхронизация ходов через сообщения чата или бот", checked: state.tab == 0)),
            MTNativeRow(id: "tab_2048", kind: .check(title: "2048", subtitle: "Классическая головоломка с таблицей рекордов", checked: state.tab == 1))
        ]
        model.tap["tab_ttt"] = { [weak self] in self?.updateState { $0.tab = 0 } }
        model.tap["tab_2048"] = { [weak self] in self?.updateState { $0.tab = 1 } }

        if state.tab == 0 {
            let winner = Self.tttWinner(board: state.tttBoard)
            var moveRows: [MTNativeRow] = [
                MTNativeRow(id: "ttt_moves_hdr", kind: .header("Клетки поля"))
            ]
            for idx in 0 ..< 9 {
                let r = idx / 3 + 1
                let c = idx % 3 + 1
                let val = state.tttBoard[idx]
                let badge = val == "X" ? "❌" : (val == "O" ? "⭕️" : "Свободно")
                let cellId = "ttt_cell_\(idx)"
                moveRows.append(MTNativeRow(
                    id: cellId,
                    kind: .disclosure(title: "Строка \(r), столбец \(c)", label: badge, icon: nil, enabled: val.isEmpty && winner == nil)
                ))
                model.tap[cellId] = { [weak self] in self?.tapTttCell(idx) }
            }

            let controlRows: [MTNativeRow] = [
                MTNativeRow(id: "ttt_ctrl_hdr", kind: .header("Управление партией")),
                MTNativeRow(id: "ttt_ai", kind: .toggle(title: "Играть против бота", value: state.tttVsAi, enabled: true)),
                MTNativeRow(id: "ttt_send", kind: .action(title: "Отправить ход в чат (Sync)", destructive: false, enabled: self.peerId != nil)),
                MTNativeRow(id: "ttt_reset", kind: .action(title: "Новая партия", destructive: true, enabled: true))
            ]
            model.toggle["ttt_ai"] = { [weak self] on in
                self?.updateState { st in
                    st.tttVsAi = on
                    st.hasMadeMoveThisTurn = false
                }
            }
            model.tap["ttt_send"] = { [weak self] in self?.sendTttMoveToChat() }
            model.tap["ttt_reset"] = { [weak self] in
                self?.updateState { st in
                    st.tttBoard = Array(repeating: "", count: 9)
                    st.tttTurn = "X"
                    st.hasMadeMoveThisTurn = false
                }
            }

            model.sections = [
                modeSection,
                [
                    MTNativeRow(id: "ttt_board_hdr", kind: .header("Игровое поле")),
                    MTNativeRow(id: "ttt_board_info", kind: .info(Self.formatTttGrid(board: state.tttBoard, turn: state.tttTurn)))
                ],
                moveRows,
                controlRows
            ]
        } else {
            model.sections = [
                modeSection,
                [
                    MTNativeRow(id: "g2048_hdr", kind: .header("Поле 2048")),
                    MTNativeRow(id: "g2048_info", kind: .info(Self.format2048Grid(grid: state.grid2048, score: state.score2048, best: state.best2048)))
                ],
                [
                    MTNativeRow(id: "g2048_moves_hdr", kind: .header("Ход")),
                    MTNativeRow(id: "m_up", kind: .action(title: "⬆️ Сдвиг вверх", destructive: false, enabled: true)),
                    MTNativeRow(id: "m_down", kind: .action(title: "⬇️ Сдвиг вниз", destructive: false, enabled: true)),
                    MTNativeRow(id: "m_left", kind: .action(title: "⬅️ Сдвиг влево", destructive: false, enabled: true)),
                    MTNativeRow(id: "m_right", kind: .action(title: "➡️ Сдвиг вправо", destructive: false, enabled: true))
                ],
                [
                    MTNativeRow(id: "g2048_act_hdr", kind: .header("Рекорд и сброс")),
                    MTNativeRow(id: "g2048_share", kind: .action(title: self.peerId != nil ? "Поделиться рекордом в чат" : "Скопировать рекорд", destructive: false, enabled: true)),
                    MTNativeRow(id: "g2048_reset", kind: .action(title: "Начать заново", destructive: true, enabled: true))
                ]
            ]
            model.tap["m_up"] = { [weak self] in self?.perform2048Move(.up) }
            model.tap["m_down"] = { [weak self] in self?.perform2048Move(.down) }
            model.tap["m_left"] = { [weak self] in self?.perform2048Move(.left) }
            model.tap["m_right"] = { [weak self] in self?.perform2048Move(.right) }
            model.tap["g2048_share"] = { [weak self] in self?.share2048Score() }
            model.tap["g2048_reset"] = { [weak self] in
                self?.updateState { st in
                    st.grid2048 = Array(repeating: Array(repeating: 0, count: 4), count: 4)
                    st.score2048 = 0
                    Self.spawn2048Tile(in: &st.grid2048)
                    Self.spawn2048Tile(in: &st.grid2048)
                }
            }
        }
        return model
    }

    private func tapTttCell(_ idx: Int) {
        guard idx >= 0 && idx < 9 else { return }
        let cur = self.stateValue
        guard cur.tttBoard[idx].isEmpty, Self.tttWinner(board: cur.tttBoard) == nil else { return }
        if !cur.tttVsAi && self.peerId != nil && cur.hasMadeMoveThisTurn {
            mtPresentNativeToast(context: self.context, from: self.controller, text: "Сначала отправьте ход в чат или обновите доску")
            return
        }
        self.updateState { st in
            st.tttBoard[idx] = st.tttTurn
            st.tttTurn = st.tttTurn == "X" ? "O" : "X"
            st.hasMadeMoveThisTurn = !st.tttVsAi && (self.peerId != nil)
            if st.tttVsAi && st.tttTurn == "O" && Self.tttWinner(board: st.tttBoard) == nil {
                if let freeIdx = st.tttBoard.indices.filter({ st.tttBoard[$0].isEmpty }).randomElement() {
                    st.tttBoard[freeIdx] = "O"
                    st.tttTurn = "X"
                }
            }
        }
    }

    private func syncTttFromChat() {
        guard let peerId = self.peerId else { return }
        let ownPeerId = self.context.account.peerId
        _ = (self.context.account.postbox.transaction { transaction -> (tag: String, isIncoming: Bool)? in
            var found: (tag: String, isIncoming: Bool)?
            transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 40) { m in
                if found != nil { return false }
                if let r = m.text.range(of: #"\[MT:TTT:[XO_]{9}:[XO]\]"#, options: .regularExpression) {
                    found = (String(m.text[r]), m.flags.contains(.Incoming))
                    return false
                }
                return true
            }
            return found
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] result in
            guard let self, let result else { return }
            let stripped = result.tag.replacingOccurrences(of: "[MT:TTT:", with: "").replacingOccurrences(of: "]", with: "")
            let parts = stripped.split(separator: ":")
            guard parts.count == 2, parts[0].count == 9 else { return }
            let parsedBoard = parts[0].map { $0 == "_" ? "" : String($0) }
            let parsedTurn = String(parts[1])
            let unlock = result.isIncoming || peerId == ownPeerId
            self.updateState { st in
                st.tttBoard = parsedBoard
                st.tttTurn = parsedTurn
                if unlock {
                    st.hasMadeMoveThisTurn = false
                }
            }
            mtPresentNativeToast(
                context: self.context,
                from: self.controller,
                text: unlock ? "Доска синхронизирована — ваш ход" : "Доска синхронизирована (ждём ход соперника)"
            )
        })
    }

    private func sendTttMoveToChat() {
        guard let peerId = self.peerId else {
            mtPresentNativeToast(context: self.context, from: self.controller, text: "Откройте .game внутри чата для отправки хода")
            return
        }
        let st = self.stateValue
        let code = st.tttBoard.map { $0.isEmpty ? "_" : $0 }.joined()
        let rows = [0, 3, 6].map { start in
            (start ..< (start + 3)).map { i in
                st.tttBoard[i] == "X" ? "❌" : (st.tttBoard[i] == "O" ? "⭕️" : "⬜️")
            }.joined()
        }.joined(separator: "\n")
        let status = Self.formatTttStatus(board: st.tttBoard, turn: st.tttTurn)
        let text = "🎮 MediaTok Крестики-нолики\n\(rows)\n\(status)\n[MT:TTT:\(code):\(st.tttTurn)]"
        let msg = EnqueueMessage.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [msg]).start()
        let lockTurn = (peerId != self.context.account.peerId)
        self.updateState { $0.hasMadeMoveThisTurn = lockTurn }
        mtPresentNativeToast(context: self.context, from: self.controller, text: "Ход отправлен в чат")
    }

    private enum Move2048 {
        case left, right, up, down
    }

    private static func spawn2048Tile(in grid: inout [[Int]]) {
        var empty: [(Int, Int)] = []
        for r in 0 ..< 4 {
            for c in 0 ..< 4 where grid[r][c] == 0 {
                empty.append((r, c))
            }
        }
        guard let pick = empty.randomElement() else { return }
        grid[pick.0][pick.1] = Int.random(in: 0 ..< 10) == 0 ? 4 : 2
    }

    private static func compressLine(_ line: [Int]) -> ([Int], Int) {
        let nonZero = line.filter { $0 != 0 }
        var result: [Int] = []
        var gained = 0
        var i = 0
        while i < nonZero.count {
            if i + 1 < nonZero.count && nonZero[i] == nonZero[i + 1] {
                let merged = nonZero[i] * 2
                result.append(merged)
                gained += merged
                i += 2
            } else {
                result.append(nonZero[i])
                i += 1
            }
        }
        while result.count < 4 { result.append(0) }
        return (result, gained)
    }

    private func perform2048Move(_ dir: Move2048) {
        var grid = self.stateValue.grid2048
        let before = grid
        var gainedTotal = 0
        switch dir {
        case .left:
            for r in 0 ..< 4 {
                let (nl, gVal) = Self.compressLine(grid[r])
                grid[r] = nl
                gainedTotal += gVal
            }
        case .right:
            for r in 0 ..< 4 {
                let (nl, gVal) = Self.compressLine(grid[r].reversed())
                grid[r] = nl.reversed()
                gainedTotal += gVal
            }
        case .up:
            for c in 0 ..< 4 {
                let col = (0 ..< 4).map { grid[$0][c] }
                let (nl, gVal) = Self.compressLine(col)
                for r in 0 ..< 4 { grid[r][c] = nl[r] }
                gainedTotal += gVal
            }
        case .down:
            for c in 0 ..< 4 {
                let col = Array((0 ..< 4).map { grid[$0][c] }.reversed())
                let (nl, gVal) = Self.compressLine(col)
                let rev = Array(nl.reversed())
                for r in 0 ..< 4 { grid[r][c] = rev[r] }
                gainedTotal += gVal
            }
        }
        if grid != before {
            let nextScore = self.stateValue.score2048 + gainedTotal
            MTMediaTokWave11Tools.best2048Score = nextScore
            Self.spawn2048Tile(in: &grid)
            let best = MTMediaTokWave11Tools.best2048Score
            self.updateState { st in
                st.grid2048 = grid
                st.score2048 = nextScore
                st.best2048 = best
            }
        }
    }

    private func share2048Score() {
        let score = self.stateValue.score2048
        let best = MTMediaTokWave11Tools.best2048Score
        let text = "🔢 MediaTok 2048 — мой счёт: \(score) (рекорд: \(best)) 🏆"
        if let peerId = self.peerId {
            let msg = EnqueueMessage.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [msg]).start()
            mtPresentNativeToast(context: self.context, from: self.controller, text: "Рекорд отправлен в чат")
        } else {
            UIPasteboard.general.string = text
            mtPresentNativeToast(context: self.context, from: self.controller, text: "Рекорд скопирован")
        }
    }
}

// ============================================================================
// #470 — Built-in RSS / Atom Reader (Native ItemListController)
// ============================================================================

private struct MTRssArticle: Equatable {
    let title: String
    let link: String
    let source: String
}

private final class MTRssXmlParser: NSObject, XMLParserDelegate {
    private var articles: [MTRssArticle] = []
    private var elementStack: [String] = []
    private var currentTitle = ""
    private var currentLink = ""
    private let sourceHost: String

    init(sourceHost: String) {
        self.sourceHost = sourceHost
    }

    func parse(_ data: Data) -> [MTRssArticle] {
        guard data.count <= 2 * 1024 * 1024 else { return [] }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = self
        _ = parser.parse()
        return self.articles
    }

    private var isDirectChildOfItem: Bool {
        guard self.elementStack.count >= 2 else { return false }
        let parent = self.elementStack[self.elementStack.count - 2]
        return parent == "item" || parent == "entry"
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let lower = elementName.lowercased()
        self.elementStack.append(lower)
        if lower == "item" || lower == "entry" {
            self.currentTitle = ""
            self.currentLink = ""
        } else if self.isDirectChildOfItem && lower == "link", let href = attributeDict["href"], !href.isEmpty {
            let rel = (attributeDict["rel"] ?? "alternate").lowercased()
            if self.currentLink.isEmpty || rel == "alternate" {
                self.currentLink = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard self.isDirectChildOfItem, let current = self.elementStack.last else { return }
        if current == "title" {
            self.currentTitle += string
        } else if current == "link" {
            self.currentLink += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard self.isDirectChildOfItem, let current = self.elementStack.last,
              let string = String(data: CDATABlock, encoding: .utf8) else { return }
        if current == "title" {
            self.currentTitle += string
        } else if current == "link" {
            self.currentLink += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let lower = elementName.lowercased()
        if lower == "item" || lower == "entry" {
            let t = self.currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let l = self.currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && !l.isEmpty {
                self.articles.append(MTRssArticle(title: t, link: l, source: self.sourceHost))
            }
        }
        if !self.elementStack.isEmpty {
            _ = self.elementStack.popLast()
        }
    }
}

private final class MTCappedRssDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private let completion: (Data?) -> Void
    private let lock = NSLock()
    private var buffer = Data()
    private var exceeded = false
    private var finished = false

    init(maxBytes: Int, completion: @escaping (Data?) -> Void) {
        self.maxBytes = maxBytes
        self.completion = completion
    }

    private func finish(_ data: Data?) {
        self.lock.lock()
        let shouldCall = !self.finished
        self.finished = true
        self.lock.unlock()
        if shouldCall {
            self.completion(data)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if response.expectedContentLength > Int64(self.maxBytes) {
            self.lock.lock()
            self.exceeded = true
            self.lock.unlock()
            completionHandler(.cancel)
            self.finish(nil)
            session.finishTasksAndInvalidate()
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.lock.lock()
        if self.buffer.count + data.count > self.maxBytes {
            self.exceeded = true
            self.buffer.removeAll(keepingCapacity: false)
            self.lock.unlock()
            dataTask.cancel()
            self.finish(nil)
            session.finishTasksAndInvalidate()
            return
        }
        self.buffer.append(data)
        self.lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.lock.lock()
        let out: Data? = (error == nil && !self.exceeded) ? self.buffer : nil
        self.buffer.removeAll(keepingCapacity: false)
        self.lock.unlock()
        self.finish(out)
        session.finishTasksAndInvalidate()
    }
}

private func mtDownloadCappedRss(url: URL, maxBytes: Int, completion: @escaping (Data?) -> Void) {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = 12.0
    cfg.timeoutIntervalForResource = 15.0
    let delegate = MTCappedRssDelegate(maxBytes: maxBytes, completion: completion)
    let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
    var req = URLRequest(url: url, timeoutInterval: 12.0)
    req.setValue("MediaTok-RSS/1.0", forHTTPHeaderField: "User-Agent")
    session.dataTask(with: req).resume()
}

private func mtMakeNativeRssReaderController(context: AccountContext, peerId: PeerId?) -> ItemListController {
    struct RssState {
        var articles: [MTRssArticle] = []
        var isLoading: Bool = true
        var generation: Int = 0
    }

    let stateAtomic = Atomic<RssState>(value: RssState())
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revCount = 0
    let bump: () -> Void = {
        revCount += 1
        revision.set(revCount)
    }

    weak var weakController: ItemListController?

    let reloadFeeds: () -> Void = {
        let gen = stateAtomic.modify { st -> RssState in
            var next = st
            next.generation += 1
            next.isLoading = true
            next.articles = []
            return next
        }.generation
        bump()

        let feeds = MTMediaTokWave11Tools.savedRssFeeds
        let group = DispatchGroup()
        let collectedBox = MTThreadSafeArray<[MTRssArticle]>(repeating: [], count: feeds.count)

        for (idx, feedStr) in feeds.enumerated() {
            guard let url = URL(string: feedStr),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  let host = url.host else { continue }
            group.enter()
            mtDownloadCappedRss(url: url, maxBytes: 2 * 1024 * 1024) { data in
                if let data {
                    let parsed = Array(MTRssXmlParser(sourceHost: host).parse(data).prefix(12))
                    collectedBox.set(parsed, at: idx)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let articles = collectedBox.snapshot().flatMap { $0 }
            var matched = false
            let _ = stateAtomic.modify { st -> RssState in
                guard st.generation == gen else { return st }
                matched = true
                var next = st
                next.isLoading = false
                next.articles = articles
                return next
            }
            if matched {
                bump()
            }
        }
    }

    reloadFeeds()

    let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let st = stateAtomic.with { $0 }
        let feeds = MTMediaTokWave11Tools.savedRssFeeds
        var screen = MTNativeScreenModel(title: "RSS-ленты")

        screen.sections.append([
            MTNativeRow(id: "rss.ctrl.h", kind: .header("Управление")),
            MTNativeRow(id: "rss.add", kind: .action(title: "Добавить RSS / Atom ленту", destructive: false, enabled: true)),
            MTNativeRow(id: "rss.refresh", kind: .action(title: st.isLoading ? "Обновление лент..." : "Обновить статьи", destructive: false, enabled: !st.isLoading)),
            MTNativeRow(id: "rss.sources", kind: .disclosure(title: "Источники", label: "\(feeds.count)", icon: .system("dot.radiowaves.up.forward"), enabled: !feeds.isEmpty))
        ])

        screen.tap["rss.add"] = {
            mtPresentNativePrompt(
                context: context,
                from: weakController,
                title: "Добавить RSS-ленту",
                subtitle: "Введите URL ленты (например https://habr.com/ru/rss/best/daily/):",
                value: "",
                placeholder: "https://.../rss.xml",
                apply: { raw in
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let url = URL(string: trimmed),
                          let scheme = url.scheme?.lowercased(),
                          (scheme == "http" || scheme == "https"),
                          url.host != nil else {
                        mtPresentNativeToast(context: context, from: weakController, text: "Укажите корректный http:// или https:// URL")
                        return
                    }
                    var list = MTMediaTokWave11Tools.savedRssFeeds
                    if !list.contains(trimmed) {
                        list.insert(trimmed, at: 0)
                        MTMediaTokWave11Tools.savedRssFeeds = list
                    }
                    reloadFeeds()
                }
            )
        }
        screen.tap["rss.refresh"] = {
            reloadFeeds()
        }
        screen.tap["rss.sources"] = {
            let btns: [(title: String, isDestructive: Bool, action: () -> Void)] = feeds.map { feedUrl in
                return (
                    title: "Удалить: \(feedUrl)",
                    isDestructive: true,
                    action: {
                        MTMediaTokWave11Tools.savedRssFeeds = MTMediaTokWave11Tools.savedRssFeeds.filter { $0 != feedUrl }
                        reloadFeeds()
                    }
                )
            }
            mtPresentNativeActionSheet(context: context, from: weakController, title: "Источники RSS", buttons: btns)
        }

        var articleRows: [MTNativeRow] = [
            MTNativeRow(id: "rss.art.h", kind: .header("Последние публикации (\(st.articles.count))"))
        ]
        if st.articles.isEmpty {
            articleRows.append(MTNativeRow(
                id: "rss.empty",
                kind: .info(st.isLoading ? "Загрузка RSS-лент..." : "Нет доступных статей")
            ))
        } else {
            for (idx, a) in st.articles.enumerated() {
                let rowId = "rss.a.\(idx)"
                articleRows.append(MTNativeRow(
                    id: rowId,
                    kind: .disclosure(title: a.title, label: a.source, icon: nil, enabled: true)
                ))
                screen.tap[rowId] = {
                    var btns: [(title: String, isDestructive: Bool, action: () -> Void)] = []
                    if let url = URL(string: a.link),
                       let scheme = url.scheme?.lowercased(),
                       (scheme == "http" || scheme == "https"),
                       url.host != nil {
                        btns.append((title: "Открыть в браузере", isDestructive: false, action: {
                            let sf = SFSafariViewController(url: url)
                            weakController?.view.window?.rootViewController?.present(sf, animated: true)
                        }))
                    }
                    if let pid = peerId {
                        btns.append((title: "Отправить в текущий чат", isDestructive: false, action: {
                            let msg = EnqueueMessage.message(text: "\(a.title)\n\(a.link)", attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                            _ = enqueueMessages(account: context.account, peerId: pid, messages: [msg]).start()
                            mtPresentNativeToast(context: context, from: weakController, text: "Статья отправлена в чат")
                        }))
                    }
                    btns.append((title: "Скопировать ссылку", isDestructive: false, action: {
                        UIPasteboard.general.string = a.link
                        mtPresentNativeToast(context: context, from: weakController, text: "Ссылка скопирована")
                    }))
                    mtPresentNativeActionSheet(context: context, from: weakController, title: a.title, buttons: btns)
                }
            }
        }
        screen.sections.append(articleRows)
        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}

// ============================================================================
// #419 — Universal Clipboard Sync (Phone <-> PC) — Native ItemListController
// ============================================================================

private enum MTSharedClipboardCrypto {
    static let encryptedEnvelopePrefix = "mtclip1:"

    static func encryptPayload(_ plaintext: String, passphrase: String) -> String? {
        var saltBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            return nil
        }
        let salt = Data(saltBytes)
        guard let key = MTMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: passphrase, salt: salt),
              let sealed = try? AES.GCM.seal(Data(plaintext.utf8), using: key, authenticating: Data("MTCLIP1".utf8)),
              let combined = sealed.combined else {
            return nil
        }
        var payload = Data()
        payload.append(salt)
        payload.append(combined)
        return Self.encryptedEnvelopePrefix + payload.base64EncodedString()
    }

    static func decryptPayload(_ envelope: String, passphrase: String) -> String? {
        guard envelope.hasPrefix(Self.encryptedEnvelopePrefix) else { return nil }
        let b64 = String(envelope.dropFirst(Self.encryptedEnvelopePrefix.count))
        guard let raw = Data(base64Encoded: b64), raw.count > 16 + 28 else { return nil }
        let salt = raw.prefix(16)
        let combined = raw.dropFirst(16)
        guard let key = MTMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: passphrase, salt: salt),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: key, authenticating: Data("MTCLIP1".utf8)),
              let str = String(data: plain, encoding: .utf8) else {
            return nil
        }
        return str
    }
}

private func mtMakeNativeSharedClipboardController(context: AccountContext) -> ItemListController {
    struct ClipState {
        var status: String = "Готов к обмену"
        var lastPreview: String = ""
    }

    let stateAtomic = Atomic<ClipState>(value: ClipState())
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revCount = 0
    let bump: () -> Void = {
        revCount += 1
        revision.set(revCount)
    }

    weak var weakController: ItemListController?

    let resolveBaseURL: () -> URL? = {
        let clean = MTMediaTokWave11Tools.clipboardTopic
        if let custom = MTMediaTokWave9Tools.customSyncMirrorURL(forTopic: clean) {
            return custom
        }
        return URL(string: "https://ntfy.sh/\(clean)")
    }

    let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let st = stateAtomic.with { $0 }
        let topic = MTMediaTokWave11Tools.clipboardTopic
        let hasPass = !MTMediaTokWave11Tools.clipboardPassphrase.isEmpty
        var screen = MTNativeScreenModel(title: "Буфер Телефон ↔ ПК")

        screen.sections.append([
            MTNativeRow(id: "clip.cfg.h", kind: .header("Канал и шифрование")),
            MTNativeRow(id: "clip.topic", kind: .disclosure(title: "Приватный топик", label: String(topic.prefix(14)) + "…", icon: .system("key"), enabled: true)),
            MTNativeRow(id: "clip.pass", kind: .disclosure(title: "Пароль AES-256-GCM", label: hasPass ? "Задан" : "Выкл.", icon: .system("lock.shield"), enabled: true)),
            MTNativeRow(id: "clip.cfg.f", kind: .footer("Статус: \(st.status)\(st.lastPreview.isEmpty ? "" : "\nПоследний фрагмент: \(st.lastPreview.prefix(120))")"))
        ])

        screen.tap["clip.topic"] = {
            mtPresentNativePrompt(
                context: context,
                from: weakController,
                title: "Топик синхронизации",
                subtitle: "От 12 до 64 символов (A-Z, 0-9, _ и -):",
                value: MTMediaTokWave11Tools.clipboardTopic,
                placeholder: "mt_clip_...",
                apply: { entered in
                    guard let valid = MTMediaTokWave11Tools.sanitizedTopic(entered.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        mtPresentNativeToast(context: context, from: weakController, text: "Некорректный формат топика (нужно 12–64 симв.)")
                        return
                    }
                    MTMediaTokWave11Tools.clipboardTopic = valid
                    bump()
                }
            )
        }

        screen.tap["clip.pass"] = {
            mtPresentNativePrompt(
                context: context,
                from: weakController,
                title: "Пароль AES-256-GCM",
                subtitle: "Опциональный пароль сквозного шифрования буфера (оставьте пустым для отключения):",
                value: MTMediaTokWave11Tools.clipboardPassphrase,
                placeholder: "Пароль шифрования",
                apply: { entered in
                    MTMediaTokWave11Tools.clipboardPassphrase = entered.trimmingCharacters(in: .whitespacesAndNewlines)
                    bump()
                }
            )
        }

        screen.sections.append([
            MTNativeRow(id: "clip.act.h", kind: .header("Обмен буфером")),
            MTNativeRow(id: "clip.push", kind: .action(title: "Отправить буфер iPhone на ПК", destructive: false, enabled: true)),
            MTNativeRow(id: "clip.pull", kind: .action(title: "Забрать буфер с ПК на iPhone", destructive: false, enabled: true)),
            MTNativeRow(id: "clip.ps", kind: .action(title: "Скопировать команду для Windows PowerShell", destructive: false, enabled: true))
        ])

        screen.tap["clip.push"] = {
            guard let url = resolveBaseURL() else { return }
            let bodyText = UIPasteboard.general.string ?? ""
            guard !bodyText.isEmpty else {
                mtPresentNativeToast(context: context, from: weakController, text: "Буфер обмена на iPhone пуст")
                return
            }
            let pass = MTMediaTokWave11Tools.clipboardPassphrase
            let isEncrypted = !pass.isEmpty
            let _ = stateAtomic.modify { var n = $0; n.status = "Отправка..."; return n }
            bump()

            DispatchQueue.global(qos: .userInitiated).async {
                let wirePayload: String
                if isEncrypted {
                    guard let enc = MTSharedClipboardCrypto.encryptPayload(bodyText, passphrase: pass) else {
                        DispatchQueue.main.async {
                            let _ = stateAtomic.modify { var n = $0; n.status = "Ошибка шифрования"; return n }
                            bump()
                        }
                        return
                    }
                    wirePayload = enc
                } else {
                    wirePayload = bodyText
                }
                var req = URLRequest(url: url, timeoutInterval: 15.0)
                req.httpMethod = "POST"
                req.httpBody = Data(wirePayload.utf8)
                MTMediaTokWave9Tools.urlSession(for: url).dataTask(with: req) { _, resp, err in
                    DispatchQueue.main.async {
                        if let err {
                            let _ = stateAtomic.modify { var n = $0; n.status = "Ошибка: \(err.localizedDescription)"; return n }
                            bump()
                            return
                        }
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        if (200 ... 299).contains(code) {
                            let _ = stateAtomic.modify { var n = $0; n.status = "Отправлено (\(bodyText.count) симв.)"; n.lastPreview = bodyText; return n }
                            bump()
                            mtPresentNativeToast(context: context, from: weakController, text: "Буфер отправлен на ПК")
                        } else {
                            let _ = stateAtomic.modify { var n = $0; n.status = "Сервер вернул HTTP \(code)"; return n }
                            bump()
                        }
                    }
                }.resume()
            }
        }

        screen.tap["clip.pull"] = {
            guard let base = resolveBaseURL(),
                  let url = URL(string: "\(base.absoluteString)/json?poll=1&since=24h") else { return }
            let pass = MTMediaTokWave11Tools.clipboardPassphrase
            let _ = stateAtomic.modify { var n = $0; n.status = "Загрузка с ПК..."; return n }
            bump()

            MTMediaTokWave9Tools.urlSession(for: url).dataTask(with: url) { data, resp, err in
                DispatchQueue.main.async {
                    if let err {
                        let _ = stateAtomic.modify { var n = $0; n.status = "Ошибка: \(err.localizedDescription)"; return n }
                        bump()
                        return
                    }
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200 ... 299).contains(code), let data, let raw = String(data: data, encoding: .utf8) else {
                        let _ = stateAtomic.modify { var n = $0; n.status = "Ошибка чтения (HTTP \(code))"; return n }
                        bump()
                        return
                    }
                    var latestMsg: String?
                    for line in raw.split(separator: "\n").reversed() {
                        if let lData = line.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: lData) as? [String: Any],
                           (obj["event"] as? String ?? "message") == "message",
                           let msg = obj["message"] as? String, !msg.isEmpty {
                            latestMsg = msg
                            break
                        }
                    }
                    guard let latestMsg else {
                        let _ = stateAtomic.modify { var n = $0; n.status = "За 24ч записей не найдено"; return n }
                        bump()
                        return
                    }
                    if latestMsg.hasPrefix(MTSharedClipboardCrypto.encryptedEnvelopePrefix) {
                        guard !pass.isEmpty, let dec = MTSharedClipboardCrypto.decryptPayload(latestMsg, passphrase: pass) else {
                            let _ = stateAtomic.modify { var n = $0; n.status = "Требуется верный пароль AES-256-GCM"; return n }
                            bump()
                            mtPresentNativeToast(context: context, from: weakController, text: "Запись зашифрована — проверьте пароль")
                            return
                        }
                        UIPasteboard.general.string = dec
                        let _ = stateAtomic.modify { var n = $0; n.status = "Расшифровано и скопировано (\(dec.count) симв.)"; n.lastPreview = dec; return n }
                        bump()
                        mtPresentNativeToast(context: context, from: weakController, text: "Буфер получен с ПК")
                    } else {
                        UIPasteboard.general.string = latestMsg
                        let _ = stateAtomic.modify { var n = $0; n.status = "Скопировано (\(latestMsg.count) симв.)"; n.lastPreview = latestMsg; return n }
                        bump()
                        mtPresentNativeToast(context: context, from: weakController, text: "Буфер получен с ПК")
                    }
                }
            }.resume()
        }

        screen.tap["clip.ps"] = {
            guard let base = resolveBaseURL() else { return }
            let baseStr = base.absoluteString
            let ps = """
            # Отправить буфер ПК -> iPhone (UTF-8):
            Invoke-RestMethod -Method Post -Uri '\(baseStr)' -Body ([System.Text.Encoding]::UTF8.GetBytes((Get-Clipboard -Raw)))
            # Забрать буфер iPhone -> ПК (UTF-8):
            (([System.Text.Encoding]::UTF8.GetString((Invoke-WebRequest -UseBasicParsing '\(baseStr)/json?poll=1&since=24h').RawContentStream.ToArray()) -split "`n") | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.event -eq 'message' -and $_.message } | Select-Object -Last 1).message | Set-Clipboard
            """
            UIPasteboard.general.string = ps
            mtPresentNativeToast(context: context, from: weakController, text: "Команды PowerShell скопированы")
        }

        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}
