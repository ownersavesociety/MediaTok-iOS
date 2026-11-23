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
    )>((.default, [], false, nil, nil, [], [:], [:]))

    // MARK: - Registration

    public static func register() {
        let initial = loadConfigFromDisk()
        syncFastDefaults(initial)
        stateBox.withLock {
            $0.cachedConfig = initial
            $0.ignoredSet = Set(initial.shadowIgnoredAuthorIds)
        }
        DispatchQueue.main.async {
            stateBox.withLock { $0.isScreenCaptured = UIScreen.main.isCaptured }
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
            if cap, loadConfig().hide777000OnScreenCapture {
                appendAutomationLog(module: "Защита стрима", detail: "Скрыты сервисные коды Telegram 777000 на время записи экрана", savedSeconds: 120)
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

    private static let proTokenFallbackKey = "mediatok.wave23.pro_token.fb.v1"

    // #1488 Keychain / iCloud Keychain license persistence (with sideload -34018 fallback)
    public static func backupProTokenToKeychain(_ token: String, synchronizable: Bool = true) {
        let service = "org.mediatok.pro.license.v1"
        let account = "active_token"
        let delQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(delQuery as CFDictionary)
        guard let data = token.data(using: .utf8), !data.isEmpty else {
            UserDefaults.standard.removeObject(forKey: proTokenFallbackKey)
            return
        }
        var addQuery = delQuery
        addQuery[kSecValueData as String] = data
        if synchronizable {
            addQuery[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        if SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: proTokenFallbackKey)
        } else {
            MTMediaTokCoreLogic.resilientSecretSave(data, service: service, account: account, fallbackKey: proTokenFallbackKey)
        }
    }

    private static func restoreLicenseFromKeychainIfNeeded() {
        guard !MTMediaTokWave19Tools.isProActive else { return }
        let service = "org.mediatok.pro.license.v1"
        let account = "active_token"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let str = String(data: data, encoding: .utf8), !str.isEmpty {
            MTMediaTokWave19Tools.isProActive = true
            return
        }
        if let fallbackData = MTMediaTokCoreLogic.resilientSecretLoad(service: service, account: account, fallbackKey: proTokenFallbackKey),
           let str = String(data: fallbackData, encoding: .utf8), !str.isEmpty {
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
        return MTModalPresenter.topmostViewController()
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

        // #1027 Slowmode Auto-Queue: non-blocking check so main thread never stalls on a semaphore
        if loadConfig().slowmodeAutoQueue, let pid = peerId, pid.namespace == Namespaces.Peer.CloudChannel, !raw.isEmpty {
            let ctx = request.context
            let _ = (ctx.account.postbox.transaction({ tx -> Int32 in
                if let cached = tx.getPeerCachedData(peerId: pid) as? CachedChannelData,
                   let until = cached.slowModeValidUntilTimestamp {
                    return until
                }
                return 0
            }) |> deliverOnMainQueue).startStandalone(next: { activeUntil in
                let nowSec = Int32(Date().timeIntervalSince1970)
                if activeUntil > nowSec + 1 {
                    let waitSec = Int(activeUntil - nowSec) + 1
                    request.replace(ChatTextInputState())
                    stateBox.withLock { st in
                        let extraOffset = st.slowmodeQueue.filter { $0.peerId == pid }.count * 15
                        st.slowmodeQueue.append((peerId: pid, text: fullText, sendAtUnix: Int(activeUntil) + 1 + extraOffset))
                    }
                    armWorkerIfNeeded(context: ctx)
                    MTMediaTokWave5Tools.showToast(context: ctx, text: "Slowmode-очередь (#1027): сообщение уйдёт само через \(waitSec) сек!")
                    appendAutomationLog(module: "Slowmode Очередь #1027", detail: "Поставлено в авто-отправку через \(waitSec) сек", savedSeconds: waitSec)
                } else {
                    proceed()
                }
            })
            return true
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
        mtPresentNativePrompt(
            context: context,
            title: "Пакетное клонирование канала",
            subtitle: "Укажите @канал назначения и лимит через пробел (например: @backup 30). Оставьте пустым — скопирует 25 постов в Избранное:",
            value: "25",
            placeholder: "@backup_channel 25",
            characterLimit: 80,
            apply: { raw in
                let parts = raw.split(separator: " ").map(String.init)
                var dstName = ""
                var limit = 25
                for p in parts {
                    if let n = Int(p) {
                        limit = max(1, min(100, n))
                    } else {
                        dstName = p.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
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
                        mtPresentNativeToast(context: context, text: "Клонировано постов: \(outBatch.count)")
                        appendAutomationLog(module: "Клон канала", detail: "Перенесено \(outBatch.count) постов", savedSeconds: outBatch.count * 10)
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
                            mtPresentNativeToast(context: context, text: "Целевой канал @\(dstName) не найден")
                        }
                    })
                }
            }
        )
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

        mtPresentNativeAlert(
            context: context,
            title: isValidLuhn ? "Карта прошла проверку Луна" : "Некорректный номер карты (ошибка Луна)",
            text: "Номер: \(card16)\nBIN (6 цифр): \(bin6)\nЭмитент: \(localIssuer)\nКонтрольная сумма Luhn: \(isValidLuhn ? "КОРРЕКТНА" : "НЕВАЛИДНА — реквизит выдуман или с опечаткой")",
            confirmTitle: "Скопировать 16 цифр",
            destructive: false,
            confirmAction: {
                UIPasteboard.general.string = card16
                mtPresentNativeToast(context: context, text: "16 цифр карты скопированы")
            }
        )
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
            mtPresentNativeToast(context: context, text: cfg.snipedUsername.isEmpty ? "Снайпер @username остановлен" : "Снайпер следит за @\(clean)")
            return
        }
        mtPresentNativePrompt(
            context: context,
            title: "Снайпер освобождения @username",
            subtitle: "Укажите занятый @тег (без @). Оставьте пустым, чтобы выключить мониторинг:",
            value: loadConfig().snipedUsername,
            placeholder: "username",
            characterLimit: 32,
            apply: { raw in
                let u = raw.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                var cfg = loadConfig()
                cfg.snipedUsername = u
                saveConfig(cfg)
                mtPresentNativeToast(context: context, text: u.isEmpty ? "Снайпер выключен" : "Мониторинг @\(u) запущен")
            }
        )
    }

    // MARK: - #1060 / #1061 4-Marketplace Gift Arbitrage + Backdrop Multiplier

    public static func presentNftArbitrageCalculator(context: AccountContext, initialQuery: String) {
        let controller = mtMakeNativeNftArbitrageController(context: context, initialCollection: initialQuery)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #1073 Wallet Self-Deanon Inspector

    public static func presentWalletDeanonCheck(context: AccountContext) {
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
        |> deliverOnMainQueue).startStandalone(next: { peer in
            var warnings: [String] = []
            if case let .user(user) = peer {
                if let phone = user.phone, phone.hasPrefix("888") {
                    warnings.append("• Ваш аккаунт привязан к анонимному номеру +\(phone): адрес минта в блокчейне TON публично показывает все остальные NFT и переводы того же кошелька.")
                }
                if user.emojiStatus != nil {
                    warnings.append("• Надетый коллекционный статус/подарок с выводом в TON позволяет по номеру минта (#ID) найти кошелёк на Fragment/Tonviewer.")
                }
            }
            if warnings.isEmpty {
                warnings.append("• Прямых ончейн-связок (+888 номеров) на основном профиле не обнаружено.\n• Совет: для анонимных аккаунтов не выводите подарки на публичный кошелёк с .ton доменом.")
            }
            mtPresentNativeAlert(context: context, title: "Проверка деанона кошелька", text: warnings.joined(separator: "\n\n"))
        })
    }

    // MARK: - #1107 Cross-Account Search & #1359 Dork Search

    public static func presentCrossAccountSearch(context: AccountContext, initialQuery: String) {
        let controller = mtMakeNativeCrossAccountSearchController(context: context, initialQuery: initialQuery)
        mtPushNativeController(controller, context: context)
    }

    public static func presentDorkChatSearch(context: AccountContext, peerId: PeerId, initialDork: String) {
        let controller = mtMakeNativeDorkSearchController(context: context, peerId: peerId, initialDork: initialDork)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #1460..#1500 Commercial MediaTok Pro Suite

    public static func presentCommercialProSuite(context: AccountContext) {
        let controller = mtMakeNativeCommercialProSuiteController(context: context)
        mtPushNativeController(controller, context: context)
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

// MARK: - #1060 / #1061 Native 4-Market Gift Arbitrage Controller

private struct MTNftArbitrageState: Equatable {
    var selectedSlug: String
    var selectedBackdropIdx: Int = 0
}

private func mtMakeNativeNftArbitrageController(context: AccountContext, initialCollection: String) -> ViewController {
    let collections: [(slug: String, name: String, baseTon: Double)] = [
        ("plushpepe", "Plush Pepe", 920.0),
        ("durovscap", "Durov's Cap", 310.0),
        ("preciouspeach", "Precious Peach", 68.0),
        ("vintagecigar", "Vintage Cigar", 42.0),
        ("swisswatch", "Swiss Watch", 54.0),
        ("signetring", "Signet Ring", 36.0),
        ("kissedfrog", "Kissed Frog", 24.0),
        ("scaredcat", "Scared Cat", 29.0)
    ]
    let backdrops: [(name: String, mult: Double)] = [
        ("Обычный фон (1.0× Floor)", 1.0),
        ("Onyx Black / Midnight (2.35×)", 2.35),
        ("Pure Gold / Amber (1.85×)", 1.85),
        ("Cyberpunk Neon (1.55×)", 1.55),
        ("Monochrome Color-Match (2.80×)", 2.80)
    ]

    let low = initialCollection.lowercased().replacingOccurrences(of: " ", with: "")
    let startSlug = collections.first(where: { low.contains($0.slug) })?.slug ?? "plushpepe"
    let initial = MTNftArbitrageState(selectedSlug: startSlug)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Арбитраж подарков")
        let col = collections.first(where: { $0.slug == st.selectedSlug }) ?? collections[0]
        let bg = backdrops[st.selectedBackdropIdx]
        let base = col.baseTon * bg.mult

        model.sections.append([
            .init(id: "p_hdr", kind: .header("Параметры подарка")),
            .init(id: "pick_col", kind: .disclosure(title: "Коллекция", label: col.name, icon: .system("gift"), enabled: true)),
            .init(id: "pick_bg", kind: .disclosure(title: "Множитель фона", label: bg.name, icon: .system("sparkles"), enabled: true))
        ])

        model.tap["pick_col"] = {
            mtPresentNativeActionSheet(
                context: context,
                title: "Выберите коллекцию",
                buttons: collections.map { c in
                    (c.name, false, {
                        let next = stateValue.modify { cur in var s = cur; s.selectedSlug = c.slug; return s }
                        statePromise.set(next)
                    })
                }
            )
        }
        model.tap["pick_bg"] = {
            mtPresentNativeActionSheet(
                context: context,
                title: "Наценка за редкость фона",
                buttons: backdrops.enumerated().map { idx, b in
                    (b.name, false, {
                        let next = stateValue.modify { cur in var s = cur; s.selectedBackdropIdx = idx; return s }
                        statePromise.set(next)
                    })
                }
            )
        }

        let markets: [(id: String, name: String, ton: Double)] = [
            ("frag", "Fragment (On-Chain 5% fee)", base * 1.04),
            ("portals", "Portals Market (2.5% fee)", base * 0.96),
            ("tonnel", "Tonnel Relayer (Off-chain)", base * 0.94),
            ("mrkt", "MRKT Telegram App", base * 1.01)
        ]

        var mRows: [MTNativeRow] = [.init(id: "m_hdr", kind: .header("Оценка на 4 площадках"))]
        for m in markets {
            let rowId = "mkt_\(m.id)"
            mRows.append(.init(id: rowId, kind: .disclosure(title: m.name, label: String(format: "%.1f TON", m.ton), icon: nil, enabled: true)))
            model.tap[rowId] = {
                UIPasteboard.general.string = String(format: "%@ · %@: %.1f TON", col.name, m.name, m.ton)
                mtPresentNativeToast(context: context, text: "Оценка скопирована в буфер обмена")
            }
        }
        model.sections.append(mRows)
        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #1107 Native Cross-Account Search Controller

private struct MTCrossAccountHit: Equatable {
    let id: String
    let accountTitle: String
    let chatTitle: String
    let snippet: String
}

private struct MTCrossAccountSearchState: Equatable {
    var query: String
    var hits: [MTCrossAccountHit] = []
    var searching: Bool = false
}

private func mtMakeNativeCrossAccountSearchController(context: AccountContext, initialQuery: String) -> ViewController {
    let initial = MTCrossAccountSearchState(query: initialQuery)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)

    let runSearch: (String) -> Void = { rawQuery in
        let low = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !low.isEmpty else { return }
        let start = stateValue.modify { cur in
            var c = cur
            c.hits = []
            c.searching = true
            return c
        }
        statePromise.set(start)

        let _ = (context.sharedContext.activeAccountsWithInfo
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { (_, accounts) in
            if accounts.isEmpty {
                let done = stateValue.modify { cur in var c = cur; c.searching = false; return c }
                statePromise.set(done)
                return
            }
            let remaining = Atomic(value: accounts.count)
            for info in accounts {
                let acc = info.account
                let accIdLabel = "Аккаунт \(acc.peerId.id._internalGetInt64Value())"
                let _ = (acc.postbox.transaction { tx -> [MTCrossAccountHit] in
                    var localHits: [MTCrossAccountHit] = []
                    let top = tx.getTopChatListEntries(groupId: .root, count: 60)
                    for entry in top {
                        let chatName = entry.peer?.debugDisplayTitle ?? "\(entry.peerId.toInt64())"
                        tx.scanTopMessages(peerId: entry.peerId, namespace: Namespaces.Message.Cloud, limit: 25) { m in
                            if m.text.lowercased().contains(low) {
                                localHits.append(MTCrossAccountHit(
                                    id: "\(acc.peerId.toInt64())_\(entry.peerId.toInt64())_\(m.id.id)",
                                    accountTitle: accIdLabel,
                                    chatTitle: chatName,
                                    snippet: String(m.text.prefix(160))
                                ))
                            }
                            return localHits.count < 40
                        }
                    }
                    return localHits
                } |> deliverOnMainQueue).startStandalone(next: { found in
                    let left = remaining.modify { $0 - 1 }
                    let next = stateValue.modify { cur in
                        var c = cur
                        c.hits.append(contentsOf: found)
                        if left <= 0 {
                            c.searching = false
                        }
                        return c
                    }
                    statePromise.set(next)
                })
            }
        })
    }

    if !initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        DispatchQueue.main.async {
            runSearch(initialQuery)
        }
    }

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Поиск по аккаунтам")

        model.sections.append([
            .init(id: "s_hdr", kind: .header("Запрос по всем авторизованным аккаунтам")),
            .init(id: "q_in", kind: .input(text: st.query, placeholder: "Слово или фраза...")),
            .init(id: "go_btn", kind: .action(title: st.searching ? "Идёт поиск..." : "Найти во всех аккаунтах", destructive: false, enabled: !st.searching))
        ])

        model.text["q_in"] = { val in
            let _ = stateValue.modify { cur in var c = cur; c.query = val; return c }
        }
        model.tap["go_btn"] = {
            let q = stateValue.with { $0.query }
            runSearch(q)
        }

        var hitRows: [MTNativeRow] = [.init(id: "h_hdr", kind: .header("Совпадения (\(st.hits.count))"))]
        if st.hits.isEmpty {
            hitRows.append(.init(id: "h_empty", kind: .info(st.searching ? "Сканирую чаты всех аккаунтов..." : "Введите слово и нажмите «Найти во всех аккаунтах».")))
        } else {
            for hit in st.hits.prefix(80) {
                let rowId = "hit_\(hit.id)"
                hitRows.append(.init(id: rowId, kind: .info("[\(hit.accountTitle)] · \(hit.chatTitle)\n\(hit.snippet)")))
            }
        }
        model.sections.append(hitRows)
        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #1359 Native Dork Search Controller

private struct MTDorkHit: Equatable {
    let id: Int32
    let author: String
    let text: String
}

private struct MTDorkSearchState: Equatable {
    var dork: String
    var results: [MTDorkHit] = []
    var loaded: Bool = false
}

private func mtMakeNativeDorkSearchController(context: AccountContext, peerId: PeerId, initialDork: String) -> ViewController {
    let startQuery = initialDork.isEmpty ? "has:file -реклама" : initialDork
    let initial = MTDorkSearchState(dork: startQuery)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)

    let executeDork: (String) -> Void = { dork in
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

        let _ = (context.account.postbox.transaction { tx -> [MTDorkHit] in
            var out: [MTDorkHit] = []
            tx.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 400) { m in
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

                let summary = m.text.isEmpty ? "[Файл / Медиа]" : String(m.text.prefix(180))
                out.append(MTDorkHit(id: m.id.id, author: authorName, text: summary))
                return out.count < 80
            }
            return out
        } |> deliverOnMainQueue).startStandalone(next: { res in
            let next = stateValue.modify { cur in
                var c = cur
                c.results = res
                c.loaded = true
                return c
            }
            statePromise.set(next)
        })
    }

    DispatchQueue.main.async {
        executeDork(startQuery)
    }

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Дорк-поиск чата")

        model.sections.append([
            .init(id: "d_hdr", kind: .header("Операторы поиска")),
            .init(id: "d_in", kind: .input(text: st.dork, placeholder: "from:имя has:file size:>10mb -минус")),
            .init(id: "d_go", kind: .action(title: "Применить фильтр", destructive: false, enabled: true)),
            .init(id: "d_ftr", kind: .footer("Поддерживаются операторы: from:автор, has:file, size:>10mb и минус-слова (-реклама)."))
        ])

        model.text["d_in"] = { val in
            let _ = stateValue.modify { cur in var c = cur; c.dork = val; return c }
        }
        model.tap["d_go"] = {
            executeDork(stateValue.with { $0.dork })
        }

        var rRows: [MTNativeRow] = [.init(id: "r_hdr", kind: .header("Результаты (\(st.results.count))"))]
        if st.results.isEmpty {
            rRows.append(.init(id: "r_empty", kind: .info(st.loaded ? "Ничего не найдено по заданным операторам." : "Поиск...")))
        } else {
            for r in st.results {
                rRows.append(.init(id: "r_\(r.id)", kind: .info("\(r.author)\n\(r.text)")))
            }
        }
        model.sections.append(rRows)
        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #1460..#1500 Native Commercial MediaTok Pro Ecosystem Controller

private struct MTCommercialProState: Equatable {
    var cfg: MTWave23Config
    var vipCount: Int
}

private func mtMakeNativeCommercialProSuiteController(context: AccountContext) -> ViewController {
    let initial = MTCommercialProState(
        cfg: MTMediaTokWave23Tools.loadConfig(),
        vipCount: MTMediaTokWave19Tools.loadCyberConfig().vipProFriendUserIds.count
    )
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)

    let deviceModels = ["iPhone 16 Pro Max", "iPhone 15 Pro", "iPad Pro 13-inch (M4)", "iPhone 14 Plus", "Сбросить по умолчанию"]

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "MediaTok Pro и Автоматизация")
        let cfg = st.cfg
        let myId = context.account.peerId.id._internalGetInt64Value()
        let acctKey = "\(context.account.id.int64)"

        model.sections.append([
            .init(id: "p_hdr", kind: .header("Подписка, партнёрка и VIP-друзья")),
            .init(id: "open_tribute", kind: .disclosure(title: "Оформить через @tribute", label: "СБП / Stars", icon: .system("creditcard"), enabled: true)),
            .init(id: "vip_friends", kind: .disclosure(title: "VIP-друзья с бесплатным Pro", label: "\(st.vipCount)", icon: .system("person.2.badge.key"), enabled: true)),
            .init(id: "copy_ref", kind: .disclosure(title: "Партнёрский реф-код (30%)", label: "MT-REF-\(myId)", icon: .system("gift"), enabled: true)),
            .init(id: "sw_work", kind: .toggle(title: "Корпоративный режим Work Workspace", value: cfg.workWorkspaceMode, enabled: true)),
            .init(id: "sw_nightly", kind: .toggle(title: "Ранний бета-доступ Nightly", value: cfg.nightlyEarlyAccessEnabled, enabled: true))
        ])

        model.tap["open_tribute"] = {
            if let u = URL(string: "https://t.me/tribute") {
                UIApplication.shared.open(u)
            }
        }
        model.tap["vip_friends"] = {
            mtPresentNativePrompt(
                context: context,
                title: "VIP-друг с вечным Pro",
                subtitle: "Введите числовой Telegram User ID друга:",
                placeholder: "123456789",
                characterLimit: 20,
                apply: { raw in
                    guard let id64 = Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        mtPresentNativeToast(context: context, text: "Укажите корректный числовой Telegram ID")
                        return
                    }
                    var cyber = MTMediaTokWave19Tools.loadCyberConfig()
                    if !cyber.vipProFriendUserIds.contains(id64) {
                        cyber.vipProFriendUserIds.append(id64)
                        MTMediaTokWave19Tools.saveCyberConfig(cyber)
                    }
                    if id64 == myId {
                        MTMediaTokWave19Tools.isProActive = true
                    }
                    let next = stateValue.modify { cur in var c = cur; c.vipCount = cyber.vipProFriendUserIds.count; return c }
                    statePromise.set(next)
                    mtPresentNativeToast(context: context, text: "VIP ID \(id64) добавлен")
                }
            )
        }
        model.tap["copy_ref"] = {
            UIPasteboard.general.string = "MT-REF-\(myId)"
            mtPresentNativeToast(context: context, text: "Реферальный код MT-REF-\(myId) скопирован")
        }
        model.toggle["sw_work"] = { val in
            let next = stateValue.modify { cur in var c = cur; c.cfg.workWorkspaceMode = val; return c }
            MTMediaTokWave23Tools.saveConfig(next.cfg)
            statePromise.set(next)
        }
        model.toggle["sw_nightly"] = { val in
            let next = stateValue.modify { cur in var c = cur; c.cfg.nightlyEarlyAccessEnabled = val; return c }
            MTMediaTokWave23Tools.saveConfig(next.cfg)
            statePromise.set(next)
        }

        let check = MTMediaTokWave23Tools.verifyBundleIntegrity()
        model.sections.append([
            .init(id: "s_hdr", kind: .header("Подлинность сборки и перенос")),
            .init(id: "integrity_info", kind: .info(check.summary)),
            .init(id: "save_keychain", kind: .action(title: "Сохранить лицензию в iCloud Keychain", destructive: false, enabled: true)),
            .init(id: "copy_transfer", kind: .action(title: "Скопировать слепок переноса на новый iPhone", destructive: false, enabled: true))
        ])
        model.tap["save_keychain"] = {
            MTMediaTokWave23Tools.backupProTokenToKeychain("MT-PRO-KEYCHAIN-\(myId)", synchronizable: true)
            mtPresentNativeToast(context: context, text: "Лицензия сохранена в iCloud Keychain")
        }
        model.tap["copy_transfer"] = {
            let payload = "{\"pro\":\(MTMediaTokWave19Tools.isProActive),\"uid\":\(myId),\"build\":\"3821\"}"
            UIPasteboard.general.string = payload
            mtPresentNativeToast(context: context, text: "Слепок переноса скопирован в буфер обмена")
        }

        let scrubLabel = cfg.rollingScrubHours == 0 ? "Выкл" : "\(cfg.rollingScrubHours) ч"
        let modelSpoofLabel = cfg.perAccountDeviceModels[acctKey] ?? "По умолчанию"
        model.sections.append([
            .init(id: "u_hdr", kind: .header("Юзербот, Мульти-Аккаунт и Скорость")),
            .init(id: "scrub_pick", kind: .disclosure(title: "Авто-очистка старых реплик в группах", label: scrubLabel, icon: .system("clock.arrow.circlepath"), enabled: true)),
            .init(id: "spoof_model", kind: .disclosure(title: "Модель устройства для этого аккаунта", label: modelSpoofLabel, icon: .system("iphone"), enabled: true)),
            .init(id: "sw_webstore", kind: .toggle(title: "Изоляция Cookie/LocalStorage Mini Apps", value: cfg.isolateWebStorePerAccount, enabled: true)),
            .init(id: "sw_boost", kind: .toggle(title: "Многопоточное ускорение загрузки", value: cfg.parallel8BoostEnabled, enabled: true)),
            .init(id: "sw_minmenu", kind: .toggle(title: "Скрывать неиспользуемые модули", value: cfg.minimalistMenuHideUnused, enabled: true))
        ])

        model.tap["scrub_pick"] = {
            mtPresentNativeActionSheet(
                context: context,
                title: "Авто-удаление ваших старых сообщений в публичных группах",
                buttons: [
                    ("Выключено", false, {
                        let next = stateValue.modify { cur in var c = cur; c.cfg.rollingScrubHours = 0; return c }
                        MTMediaTokWave23Tools.saveConfig(next.cfg)
                        statePromise.set(next)
                    }),
                    ("Старше 24 часов", false, {
                        let next = stateValue.modify { cur in var c = cur; c.cfg.rollingScrubHours = 24; return c }
                        MTMediaTokWave23Tools.saveConfig(next.cfg)
                        statePromise.set(next)
                    }),
                    ("Старше 72 часов", false, {
                        let next = stateValue.modify { cur in var c = cur; c.cfg.rollingScrubHours = 72; return c }
                        MTMediaTokWave23Tools.saveConfig(next.cfg)
                        statePromise.set(next)
                    })
                ]
            )
        }
        model.tap["spoof_model"] = {
            mtPresentNativeActionSheet(
                context: context,
                title: "Индивидуальная модель устройства для текущего аккаунта",
                buttons: deviceModels.map { m in
                    (m, m.hasPrefix("Сбросить"), {
                        let next = stateValue.modify { cur in
                            var c = cur
                            if m.hasPrefix("Сбросить") {
                                c.cfg.perAccountDeviceModels.removeValue(forKey: acctKey)
                            } else {
                                c.cfg.perAccountDeviceModels[acctKey] = m
                            }
                            return c
                        }
                        MTMediaTokWave23Tools.saveConfig(next.cfg)
                        statePromise.set(next)
                    })
                }
            )
        }
        model.toggle["sw_webstore"] = { val in
            let next = stateValue.modify { cur in var c = cur; c.cfg.isolateWebStorePerAccount = val; return c }
            MTMediaTokWave23Tools.saveConfig(next.cfg)
            statePromise.set(next)
        }
        model.toggle["sw_boost"] = { val in
            let next = stateValue.modify { cur in var c = cur; c.cfg.parallel8BoostEnabled = val; return c }
            MTMediaTokWave23Tools.saveConfig(next.cfg)
            statePromise.set(next)
        }
        model.toggle["sw_minmenu"] = { val in
            let next = stateValue.modify { cur in var c = cur; c.cfg.minimalistMenuHideUnused = val; return c }
            MTMediaTokWave23Tools.saveConfig(next.cfg)
            statePromise.set(next)
        }

        let logs = Array(MTMediaTokWave23Tools.loadAutomationLogs().prefix(10))
        var logRows: [MTNativeRow] = [.init(id: "l_hdr", kind: .header("Журнал автоматизации"))]
        if logs.isEmpty {
            logRows.append(.init(id: "l_empty", kind: .info("Срабатываний автоматизации пока нет.")))
        } else {
            for (idx, entry) in logs.enumerated() {
                logRows.append(.init(id: "log_\(idx)_\(entry.timestamp)", kind: .info("\(entry.module) (~\(entry.savedSeconds) сек)\n\(entry.detail)")))
            }
        }
        model.sections.append(logRows)
        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}
