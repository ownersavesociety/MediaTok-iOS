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

    public static var clipboardPassphrase: String {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: clipboardKeychainService,
                kSecAttrAccount as String: clipboardKeychainAccount,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data,
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            // Migrate legacy UserDefaults passphrase to Keychain
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
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: clipboardKeychainService,
            kSecAttrAccount as String: clipboardKeychainAccount
        ]
        if clean.isEmpty {
            SecItemDelete(base as CFDictionary)
            return
        }
        let data = Data(clean.utf8)
        if SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary) != errSecSuccess {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
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
        let sheet = UIAlertController(
            title: "MediaTok Wave 5 — AI, Игры, RSS и Экосистема",
            message: "Все инструменты 5-й волны в одном месте",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Переводчик текста на фото / манге (.trimg)", style: .default) { _ in
            presentImageTranslator(context: context, initialImage: nil, peerId: peerId)
        })
        sheet.addAction(UIAlertAction(title: "Magic Eraser — умный ластик (.erase)", style: .default) { _ in
            presentMagicEraser(context: context)
        })
        sheet.addAction(UIAlertAction(title: "AI Апскейл фото (.upscale)", style: .default) { _ in
            presentUpscaler(context: context)
        })
        sheet.addAction(UIAlertAction(title: "Мини-игры в чате: Крестики-нолики и 2048 (.game)", style: .default) { _ in
            presentMiniGames(context: context, peerId: peerId, initialTab: 0)
        })
        sheet.addAction(UIAlertAction(title: "Встроенный RSS-ридер (.rss)", style: .default) { _ in
            presentRssReader(context: context, peerId: peerId)
        })
        sheet.addAction(UIAlertAction(title: "Общий буфер обмена Телефон ↔ ПК (.pcclip)", style: .default) { _ in
            presentSharedClipboard(context: context)
        })
        sheet.addAction(UIAlertAction(title: "Siri / Команды, Виджеты, iPad-клавиши, Миграция", style: .default) { _ in
            presentEcosystemHub(context: context)
        })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTModalPresenter.presentOnTopmost(sheet)
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
        let vc = MTUpscaleViewController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        MTModalPresenter.presentOnTopmost(nav)
    }

    public static func presentMiniGames(context: AccountContext, peerId: PeerId?, initialTab: Int = 0) {
        let vc = MTChatMiniGamesViewController(context: context, peerId: peerId, initialTab: initialTab)
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        MTModalPresenter.presentOnTopmost(nav)
    }

    public static func presentRssReader(context: AccountContext, peerId: PeerId?) {
        let vc = MTRssReaderViewController(context: context, peerId: peerId)
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        MTModalPresenter.presentOnTopmost(nav)
    }

    public static func presentSharedClipboard(context: AccountContext) {
        let vc = MTSharedClipboardViewController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        MTModalPresenter.presentOnTopmost(nav)
    }

    public static func presentEcosystemHub(context: AccountContext) {
        refreshWidgetSnapshot()
        let msg = """
        #494 Авто-миграция:
        \(migrationSummary)

        #488 Apple Shortcuts / Siri URL-схемы:
        • mediatok://cmd?action=reconnect
        • mediatok://cmd?action=lyrics
        • mediatok://cmd?action=trimg
        • mediatok://cmd?action=clip
        • mediatok://cmd?action=rss

        #489 Клавиатура iPad / Bluetooth:
        • ⇧⌘K — Spotlight Palette
        • ⇧⌘R — Force Reconnect
        • ⇧⌘L — Караоке-лирика

        #487 Widget Snapshot JSON готов к чтению.
        """
        let alert = UIAlertController(title: "⚡️ Экосистема MediaTok", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Скопировать URL для Команд (Siri)", style: .default) { _ in
            UIPasteboard.general.string = "mediatok://cmd?action=reconnect"
            MTMediaTokWave5Tools.showToast(context: context, text: "📋 mediatok://cmd?action=reconnect скопирован")
        })
        alert.addAction(UIAlertAction(title: "Скопировать JSON виджета", style: .default) { _ in
            UIPasteboard.general.string = widgetSnapshotJson
            MTMediaTokWave5Tools.showToast(context: context, text: "📋 Widget JSON скопирован")
        })
        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        MTModalPresenter.presentOnTopmost(alert)
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
        let buildPayload: (_ uploadedPath: String, _ isAnime: Bool, _ factor: Int) -> [String: Any]
    }

    private static let mirrors: [Mirror] = [
        Mirror(
            name: "Real-ESRGAN Cloud #1",
            baseURL: "https://guetlzy-real-esrgan-demo.hf.space",
            uploadPath: "/gradio_api/upload",
            callPath: "/gradio_api/call/enhance",
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
        var lastError = "Облачные серверы Real-ESRGAN сейчас заняты — попробуй iLoveIMG / Bigjpg ниже или режим «Офлайн»."
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
        guard let resultURLString = self.extractImageURL(fromSSE: sseText, baseURL: mirror.baseURL),
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

    private static func extractImageURL(fromSSE text: String, baseURL: String) -> String? {
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
                        return "\(prefix)/gradio_api/file=\(path)"
                    }
                } else if let str = item as? String, str.hasPrefix("http") {
                    return str
                }
            }
        }
        return nil
    }
}

