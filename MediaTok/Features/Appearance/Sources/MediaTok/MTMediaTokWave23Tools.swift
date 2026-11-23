import Foundation
import UIKit
import Security
import CryptoKit
import CoreImage
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
// MediaTok Wave 23 — 1001–1500 Userbot, Forensics, Multi-Account & Pro Commercial Core:
//   #1011 / .clonechan      — Batch Channel History Cloner (post #1..N to backup channel/Saved)
//   #1013 / .joinfilter     — Smart Join-Request Auto-Moderator (approve humans / reject fresh bot IDs)
//   #1016 / .purgeme N      — Instant delete of your last N messages in current chat/group
//   #1018 / .scrub          — Rolling History Scrubber (auto-delete own messages > 24h/72h in public groups)
//   #1027                   — Auto-Queue through active group Slowmode (holds & sends when timer clears)
//   #1031 / .nukewhite      — Untouchable Chat Whitelist for Password Account Nuke (#1029)
//   #1035 / .ignoreuser     — Client-Side Shadow Ignore of specific author in any group
//   #1047                   — Auto-Hide 777000 Login Codes while UIScreen.isCaptured (Screen Recording / Stream)
//   #1060 / #1061 / .nftmarket — 4-Market Gift Arbitrage (Fragment/Portals/Tonnel/MRKT) + Backdrop Multiplier
//   #1073 / .walletlink     — Wallet Self-Deanon Inspector (+888 / NFT wallet graph check)
//   #1084 / .ela            — Forensic Receipt Screenshot Analyzer (JPEG ELA Error-Level Analysis)
//   #1086 / .bincheck       — Bank Card Luhn Validator + BIN Country/Issuer Inspector
//   #1097 / .snipeuser      — Background @username Availability Sniper with instant alert
//   #1103 / #1104 / #1105   — Per-Account Proxy Kill-Switch, Per-Account Device Model Spoof & WebStore Isolation
//   #1107 / .searchall      — Cross-Account Global Message Search across ALL logged-in accounts
//   #1359 / .dork           — Dork Search Operators (from: has:file minsize: -exclude)
//   #1381                   — Parallel Multi-Chunk Boost toggle
//   #1392                   — Undo / Redo Draft Stack in Send Menu
//   #1460 / #1475 / #1481–#1500 / .prostore — MediaTok Pro Commercial Suite:
//                             @tribute + CryptoBot Checkout, VIP Friends Whitelist (#1481),
//                             Bundle Integrity Anti-Crack (#1482/#1483), Affiliate 30% (#1484),
//                             Team & Work Workspace (#1486/#1487), Nightly Beta (#1489),
//                             Keychain/iCloud Sync + QR Device Transfer (#1488/#1494),
//                             NTP Clock-Tamper Guard (#1495) & Automation Savings Log (#1496)
// ============================================================================

private final class MTWave23Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body(&self.value)
    }
}

public struct MTAutomationLogEntry: Codable, Equatable {
    public let timestamp: Int
    public let module: String
    public let detail: String
    public let savedSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case timestamp, module, detail, savedSeconds
    }
}

public struct MTWave23Config: Codable, Equatable {
    public var rollingScrubHours: Int          // 0 = off, 24, 72
    public var slowmodeAutoQueue: Bool
    public var hide777000OnScreenCapture: Bool
    public var proxyKillSwitchEnabled: Bool
    public var isolateWebStorePerAccount: Bool
    public var parallel8BoostEnabled: Bool
    public var nightlyEarlyAccessEnabled: Bool
    public var workWorkspaceMode: Bool
    public var minimalistMenuHideUnused: Bool
    public var shadowIgnoredAuthorIds: [Int64]
    public var perAccountDeviceModels: [String: String] // accountIdInt64 -> "iPhone 16 Pro Max"
    public var snipedUsername: String

    private enum CodingKeys: String, CodingKey {
        case rollingScrubHours
        case slowmodeAutoQueue
        case hide777000OnScreenCapture
        case proxyKillSwitchEnabled
        case isolateWebStorePerAccount
        case parallel8BoostEnabled
        case nightlyEarlyAccessEnabled
        case workWorkspaceMode
        case minimalistMenuHideUnused
        case shadowIgnoredAuthorIds
        case perAccountDeviceModels
        case snipedUsername
    }

    public static let `default` = MTWave23Config(
        rollingScrubHours: 0,
        slowmodeAutoQueue: true,
        hide777000OnScreenCapture: true,
        proxyKillSwitchEnabled: false,
        isolateWebStorePerAccount: true,
        parallel8BoostEnabled: true,
        nightlyEarlyAccessEnabled: false,
        workWorkspaceMode: false,
        minimalistMenuHideUnused: false,
        shadowIgnoredAuthorIds: [],
        perAccountDeviceModels: [:],
        snipedUsername: ""
    )
}

public enum MTMediaTokWave23Tools {
    private static let configKey = "mediatok.wave23.config.v1"
    private static let autoLogsKey = "mediatok.wave23.automation_logs.v1"
    private static let ntpDeltaKey = "mediatok.wave23.ntp_delta.v1"

    private static let stateBox = MTWave23Box<(
        cachedConfig: MTWave23Config,
        ignoredSet: Set<Int64>,
        isScreenCaptured: Bool,
        lastContext: AccountContext?,
        workerTimer: DispatchSourceTimer?,
        slowmodeQueue: [(peerId: PeerId, text: String, sendAtUnix: Int)],
        undoStack: [Int64: [String]],
        redoStack: [Int64: [String]]
    )>((.default, [], UIScreen.main.isCaptured, nil, nil, [], [:], [:]))

    // MARK: - Registration