private final class MTUpscaleViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let context: AccountContext
    private var sourceImage: UIImage?
    private var upscaledImage: UIImage?
    private var activeCancelBox: MTUpscaleCancelBox?

    private let styleSegment = UISegmentedControl(items: ["Онлайн Фото", "Онлайн Арт", "Офлайн Waifu2x"])
    private let factorSegment = UISegmentedControl(items: ["2× HD", "4× Ultra"])
    private let imageView = UIImageView()
    private let compareBadge = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let infoLabel = UILabel()
    private let runBtn = UIButton(type: .system)
    private let shareBtn = UIButton(type: .system)

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        self.activeCancelBox?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = .dark
        self.title = "AI Апскейл фото"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "photo.on.rectangle.angled"),
            style: .done,
            target: self,
            action: #selector(self.pickPhotoTapped)
        )

        self.styleSegment.selectedSegmentIndex = 0
        self.factorSegment.selectedSegmentIndex = 0

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.backgroundColor = UIColor(rgb: 0x1C1C1E)
        self.imageView.layer.cornerRadius = 16
        self.imageView.layer.cornerCurve = .continuous
        self.imageView.clipsToBounds = true
        self.imageView.isUserInteractionEnabled = true

        let holdCompare = UILongPressGestureRecognizer(target: self, action: #selector(self.handleCompareHold(_:)))
        holdCompare.minimumPressDuration = 0.08
        self.imageView.addGestureRecognizer(holdCompare)

        self.compareBadge.text = "  ДО / ПОСЛЕ (удерживай)  "
        self.compareBadge.font = .systemFont(ofSize: 11, weight: .bold)
        self.compareBadge.textColor = .white
        self.compareBadge.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        self.compareBadge.layer.cornerRadius = 8
        self.compareBadge.clipsToBounds = true
        self.compareBadge.isHidden = true
        self.compareBadge.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.addSubview(self.compareBadge)

        self.progressView.progressTintColor = .white
        self.progressView.trackTintColor = UIColor(white: 0.22, alpha: 1.0)
        self.progressView.progress = 0.0
        self.progressView.isHidden = true

        self.infoLabel.textColor = .secondaryLabel
        self.infoLabel.font = .systemFont(ofSize: 13, weight: .medium)
        self.infoLabel.textAlignment = .center
        self.infoLabel.numberOfLines = 2
        self.infoLabel.text = "Бесплатный облачный Real-ESRGAN (без API-ключа) + iLoveIMG / Bigjpg и офлайн-режим."

        self.configureActionBtn(self.runBtn, symbol: "wand.and.stars", title: "Улучшить (Онлайн AI)", bg: .white, fg: .black, action: #selector(self.runUpscaleTapped))
        self.configureActionBtn(self.shareBtn, symbol: "square.and.arrow.up", title: "Сохранить / Отправить", bg: UIColor(rgb: 0x1C1C1E), fg: .white, action: #selector(self.shareTapped))

        let webRow = UIStackView()
        webRow.axis = .horizontal
        webRow.spacing = 8
        webRow.distribution = .fillEqually
        let iloveBtn = UIButton(type: .system)
        self.configureActionBtn(iloveBtn, symbol: "globe", title: "iLoveIMG", bg: UIColor(rgb: 0x1C1C1E), fg: UIColor(white: 0.88, alpha: 1.0), action: #selector(self.openILoveImgTapped))
        let bigjpgBtn = UIButton(type: .system)
        self.configureActionBtn(bigjpgBtn, symbol: "globe", title: "Bigjpg", bg: UIColor(rgb: 0x1C1C1E), fg: UIColor(white: 0.88, alpha: 1.0), action: #selector(self.openBigjpgTapped))
        webRow.addArrangedSubview(iloveBtn)
        webRow.addArrangedSubview(bigjpgBtn)

        let stack = UIStackView(arrangedSubviews: [
            self.styleSegment,
            self.factorSegment,
            self.imageView,
            self.progressView,
            self.infoLabel,
            self.runBtn,
            self.shareBtn,
            webRow
        ])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            self.compareBadge.topAnchor.constraint(equalTo: self.imageView.topAnchor, constant: 10),
            self.compareBadge.trailingAnchor.constraint(equalTo: self.imageView.trailingAnchor, constant: -10),
            self.compareBadge.heightAnchor.constraint(equalToConstant: 24),
            self.runBtn.heightAnchor.constraint(equalToConstant: 46),
            self.shareBtn.heightAnchor.constraint(equalToConstant: 44),
            webRow.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func configureActionBtn(_ b: UIButton, symbol: String, title: String, bg: UIColor, fg: UIColor, action: Selector) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        b.setImage(UIImage(systemName: symbol, withConfiguration: cfg)?.withTintColor(fg, renderingMode: .alwaysOriginal), for: .normal)
        b.setTitle("  " + title, for: .normal)
        b.setTitleColor(fg, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14.5, weight: .semibold)
        b.backgroundColor = bg
        b.layer.cornerRadius = 12
        b.layer.cornerCurve = .continuous
        b.addTarget(self, action: action, for: .touchUpInside)
    }

    private func setRunButtonRendering(_ rendering: Bool) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if rendering {
            self.runBtn.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: cfg)?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
            self.runBtn.setTitle("  Отменить", for: .normal)
            self.runBtn.setTitleColor(.white, for: .normal)
            self.runBtn.backgroundColor = .systemRed
        } else {
            self.runBtn.setImage(UIImage(systemName: "wand.and.stars", withConfiguration: cfg)?.withTintColor(.black, renderingMode: .alwaysOriginal), for: .normal)
            self.runBtn.setTitle("  Улучшить (Онлайн AI)", for: .normal)
            self.runBtn.setTitleColor(.black, for: .normal)
            self.runBtn.backgroundColor = .white
        }
    }

    @objc private func openILoveImgTapped() {
        if let url = URL(string: "https://www.iloveimg.com/upscale-image") {
            let sf = SFSafariViewController(url: url)
            sf.overrideUserInterfaceStyle = .dark
            self.present(sf, animated: true)
        }
    }

    @objc private func openBigjpgTapped() {
        if let url = URL(string: "https://bigjpg.com") {
            let sf = SFSafariViewController(url: url)
            sf.overrideUserInterfaceStyle = .dark
            self.present(sf, animated: true)
        }
    }

    @objc private func closeTapped() {
        self.activeCancelBox?.cancel()
        self.dismiss(animated: true)
    }

    @objc private func handleCompareHold(_ gr: UILongPressGestureRecognizer) {
        guard let src = self.sourceImage, let up = self.upscaledImage else { return }
        switch gr.state {
        case .began, .changed:
            self.imageView.image = src
            self.compareBadge.text = "  ОРИГИНАЛ  "
        default:
            self.imageView.image = up
            self.compareBadge.text = "  ДО / ПОСЛЕ (удерживай)  "
        }
    }

    @objc private func pickPhotoTapped() {
        guard self.activeCancelBox == nil else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        self.present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let img = info[.originalImage] as? UIImage {
            let normalized = MTNeuralWaifu2xModel.normalizeOrientation(img)
            self.sourceImage = normalized
            self.upscaledImage = nil
            self.compareBadge.isHidden = true
            self.imageView.image = normalized
            let w = Int(normalized.size.width.rounded())
            let h = Int(normalized.size.height.rounded())
            self.infoLabel.text = "Оригинал: \(w)×\(h) px. Нажми «Улучшить (Онлайн AI)»."
        }
    }

    @objc private func runUpscaleTapped() {
        if let active = self.activeCancelBox {
            active.cancel()
            return
        }
        guard let src = self.sourceImage else {
            self.pickPhotoTapped()
            return
        }
        let modeIdx = self.styleSegment.selectedSegmentIndex
        let factor: Int = self.factorSegment.selectedSegmentIndex == 0 ? 2 : 4
        let srcW = Int(src.size.width.rounded())
        let srcH = Int(src.size.height.rounded())

        let cancelBox = MTUpscaleCancelBox()
        self.activeCancelBox = cancelBox
        self.setRunButtonRendering(true)
        self.progressView.progress = 0.08
        self.progressView.isHidden = false
        self.infoLabel.text = modeIdx == 2 ? "Запуск офлайн-нейросети Waifu2x..." : "Подключение к облачному Real-ESRGAN..."
        let startedAt = CFAbsoluteTimeGetCurrent()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result: UIImage
                let engineTag: String
                if modeIdx == 2 {
                    engineTag = "Waifu2x"
                    result = try MTNeuralWaifu2xModel.upscale(
                        image: src,
                        style: .photo,
                        factor: factor,
                        maxOutputSide: 4096,
                        isCancelled: { cancelBox.isCancelled },
                        onProgress: { progress, statusText in
                            DispatchQueue.main.async { [weak self] in
                                guard let self, self.activeCancelBox === cancelBox else { return }
                                self.progressView.setProgress(progress, animated: true)
                                self.infoLabel.text = statusText
                            }
                        }
                    )
                } else {
                    engineTag = "Real-ESRGAN Cloud"
                    result = try MTOnlineRealESRGAN.upscale(
                        image: src,
                        isAnime: modeIdx == 1,
                        factor: factor,
                        isCancelled: { cancelBox.isCancelled },
                        onProgress: { progress, statusText in
                            DispatchQueue.main.async { [weak self] in
                                guard let self, self.activeCancelBox === cancelBox else { return }
                                self.progressView.setProgress(progress, animated: true)
                                self.infoLabel.text = statusText
                            }
                        }
                    )
                }
                let elapsed = max(0.05, CFAbsoluteTimeGetCurrent() - startedAt)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.activeCancelBox === cancelBox else { return }
                    self.activeCancelBox = nil
                    self.setRunButtonRendering(false)
                    self.progressView.isHidden = true
                    self.upscaledImage = result
                    self.imageView.image = result
                    self.compareBadge.text = "  ДО / ПОСЛЕ (удерживай)  "
                    self.compareBadge.isHidden = false
                    let outW = Int((result.size.width * result.scale).rounded())
                    let outH = Int((result.size.height * result.scale).rounded())
                    self.infoLabel.text = String(format: "Готово за %.1f сек: %d×%d → %d×%d px (%@)", elapsed, srcW, srcH, outW, outH, engineTag)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.activeCancelBox === cancelBox else { return }
                    self.activeCancelBox = nil
                    self.setRunButtonRendering(false)
                    self.progressView.isHidden = true
                    self.infoLabel.text = error.localizedDescription
                }
            }
        }
    }

    @objc private func shareTapped() {
        guard let img = self.upscaledImage ?? self.sourceImage else {
            self.pickPhotoTapped()
            return
        }
        let ctx = self.context
        let sheet = UIAlertController(title: "Экспорт 4K PNG", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Отправить файлом в Избранное (без сжатия)", style: .default, handler: { [weak self] _ in
            guard let pngData = img.pngData() else { return }
            let w = Int32((img.size.width * img.scale).rounded())
            let h = Int32((img.size.height * img.scale).rounded())
            let fileId = Int64.random(in: Int64.min ... Int64.max)
            let resource = LocalFileMediaResource(fileId: fileId, size: Int64(pngData.count), isSecretRelated: false)
            ctx.account.postbox.mediaBox.storeResourceData(resource.id, data: pngData, synchronous: true)
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
                    .FileName(fileName: "MediaTok_Waifu2x_\(w)x\(h).png"),
                    .ImageSize(size: PixelDimensions(width: w, height: h))
                ],
                alternativeRepresentations: []
            )
            let _ = enqueueMessages(account: ctx.account, peerId: ctx.account.peerId, messages: [
                .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            ]).startStandalone()
            self?.infoLabel.text = "Отправлено без потери качества в Избранное (\(w)×\(h) PNG)"
        }))
        sheet.addAction(UIAlertAction(title: "Сохранить в Фото / Поделиться...", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let ac = UIActivityViewController(activityItems: [img], applicationActivities: nil)
            MTModalPresenter.configurePopover(ac, hostView: self.view)
            self.present(ac, animated: true)
        }))
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTModalPresenter.configurePopover(sheet, hostView: self.view, sourceView: self.shareBtn)
        self.present(sheet, animated: true)
    }
}

// ============================================================================
// #467 — Chat-Synced Mini-Games (Tic-Tac-Toe [MT:TTT] + Playable 2048)
// ============================================================================

private final class MTChatMiniGamesViewController: UIViewController {
    private let context: AccountContext
    private let peerId: PeerId?
    private let modeSegment = UISegmentedControl(items: ["Крестики-нолики", "2048"])
    private let tttContainer = UIView()
    private let g2048Container = UIView()

    // Tic-Tac-Toe state
    private var tttBoard: [String] = Array(repeating: "", count: 9)
    private var tttTurn: String = "X"
    private var tttVsAi: Bool = false
    private var hasMadeMoveThisTurn: Bool = false
    private var tttButtons: [UIButton] = []
    private let tttStatusLabel = UILabel()

    // 2048 state
    private var grid2048: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    private var score2048: Int = 0
    private var tileLabels: [[UILabel]] = []
    private let score2048Label = UILabel()

    init(context: AccountContext, peerId: PeerId?, initialTab: Int) {
        self.context = context
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
        self.modeSegment.selectedSegmentIndex = initialTab
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        self.title = "Мини-игры MediaTok"
        self.view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        if self.peerId != nil {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(syncTttFromChat))
        }

        self.modeSegment.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        self.modeSegment.translatesAutoresizingMaskIntoConstraints = false
        self.tttContainer.translatesAutoresizingMaskIntoConstraints = false
        self.g2048Container.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.modeSegment)
        self.view.addSubview(self.tttContainer)
        self.view.addSubview(self.g2048Container)

        NSLayoutConstraint.activate([
            self.modeSegment.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            self.modeSegment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.modeSegment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.tttContainer.topAnchor.constraint(equalTo: self.modeSegment.bottomAnchor, constant: 14),
            self.tttContainer.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.tttContainer.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.tttContainer.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -14),

            self.g2048Container.topAnchor.constraint(equalTo: self.modeSegment.bottomAnchor, constant: 14),
            self.g2048Container.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.g2048Container.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.g2048Container.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -14)
        ])

        buildTicTacToeUI()
        build2048UI()
        modeChanged()
        if self.peerId != nil {
            syncTttFromChat()
        }
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }

    @objc private func modeChanged() {
        let isTtt = self.modeSegment.selectedSegmentIndex == 0
        self.tttContainer.isHidden = !isTtt
        self.g2048Container.isHidden = isTtt
    }

    // MARK: Tic-Tac-Toe

    private func buildTicTacToeUI() {
        self.tttStatusLabel.textColor = .white
        self.tttStatusLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        self.tttStatusLabel.textAlignment = .center
        self.tttStatusLabel.text = "Ход: ❌"

        let gridStack = UIStackView()
        gridStack.axis = .vertical
        gridStack.spacing = 8
        gridStack.distribution = .fillEqually

        self.tttButtons.removeAll()
        for r in 0..<3 {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            for c in 0..<3 {
                let idx = r * 3 + c
                let btn = UIButton(type: .system)
                btn.tag = idx
                btn.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
                btn.layer.cornerRadius = 14
                btn.titleLabel?.font = .systemFont(ofSize: 40, weight: .bold)
                btn.setTitleColor(.white, for: .normal)
                btn.addTarget(self, action: #selector(tttCellTapped(_:)), for: .touchUpInside)
                self.tttButtons.append(btn)
                row.addArrangedSubview(btn)
            }
            gridStack.addArrangedSubview(row)
        }

        let sendBtn = makeGameBtn("📤 Отправить ход в чат (Sync)", .systemBlue, #selector(sendTttMoveToChat))
        let aiBtn = makeGameBtn("🤖 Режим с ботом: ВЫКЛ", UIColor(white: 0.22, alpha: 1.0), #selector(toggleAiTapped(_:)))
        let resetBtn = makeGameBtn("🔄 Новая партия", .systemOrange, #selector(resetTttTapped))

        let stack = UIStackView(arrangedSubviews: [self.tttStatusLabel, gridStack, sendBtn, aiBtn, resetBtn])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.tttContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.tttContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: self.tttContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: self.tttContainer.trailingAnchor),
            gridStack.heightAnchor.constraint(equalTo: gridStack.widthAnchor, multiplier: 0.92),
            sendBtn.heightAnchor.constraint(equalToConstant: 44),
            aiBtn.heightAnchor.constraint(equalToConstant: 42),
            resetBtn.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func makeGameBtn(_ title: String, _ bg: UIColor, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.backgroundColor = bg
        b.layer.cornerRadius = 12
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    @objc private func tttCellTapped(_ sender: UIButton) {
        let idx = sender.tag
        guard self.tttBoard[idx].isEmpty, tttWinner() == nil else { return }
        if !self.tttVsAi && self.peerId != nil && self.hasMadeMoveThisTurn {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "📤 Сначала отправь ход в чат (или обнови доску)")
            return
        }
        self.tttBoard[idx] = self.tttTurn
        self.tttTurn = self.tttTurn == "X" ? "O" : "X"
        self.hasMadeMoveThisTurn = !self.tttVsAi && (self.peerId != nil)
        refreshTttUI()

        if self.tttVsAi && self.tttTurn == "O" && tttWinner() == nil {
            if let freeIdx = self.tttBoard.indices.filter({ self.tttBoard[$0].isEmpty }).randomElement() {
                self.tttBoard[freeIdx] = "O"
                self.tttTurn = "X"
                refreshTttUI()
            }
        }
    }

    private func tttWinner() -> String? {
        let lines = [
            [0,1,2],[3,4,5],[6,7,8],
            [0,3,6],[1,4,7],[2,5,8],
            [0,4,8],[2,4,6]
        ]
        for l in lines {
            let a = self.tttBoard[l[0]]
            if !a.isEmpty && a == self.tttBoard[l[1]] && a == self.tttBoard[l[2]] {
                return a
            }
        }
        if !self.tttBoard.contains("") { return "DRAW" }
        return nil
    }

    private func refreshTttUI() {
        for i in 0..<9 {
            let v = self.tttBoard[i]
            self.tttButtons[i].setTitle(v == "X" ? "❌" : (v == "O" ? "⭕️" : ""), for: .normal)
        }
        if let w = tttWinner() {
            self.tttStatusLabel.text = w == "DRAW" ? "🤝 Ничья!" : "🏆 Победил \(w == "X" ? "❌" : "⭕️")!"
        } else {
            self.tttStatusLabel.text = "Ход: \(self.tttTurn == "X" ? "❌" : "⭕️")"
        }
    }

    @objc private func toggleAiTapped(_ sender: UIButton) {
        self.tttVsAi.toggle()
        self.hasMadeMoveThisTurn = false
        sender.setTitle("🤖 Режим с ботом: \(self.tttVsAi ? "ВКЛ" : "ВЫКЛ")", for: .normal)
    }

    @objc private func resetTttTapped() {
        self.tttBoard = Array(repeating: "", count: 9)
        self.tttTurn = "X"
        self.hasMadeMoveThisTurn = false
        refreshTttUI()
    }

    @objc private func syncTttFromChat() {
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
            self.tttBoard = parts[0].map { $0 == "_" ? "" : String($0) }
            self.tttTurn = String(parts[1])
            if result.isIncoming || peerId == ownPeerId {
                self.hasMadeMoveThisTurn = false
            }
            self.refreshTttUI()
            MTMediaTokWave5Tools.showToast(context: self.context, text: result.isIncoming || peerId == ownPeerId ? "🎮 Доска синхронизирована — твой ход!" : "🎮 Доска синхронизирована (ждём ход соперника)")
        })
    }

    @objc private func sendTttMoveToChat() {
        guard let peerId = self.peerId else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Открой .game внутри чата для отправки хода")
            return
        }
        let code = self.tttBoard.map { $0.isEmpty ? "_" : $0 }.joined()
        let rows = [0, 3, 6].map { start in
            (start..<(start + 3)).map { i in
                self.tttBoard[i] == "X" ? "❌" : (self.tttBoard[i] == "O" ? "⭕️" : "⬜️")
            }.joined()
        }.joined(separator: "\n")
        let status = self.tttStatusLabel.text ?? ""
        let text = "🎮 MediaTok Крестики-нолики\n\(rows)\n\(status)\n[MT:TTT:\(code):\(self.tttTurn)]"
        let msg = EnqueueMessage.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [msg]).start()
        self.hasMadeMoveThisTurn = (peerId != self.context.account.peerId)
        MTMediaTokWave5Tools.showToast(context: self.context, text: "📤 Ход отправлен в чат!")
    }

    // MARK: 2048

    private func build2048UI() {
        self.score2048Label.textColor = .white
        self.score2048Label.font = .systemFont(ofSize: 16, weight: .bold)
        self.score2048Label.textAlignment = .center

        let board = UIStackView()
        board.axis = .vertical
        board.spacing = 6
        board.distribution = .fillEqually
        board.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        board.layer.cornerRadius = 14
        board.isLayoutMarginsRelativeArrangement = true
        board.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        self.tileLabels.removeAll()
        for _ in 0..<4 {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
            var rowLabels: [UILabel] = []
            for _ in 0..<4 {
                let lbl = UILabel()
                lbl.textAlignment = .center
                lbl.font = .systemFont(ofSize: 22, weight: .heavy)
                lbl.layer.cornerRadius = 10
                lbl.clipsToBounds = true
                row.addArrangedSubview(lbl)
                rowLabels.append(lbl)
            }
            self.tileLabels.append(rowLabels)
            board.addArrangedSubview(row)
        }

        for dir: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handle2048Swipe(_:)))
            swipe.direction = dir
            board.addGestureRecognizer(swipe)
        }

        let shareScoreBtn = makeGameBtn("🏆 Поделиться рекордом в чат", .systemGreen, #selector(share2048Score))
        let reset2048Btn = makeGameBtn("🔄 Заново", .systemOrange, #selector(reset2048Tapped))

        let stack = UIStackView(arrangedSubviews: [self.score2048Label, board, shareScoreBtn, reset2048Btn])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.g2048Container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.g2048Container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: self.g2048Container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: self.g2048Container.trailingAnchor),
            board.heightAnchor.constraint(equalTo: board.widthAnchor),
            shareScoreBtn.heightAnchor.constraint(equalToConstant: 44),
            reset2048Btn.heightAnchor.constraint(equalToConstant: 42)
        ])

        reset2048Tapped()
    }

    @objc private func reset2048Tapped() {
        self.grid2048 = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        self.score2048 = 0
        spawn2048Tile()
        spawn2048Tile()
        refresh2048UI()
    }

    private func spawn2048Tile() {
        var empty: [(Int, Int)] = []
        for r in 0..<4 {
            for c in 0..<4 where self.grid2048[r][c] == 0 {
                empty.append((r, c))
            }
        }
        guard let pick = empty.randomElement() else { return }
        self.grid2048[pick.0][pick.1] = Int.random(in: 0..<10) == 0 ? 4 : 2
    }

    private func compressLine(_ line: [Int]) -> ([Int], Int) {
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

    @objc private func handle2048Swipe(_ g: UISwipeGestureRecognizer) {
        let before = self.grid2048
        var gainedTotal = 0
        switch g.direction {
        case .left:
            for r in 0..<4 {
                let (nl, gVal) = compressLine(self.grid2048[r])
                self.grid2048[r] = nl
                gainedTotal += gVal
            }
        case .right:
            for r in 0..<4 {
                let (nl, gVal) = compressLine(self.grid2048[r].reversed())
                self.grid2048[r] = nl.reversed()
                gainedTotal += gVal
            }
        case .up:
            for c in 0..<4 {
                let col = (0..<4).map { self.grid2048[$0][c] }
                let (nl, gVal) = compressLine(col)
                for r in 0..<4 { self.grid2048[r][c] = nl[r] }
                gainedTotal += gVal
            }
        case .down:
            for c in 0..<4 {
                let col = (0..<4).map { self.grid2048[$0][c] }.reversed()
                let (nl, gVal) = compressLine(Array(col))
                let rev = Array(nl.reversed())
                for r in 0..<4 { self.grid2048[r][c] = rev[r] }
                gainedTotal += gVal
            }
        default:
            break
        }
        if self.grid2048 != before {
            self.score2048 += gainedTotal
            MTMediaTokWave11Tools.best2048Score = self.score2048
            spawn2048Tile()
            refresh2048UI()
        }
    }

    private func tileColor(_ v: Int) -> UIColor {
        switch v {
        case 0: return UIColor(white: 0.20, alpha: 1.0)
        case 2: return UIColor(red: 0.30, green: 0.34, blue: 0.42, alpha: 1.0)
        case 4: return UIColor(red: 0.35, green: 0.42, blue: 0.55, alpha: 1.0)
        case 8: return UIColor.systemOrange
        case 16: return UIColor.systemRed
        case 32: return UIColor.systemPink
        case 64: return UIColor.systemPurple
        case 128, 256, 512: return UIColor.systemIndigo
        default: return UIColor.systemYellow
        }
    }

    private func refresh2048UI() {
        self.score2048Label.text = "Счёт: \(self.score2048)  •  Рекорд: \(MTMediaTokWave11Tools.best2048Score) (свайпай)"
        for r in 0..<4 {
            for c in 0..<4 {
                let v = self.grid2048[r][c]
                let lbl = self.tileLabels[r][c]
                lbl.text = v == 0 ? "" : "\(v)"
                lbl.backgroundColor = tileColor(v)
                lbl.textColor = v >= 1024 ? .black : .white
            }
        }
    }

    @objc private func share2048Score() {
        let text = "🔢 MediaTok 2048 — мой счёт: \(self.score2048) (рекорд: \(MTMediaTokWave11Tools.best2048Score)) 🏆"
        if let peerId = self.peerId {
            let msg = EnqueueMessage.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [msg]).start()
            MTMediaTokWave5Tools.showToast(context: self.context, text: "🏆 Рекорд отправлен в чат!")
        } else {
            UIPasteboard.general.string = text
            MTMediaTokWave5Tools.showToast(context: self.context, text: "📋 Рекорд скопирован")
        }
    }
}