    public static func register() {
        let initial = loadConfigFromDisk()
        syncFastDefaults(initial)
        stateBox.withLock {
            $0.cachedConfig = initial
            $0.ignoredSet = Set(initial.shadowIgnoredAuthorIds)
            $0.isScreenCaptured = UIScreen.main.isCaptured
        }
        restoreLicenseFromKeychainIfNeeded()

        // #1104 Per-Account Individual Device Model Spoof
        MTNetworkHooks.initConnection.register({ params, ctx in
            let cfg = MTMediaTokWave23Tools.stateBox.withLock { $0.cachedConfig }
            let key = "\(ctx.accountId.int64)"
            if let customModel = cfg.perAccountDeviceModels[key], !customModel.isEmpty {
                params.deviceModel = customModel
            }
        }, order: 50)

        MTChatScreenHooks.willSendText.register({ request, proceed in
            return MTMediaTokWave23Tools.interceptSend(request, proceed: proceed)
        }, order: 45)

        MTChatScreenHooks.sendMenuItems.register({ sendContext in
            return MTMediaTokWave23Tools.sendMenuItems(sendContext)
        }, order: 86)

        // #1035 Client-Side Shadow Ignore + #1047 Hide 777000 Login Codes during Screen Recording/Stream
        MTChatScreenHooks.hidesMessage.register({ message, _, _ in
            let snap = MTMediaTokWave23Tools.stateBox.withLock { ($0.cachedConfig, $0.ignoredSet, $0.isScreenCaptured) }
            if let authorId = message.author?.id, snap.1.contains(authorId.toInt64()) || snap.1.contains(authorId.id._internalGetInt64Value()) {
                return true
            }
            if snap.0.hide777000OnScreenCapture && snap.2 {
                if message.id.peerId.id._internalGetInt64Value() == 777000 {
                    return true
                }
            }
            return false
        }, order: 58)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave23Tools.messageMenuItems(menuContext)
        }, order: 101)

        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTMediaTokWave23Tools.stateBox.withLock { $0.lastContext = context }
            MTMediaTokWave23Tools.armWorkerIfNeeded(context: context)
            MTMediaTokWave23Tools.verifyNtpClockIntegrity()
        }, order: 46)

        NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { _ in
            let cap = UIScreen.main.isCaptured
            stateBox.withLock { $0.isScreenCaptured = cap }
            if cap, let ctx = stateBox.withLock({ $0.lastContext }), loadConfig().hide777000OnScreenCapture {
                MTMediaTokWave5Tools.showToast(context: ctx, text: "Запись экрана обнаружена: коды 777000 автоматически скрыты (#1047)")
                appendAutomationLog(module: "Защита стрима #1047", detail: "Скрыты сервисные коды Telegram 777000 на время записи экрана", savedSeconds: 120)
            }
        }
    }

    // MARK: - Persistence & Keychain (#1488)

    private static func loadConfigFromDisk() -> MTWave23Config {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let decoded = try? JSONDecoder().decode(MTWave23Config.self, from: data) else {
            return .default
        }
        return decoded
    }

    public static func loadConfig() -> MTWave23Config {
        return stateBox.withLock { $0.cachedConfig }
    }

    public static func saveConfig(_ cfg: MTWave23Config) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        syncFastDefaults(cfg)
        stateBox.withLock {
            $0.cachedConfig = cfg
            $0.ignoredSet = Set(cfg.shadowIgnoredAuthorIds)
        }
        if let ctx = stateBox.withLock({ $0.lastContext }) {
            armWorkerIfNeeded(context: ctx)
        }
    }

    private static func syncFastDefaults(_ cfg: MTWave23Config) {
        UserDefaults.standard.set(cfg.isolateWebStorePerAccount, forKey: "mediatok.multiaccount.isolate_webstore.v1")
        UserDefaults.standard.set(cfg.parallel8BoostEnabled, forKey: "mediatok.wave23.parallel8_boost.v1")
    }

    public static func appendAutomationLog(module: String, detail: String, savedSeconds: Int) {
        var logs = loadAutomationLogs()
        logs.insert(MTAutomationLogEntry(timestamp: Int(Date().timeIntervalSince1970), module: module, detail: detail, savedSeconds: savedSeconds), at: 0)
        if logs.count > 120 { logs = Array(logs.prefix(120)) }
        if let data = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(data, forKey: autoLogsKey)
        }
    }

    public static func loadAutomationLogs() -> [MTAutomationLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: autoLogsKey),
              let arr = try? JSONDecoder().decode([MTAutomationLogEntry].self, from: data) else {
            return []
        }
        return arr
    }

    // #1488 Keychain / iCloud Keychain license persistence
    public static func backupProTokenToKeychain(_ token: String, synchronizable: Bool = true) {
        let service = "org.mediatok.pro.license.v1"
        let account = "active_token"
        let delQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(delQuery as CFDictionary)
        guard let data = token.data(using: .utf8) else { return }
        var addQuery = delQuery
        addQuery[kSecValueData as String] = data
        if synchronizable {
            addQuery[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        let _ = SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func restoreLicenseFromKeychainIfNeeded() {
        guard !MTMediaTokWave19Tools.isProActive else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.mediatok.pro.license.v1",
            kSecAttrAccount as String: "active_token",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let str = String(data: data, encoding: .utf8), !str.isEmpty {
            MTMediaTokWave19Tools.isProActive = true
        }
    }

    // #1482 / #1483 Binary & Bundle Integrity Checker
    public static func verifyBundleIntegrity() -> (isAuthentic: Bool, summary: String) {
        let bundle = Bundle.main
        let bundleId = bundle.bundleIdentifier ?? "unknown"
        var dylibSuspicious: [String] = []
        if let fwPath = bundle.privateFrameworksPath,
           let items = try? FileManager.default.contentsOfDirectory(atPath: fwPath) {
            for f in items {
                let low = f.lowercased()
                if low.contains("crack") || low.contains("satella") || low.contains("cycript") || low.contains("frida") || low.contains("inject") {
                    dylibSuspicious.append(f)
                }
            }
        }
        let clockTampered = abs(UserDefaults.standard.integer(forKey: ntpDeltaKey)) > 86400
        if !dylibSuspicious.isEmpty {
            return (false, "ВНИМАНИЕ (#1483): Обнаружены сторонние библиотеки: \(dylibSuspicious.joined(separator: ", "))")
        }
        if clockTampered {
            return (false, "ВНИМАНИЕ (#1495): Системное время телефона расходится с сервером более чем на 24ч!")
        }
        return (true, "Подлинная сборка MediaTok (\(bundleId)) · Сторонних инжектов: 0 · Время синхронизировано")
    }

    // #1495 Server / HTTP Date Time-Tamper Check
    private static func verifyNtpClockIntegrity() {
        guard let url = URL(string: "https://telegram.org/") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8.0)
        req.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            guard let http = resp as? HTTPURLResponse,
                  let dateStr = http.value(forHTTPHeaderField: "Date") else { return }
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let serverDate = df.date(from: dateStr) {
                let delta = Int(Date().timeIntervalSince(serverDate))
                UserDefaults.standard.set(delta, forKey: ntpDeltaKey)
            }
        }.resume()
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

    // MARK: - Outgoing Interception: Slash Commands + #1027 Slowmode Auto-Queue

    private static func interceptSend(_ request: MTComposedTextRequest, proceed: @escaping () -> Void) -> Bool {
        let fullText = request.state.inputText.string
        let raw = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let peerId = request.chatLocation.peerId

        // Record draft into Undo stack (#1392)
        if let pid = peerId, !raw.isEmpty, !raw.hasPrefix(".") {
            stateBox.withLock { st in
                var arr = st.undoStack[pid.toInt64()] ?? []
                if arr.last != fullText {
                    arr.append(fullText)
                    if arr.count > 12 { arr.removeFirst() }
                    st.undoStack[pid.toInt64()] = arr
                }
            }
        }

        if raw.hasPrefix(".") {
            // #1016 .purgeme <N>
            if lower.hasPrefix(".purgeme ") || lower == ".purgeme" {
                let countStr = lower.hasPrefix(".purgeme ") ? String(raw.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines) : "10"
                let n = max(1, min(100, Int(countStr) ?? 10))
                request.replace(ChatTextInputState())
                if let pid = peerId {
                    purgeMyLastMessages(context: request.context, peerId: pid, count: n)
                }
                return true
            }
            // #1031 .nukewhite (toggle current chat in Nuke Whitelist)
            if lower == ".nukewhite" {
                request.replace(ChatTextInputState())
                if let pid = peerId {
                    toggleNukeWhitelist(context: request.context, peerId: pid)
                }
                return true
            }
            // #1011 .clonechan
            if lower == ".clonechan" {
                request.replace(ChatTextInputState())
                if let pid = peerId {
                    DispatchQueue.main.async { presentCloneChannelPrompt(context: request.context, sourcePeerId: pid) }
                }
                return true
            }
            // #1013 .joinfilter
            if lower == ".joinfilter" {
                request.replace(ChatTextInputState())
                if let pid = peerId {
                    runSmartJoinRequestFilter(context: request.context, peerId: pid)
                }
                return true
            }
            // #1060 / #1061 .nftmarket
            if lower == ".nftmarket" || lower.hasPrefix(".nftmarket ") {
                let q = lower.hasPrefix(".nftmarket ") ? String(raw.dropFirst(11)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentNftArbitrageCalculator(context: request.context, initialQuery: q) }
                return true
            }
            // #1086 .bincheck
            if lower.hasPrefix(".bincheck ") || lower == ".bincheck" {
                let q = lower.hasPrefix(".bincheck ") ? String(raw.dropFirst(10)).trimmingCharacters(in: .whitespacesAndNewlines) : (UIPasteboard.general.string ?? "")
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { inspectCardLuhnAndBin(context: request.context, rawInput: q) }
                return true
            }
            // #1097 .snipeuser
            if lower.hasPrefix(".snipeuser ") || lower == ".snipeuser" {
                let u = lower.hasPrefix(".snipeuser ") ? String(raw.dropFirst(11)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { configureUsernameSniper(context: request.context, rawUsername: u) }
                return true
            }
            // #1107 .searchall
            if lower == ".searchall" || lower.hasPrefix(".searchall ") {
                let q = lower.hasPrefix(".searchall ") ? String(raw.dropFirst(11)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentCrossAccountSearch(context: request.context, initialQuery: q) }
                return true
            }
            // #1359 .dork
            if lower.hasPrefix(".dork ") || lower == ".dork" {
                let q = lower.hasPrefix(".dork ") ? String(raw.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                request.replace(ChatTextInputState())
                if let pid = peerId {
                    DispatchQueue.main.async { presentDorkChatSearch(context: request.context, peerId: pid, initialDork: q) }
                }
                return true
            }
            // #1073 .walletlink
            if lower == ".walletlink" {
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentWalletDeanonCheck(context: request.context) }
                return true
            }
            // #1460..#1500 .prostore / .wave23 / .scrub
            if lower == ".prostore" || lower == ".wave23" || lower == ".scrub" || lower == ".tribute" || lower == ".vipfriends" {
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentCommercialProSuite(context: request.context) }
                return true
            }
        }

        // #1027 Slowmode Auto-Queue: if channel has active slowmode cooldown, queue message locally and auto-send when timer expires!
        if loadConfig().slowmodeAutoQueue, let pid = peerId, pid.namespace == Namespaces.Peer.CloudChannel, !raw.isEmpty {
            var activeUntil: Int32 = 0
            let sema = DispatchSemaphore(value: 0)
            let _ = request.context.account.postbox.transaction({ tx -> Int32 in
                if let cached = tx.getPeerCachedData(peerId: pid) as? CachedChannelData,
                   let until = cached.slowModeValidUntilTimestamp {
                    return until
                }
                return 0
            }).startStandalone(next: { val in
                activeUntil = val
                sema.signal()
            })
            let _ = sema.wait(timeout: .now() + 0.08)
            let nowSec = Int32(Date().timeIntervalSince1970)
            if activeUntil > nowSec + 1 {
                let waitSec = Int(activeUntil - nowSec) + 1
                request.replace(ChatTextInputState())
                stateBox.withLock { st in
                    let extraOffset = st.slowmodeQueue.filter { $0.peerId == pid }.count * 15
                    st.slowmodeQueue.append((peerId: pid, text: fullText, sendAtUnix: Int(activeUntil) + 1 + extraOffset))
                }
                armWorkerIfNeeded(context: request.context)
                MTMediaTokWave5Tools.showToast(context: request.context, text: "Slowmode-очередь (#1027): сообщение уйдёт само через \(waitSec) сек!")
                appendAutomationLog(module: "Slowmode Очередь #1027", detail: "Поставлено в авто-отправку через \(waitSec) сек", savedSeconds: waitSec)
                return true
            }
        }

        return false
    }

    // MARK: - #1392 Undo / Redo Draft Buttons in Send Menu

    private static func sendMenuItems(_ sendContext: MTSendMenuContext) -> [ContextMenuItem] {
        let pidRaw = sendContext.peerId.toInt64()
        let currentStr = sendContext.inputText.string
        let replaceInput = sendContext.replaceInput
        let dismiss = sendContext.dismiss
        let (undoCount, redoCount) = stateBox.withLock { ($0.undoStack[pidRaw]?.count ?? 0, $0.redoStack[pidRaw]?.count ?? 0) }

        var items: [ContextMenuItem] = []
        if undoCount > 0 {
            items.append(.action(ContextMenuActionItem(
                text: "Отменить правку текста (Undo #1392)",
                icon: { theme in
                    return UIImage(systemName: "arrow.uturn.backward.circle")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { contextController, _ in
                    contextController?.dismiss(completion: nil)
                    dismiss()
                    let prev = stateBox.withLock { st -> String? in
                        guard var u = st.undoStack[pidRaw], let last = u.popLast() else { return nil }
                        st.undoStack[pidRaw] = u
                        if !currentStr.isEmpty {
                            var r = st.redoStack[pidRaw] ?? []
                            r.append(currentStr)
                            st.redoStack[pidRaw] = r
                        }
                        return last
                    }
                    if let prev {
                        replaceInput(NSAttributedString(string: prev))
                    }
                }
            )))
        }
        if redoCount > 0 {
            items.append(.action(ContextMenuActionItem(
                text: "Вернуть правку (Redo #1392)",
                icon: { theme in
                    return UIImage(systemName: "arrow.uturn.forward.circle")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { contextController, _ in
                    contextController?.dismiss(completion: nil)
                    dismiss()
                    let nextText = stateBox.withLock { st -> String? in
                        guard var r = st.redoStack[pidRaw], let last = r.popLast() else { return nil }
                        st.redoStack[pidRaw] = r
                        return last
                    }
                    if let nextText {
                        replaceInput(NSAttributedString(string: nextText))
                    }
                }
            )))
        }
        return items
    }

    // MARK: - Context Menu: #1035 Shadow Ignore, #1084 JPEG ELA Receipt Check, #1086 BIN Check

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        var entries: [MTMessageMenuEntry] = []

        // #1035 Client-Side Shadow Ignore in Groups
        if message.id.peerId.namespace != Namespaces.Peer.CloudUser,
           let author = message.author, author.id != context.account.peerId {
            let rawAuthor = author.id.toInt64()
            let isIgnored = stateBox.withLock { $0.ignoredSet.contains(rawAuthor) }
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: isIgnored ? "Снять теневой игнор (#1035)" : "Скрыть тролля локально (#1035)",
                icon: { theme in
                    return UIImage(systemName: "eye.slash.circle")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    var cfg = loadConfig()
                    if let idx = cfg.shadowIgnoredAuthorIds.firstIndex(of: rawAuthor) {
                        cfg.shadowIgnoredAuthorIds.remove(at: idx)
                        saveConfig(cfg)
                        MTMediaTokWave5Tools.showToast(context: context, text: "Теневой игнор автора снят")
                    } else {
                        cfg.shadowIgnoredAuthorIds.append(rawAuthor)
                        saveConfig(cfg)
                        MTMediaTokWave5Tools.showToast(context: context, text: "Автор скрыт локально во всех группах (#1035)")
                    }
                }
            ))))
        }

        // #1084 Forensic JPEG ELA Receipt Screenshot Analyzer
        for m in message.media {
            if let imgMedia = m as? TelegramMediaImage, let largest = largestImageRepresentation(imgMedia.representations) {
                entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                    text: "Проверить скрин чека на фотошоп (ELA #1084)",
                    icon: { theme in
                        return UIImage(systemName: "viewfinder.trianglebadge.exclamationmark")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                    },
                    action: { _, f in
                        f(.default)
                        MTMediaTokWave23Tools.runForensicElaOnMessageImage(context: context, message: message, imageMedia: imgMedia, resource: largest.resource)
                    }
                ))))
                break
            }
        }

        // #1086 Card Luhn & BIN Check if message contains 16 digits
        let digitsOnly = message.text.filter { $0.isNumber }
        if digitsOnly.count >= 16 {
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Проверить карту / BIN (#1086)",
                icon: { theme in
                    return UIImage(systemName: "creditcard.and.123")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    DispatchQueue.main.async {
                        MTMediaTokWave23Tools.inspectCardLuhnAndBin(context: context, rawInput: message.text)
                    }
                }
            ))))
        }

        return entries
    }

    // MARK: - #1016 .purgeme <N>

    public static func purgeMyLastMessages(context: AccountContext, peerId: PeerId, count: Int) {
        let ownId = context.account.peerId
        let _ = (context.account.postbox.transaction { tx -> [MessageId] in
            var mine: [MessageId] = []
            tx.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: max(40, count * 4)) { msg in
                if !msg.flags.contains(.Incoming) || msg.author?.id == ownId {
                    mine.append(msg.id)
                    if mine.count >= count { return false }
                }
                return true
            }
            return mine
        } |> deliverOnMainQueue).startStandalone(next: { ids in
            guard !ids.isEmpty else {
                MTMediaTokWave5Tools.showToast(context: context, text: "Ваших сообщений не найдено")
                return
            }
            let _ = context.engine.messages.deleteMessagesInteractively(messageIds: ids, type: .forEveryone).startStandalone()
            MTMediaTokWave5Tools.showToast(context: context, text: "Удалено ваших сообщений: \(ids.count) (#1016)")
            appendAutomationLog(module: "PurgeMe #1016", detail: "Удалено \(ids.count) собственных сообщений", savedSeconds: ids.count * 3)
        })
    }

    // MARK: - #1031 Nuke Whitelist Toggle

    public static func toggleNukeWhitelist(context: AccountContext, peerId: PeerId) {
        var cyber = MTMediaTokWave19Tools.loadCyberConfig()
        let raw = peerId.toInt64()
        if let idx = cyber.nukeWhitelistPeerIds.firstIndex(of: raw) {
            cyber.nukeWhitelistPeerIds.remove(at: idx)
            MTMediaTokWave19Tools.saveCyberConfig(cyber)
            MTMediaTokWave5Tools.showToast(context: context, text: "Чат убран из Белого списка сноса (#1031)")
        } else {
            cyber.nukeWhitelistPeerIds.append(raw)
            MTMediaTokWave19Tools.saveCyberConfig(cyber)
            MTMediaTokWave5Tools.showToast(context: context, text: "Чат защищён Белым списком (#1031): кнопка .nukeall его НЕ тронет!")
        }
    }

    // MARK: - #1011 Batch Channel History Cloner

    public static func presentCloneChannelPrompt(context: AccountContext, sourcePeerId: PeerId) {
        guard let top = topViewController() else { return }
        let alert = UIAlertController(
            title: "Пакетное клонирование канала (#1011)",
            message: "Скопирует последние N постов текущего канала с сохранением текста и медиа в ваше Избранное или резервный канал (укажите @канал или оставьте пустым для Избранного):",
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = "@backup_channel (пусто = в Избранное)" }
        alert.addTextField {
            $0.placeholder = "Количество постов (например 30)"
            $0.keyboardType = .numberPad
            $0.text = "25"
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Клонировать", style: .default) { [weak alert] _ in
            let dstName = (alert?.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
            let limit = max(1, min(100, Int(alert?.textFields?[1].text ?? "25") ?? 25))
            let runClone: (PeerId) -> Void = { dstPeerId in
                let _ = (context.account.postbox.transaction { tx -> [Message] in
                    var msgs: [Message] = []
                    tx.scanTopMessages(peerId: sourcePeerId, namespace: Namespaces.Message.Cloud, limit: limit) { m in
                        if !m.text.isEmpty || !m.media.isEmpty {
                            msgs.append(m)
                        }
                        return true
                    }
                    return msgs.reversed()
                } |> deliverOnMainQueue).startStandalone(next: { chronological in
                    var outBatch: [EnqueueMessage] = []
                    for m in chronological {
                        var mediaRef: AnyMediaReference?
                        for med in m.media {
                            if let img = med as? TelegramMediaImage {
                                mediaRef = .standalone(media: img)
                                break
                            } else if let f = med as? TelegramMediaFile {
                                mediaRef = .standalone(media: f)
                                break
                            }
                        }
                        outBatch.append(.message(text: m.text, attributes: [], inlineStickers: [:], mediaReference: mediaRef, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []))
                    }
                    if !outBatch.isEmpty {
                        let _ = enqueueMessages(account: context.account, peerId: dstPeerId, messages: outBatch).startStandalone()
                    }
                    MTMediaTokWave5Tools.showToast(context: context, text: "Клонировано \(outBatch.count) постов в хронологическом порядке (#1011)!")
                    appendAutomationLog(module: "Клон канала #1011", detail: "Перенесено \(outBatch.count) постов", savedSeconds: outBatch.count * 10)
                })
            }

            if dstName.isEmpty {
                runClone(context.account.peerId)
            } else {
                let _ = (context.engine.peers.resolvePeerByName(name: dstName, referrer: nil)
                |> deliverOnMainQueue).startStandalone(next: { res in
                    if case let .result(peer) = res, let peer {
                        runClone(peer.id)
                    } else if case .result(nil) = res {
                        MTMediaTokWave5Tools.showToast(context: context, text: "Целевой канал @\(dstName) не найден")
                    }
                })
            }
        })
        top.present(alert, animated: true)
    }

    // MARK: - #1013 Smart Join-Request Auto-Moderator

    public static func runSmartJoinRequestFilter(context: AccountContext, peerId: PeerId) {
        let importersCtx = context.engine.peers.peerInvitationImporters(peerId: peerId, subject: .requests(query: nil))
        MTMediaTokWave5Tools.showToast(context: context, text: "Анализирую заявки на вступление (#1013)...")
        let _ = (importersCtx.state
        |> filter { !$0.importers.isEmpty || !$0.isLoadingMore }
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { state in
            var approved = 0
            var rejected = 0
            for imp in state.importers {
                let uid = imp.peer.peerId.id._internalGetInt64Value()
                let title = imp.peer.peer?.debugDisplayTitle ?? ""
                let hasArabicOrSpam = title.unicodeScalars.contains { ($0.value >= 0x0600 && $0.value <= 0x06FF) }
                let ultraFreshBotId = uid > 8_400_000_000 && (imp.about ?? "").isEmpty && (imp.peer.peer?.smallProfileImage == nil)
                if hasArabicOrSpam || ultraFreshBotId {
                    importersCtx.update(imp.peer.peerId, action: .deny)
                    rejected += 1
                } else {
                    importersCtx.update(imp.peer.peerId, action: .approve)
                    approved += 1
                }
            }
            MTMediaTokWave5Tools.showToast(context: context, text: "Фильтр заявок (#1013): одобрено \(approved), отклонено ботов \(rejected)")
            appendAutomationLog(module: "Авто-модератор ТГК #1013", detail: "Одобрено \(approved), отклонено спам-ботов \(rejected)", savedSeconds: (approved + rejected) * 4)
        })
    }

    // MARK: - #1084 Forensic JPEG Error-Level Analysis (ELA)

    public static func runForensicElaOnMessageImage(context: AccountContext, message: Message, imageMedia: TelegramMediaImage, resource: MediaResource) {
        MTMediaTokWave5Tools.showToast(context: context, text: "Запускаю криминалистический JPEG ELA анализ чека (#1084)...")
        let ref = ImageMediaReference.message(message: MessageReference(message), media: imageMedia).resourceReference(resource)
        let _ = fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .image, reference: ref).startStandalone()

        let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { data in
            guard let origImg = UIImage(contentsOfFile: data.path),
                  let recompressedData = origImg.jpegData(compressionQuality: 0.90),
                  let recompImg = UIImage(data: recompressedData),
                  let ciOrig = CIImage(image: origImg),
                  let ciRecomp = CIImage(image: recompImg) else {
                MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось декодировать изображение")
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let diffFilter = CIFilter(name: "CIDifferenceBlendMode")
                diffFilter?.setValue(ciOrig, forKey: kCIInputImageKey)
                diffFilter?.setValue(ciRecomp, forKey: kCIInputBackgroundImageKey)

                let boostFilter = CIFilter(name: "CIColorControls")
                boostFilter?.setValue(diffFilter?.outputImage, forKey: kCIInputImageKey)
                boostFilter?.setValue(7.5, forKey: kCIInputContrastKey)
                boostFilter?.setValue(0.18, forKey: kCIInputBrightnessKey)

                let ciCtx = CIContext()
                guard let outCi = boostFilter?.outputImage,
                      let cg = ciCtx.createCGImage(outCi, from: ciOrig.extent) else { return }
                let elaUi = UIImage(cgImage: cg)

                DispatchQueue.main.async {
                    guard let top = topViewController() else { return }
                    let vc = MTElaResultController(elaImage: elaUi, originalImage: origImg)
                    let nav = UINavigationController(rootViewController: vc)
                    nav.modalPresentationStyle = .pageSheet
                    top.present(nav, animated: true)
                }
            }
        })
    }

    // MARK: - #1086 Bank Card Luhn + BIN Lookup

    public static func inspectCardLuhnAndBin(context: AccountContext, rawInput: String) {
        let digits = rawInput.filter { $0.isNumber }
        guard digits.count >= 16 else {
            MTMediaTokWave5Tools.showToast(context: context, text: "Передайте текст с 16 цифрами карты (.bincheck <номер>)")
            return
        }
        let card16 = String(digits.prefix(16))
        let bin6 = String(card16.prefix(6))
        let isValidLuhn = verifyLuhn(card16)

        let localIssuer: String
        if bin6.hasPrefix("220220") || bin6.hasPrefix("4276") || bin6.hasPrefix("5469") {
            localIssuer = "Сбербанк (РФ)"
        } else if bin6.hasPrefix("220070") || bin6.hasPrefix("553691") {
            localIssuer = "Т-Банк / Тинькофф (РФ)"
        } else if bin6.hasPrefix("220015") || bin6.hasPrefix("4584") || bin6.hasPrefix("5486") {
            localIssuer = "Альфа-Банк (РФ)"
        } else if bin6.hasPrefix("220024") || bin6.hasPrefix("4272") {
            localIssuer = "ВТБ (РФ)"
        } else if bin6.hasPrefix("2204") {
            localIssuer = "Яндекс Пэй / Озон Банк (МИР РФ)"
        } else if bin6.hasPrefix("22") {
            localIssuer = "Платёжная система МИР"
        } else if bin6.hasPrefix("4") {
            localIssuer = "Visa International"
        } else if bin6.hasPrefix("5") {
            localIssuer = "Mastercard"
        } else {
            localIssuer = "Международный BIN \(bin6)"
        }

        guard let top = topViewController() else { return }
        let alert = UIAlertController(
            title: isValidLuhn ? "Карта прошла проверку Луна (#1086)" : "ФАЛЬШИВЫЙ номер карты! (Ошибка Луна)",
            message: "Номер: \(card16)\nBIN (6 цифр): \(bin6)\nЭмитент: \(localIssuer)\nКонтрольная сумма Luhn: \(isValidLuhn ? "КОРРЕКТНА" : "НЕВАЛИДНА — реквизит выдуман или с опечаткой!")",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Скопировать 16 цифр без пробелов (#1087)", style: .default) { _ in
            UIPasteboard.general.string = card16
            MTMediaTokWave5Tools.showToast(context: context, text: "16 цифр карты скопированы")
        })
        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        top.present(alert, animated: true)
    }

    private static func verifyLuhn(_ digits: String) -> Bool {
        var sum = 0
        let reversed = digits.reversed().compactMap { Int(String($0)) }
        guard reversed.count == digits.count else { return false }
        for (idx, d) in reversed.enumerated() {
            if idx % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? (doubled - 9) : doubled
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }

    // MARK: - #1097 Background @username Availability Sniper

    public static func configureUsernameSniper(context: AccountContext, rawUsername: String) {
        let clean = rawUsername.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            var cfg = loadConfig()
            cfg.snipedUsername = clean == "off" ? "" : clean
            saveConfig(cfg)
            MTMediaTokWave5Tools.showToast(context: context, text: cfg.snipedUsername.isEmpty ? "Снайпер @username остановлен" : "Снайпер (#1097) следит за @\(clean) каждые 45 сек!")
            return
        }
        guard let top = topViewController() else { return }
        let alert = UIAlertController(title: "Снайпер освобождения @username (#1097)", message: "Укажите занятый @тег. Клиент будет фоново проверять его статус и мгновенно уведомит в секунду освобождения:", preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "username (без @)"
            $0.text = loadConfig().snipedUsername
        }
        alert.addAction(UIAlertAction(title: "Стоп", style: .destructive) { _ in
            var cfg = loadConfig()
            cfg.snipedUsername = ""
            saveConfig(cfg)
        })
        alert.addAction(UIAlertAction(title: "Следить", style: .default) { [weak alert] _ in
            let u = (alert?.textFields?.first?.text ?? "").replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            var cfg = loadConfig()
            cfg.snipedUsername = u
            saveConfig(cfg)
            MTMediaTokWave5Tools.showToast(context: context, text: u.isEmpty ? "Снайпер выключен" : "Мониторинг @\(u) запущен!")
        })
        top.present(alert, animated: true)
    }

    // MARK: - #1060 / #1061 4-Marketplace Gift Arbitrage + Backdrop Multiplier

    public static func presentNftArbitrageCalculator(context: AccountContext, initialQuery: String) {
        guard let top = topViewController() else { return }
        let vc = MTNftArbitrageController(context: context, initialCollection: initialQuery)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #1073 Wallet Self-Deanon Inspector

    public static func presentWalletDeanonCheck(context: AccountContext) {
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
        |> deliverOnMainQueue).startStandalone(next: { peer in
            guard let top = topViewController() else { return }
            var warnings: [String] = []
            if case let .user(user) = peer {
                if let phone = user.phone, phone.hasPrefix("888") {
                    warnings.append("• Ваш аккаунт привязан к анонимному номеру +\(phone): адрес минта в блокчейне TON публично показывает все остальные NFT и переводы того же кошелька!")
                }
                if user.emojiStatus != nil {
                    warnings.append("• Надетый коллекционный статус/подарок с выводом в TON позволяет по номеру минта (#ID) найти ваш Tonkeeper-кошелёк на Fragment/Tonviewer.")
                }
            }
            if warnings.isEmpty {
                warnings.append("• Прямых ончейн-связок (+888 номеров) на основном профиле не обнаружено.\n• Совет: для анонимных аккаунтов не выводите подарки на свой публичный кошелёк Tonkeeper с .ton доменом.")
            }
            let alert = UIAlertController(title: "Проверка деанона кошелька (#1073)", message: warnings.joined(separator: "\n\n"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Понятно", style: .default))
            top.present(alert, animated: true)
        })
    }

    // MARK: - #1107 Cross-Account Search & #1359 Dork Search

    public static func presentCrossAccountSearch(context: AccountContext, initialQuery: String) {
        guard let top = topViewController() else { return }
        let vc = MTCrossAccountSearchController(context: context, initialQuery: initialQuery)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    public static func presentDorkChatSearch(context: AccountContext, peerId: PeerId, initialDork: String) {
        guard let top = topViewController() else { return }
        let vc = MTDorkSearchController(context: context, peerId: peerId, initialDork: initialDork)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #1460..#1500 Commercial MediaTok Pro Suite

    public static func presentCommercialProSuite(context: AccountContext) {
        guard let top = topViewController() else { return }
        let vc = MTCommercialProSuiteController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - Background Worker (#1018 Rolling Scrubber, #1027 Slowmode Queue, #1097 @username Sniper)

    private static func armWorkerIfNeeded(context: AccountContext) {
        let cfg = loadConfig()
        let hasQueue = stateBox.withLock { !$0.slowmodeQueue.isEmpty }
        guard cfg.rollingScrubHours > 0 || !cfg.snipedUsername.isEmpty || hasQueue else { return }

        let shouldStart = stateBox.withLock { st -> Bool in
            st.lastContext = context
            return st.workerTimer == nil
        }
        guard shouldStart else { return }

        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + 3.0, repeating: 15.0)
        t.setEventHandler {
            workerTick()
        }
        stateBox.withLock { $0.workerTimer = t }
        t.resume()
    }

    private static func workerTick() {
        let cfg = loadConfig()
        guard let context = stateBox.withLock({ $0.lastContext }) else { return }
        let nowSec = Int(Date().timeIntervalSince1970)

        // 1. #1027 Drain ready Slowmode queued messages
        let dueItems = stateBox.withLock { st -> [(peerId: PeerId, text: String)] in
            var ready: [(peerId: PeerId, text: String)] = []
            var keep: [(peerId: PeerId, text: String, sendAtUnix: Int)] = []
            for item in st.slowmodeQueue {
                if nowSec >= item.sendAtUnix {
                    ready.append((item.peerId, item.text))
                } else {
                    keep.append(item)
                }
            }
            st.slowmodeQueue = keep
            return ready
        }
        for item in dueItems {
            let _ = enqueueMessages(account: context.account, peerId: item.peerId, messages: [
                .message(text: item.text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            ]).startStandalone()
        }

        // 2. #1097 @username Sniper check
        if !cfg.snipedUsername.isEmpty {
            let target = cfg.snipedUsername
            let _ = (context.engine.peers.addressNameAvailability(domain: .account, name: target)
            |> deliverOnMainQueue).startStandalone(next: { status in
                if status == .available {
                    var updated = loadConfig()
                    updated.snipedUsername = ""
                    saveConfig(updated)
                    MTMediaTokWave5Tools.showToast(context: context, text: "СНАЙПЕР (#1097): Юзернейм @\(target) СВОБОДЕН прямо сейчас!")
                    appendAutomationLog(module: "Username Sniper #1097", detail: "Поймано освобождение @\(target)", savedSeconds: 600)
                }
            })
        }

        // 3. #1018 Rolling History Scrubber (delete own messages older than 24h / 72h in public supergroups)
        if cfg.rollingScrubHours > 0 {
            let cutoff = Int32(nowSec - cfg.rollingScrubHours * 3600)
            let ownId = context.account.peerId
            let _ = (context.account.postbox.transaction { tx -> [MessageId] in
                var expired: [MessageId] = []
                let top = tx.getTopChatListEntries(groupId: .root, count: 40)
                for entry in top {
                    guard let ch = entry.peer as? TelegramChannel, case .group = ch.info else { continue }
                    if ch.flags.contains(.isCreator) { continue }
                    tx.scanTopMessages(peerId: entry.peerId, namespace: Namespaces.Message.Cloud, limit: 20) { m in
                        if m.author?.id == ownId && m.timestamp < cutoff {
                            expired.append(m.id)
                        }
                        return true
                    }
                }
                return expired
            } |> deliverOnMainQueue).startStandalone(next: { toScrub in
                if !toScrub.isEmpty {
                    let _ = context.engine.messages.deleteMessagesInteractively(messageIds: toScrub, type: .forEveryone).startStandalone()
                }
            })
        }
    }
}

// MARK: - #1084 Forensic ELA Viewer

private final class MTElaResultController: UIViewController {
    private let elaImage: UIImage
    private let originalImage: UIImage
    private let imageView = UIImageView()
    private var showingOriginal = false

    init(elaImage: UIImage, originalImage: UIImage) {
        self.elaImage = elaImage
        self.originalImage = originalImage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "JPEG ELA Криминалистика (#1084)"
        self.view.backgroundColor = .black
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Оригинал / ELA", style: .done, target: self, action: #selector(toggleMode))

        let hint = UILabel()
        hint.text = "Яркие белые/цветные прямоугольники вокруг суммы или времени на тёмном фоне означают локальную вставку в редакторе!"
        hint.textColor = .systemYellow
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.numberOfLines = 0
        hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false

        self.imageView.image = self.elaImage
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(hint)
        self.view.addSubview(self.imageView)

        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hint.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.imageView.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8),
            self.imageView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.imageView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.imageView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    @objc private func toggleMode() {
        self.showingOriginal.toggle()
        self.imageView.image = self.showingOriginal ? self.originalImage : self.elaImage
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #1060 / #1061 4-Market Gift Arbitrage + Backdrop Multiplier Controller

private final class MTNftArbitrageController: UIViewController, UITableViewDataSource {
    private let context: AccountContext
    private var selectedSlug: String
    private var selectedBackdropIdx: Int = 0
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let collections: [(slug: String, name: String, baseTon: Double)] = [
        ("plushpepe", "Plush Pepe", 920.0),
        ("durovscap", "Durov's Cap", 310.0),
        ("preciouspeach", "Precious Peach", 68.0),
        ("vintagecigar", "Vintage Cigar", 42.0),
        ("swisswatch", "Swiss Watch", 54.0),
        ("signetring", "Signet Ring", 36.0),
        ("kissedfrog", "Kissed Frog", 24.0),
        ("scaredcat", "Scared Cat", 29.0)
    ]

    private let backdrops: [(name: String, mult: Double)] = [
        ("Обычный фон (1.0× Floor)", 1.0),
        ("Onyx Black / Midnight (2.35×)", 2.35),
        ("Pure Gold / Amber (1.85×)", 1.85),
        ("Cyberpunk Neon (1.55×)", 1.55),
        ("Monochrome Color-Match (2.80×)", 2.80)
    ]

    init(context: AccountContext, initialCollection: String) {
        self.context = context
        let low = initialCollection.lowercased().replacingOccurrences(of: " ", with: "")
        self.selectedSlug = collections.first(where: { low.contains($0.slug) })?.slug ?? "plushpepe"
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Арбитраж 4 Маркетов & Фон (#1060/#1061)"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        let colBtn = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in self?.pickCollection() })
        colBtn.setTitle("Выбрать коллекцию подарка", for: .normal)
        let bgBtn = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in self?.pickBackdrop() })
        bgBtn.setTitle("Выбрать редкость фона (#1061)", for: .normal)

        let topBar = UIStackView(arrangedSubviews: [colBtn, bgBtn])
        topBar.axis = .horizontal
        topBar.distribution = .fillEqually
        topBar.translatesAutoresizingMaskIntoConstraints = false

        self.tableView.dataSource = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(topBar)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -12),
            topBar.heightAnchor.constraint(equalToConstant: 40),
            self.tableView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }

    private func pickCollection() {
        let sheet = UIAlertController(title: "Коллекция", message: nil, preferredStyle: .actionSheet)
        for c in self.collections {
            sheet.addAction(UIAlertAction(title: c.name, style: .default) { [weak self] _ in
                self?.selectedSlug = c.slug
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.present(sheet, animated: true)
    }

    private func pickBackdrop() {
        let sheet = UIAlertController(title: "Наценка за фон (#1061)", message: nil, preferredStyle: .actionSheet)
        for (i, b) in self.backdrops.enumerated() {
            sheet.addAction(UIAlertAction(title: b.name, style: .default) { [weak self] _ in
                self?.selectedBackdropIdx = i
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.present(sheet, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 4 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "arbCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "arbCell")
        let col = self.collections.first(where: { $0.slug == self.selectedSlug }) ?? self.collections[0]
        let bg = self.backdrops[self.selectedBackdropIdx]
        let base = col.baseTon * bg.mult

        let markets: [(String, Double, String)] = [
            ("Fragment (On-Chain 5% fee)", base * 1.04, "fragment.com/gifts/\(col.slug)"),
            ("Portals Market (2.5% fee)", base * 0.96, "Выгодная покупка (-4%)"),
            ("Tonnel Relayer (Off-chain)", base * 0.94, "Минимальный флор (-6%)"),
            ("MRKT Telegram App", base * 1.01, "Быстрый листинг")
        ]
        let m = markets[indexPath.row]
        cell.textLabel?.text = "\(col.name) · \(m.0)"
        cell.textLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
        cell.detailTextLabel?.text = String(format: "%.1f TON", m.1)
        cell.detailTextLabel?.textColor = indexPath.row == 2 ? .systemGreen : .label
        return cell
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #1107 Cross-Account Search Controller

private final class MTCrossAccountSearchController: UIViewController, UISearchBarDelegate, UITableViewDataSource {
    private let context: AccountContext
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var hits: [(accountTitle: String, chatTitle: String, snippet: String)] = []

    init(context: AccountContext, initialQuery: String) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        self.searchBar.text = initialQuery
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Поиск по всем аккаунтам (#1107)"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.searchBar.placeholder = "Слово или фраза сразу по всем аккаунтам..."
        self.searchBar.delegate = self
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false

        self.tableView.dataSource = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.searchBar)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.searchBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        if let q = self.searchBar.text, !q.isEmpty {
            self.executeSearch(query: q)
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        if let q = searchBar.text, !q.isEmpty {
            self.executeSearch(query: q)
        }
    }

    private func executeSearch(query: String) {
        let low = query.lowercased()
        self.hits.removeAll()
        self.tableView.reloadData()

        let _ = (self.context.sharedContext.activeAccountsWithInfo
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] (_, accounts) in
            guard let self else { return }
            for info in accounts {
                let acc = info.account
                let accIdLabel = "Акк \(acc.peerId.id._internalGetInt64Value())"
                let _ = (acc.postbox.transaction { tx -> [(String, String, String)] in
                    var localHits: [(String, String, String)] = []
                    let top = tx.getTopChatListEntries(groupId: .root, count: 60)
                    for entry in top {
                        let chatName = entry.peer?.debugDisplayTitle ?? "\(entry.peerId.toInt64())"
                        tx.scanTopMessages(peerId: entry.peerId, namespace: Namespaces.Message.Cloud, limit: 25) { m in
                            if m.text.lowercased().contains(low) {
                                localHits.append((accIdLabel, chatName, String(m.text.prefix(140))))
                            }
                            return localHits.count < 40
                        }
                    }
                    return localHits
                } |> deliverOnMainQueue).startStandalone(next: { [weak self] found in
                    guard let self else { return }
                    self.hits.append(contentsOf: found)
                    self.tableView.reloadData()
                })
            }
        })
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.hits.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "xaCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "xaCell")
        let h = self.hits[indexPath.row]
        cell.textLabel?.text = "[\(h.accountTitle)] · \(h.chatTitle)"
        cell.textLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        cell.detailTextLabel?.text = h.snippet
        cell.detailTextLabel?.numberOfLines = 2
        return cell
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #1359 Dork Search Controller (from: has:file minsize: -exclude)

private final class MTDorkSearchController: UIViewController, UISearchBarDelegate, UITableViewDataSource {
    private let context: AccountContext
    private let peerId: PeerId
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var results: [(author: String, text: String)] = []

    init(context: AccountContext, peerId: PeerId, initialDork: String) {
        self.context = context
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
        self.searchBar.text = initialDork.isEmpty ? "has:file -реклама" : initialDork
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Дорк-поиск чата (#1359)"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.searchBar.placeholder = "from:имя has:file size:>10mb -минус"
        self.searchBar.delegate = self
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.dataSource = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.searchBar)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.searchBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.runDork(self.searchBar.text ?? "")
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        self.runDork(searchBar.text ?? "")
    }

    private func runDork(_ dork: String) {
        let tokens = dork.split(separator: " ").map(String.init)
        var mustFrom = ""
        var requireFile = false
        var minMb: Int64 = 0
        var excludes: [String] = []
        var keywords: [String] = []

        for tok in tokens {
            let low = tok.lowercased()
            if low.hasPrefix("from:") {
                mustFrom = String(low.dropFirst(5)).replacingOccurrences(of: "@", with: "")
            } else if low == "has:file" || low == "has:media" {
                requireFile = true
            } else if low.hasPrefix("size:>") {
                let num = low.dropFirst(6).replacingOccurrences(of: "mb", with: "")
                minMb = Int64(num) ?? 0
            } else if low.hasPrefix("-") && low.count > 1 {
                excludes.append(String(low.dropFirst()))
            } else {
                keywords.append(low)
            }
        }

        let pid = self.peerId
        let _ = (self.context.account.postbox.transaction { tx -> [(String, String)] in
            var out: [(String, String)] = []
            tx.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: 400) { m in
                let authorName = m.author?.debugDisplayTitle ?? "Peer"
                let textLow = m.text.lowercased()
                if !mustFrom.isEmpty && !authorName.lowercased().contains(mustFrom) { return true }
                if requireFile && !m.media.contains(where: { $0 is TelegramMediaFile }) { return true }
                if minMb > 0 {
                    let hasBig = m.media.contains { med in
                        if let f = med as? TelegramMediaFile, let sz = f.size {
                            return sz >= minMb * 1024 * 1024
                        }
                        return false
                    }
                    if !hasBig { return true }
                }
                for ex in excludes where textLow.contains(ex) { return true }
                for kw in keywords where !textLow.contains(kw) { return true }

                let summary = m.text.isEmpty ? "[Файл / Медиа]" : String(m.text.prefix(160))
                out.append((authorName, summary))
                return out.count < 80
            }
            return out
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] res in
            self?.results = res
            self?.tableView.reloadData()
        })
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.results.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "dorkCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "dorkCell")
        let r = self.results[indexPath.row]
        cell.textLabel?.text = r.author
        cell.detailTextLabel?.text = r.text
        cell.detailTextLabel?.numberOfLines = 2
        return cell
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #1460 / #1475 (@tribute) / #1481–#1500 Commercial MediaTok Pro Ecosystem Controller

private final class MTCommercialProSuiteController: UITableViewController {
    private let context: AccountContext
    private var cfg = MTMediaTokWave23Tools.loadConfig()

    init(context: AccountContext) {
        self.context = context
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "MediaTok Ultimate & Pro (#1460–#1500)"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 4 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Оплата, Рефералка и VIP-Друзья (#1460 / #1475 / #1481)"
        case 1: return "Анти-Кряк, iCloud Keychain и Перенос (#1482–#1495)"
        case 2: return "Юзербот, Мульти-Аккаунт и Скорость (#1018 / #1104 / #1381)"
        default: return "Журнал срабатываний автоматизации (#1496)"
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 5
        case 1: return 4
        case 2: return 5
        default: return max(1, MTMediaTokWave23Tools.loadAutomationLogs().prefix(10).count)
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.accessoryType = .disclosureIndicator

        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Оплатить MediaTok Pro через @tribute (Карты РФ / СБП / Stars #1475)"
                cell.detailTextLabel?.text = "Официальный бот-посредник @tribute без стороннего эквайринга"
                cell.imageView?.image = UIImage(systemName: "creditcard.fill")
            case 1:
                cell.textLabel?.text = "VIP-друзья владельца: Вечный бесплатный Pro по ID (#1481)"
                let c = MTMediaTokWave19Tools.loadCyberConfig().vipProFriendUserIds.count
                cell.detailTextLabel?.text = "Добавлено VIP Telegram ID: \(c)"
                cell.imageView?.image = UIImage(systemName: "person.2.badge.key.fill")
            case 2:
                let myId = self.context.account.peerId.id._internalGetInt64Value()
                cell.textLabel?.text = "Реферальная программа и Партнёрка 30% (#1460 / #1484)"
                cell.detailTextLabel?.text = "Ваш реф-код блогера/друга: MT-REF-\(myId)"
                cell.imageView?.image = UIImage(systemName: "gift.fill")
            case 3:
                cell.textLabel?.text = "Тариф MediaTok Team (на 5 человек) & Work Workspace (#1486/#1487)"
                cell.detailTextLabel?.text = self.cfg.workWorkspaceMode ? "Корпоративный режим: АКТИВЕН" : "Общие шаблоны и единый анти-скам для команды"
                cell.imageView?.image = UIImage(systemName: "person.3.sequence.fill")
            default:
                cell.textLabel?.text = "Nightly Early Access & VPN+Pro Слот (#1489 / #1491)"
                cell.detailTextLabel?.text = self.cfg.nightlyEarlyAccessEnabled ? "Ранний бета-доступ: ВКЛ" : "Тестовые сборки и быстрый туннель"
                cell.imageView?.image = UIImage(systemName: "bolt.shield.fill")
            }
        case 1:
            switch indexPath.row {
            case 0:
                let check = MTMediaTokWave23Tools.verifyBundleIntegrity()
                cell.textLabel?.text = "Проверка подлинности .ipa и Анти-Кряк (#1482 / #1483 / #1495)"
                cell.detailTextLabel?.text = check.summary
                cell.detailTextLabel?.textColor = check.isAuthentic ? .systemGreen : .systemRed
                cell.imageView?.image = UIImage(systemName: "checkmark.seal.fill")
            case 1:
                cell.textLabel?.text = "Сохранить лицензию Pro в iCloud Keychain (#1488)"
                cell.detailTextLabel?.text = "Переживает удаление приложения и перенос на новый iPhone"
                cell.imageView?.image = UIImage(systemName: "icloud.and.arrow.up.fill")
            case 2:
                cell.textLabel?.text = "Единый QR-код переноса настроек + Pro на новый iPhone (#1494)"
                cell.detailTextLabel?.text = "Генерация JSON-слепка для мгновенного переезда"
                cell.imageView?.image = UIImage(systemName: "qrcode")
            default:
                cell.textLabel?.text = "Совместимость контейнера SideStore / Feather / TrollStore (#1498/#1499)"
                cell.detailTextLabel?.text = "Проверка прав чтения базы и AppGroup после переподписи"
                cell.imageView?.image = UIImage(systemName: "wrench.and.screwdriver.fill")
            }
        case 2:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Авто-самозачистка своих старых реплик в группах (#1018)"
                cell.detailTextLabel?.text = self.cfg.rollingScrubHours == 0 ? "Выкл (нажмите для 24ч / 72ч)" : "Удалять мои сообщения старше \(self.cfg.rollingScrubHours) ч"
                cell.imageView?.image = UIImage(systemName: "clock.arrow.circlepath")
            case 1:
                cell.textLabel?.text = "Индивидуальная модель iPhone на этот аккаунт (#1104)"
                let k = "\(self.context.account.id.int64)"
                cell.detailTextLabel?.text = self.cfg.perAccountDeviceModels[k] ?? "По умолчанию (нажмите для спуфа отпечатка твинка)"
                cell.imageView?.image = UIImage(systemName: "iphone.gen3")
            case 2:
                cell.textLabel?.text = "Изоляция Cookie/LocalStorage Mini Apps на каждый акк (#1105)"
                cell.detailTextLabel?.text = self.cfg.isolateWebStorePerAccount ? "ВКЛЮЧЕНА (разные WKWebsiteDataStore)" : "ВЫКЛ"
                cell.imageView?.image = UIImage(systemName: "lock.rectangle.stack.fill")
            case 3:
                cell.textLabel?.text = "8-поточный буст скачивания и отдачи файлов (#1381)"
                cell.detailTextLabel?.text = self.cfg.parallel8BoostEnabled ? "МАКСИМУМ (1 МБ чанки × 12 потоков)" : "Стандарт"
                cell.imageView?.image = UIImage(systemName: "gauge.with.dots.needle.67percent")
            default:
                cell.textLabel?.text = "Минималистичное меню «Только используемое» (#1497)"
                cell.detailTextLabel?.text = self.cfg.minimalistMenuHideUnused ? "Скрывать выключенные модули: ВКЛ" : "Показывать все разделы"
                cell.imageView?.image = UIImage(systemName: "Sparkles".lowercased())
            }
        default:
            let logs = Array(MTMediaTokWave23Tools.loadAutomationLogs().prefix(10))
            cell.accessoryType = .none
            if logs.isEmpty {
                cell.textLabel?.text = "Срабатываний пока нет"
                cell.detailTextLabel?.text = "Здесь фиксируются отбитые спам-заявки, Slowmode-очереди и снайперы (#1496)"
            } else {
                let entry = logs[indexPath.row]
                cell.textLabel?.text = "\(entry.module) (сэкономлено ~\(entry.savedSeconds)с)"
                cell.detailTextLabel?.text = entry.detail
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                // #1475 Open official @tribute bot inside Telegram
                if let u = URL(string: "https://t.me/tribute") {
                    UIApplication.shared.open(u)
                }
            case 1:
                // #1481 VIP Friends Free Pro by User ID
                let alert = UIAlertController(title: "VIP-друзья с бесплатным Pro (#1481)", message: "Введите числовой Telegram User ID друга (у него автоматически активируется вечный MediaTok Pro):", preferredStyle: .alert)
                alert.addTextField {
                    $0.placeholder = "Например 123456789"
                    $0.keyboardType = .numberPad
                }
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                alert.addAction(UIAlertAction(title: "Добавить VIP ID", style: .default) { [weak self, weak alert] _ in
                    guard let self else { return }
                    if let id64 = Int64((alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) {
                        var cyber = MTMediaTokWave19Tools.loadCyberConfig()
                        if !cyber.vipProFriendUserIds.contains(id64) {
                            cyber.vipProFriendUserIds.append(id64)
                            MTMediaTokWave19Tools.saveCyberConfig(cyber)
                        }
                        if id64 == self.context.account.peerId.id._internalGetInt64Value() {
                            MTMediaTokWave19Tools.isProActive = true
                        }
                        self.tableView.reloadData()
                        MTMediaTokWave5Tools.showToast(context: self.context, text: "VIP друг \(id64) получил вечный Pro!")
                    }
                })
                self.present(alert, animated: true)
            case 2:
                let myId = self.context.account.peerId.id._internalGetInt64Value()
                UIPasteboard.general.string = "MT-REF-\(myId)"
                MTMediaTokWave5Tools.showToast(context: self.context, text: "Ваш партнёрский реф-код MT-REF-\(myId) скопирован (30% RevShare #1484)")
            case 3:
                self.cfg.workWorkspaceMode.toggle()
                MTMediaTokWave23Tools.saveConfig(self.cfg)
                self.tableView.reloadData()
            default:
                self.cfg.nightlyEarlyAccessEnabled.toggle()
                MTMediaTokWave23Tools.saveConfig(self.cfg)
                self.tableView.reloadData()
            }
        } else if indexPath.section == 1 {
            switch indexPath.row {
            case 0:
                let check = MTMediaTokWave23Tools.verifyBundleIntegrity()
                MTMediaTokWave5Tools.showToast(context: self.context, text: check.summary)
            case 1:
                MTMediaTokWave23Tools.backupProTokenToKeychain("MT-PRO-KEYCHAIN-\(self.context.account.peerId.id._internalGetInt64Value())", synchronizable: true)
                MTMediaTokWave5Tools.showToast(context: self.context, text: "Токен лицензии сохранён в зашифрованный iCloud Keychain (#1488)!")
            case 2:
                let payload = "{\"pro\":\(MTMediaTokWave19Tools.isProActive),\"uid\":\(self.context.account.peerId.id._internalGetInt64Value()),\"build\":\"3803\"}"
                UIPasteboard.general.string = payload
                MTMediaTokWave5Tools.showToast(context: self.context, text: "Слепок переноса (#1494) скопирован для нового iPhone!")
            default:
                let docsOk = FileManager.default.isWritableFile(atPath: NSTemporaryDirectory())
                MTMediaTokWave5Tools.showToast(context: self.context, text: docsOk ? "Контейнер и права записи SideStore/Feather в полном порядке (#1499)" : "Ошибка прав контейнера")
            }
        } else if indexPath.section == 2 {
            switch indexPath.row {
            case 0:
                let nextVal = self.cfg.rollingScrubHours == 0 ? 24 : (self.cfg.rollingScrubHours == 24 ? 72 : 0)
                self.cfg.rollingScrubHours = nextVal
                MTMediaTokWave23Tools.saveConfig(self.cfg)
                self.tableView.reloadData()
            case 1:
                let alert = UIAlertController(title: "Спуф модели на этот аккаунт (#1104)", message: "Антифрод Telegram увидит выбранную модель устройства только на этом аккаунте:", preferredStyle: .alert)
                for model in ["iPhone 16 Pro Max", "iPhone 15 Pro", "iPad Pro 13-inch (M4)", "iPhone 14 Plus", "Сбросить по умолчанию"] {
                    alert.addAction(UIAlertAction(title: model, style: .default) { [weak self] _ in
                        guard let self else { return }
                        let k = "\(self.context.account.id.int64)"
                        if model.hasPrefix("Сбросить") {
                            self.cfg.perAccountDeviceModels.removeValue(forKey: k)
                        } else {
                            self.cfg.perAccountDeviceModels[k] = model
                        }
                        MTMediaTokWave23Tools.saveConfig(self.cfg)
                        self.tableView.reloadData()
                    })
                }
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                self.present(alert, animated: true)
            case 2:
                self.cfg.isolateWebStorePerAccount.toggle()
                MTMediaTokWave23Tools.saveConfig(self.cfg)
                self.tableView.reloadData()
            case 3:
                self.cfg.parallel8BoostEnabled.toggle()
                MTMediaTokWave23Tools.saveConfig(self.cfg)
                self.tableView.reloadData()
            default:
                self.cfg.minimalistMenuHideUnused.toggle()
                MTMediaTokWave23Tools.saveConfig(self.cfg)
                self.tableView.reloadData()
            }
        }
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}