// ============================================================================
// #470 — Built-in RSS / Atom Reader ViewController
// ============================================================================

private struct MTRssArticle {
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

private final class MTRssReaderViewController: UITableViewController {
    private let context: AccountContext
    private let peerId: PeerId?
    private var articles: [MTRssArticle] = []
    private var isLoading: Bool = false

    init(context: AccountContext, peerId: PeerId?) {
        self.context = context
        self.peerId = peerId
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "📰 RSS-ридер"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        let addBtn = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addFeedTapped))
        let refreshBtn = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reloadFeeds))
        self.navigationItem.rightBarButtonItems = [addBtn, refreshBtn]
        reloadFeeds()
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }

    @objc private func addFeedTapped() {
        let alert = UIAlertController(title: "Добавить RSS / Atom ленту", message: "Введи URL фида (например https://habr.com/ru/rss/best/daily/)", preferredStyle: .alert)
        alert.addTextField { tf in tf.placeholder = "https://.../rss.xml" }
        alert.addAction(UIAlertAction(title: "Добавить", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            guard let raw = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.host != nil else {
                MTMediaTokWave5Tools.showToast(context: self.context, text: "Введите корректный http:// или https:// URL ленты")
                return
            }
            var feeds = MTMediaTokWave11Tools.savedRssFeeds
            if !feeds.contains(raw) {
                feeds.insert(raw, at: 0)
                MTMediaTokWave11Tools.savedRssFeeds = feeds
            }
            self.reloadFeeds()
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.present(alert, animated: true)
    }

    private var reloadGeneration: Int = 0

    @objc private func reloadFeeds() {
        self.reloadGeneration += 1
        let gen = self.reloadGeneration
        let feeds = MTMediaTokWave11Tools.savedRssFeeds
        self.articles = []
        self.isLoading = true
        self.tableView.reloadData()

        let group = DispatchGroup()
        let collectedBox = MTThreadSafeArray<[MTRssArticle]>(repeating: [], count: feeds.count)

        for (idx, feedStr) in feeds.enumerated() {
            guard let url = URL(string: feedStr),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  let host = url.host else { continue }
            group.enter()
            Self.downloadCappedRss(url: url, maxBytes: 2 * 1024 * 1024) { data in
                if let data {
                    let parsed = Array(MTRssXmlParser(sourceHost: host).parse(data).prefix(12))
                    collectedBox.set(parsed, at: idx)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, self.reloadGeneration == gen else { return }
            self.isLoading = false
            self.articles = collectedBox.snapshot().flatMap { $0 }
            self.tableView.reloadData()
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

    private static func downloadCappedRss(url: URL, maxBytes: Int, completion: @escaping (Data?) -> Void) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12.0
        cfg.timeoutIntervalForResource = 15.0
        let delegate = MTCappedRssDelegate(maxBytes: maxBytes, completion: completion)
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        var req = URLRequest(url: url, timeoutInterval: 12.0)
        req.setValue("MediaTok-RSS/1.0", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: req).resume()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(1, self.articles.count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "rss") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "rss")
        if self.articles.isEmpty {
            cell.textLabel?.text = self.isLoading ? "Загрузка RSS-лент..." : "Нет доступных статей (проверь подключение или URL лент)"
            cell.detailTextLabel?.text = "\(MTMediaTokWave11Tools.savedRssFeeds.count) источников"
            cell.accessoryType = .none
        } else {
            let a = self.articles[indexPath.row]
            cell.textLabel?.text = a.title
            cell.textLabel?.numberOfLines = 2
            cell.detailTextLabel?.text = "\(a.source) • \(a.link)"
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < self.articles.count else { return }
        let a = self.articles[indexPath.row]
        let sheet = UIAlertController(title: a.title, message: a.source, preferredStyle: .actionSheet)
        if let url = URL(string: a.link),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           url.host != nil {
            sheet.addAction(UIAlertAction(title: "🌐 Открыть статью", style: .default) { [weak self] _ in
                let sf = SFSafariViewController(url: url)
                self?.present(sf, animated: true)
            })
        }
        if let peerId = self.peerId {
            sheet.addAction(UIAlertAction(title: "📤 Переслать в текущий чат", style: .default) { [weak self] _ in
                guard let self else { return }
                let msg = EnqueueMessage.message(text: "📰 \(a.title)\n\(a.link)", attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [msg]).start()
                MTMediaTokWave5Tools.showToast(context: self.context, text: "📤 Статья отправлена в чат")
            })
        }
        sheet.addAction(UIAlertAction(title: "📋 Скопировать ссылку", style: .default) { [weak self] _ in
            guard let self else { return }
            UIPasteboard.general.string = a.link
            MTMediaTokWave5Tools.showToast(context: self.context, text: "📋 Ссылка скопирована")
        })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTModalPresenter.configurePopover(sheet, hostView: self.view)
        self.present(sheet, animated: true)
    }
}

// ============================================================================
// #419 — Universal Clipboard Sync (Phone <-> PC)
// ============================================================================

private final class MTSharedClipboardViewController: UIViewController {
    private static let encryptedEnvelopePrefix = "mtclip1:"

    private let context: AccountContext
    private let topicField = UITextField()
    private let passField = UITextField()
    private let textView = UITextView()
    private let statusLabel = UILabel()

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func encryptPayload(_ plaintext: String, passphrase: String) -> String? {
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

    private static func decryptPayload(_ envelope: String, passphrase: String) -> String? {
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

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "📋 Буфер Телефон ↔ ПК"
        self.view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.topicField.borderStyle = .roundedRect
        self.topicField.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        self.topicField.textColor = .white
        self.topicField.text = MTMediaTokWave11Tools.clipboardTopic
        self.topicField.placeholder = "Приватный 128-бит топик (A-Z, 0-9, _ -)"

        self.passField.borderStyle = .roundedRect
        self.passField.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        self.passField.textColor = .white
        self.passField.isSecureTextEntry = true
        self.passField.text = MTMediaTokWave11Tools.clipboardPassphrase
        self.passField.placeholder = "Пароль E2E AES-256-GCM (опционально для шифрования)"

        self.textView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        self.textView.textColor = .white
        self.textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        self.textView.layer.cornerRadius = 12
        self.textView.text = UIPasteboard.general.string ?? ""

        self.statusLabel.textColor = .secondaryLabel
        self.statusLabel.font = .systemFont(ofSize: 12)
        self.statusLabel.numberOfLines = 2
        self.statusLabel.text = "128-бит топик + опциональное E2E шифрование AES-256-GCM между устройствами."

        let pushBtn = makeBtn("⬆️ Отправить буфер на ПК", .systemBlue, #selector(pushTapped))
        let pullBtn = makeBtn("⬇️ Забрать буфер с ПК", .systemGreen, #selector(pullTapped))
        let pcCmdBtn = makeBtn("💻 Скопировать команду для Windows PowerShell", UIColor(white: 0.22, alpha: 1.0), #selector(copyPsTapped))

        let row = UIStackView(arrangedSubviews: [pushBtn, pullBtn])
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [self.topicField, self.passField, self.textView, self.statusLabel, row, pcCmdBtn])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            self.topicField.heightAnchor.constraint(equalToConstant: 40),
            self.passField.heightAnchor.constraint(equalToConstant: 40),
            row.heightAnchor.constraint(equalToConstant: 46),
            pcCmdBtn.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func makeBtn(_ title: String, _ bg: UIColor, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.backgroundColor = bg
        b.layer.cornerRadius = 12
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }

    private func baseTopicURL() -> URL? {
        let input = (self.topicField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty {
            guard let valid = MTMediaTokWave11Tools.sanitizedTopic(input) else {
                self.statusLabel.text = "⚠️ Топик: латиница, цифры, _ и - (от 12 до 64 симв.)"
                return nil
            }
            MTMediaTokWave11Tools.clipboardTopic = valid
        }
        let pass = (self.passField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        MTMediaTokWave11Tools.clipboardPassphrase = pass
        let clean = MTMediaTokWave11Tools.clipboardTopic
        self.topicField.text = clean
        if let custom = MTMediaTokWave9Tools.customSyncMirrorURL(forTopic: clean) {
            return custom
        }
        return URL(string: "https://ntfy.sh/\(clean)")
    }

    @objc private func pushTapped() {
        guard let url = baseTopicURL() else { return }
        let bodyText = (self.textView.text ?? "").isEmpty ? (UIPasteboard.general.string ?? "") : (self.textView.text ?? "")
        guard !bodyText.isEmpty else {
            self.statusLabel.text = "Буфер пуст."
            return
        }
        let pass = MTMediaTokWave11Tools.clipboardPassphrase
        let isEncrypted = !pass.isEmpty
        self.statusLabel.text = isEncrypted ? "⬆️ Шифрую AES-256-GCM и отправляю..." : "⬆️ Отправляю..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let wirePayload: String
            if isEncrypted {
                guard let enc = Self.encryptPayload(bodyText, passphrase: pass) else {
                    DispatchQueue.main.async { self?.statusLabel.text = "Ошибка AES-GCM шифрования." }
                    return
                }
                wirePayload = enc
            } else {
                wirePayload = bodyText
            }
            var req = URLRequest(url: url, timeoutInterval: 15.0)
            req.httpMethod = "POST"
            req.httpBody = Data(wirePayload.utf8)
            MTMediaTokWave9Tools.urlSession(for: url).dataTask(with: req) { [weak self] _, resp, err in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if let err {
                        self.statusLabel.text = "Ошибка: \(err.localizedDescription)"
                        return
                    }
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if (200...299).contains(code) {
                        let badge = isEncrypted ? "🔒 AES-256-GCM" : "открытый текст"
                        self.statusLabel.text = "✅ Отправлено (HTTP \(code), \(badge)), \(bodyText.count) симв."
                        MTMediaTokWave5Tools.showToast(context: self.context, text: "⬆️ Буфер отправлен на ПК")
                    } else {
                        self.statusLabel.text = "❌ Сервер вернул HTTP \(code)"
                    }
                }
            }.resume()
        }
    }

    @objc private func pullTapped() {
        guard let base = baseTopicURL(),
              let url = URL(string: "\(base.absoluteString)/json?poll=1&since=24h") else { return }
        let pass = MTMediaTokWave11Tools.clipboardPassphrase
        self.statusLabel.text = "⬇️ Проверяю последние записи..."
        MTMediaTokWave9Tools.urlSession(for: url).dataTask(with: url) { [weak self] data, resp, err in
            if let err {
                DispatchQueue.main.async { self?.statusLabel.text = "Ошибка: \(err.localizedDescription)" }
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(code),
                  let data,
                  let raw = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { self?.statusLabel.text = "Ошибка чтения (HTTP \(code))." }
                return
            }
            let lines = raw.split(separator: "\n")
            var latestMsg: String?
            for line in lines.reversed() {
                if let lData = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: lData) as? [String: Any],
                   (obj["event"] as? String ?? "message") == "message",
                   let msg = obj["message"] as? String, !msg.isEmpty {
                    latestMsg = msg
                    break
                }
            }
            guard let latestMsg else {
                DispatchQueue.main.async { self?.statusLabel.text = "За последние 24ч записей не найдено." }
                return
            }
            if latestMsg.hasPrefix(Self.encryptedEnvelopePrefix) {
                guard !pass.isEmpty else {
                    DispatchQueue.main.async { self?.statusLabel.text = "🔒 Запись зашифрована AES-256-GCM — введи пароль E2E выше." }
                    return
                }
                guard let decrypted = Self.decryptPayload(latestMsg, passphrase: pass) else {
                    DispatchQueue.main.async { self?.statusLabel.text = "❌ Неверный пароль E2E AES-256-GCM." }
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.textView.text = decrypted
                    UIPasteboard.general.string = decrypted
                    self.statusLabel.text = "✅ Расшифровано AES-256-GCM и скопировано (\(decrypted.count) симв.)"
                    MTMediaTokWave5Tools.showToast(context: self.context, text: "⬇️ Буфер получен с ПК!")
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.textView.text = latestMsg
                    UIPasteboard.general.string = latestMsg
                    self.statusLabel.text = "✅ Получено и скопировано (\(latestMsg.count) симв.)"
                    MTMediaTokWave5Tools.showToast(context: self.context, text: "⬇️ Буфер получен с ПК!")
                }
            }
        }.resume()
    }

    @objc private func copyPsTapped() {
        guard let base = baseTopicURL() else { return }
        let baseStr = base.absoluteString
        let e2eNote = MTMediaTokWave11Tools.clipboardPassphrase.isEmpty ? "" : "# Внимание: на iPhone задан пароль E2E (mtclip1:...) — очисти пароль для открытого обмена с PowerShell.\n"
        let ps = """
        \(e2eNote)# Отправить буфер ПК -> iPhone (UTF-8):
        Invoke-RestMethod -Method Post -Uri '\(baseStr)' -Body ([System.Text.Encoding]::UTF8.GetBytes((Get-Clipboard -Raw)))
        # Забрать буфер iPhone -> ПК (UTF-8, без кракозябр в PS 5.1):
        (([System.Text.Encoding]::UTF8.GetString((Invoke-WebRequest -UseBasicParsing '\(baseStr)/json?poll=1&since=24h').RawContentStream.ToArray()) -split "`n") | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.event -eq 'message' -and $_.message } | Select-Object -Last 1).message | Set-Clipboard
        """
        UIPasteboard.general.string = ps
        MTMediaTokWave5Tools.showToast(context: self.context, text: "💻 PowerShell-скрипт скопирован")
    }
}
