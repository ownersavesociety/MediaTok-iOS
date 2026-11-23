import Foundation
import UIKit
import AsyncDisplayKit
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
// MediaTok Wave 20 — CallKit Recents Bypass, Mirror DM, Typing Stopwatch,
//                    DC Header Pill, Smart URL Joiner, Macros, Ghost-Read Burn & Songlink:
//   #776 / .callrecents — Hide Telegram calls from iOS Phone.app "Recents" (CallKit + Siri Intents)
//   #505 / .mirror      — Auto-mirror incoming stickers & reactions back to sender in DM
//   #532 / .ignoreall   — Suppress @all / @everyone / @admin mass-tag highlights
//   #537                — Live Typing Stopwatch pill ("печатает... 42с") in chat screen
//   #995 / .dcheader    — Compact live "DC2 · Online" pill in chat screen
//   #990 / .macros      — Quick text expansion (;аббр -> full phrase) on send
//   #992                — Auto-repair multi-line broken URLs before sending
//   #993                — Live Message Preview Card in Send-button long-press menu
//   #994 / .ghost1m     — Send silently + auto-delete for everyone 60s AFTER recipient reads it
//   #928 / .songlink    — Universal Songlink/Odesli resolver (Apple Music / Spotify / YouTube Music)
//   #503 / .captcha     — Anti-spam math/code challenge gate for unknown DM senders
// ============================================================================

private final class MTWave20Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body(&self.value)
    }
}

public struct MTWave20Config: Codable, Equatable {
    public var hideCallKitRecents: Bool
    public var typingStopwatchEnabled: Bool
    public var dcHeaderDotEnabled: Bool
    public var autoJoinBrokenUrls: Bool
    public var ignoreMassMentions: Bool
    public var dmCaptchaEnabled: Bool
    public var macros: [String: String]

    private enum CodingKeys: String, CodingKey {
        case hideCallKitRecents
        case typingStopwatchEnabled
        case dcHeaderDotEnabled
        case autoJoinBrokenUrls
        case ignoreMassMentions
        case dmCaptchaEnabled
        case macros
    }

    public static let `default` = MTWave20Config(
        hideCallKitRecents: false,
        typingStopwatchEnabled: true,
        dcHeaderDotEnabled: false,
        autoJoinBrokenUrls: true,
        ignoreMassMentions: false,
        dmCaptchaEnabled: false,
        macros: [
            ";рекв": "Отправьте реквизиты, пожалуйста.",
            ";спс": "Спасибо большое, всё получил!"
        ]
    )
}

private struct MTGhostBurnJob: Codable, Equatable {
    let peerIdRaw: Int64
    let messageNamespace: Int32
    let messageId: Int32
    var readAtUnix: Int?
    var expectedText: String?
    var sentAtUnix: Int?

    private enum CodingKeys: String, CodingKey {
        case peerIdRaw, messageNamespace, messageId, readAtUnix, expectedText, sentAtUnix
    }
}

public enum MTMediaTokWave20Tools {
    public static let hideCallRecentsDefaultsKey = "mediatok.calls.hide_recents.v1"
    private static let configKey = "mediatok.wave20.config.v1"
    private static let mirrorPeersKey = "mediatok.wave20.mirror_peers.v1"
    private static let mirroredIdsKey = "mediatok.wave20.mirrored_msg_ids.v1"
    private static let ghostJobsKey = "mediatok.wave20.ghost_burn_jobs.v1"
    private static let verifiedCaptchaPeersKey = "mediatok.wave20.captcha_verified.v1"

    private static let stateBox = MTWave20Box<(
        cachedConfig: MTWave20Config,
        lastContext: AccountContext?,
        workerTimer: DispatchSourceTimer?,
        mirroredIds: Set<MessageId>,
        challengedPeers: [Int64: Int]
    )>((.default, nil, nil, [], [:]))

    // MARK: - Registration

    public static func register() {
        let initial = loadConfigFromDisk()
        UserDefaults.standard.set(initial.hideCallKitRecents, forKey: hideCallRecentsDefaultsKey)
        stateBox.withLock { $0.cachedConfig = initial }

        MTChatScreenHooks.willSendText.register({ request, proceed in
            return MTMediaTokWave20Tools.interceptSend(request, proceed: proceed)
        }, order: 42)

        MTChatScreenHooks.sendMenuItems.register({ sendContext in
            return MTMediaTokWave20Tools.sendMenuItems(sendContext)
        }, order: 82)

        MTChatScreenHooks.overlays.register({ screen in
            if screen.isPreview {
                return []
            }
            return [MTWave20StatusPillOverlay(screen: screen)]
        }, order: 145)

        MTChatScreenHooks.hidesMessage.register({ message, _, _ in
            let cfg = MTMediaTokWave20Tools.stateBox.withLock { $0.cachedConfig }
            guard cfg.ignoreMassMentions, message.flags.contains(.Incoming) else { return false }
            let lower = message.text.lowercased()
            if lower.contains("@all") || lower.contains("@everyone") || lower.contains("@here") || lower.contains("@admin") {
                if lower.trimmingCharacters(in: .whitespacesAndNewlines).count <= 32 {
                    return true
                }
            }
            return false
        }, order: 56)

        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTMediaTokWave20Tools.stateBox.withLock { $0.lastContext = context }
            MTMediaTokWave20Tools.armBackgroundWorkerIfNeeded(context: context)
        }, order: 43)

        MTChatScreenHooks.lifecycle.register({ event, screen in
            if event == .didAppear {
                MTMediaTokWave20Tools.stateBox.withLock { $0.lastContext = screen.context }
                MTMediaTokWave20Tools.armBackgroundWorkerIfNeeded(context: screen.context)
            }
        }, order: 43)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave20Tools.messageMenuItems(menuContext)
        }, order: 99)
    }

    // MARK: - Persistence

    private static func loadConfigFromDisk() -> MTWave20Config {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let decoded = try? JSONDecoder().decode(MTWave20Config.self, from: data) else {
            return .default
        }
        return decoded
    }

    public static func loadConfig() -> MTWave20Config {
        return stateBox.withLock { $0.cachedConfig }
    }

    public static func saveConfig(_ cfg: MTWave20Config) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        UserDefaults.standard.set(cfg.hideCallKitRecents, forKey: hideCallRecentsDefaultsKey)
        stateBox.withLock { $0.cachedConfig = cfg }
        NotificationCenter.default.post(name: Notification.Name("mediatok.wave20.config_changed"), object: nil)
        if let ctx = stateBox.withLock({ $0.lastContext }) {
            armBackgroundWorkerIfNeeded(context: ctx)
        }
    }

    private static func loadGhostJobs() -> [MTGhostBurnJob] {
        guard let data = UserDefaults.standard.data(forKey: ghostJobsKey),
              let arr = try? JSONDecoder().decode([MTGhostBurnJob].self, from: data) else {
            return []
        }
        return arr
    }

    private static func saveGhostJobs(_ jobs: [MTGhostBurnJob]) {
        if let data = try? JSONEncoder().encode(jobs) {
            UserDefaults.standard.set(data, forKey: ghostJobsKey)
        }
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

    // MARK: - Outgoing Text Interception: Slash Commands, #990 Macros, #992 Broken URL Joiner

    private static func interceptSend(_ request: MTComposedTextRequest, proceed: @escaping () -> Void) -> Bool {
        let fullText = request.state.inputText.string
        let raw = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let peerId = request.chatLocation.peerId

        if raw.hasPrefix(".") {
            if lower == ".wave20" || lower == ".callrecents" || lower == ".dcheader" || lower == ".ignoreall" || lower == ".captcha" {
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentWave20Hub(context: request.context) }
                return true
            }
            if lower == ".mirror" {
                request.replace(ChatTextInputState())
                if let pid = peerId {
                    toggleMirrorInDm(context: request.context, peerId: pid)
                }
                return true
            }
            if lower == ".macros" {
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentMacrosEditor(context: request.context) }
                return true
            }
            if lower.hasPrefix(".ghost1m ") {
                let body = String(raw.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
                request.replace(ChatTextInputState())
                if let pid = peerId, !body.isEmpty {
                    sendSilentReadBurnMessage(context: request.context, peerId: pid, text: body)
                }
                return true
            }
            if lower == ".ghost1m" {
                request.replace(ChatTextInputState())
                MTMediaTokWave5Tools.showToast(context: request.context, text: "Использование: .ghost1m <текст> (тихая отправка + снос через 1 мин после прочтения)")
                return true
            }
            if lower == ".songlink" || lower.hasPrefix(".songlink ") {
                let query = lower.hasPrefix(".songlink ") ? String(raw.dropFirst(10)).trimmingCharacters(in: .whitespacesAndNewlines) : (UIPasteboard.general.string ?? "")
                request.replace(ChatTextInputState())
                DispatchQueue.main.async {
                    resolveSonglink(context: request.context, urlOrQuery: query, peerId: peerId)
                }
                return true
            }
        }

        let cfg = loadConfig()
        var transformed = fullText
        var didTransform = false

        // #990 Quick ";abbr" text expansion
        for (abbr, expansion) in cfg.macros where !abbr.isEmpty && transformed.contains(abbr) {
            transformed = transformed.replacingOccurrences(of: abbr, with: expansion)
            didTransform = true
        }

        // #992 Auto-join multi-line broken URLs
        if cfg.autoJoinBrokenUrls && (transformed.contains("http://") || transformed.contains("https://")) && transformed.contains("\n") {
            let repaired = joinBrokenMultilineUrls(transformed)
            if repaired != transformed {
                transformed = repaired
                didTransform = true
            }
        }

        if didTransform {
            request.replace(ChatTextInputState(inputText: NSAttributedString(string: transformed)))
            proceed()
            return true
        }

        return false
    }

    public static func joinBrokenMultilineUrls(_ input: String) -> String {
        let rawLines = input.components(separatedBy: "\n")
        guard rawLines.count >= 2 else { return input }
        var out: [String] = []
        var idx = 0
        while idx < rawLines.count {
            var cur = rawLines[idx]
            let trimmed = cur.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                while idx + 1 < rawLines.count {
                    let nextTrim = rawLines[idx + 1].trimmingCharacters(in: .whitespaces)
                    if nextTrim.isEmpty || nextTrim.contains(" ") || nextTrim.hasPrefix("http://") || nextTrim.hasPrefix("https://") {
                        break
                    }
                    let looksLikeUrlTail = nextTrim.allSatisfy { ch in
                        ch.isASCII && !ch.isWhitespace
                    } && (cur.hasSuffix("/") || cur.hasSuffix("-") || cur.hasSuffix("_") || cur.hasSuffix("=") || cur.hasSuffix("&") || cur.hasSuffix("?") || nextTrim.hasPrefix("/") || nextTrim.hasPrefix("?") || nextTrim.hasPrefix("&") || cur.count >= 45)
                    if looksLikeUrlTail {
                        cur = trimmed + nextTrim
                        idx += 1
                    } else {
                        break
                    }
                }
            }
            out.append(cur)
            idx += 1
        }
        return out.joined(separator: "\n")
    }

    // MARK: - #993 Live Preview & #994 Silent+1m-Read-Burn in Send Menu

    private static func sendMenuItems(_ sendContext: MTSendMenuContext) -> [ContextMenuItem] {
        let text = sendContext.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let context = sendContext.context
        let peerId = sendContext.peerId
        let replaceInput = sendContext.replaceInput
        let dismiss = sendContext.dismiss

        var items: [ContextMenuItem] = []

        // #993 Live Bubble Preview before sending
        items.append(.action(ContextMenuActionItem(
            text: "Предпросмотр пузыря (#993)",
            icon: { theme in
                return UIImage(systemName: "eye.circle.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                DispatchQueue.main.async {
                    presentLiveMessagePreview(context: context, attributedText: sendContext.inputText, onConfirmSend: {
                        replaceInput(NSAttributedString(string: ""))
                        let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [
                            .message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                        ]).startStandalone()
                    })
                }
            }
        )))

        // #994 Send Silently + Auto-Delete for everyone 1m after recipient reads
        items.append(.action(ContextMenuActionItem(
            text: "Тихо + снос через 1 мин после чтения",
            icon: { theme in
                return UIImage(systemName: "timer")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                replaceInput(NSAttributedString(string: ""))
                sendSilentReadBurnMessage(context: context, peerId: peerId, text: text)
            }
        )))

        return items
    }

    // MARK: - #928 Songlink Context Menu Item

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let msg = menuContext.messages.first else { return [] }
        let text = msg.text
        let lower = text.lowercased()
        let isMusicLink = lower.contains("music.apple.com/") || lower.contains("open.spotify.com/") || lower.contains("music.youtube.com/") || lower.contains("soundcloud.com/") || lower.contains("deezer.com/") || lower.contains("music.yandex.")
        guard isMusicLink else { return [] }

        let context = menuContext.context
        let peerId = msg.id.peerId
        return [MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
            text: "Найти на всех площадках (Songlink)",
            icon: { theme in
                return UIImage(systemName: "music.quarternote.3")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { _, f in
                f(.default)
                MTMediaTokWave20Tools.resolveSonglink(context: context, urlOrQuery: text, peerId: peerId)
            }
        )))]
    }

    // MARK: - #994 Silent Send + 60s Post-Read Auto-Delete

    public static func sendSilentReadBurnMessage(context: AccountContext, peerId: PeerId, text: String) {
        let attrs: [MessageAttribute] = [NotificationInfoMessageAttribute(flags: .muted)]
        let _ = (enqueueMessages(account: context.account, peerId: peerId, messages: [
            .message(text: text, attributes: attrs, inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        ]) |> deliverOnMainQueue).startStandalone(next: { msgIds in
            var jobs = loadGhostJobs()
            let sentUnix = Int(Date().timeIntervalSince1970)
            for maybeId in msgIds {
                if let mid = maybeId {
                    jobs.append(MTGhostBurnJob(peerIdRaw: mid.peerId.toInt64(), messageNamespace: mid.namespace, messageId: mid.id, readAtUnix: nil, expectedText: text, sentAtUnix: sentUnix))
                }
            }
            saveGhostJobs(jobs)
            armBackgroundWorkerIfNeeded(context: context)
            MTMediaTokWave5Tools.showToast(context: context, text: "Отправлено без звука (#994): удалится у обоих через 60 сек после прочтения")
        })
    }

    // MARK: - #505 Mirror Mode in DM

    public static func toggleMirrorInDm(context: AccountContext, peerId: PeerId) {
        guard peerId.namespace == Namespaces.Peer.CloudUser, peerId != context.account.peerId else {
            MTMediaTokWave5Tools.showToast(context: context, text: ".mirror работает в личных диалогах (ЛС)")
            return
        }
        var map = (UserDefaults.standard.dictionary(forKey: mirrorPeersKey) as? [String: Int]) ?? [:]
        let k = "\(peerId.toInt64())"
        if map[k] != nil {
            map.removeValue(forKey: k)
            UserDefaults.standard.set(map, forKey: mirrorPeersKey)
            MTMediaTokWave5Tools.showToast(context: context, text: "Режим «Зеркало» (.mirror) выключен")
        } else {
            map[k] = Int(Date().timeIntervalSince1970)
            UserDefaults.standard.set(map, forKey: mirrorPeersKey)
            armBackgroundWorkerIfNeeded(context: context)
            MTMediaTokWave5Tools.showToast(context: context, text: "Режим «Зеркало» включён (#505): стикеры и реакции собеседника зеркалятся в ответ")
        }
    }

    // MARK: - Background Worker (#505 Mirror, #994 Read-Burn, #503 DM Captcha)

    private static func armBackgroundWorkerIfNeeded(context: AccountContext) {
        let mirrorMap = (UserDefaults.standard.dictionary(forKey: mirrorPeersKey) as? [String: Int]) ?? [:]
        let jobs = loadGhostJobs()
        let captchaOn = loadConfig().dmCaptchaEnabled
        guard !mirrorMap.isEmpty || !jobs.isEmpty || captchaOn else { return }

        let shouldStart = stateBox.withLock { st -> Bool in
            st.lastContext = context
            return st.workerTimer == nil
        }
        guard shouldStart else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 2.0, repeating: 2.5)
        timer.setEventHandler {
            runBackgroundTick()
        }
        stateBox.withLock { $0.workerTimer = timer }
        timer.resume()
    }

    private static func runBackgroundTick() {
        let mirrorMap = (UserDefaults.standard.dictionary(forKey: mirrorPeersKey) as? [String: Int]) ?? [:]
        let jobs = loadGhostJobs()
        let captchaOn = loadConfig().dmCaptchaEnabled

        if mirrorMap.isEmpty && jobs.isEmpty && !captchaOn {
            stateBox.withLock { st in
                st.workerTimer?.cancel()
                st.workerTimer = nil
            }
            return
        }
        guard let context = stateBox.withLock({ $0.lastContext }) else { return }
        let nowSec = Int(Date().timeIntervalSince1970)

        // 1. Check #994 Read-Burn Jobs
        if !jobs.isEmpty {
            let _ = (context.account.postbox.transaction { transaction -> ([MTGhostBurnJob], [MessageId]) in
                var updated: [MTGhostBurnJob] = []
                var toDelete: [MessageId] = []
                for var job in jobs {
                    let pid = PeerId(job.peerIdRaw)
                    let mid = MessageId(peerId: pid, namespace: job.messageNamespace, id: job.messageId)
                    guard let msg = transaction.getMessage(mid) else {
                        // Message either still pending (local namespace) or already deleted
                        if mid.namespace == Namespaces.Message.Local {
                            // Match resolved Cloud outgoing message by exact text + timestamp window
                            var cloudMatch: Message?
                            transaction.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: 8) { m in
                                if !m.flags.contains(.Incoming) {
                                    let textOk = (job.expectedText == nil || m.text == job.expectedText)
                                    let timeOk = (job.sentAtUnix == nil || abs(Int(m.timestamp) - (job.sentAtUnix ?? 0)) <= 120)
                                    if textOk && timeOk {
                                        cloudMatch = m
                                        return false
                                    }
                                }
                                return true
                            }
                            if let cm = cloudMatch {
                                job = MTGhostBurnJob(peerIdRaw: job.peerIdRaw, messageNamespace: cm.id.namespace, messageId: cm.id.id, readAtUnix: job.readAtUnix, expectedText: job.expectedText, sentAtUnix: job.sentAtUnix)
                                updated.append(job)
                            } else if let sentAt = job.sentAtUnix, nowSec - sentAt < 60 {
                                updated.append(job)
                            }
                        }
                        continue
                    }
                    if let readAt = job.readAtUnix {
                        if nowSec - readAt >= 60 {
                            toDelete.append(msg.id)
                        } else {
                            updated.append(job)
                        }
                    } else if let readState = transaction.getCombinedPeerReadState(pid), readState.isOutgoingMessageIndexRead(msg.index) {
                        job.readAtUnix = nowSec
                        updated.append(job)
                    } else {
                        updated.append(job)
                    }
                }
                return (updated, toDelete)
            } |> deliverOnMainQueue).startStandalone(next: { updated, toDelete in
                saveGhostJobs(updated)
                if !toDelete.isEmpty {
                    let _ = context.engine.messages.deleteMessagesInteractively(messageIds: toDelete, type: .forEveryone).startStandalone()
                }
            })
        }

        // 2. Check #505 Mirror Mode in DM
        if !mirrorMap.isEmpty {
            let _ = (context.account.postbox.transaction { transaction -> [(PeerId, MessageId, TelegramMediaFile?, String?)] in
                var actions: [(PeerId, MessageId, TelegramMediaFile?, String?)] = []
                for (k, sinceSec) in mirrorMap {
                    guard let raw = Int64(k) else { continue }
                    let pid = PeerId(raw)
                    transaction.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: 6) { msg in
                        if Int(msg.timestamp) < sinceSec { return false }
                        if msg.flags.contains(.Incoming) {
                            for m in msg.media {
                                if let f = m as? TelegramMediaFile, f.isSticker {
                                    actions.append((pid, msg.id, f, nil))
                                    break
                                }
                            }
                        } else {
                            // Check if peer reacted to our message
                            for attr in msg.attributes {
                                if let rAttr = attr as? ReactionsMessageAttribute {
                                    for rp in rAttr.recentPeers where rp.peerId == pid {
                                        if case let .builtin(emoji) = rp.value {
                                            actions.append((pid, msg.id, nil, emoji))
                                        }
                                    }
                                }
                            }
                        }
                        return true
                    }
                }
                return actions
            } |> deliverOnMainQueue).startStandalone(next: { candidates in
                var persistedKeys = (UserDefaults.standard.array(forKey: mirroredIdsKey) as? [String]) ?? []
                var persistedSet = Set(persistedKeys)
                var didPersistChange = false
                for (pid, mid, stickerFile, reactedEmoji) in candidates {
                    let keyStr = "\(mid.peerId.toInt64()):\(mid.id)"
                    let shouldAct = stateBox.withLock { st -> Bool in
                        if st.mirroredIds.contains(mid) || persistedSet.contains(keyStr) { return false }
                        st.mirroredIds.insert(mid)
                        return true
                    }
                    guard shouldAct else { continue }
                    persistedSet.insert(keyStr)
                    persistedKeys.append(keyStr)
                    if persistedKeys.count > 200 {
                        persistedKeys.removeFirst(persistedKeys.count - 200)
                    }
                    didPersistChange = true
                    if let sf = stickerFile {
                        let _ = enqueueMessages(account: context.account, peerId: pid, messages: [
                            .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: sf), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                        ]).startStandalone()
                    } else if let emoji = reactedEmoji {
                        let _ = (context.account.postbox.transaction { tx -> MessageId? in
                            var peerMsgId: MessageId?
                            tx.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: 5) { m in
                                if m.flags.contains(.Incoming) {
                                    peerMsgId = m.id
                                    return false
                                }
                                return true
                            }
                            return peerMsgId
                        } |> deliverOnMainQueue).startStandalone(next: { targetMsgId in
                            if let tId = targetMsgId {
                                context.engine.messages.setMessageReactions(ids: [tId], reactions: [.builtin(emoji)])
                            }
                        })
                    }
                }
                if didPersistChange {
                    UserDefaults.standard.set(persistedKeys, forKey: mirroredIdsKey)
                }
            })
        }

        // 3. Check #503 Anti-Spam DM Captcha for unknown non-contacts
        if captchaOn {
            let verifiedArr = Set((UserDefaults.standard.array(forKey: verifiedCaptchaPeersKey) as? [Int64]) ?? [])
            let challengedSnapshot = stateBox.withLock { $0.challengedPeers }
            let ownId = context.account.peerId
            let _ = (context.account.postbox.transaction { tx -> [(PeerId, String)] in
                var incomingNew: [(PeerId, String)] = []
                let top = tx.getTopChatListEntries(groupId: .root, count: 25)
                for entry in top {
                    let pid = entry.peerId
                    guard pid.namespace == Namespaces.Peer.CloudUser, pid != ownId else { continue }
                    let raw = pid.toInt64()
                    if pid.id._internalGetInt64Value() == 777000 || verifiedArr.contains(raw) { continue }
                    if let user = entry.peer as? TelegramUser {
                        if user.botInfo != nil || user.flags.contains(.isSupport) || tx.isPeerContact(peerId: pid) {
                            continue
                        }
                    }
                    let isAlreadyChallenged = (challengedSnapshot[raw] != nil)
                    var latestIn: Message?
                    var hasHumanOutgoing = false
                    tx.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: 8) { m in
                        if !m.flags.contains(.Incoming) {
                            if !m.text.hasPrefix("[MediaTok ") {
                                hasHumanOutgoing = true
                            }
                        } else if latestIn == nil && (nowSec - Int(m.timestamp)) < 300 {
                            latestIn = m
                        }
                        return true
                    }
                    if let m = latestIn, (isAlreadyChallenged || !hasHumanOutgoing) {
                        incomingNew.append((pid, m.text.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                }
                return incomingNew
            } |> deliverOnMainQueue).startStandalone(next: { list in
                for (pid, text) in list {
                    let raw = pid.toInt64()
                    let existingExpected = stateBox.withLock { $0.challengedPeers[raw] }
                    if let expected = existingExpected {
                        if Int(text) == expected {
                            var v = (UserDefaults.standard.array(forKey: verifiedCaptchaPeersKey) as? [Int64]) ?? []
                            v.append(raw)
                            UserDefaults.standard.set(v, forKey: verifiedCaptchaPeersKey)
                            stateBox.withLock { _ = $0.challengedPeers.removeValue(forKey: raw) }
                            let _ = context.engine.peers.updatePeerMuteSetting(peerId: pid, threadId: nil, muteInterval: nil).startStandalone()
                            let _ = enqueueMessages(account: context.account, peerId: pid, messages: [
                                .message(text: "[MediaTok Anti-Spam] Проверка пройдена, уведомления включены.", attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                            ]).startStandalone()
                        }
                    } else {
                        let a = Int.random(in: 11 ... 49)
                        let b = Int.random(in: 2 ... 9)
                        let sum = a + b
                        stateBox.withLock { $0.challengedPeers[raw] = sum }
                        let _ = context.engine.peers.updatePeerMuteSetting(peerId: pid, threadId: nil, muteInterval: Int32.max).startStandalone()
                        let challenge = "[MediaTok Защита ЛС #503] Вы пишете впервые. Ответьте числом \(a) + \(b), чтобы разблокировать уведомления."
                        let _ = enqueueMessages(account: context.account, peerId: pid, messages: [
                            .message(text: challenge, attributes: [NotificationInfoMessageAttribute(flags: .muted)], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                        ]).startStandalone()
                    }
                }
            })
        }
    }

    // MARK: - #928 Songlink / Odesli Universal Music Resolver

    public static func resolveSonglink(context: AccountContext, urlOrQuery: String, peerId: PeerId?) {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let nsRange = NSRange(urlOrQuery.startIndex..<urlOrQuery.endIndex, in: urlOrQuery)
        let extractedUrl = detector?.matches(in: urlOrQuery, options: [], range: nsRange).compactMap { $0.url?.absoluteString }.first ?? urlOrQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard extractedUrl.lowercased().hasPrefix("http"),
              let encoded = extractedUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let apiUrl = URL(string: "https://api.song.link/v1-alpha.1/links?url=\(encoded)&userCountry=US") else {
            MTMediaTokWave5Tools.showToast(context: context, text: "Скопируйте или передайте ссылку Apple Music / Spotify / YouTube Music (.songlink <URL>)")
            return
        }

        MTMediaTokWave5Tools.showToast(context: context, text: "Ищу трек на всех площадках (Songlink #928)...")
        URLSession.shared.dataTask(with: apiUrl) { data, _, _ in
            guard let data = data,
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let linksByPlatform = root["linksByPlatform"] as? [String: Any] else {
                DispatchQueue.main.async {
                    MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось найти совпадения через Songlink API")
                }
                return
            }

            let pageUrl = (root["pageUrl"] as? String) ?? extractedUrl
            var titleLine = "Музыкальный релиз"
            if let entities = root["entitiesByUniqueId"] as? [String: Any],
               let firstEntity = entities.values.first as? [String: Any] {
                let t = (firstEntity["title"] as? String) ?? ""
                let a = (firstEntity["artistName"] as? String) ?? ""
                if !t.isEmpty {
                    titleLine = a.isEmpty ? t : "\(a) — \(t)"
                }
            }

            let wanted: [(String, String)] = [
                ("appleMusic", "Apple Music"),
                ("spotify", "Spotify"),
                ("youtubeMusic", "YouTube Music"),
                ("yandex", "Яндекс Музыка"),
                ("soundcloud", "SoundCloud"),
                ("deezer", "Deezer")
            ]

            var foundLinks: [(String, String)] = []
            for (key, label) in wanted {
                if let info = linksByPlatform[key] as? [String: Any], let u = info["url"] as? String {
                    foundLinks.append((label, u))
                }
            }

            DispatchQueue.main.async {
                guard let top = topViewController() else { return }
                let sheet = UIAlertController(title: titleLine, message: "Выберите площадку или отправьте сводку ссылок в чат:", preferredStyle: .actionSheet)
                for (label, link) in foundLinks {
                    sheet.addAction(UIAlertAction(title: "Открыть в \(label)", style: .default) { _ in
                        if let u = URL(string: link) {
                            UIApplication.shared.open(u)
                        }
                    })
                }
                if let pid = peerId {
                    sheet.addAction(UIAlertAction(title: "Отправить все ссылки в чат", style: .default) { _ in
                        var lines = ["\(titleLine)"]
                        for (label, link) in foundLinks {
                            lines.append("• \(label): \(link)")
                        }
                        lines.append("Все площадки: \(pageUrl)")
                        let _ = enqueueMessages(account: context.account, peerId: pid, messages: [
                            .message(text: lines.joined(separator: "\n"), attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                        ]).startStandalone()
                    })
                }
                sheet.addAction(UIAlertAction(title: "Скопировать универсальную ссылку", style: .default) { _ in
                    UIPasteboard.general.string = pageUrl
                    MTMediaTokWave5Tools.showToast(context: context, text: "Ссылка song.link скопирована")
                })
                sheet.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
                if let pop = sheet.popoverPresentationController {
                    pop.sourceView = top.view
                    pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                }
                top.present(sheet, animated: true)
            }
        }.resume()
    }

    // MARK: - Screens: Wave 20 Hub, #993 Live Preview, #990 Macros Editor

    public static func presentWave20Hub(context: AccountContext) {
        guard let top = topViewController() else { return }
        let vc = MTWave20SettingsController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    public static func presentMacrosEditor(context: AccountContext) {
        guard let top = topViewController() else { return }
        let vc = MTWave20MacrosController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    public static func presentLiveMessagePreview(context: AccountContext, attributedText: NSAttributedString, onConfirmSend: @escaping () -> Void) {
        guard let top = topViewController() else { return }
        let vc = MTLiveBubblePreviewController(attributedText: attributedText, onConfirmSend: onConfirmSend)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }
}

// MARK: - #537 Live Typing Stopwatch + #995 Compact DC Header Pill Overlay

private final class MTWave20StatusPillOverlay: MTChatOverlay {
    let node = ASDisplayNode()
    let placement: MTChatOverlayPlacement = .aboveHistory

    private let pillView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let dotView = UIView()
    private let label = UILabel()

    private let context: AccountContext
    private let peerId: PeerId?
    private var activitiesDisposable: Disposable?
    private var networkDisposable: Disposable?
    private var tickTimer: Foundation.Timer?
    private var configObserver: NSObjectProtocol?

    private var typingStartDate: Date?
    private var activeTypingVerb: String = ""
    private var isNetworkOnline: Bool = true
    private var lastBounds: CGRect = .zero
    private var lastInsets: UIEdgeInsets = .zero

    init(screen: MTChatScreen) {
        self.context = screen.context
        self.peerId = screen.chatLocation.peerId
        self.node.isUserInteractionEnabled = false

        DispatchQueue.main.async { [weak self] in
            self?.setupViews()
        }
    }

    deinit {
        self.activitiesDisposable?.dispose()
        self.networkDisposable?.dispose()
        self.tickTimer?.invalidate()
        if let obs = self.configObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func setupViews() {
        self.pillView.layer.cornerRadius = 11
        self.pillView.clipsToBounds = true
        self.pillView.isUserInteractionEnabled = false
        self.pillView.isHidden = true

        self.dotView.layer.cornerRadius = 3.5
        self.dotView.backgroundColor = .systemGreen

        self.label.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        self.label.textColor = .white

        self.pillView.contentView.addSubview(self.dotView)
        self.pillView.contentView.addSubview(self.label)
        self.node.view.addSubview(self.pillView)

        if let pid = self.peerId {
            let space = PeerActivitySpace(peerId: pid, category: .global)
            self.activitiesDisposable = (self.context.account.peerInputActivities(peerId: space)
            |> deliverOnMainQueue).startStrict(next: { [weak self] items in
                guard let self else { return }
                let others = items.filter { $0.0 != self.context.account.peerId }
                if let first = others.first {
                    if self.typingStartDate == nil {
                        self.typingStartDate = Date()
                    }
                    switch first.1 {
                    case .recordingVoice:
                        self.activeTypingVerb = "записывает ГС"
                    case .recordingInstantVideo:
                        self.activeTypingVerb = "записывает кружок"
                    case .choosingSticker:
                        self.activeTypingVerb = "выбирает стикер"
                    case .uploadingFile, .uploadingPhoto, .uploadingVideo, .uploadingInstantVideo:
                        self.activeTypingVerb = "отправляет медиа"
                    default:
                        self.activeTypingVerb = "печатает"
                    }
                    self.ensureTickTimerRunning()
                } else {
                    self.typingStartDate = nil
                    self.activeTypingVerb = ""
                }
                self.refreshPillContent()
            })
        }

        self.networkDisposable = (self.context.account.networkState
        |> deliverOnMainQueue).startStrict(next: { [weak self] netState in
            guard let self else { return }
            if case .online = netState {
                self.isNetworkOnline = true
            } else {
                self.isNetworkOnline = false
            }
            self.refreshPillContent()
        })

        self.configObserver = NotificationCenter.default.addObserver(forName: Notification.Name("mediatok.wave20.config_changed"), object: nil, queue: .main) { [weak self] _ in
            self?.refreshPillContent()
        }
        self.refreshPillContent()
    }

    private func ensureTickTimerRunning() {
        guard self.tickTimer == nil else { return }
        self.tickTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            if self.typingStartDate == nil {
                t.invalidate()
                self.tickTimer = nil
            }
            self.refreshPillContent()
        }
    }

    private func refreshPillContent() {
        let cfg = MTMediaTokWave20Tools.loadConfig()
        var parts: [String] = []

        if cfg.dcHeaderDotEnabled {
            let dc = self.context.account.network.datacenterId
            parts.append("DC\(dc)")
        }

        if cfg.typingStopwatchEnabled, let start = self.typingStartDate, !self.activeTypingVerb.isEmpty {
            let secs = max(1, Int(Date().timeIntervalSince(start)))
            parts.append("\(self.activeTypingVerb)... (\(secs)с)")
        }

        guard !parts.isEmpty else {
            self.pillView.isHidden = true
            return
        }

        self.dotView.backgroundColor = self.isNetworkOnline ? .systemGreen : .systemOrange
        self.label.text = parts.joined(separator: " · ")
        self.pillView.isHidden = false
        self.layoutPill()
    }

    private func layoutPill() {
        guard !self.pillView.isHidden, self.lastBounds.width > 40 else { return }
        self.label.sizeToFit()
        let padH: CGFloat = 10
        let dotSize: CGFloat = 7
        let spacing: CGFloat = 6
        let totalW = min(self.lastBounds.width - 32, padH * 2 + dotSize + spacing + self.label.bounds.width)
        let totalH: CGFloat = 22
        let topY = max(44, self.lastInsets.top + 6)
        self.pillView.frame = CGRect(x: (self.lastBounds.width - totalW) * 0.5, y: topY, width: totalW, height: totalH)
        self.dotView.frame = CGRect(x: padH, y: (totalH - dotSize) * 0.5, width: dotSize, height: dotSize)
        self.label.frame = CGRect(x: padH + dotSize + spacing, y: (totalH - self.label.bounds.height) * 0.5, width: totalW - (padH * 2 + dotSize + spacing), height: self.label.bounds.height)
    }

    func updateLayout(bounds: CGRect, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        self.lastBounds = bounds
        self.lastInsets = insets
        self.layoutPill()
    }
}

// MARK: - Wave 20 Settings Controller

private final class MTWave20SettingsController: UIViewController {
    private let context: AccountContext
    private var config = MTMediaTokWave20Tools.loadConfig()

    private let recentsSwitch = UISwitch()
    private let typingSwitch = UISwitch()
    private let dcSwitch = UISwitch()
    private let urlJoinSwitch = UISwitch()
    private let ignoreAllSwitch = UISwitch()
    private let captchaSwitch = UISwitch()

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Звонки, Чат и Сеть (Wave 20)"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(saveTapped))

        self.recentsSwitch.isOn = self.config.hideCallKitRecents
        self.typingSwitch.isOn = self.config.typingStopwatchEnabled
        self.dcSwitch.isOn = self.config.dcHeaderDotEnabled
        self.urlJoinSwitch.isOn = self.config.autoJoinBrokenUrls
        self.ignoreAllSwitch.isOn = self.config.ignoreMassMentions
        self.captchaSwitch.isOn = self.config.dmCaptchaEnabled

        var macroCfg = UIButton.Configuration.tinted()
        macroCfg.title = "Настроить быстрые сокращения (;аббр #990)"
        macroCfg.image = UIImage(systemName: "text.badge.plus")
        macroCfg.imagePadding = 8
        macroCfg.cornerStyle = .large
        let macroBtn = UIButton(configuration: macroCfg, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let vc = MTWave20MacrosController(context: self.context)
            self.navigationController?.pushViewController(vc, animated: true)
        })

        let stack = UIStackView(arrangedSubviews: [
            makeRow("Скрыть звонки TG из журнала iPhone (#776 CallKit)", self.recentsSwitch),
            makeRow("Секундомер набора «печатает... (42с)» (#537)", self.typingSwitch),
            makeRow("Индикатор DC и статуса сети в шапке чата (#995)", self.dcSwitch),
            makeRow("Авто-склейка разорванных ссылок при отправке (#992)", self.urlJoinSwitch),
            makeRow("Игнор массовых тегов @all / @everyone / @admin (#532)", self.ignoreAllSwitch),
            makeRow("Анти-спам капча для новых незнакомцев в ЛС (#503)", self.captchaSwitch),
            macroBtn
        ])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            macroBtn.heightAnchor.constraint(equalToConstant: 46),
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16)
        ])
    }

    private func makeRow(_ text: String, _ sw: UISwitch) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        let lbl = UILabel()
        lbl.text = text
        lbl.font = .systemFont(ofSize: 14)
        lbl.numberOfLines = 0
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(sw)
        return row
    }

    @objc private func saveTapped() {
        var latest = MTMediaTokWave20Tools.loadConfig()
        latest.hideCallKitRecents = self.recentsSwitch.isOn
        latest.typingStopwatchEnabled = self.typingSwitch.isOn
        latest.dcHeaderDotEnabled = self.dcSwitch.isOn
        latest.autoJoinBrokenUrls = self.urlJoinSwitch.isOn
        latest.ignoreMassMentions = self.ignoreAllSwitch.isOn
        latest.dmCaptchaEnabled = self.captchaSwitch.isOn
        MTMediaTokWave20Tools.saveConfig(latest)
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Настройки сохранены (для CallKit перезапустите звонок)")
        self.dismiss(animated: true)
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #990 Quick Text Expansion Macros Controller

private final class MTWave20MacrosController: UITableViewController {
    private let context: AccountContext
    private var pairs: [(String, String)] = []

    init(context: AccountContext) {
        self.context = context
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Быстрые фразы (;аббр)"
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        if self.navigationController?.viewControllers.first === self {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        }
        self.reloadPairs()
    }

    private func reloadPairs() {
        self.pairs = MTMediaTokWave20Tools.loadConfig().macros.sorted { $0.key < $1.key }
        self.tableView.reloadData()
    }

    @objc private func addTapped() {
        let alert = UIAlertController(title: "Новое сокращение (#990)", message: "Введите триггер (например ;адрес) и полный текст замены:", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = ";триггер" }
        alert.addTextField { $0.placeholder = "Полный текст фразы" }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            var trig = (alert?.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let body = (alert?.textFields?[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trig.isEmpty, !body.isEmpty else { return }
            if !trig.hasPrefix(";") { trig = ";" + trig }
            var cfg = MTMediaTokWave20Tools.loadConfig()
            cfg.macros[trig] = body
            MTMediaTokWave20Tools.saveConfig(cfg)
            self.reloadPairs()
        })
        self.present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.pairs.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "macroCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "macroCell")
        let item = self.pairs[indexPath.row]
        cell.textLabel?.text = item.0
        cell.detailTextLabel?.text = item.1
        return cell
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let key = self.pairs[indexPath.row].0
            var cfg = MTMediaTokWave20Tools.loadConfig()
            cfg.macros.removeValue(forKey: key)
            MTMediaTokWave20Tools.saveConfig(cfg)
            self.reloadPairs()
        }
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #993 Live Bubble Preview Controller

private final class MTLiveBubblePreviewController: UIViewController {
    private let attributedText: NSAttributedString
    private let onConfirmSend: () -> Void

    init(attributedText: NSAttributedString, onConfirmSend: @escaping () -> Void) {
        self.attributedText = attributedText
        self.onConfirmSend = onConfirmSend
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Предпросмотр сообщения (#993)"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Назад", style: .plain, target: self, action: #selector(closeTapped))

        let plain = self.attributedText.string
        let repaired = MTMediaTokWave20Tools.loadConfig().autoJoinBrokenUrls ? MTMediaTokWave20Tools.joinBrokenMultilineUrls(plain) : plain

        let bubble = UIView()
        bubble.backgroundColor = UIColor(red: 0.18, green: 0.48, blue: 0.96, alpha: 1.0)
        bubble.layer.cornerRadius = CGFloat(MTMediaTokWave17Tools.loadConfig().bubbleRadiusPt)
        bubble.translatesAutoresizingMaskIntoConstraints = false

        let textLbl = UILabel()
        textLbl.text = repaired
        textLbl.font = .systemFont(ofSize: 16)
        textLbl.textColor = .white
        textLbl.numberOfLines = 0
        textLbl.translatesAutoresizingMaskIntoConstraints = false

        let metaLbl = UILabel()
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        metaLbl.text = "\(repaired.count) симв. · \(df.string(from: Date())) ✓✓"
        metaLbl.font = .systemFont(ofSize: 11, weight: .medium)
        metaLbl.textColor = UIColor(white: 1.0, alpha: 0.78)
        metaLbl.textAlignment = .right
        metaLbl.translatesAutoresizingMaskIntoConstraints = false

        bubble.addSubview(textLbl)
        bubble.addSubview(metaLbl)

        var sendCfg = UIButton.Configuration.filled()
        sendCfg.title = "Отправить сейчас"
        sendCfg.image = UIImage(systemName: "paperplane.fill")
        sendCfg.imagePadding = 8
        sendCfg.cornerStyle = .large
        let sendBtn = UIButton(configuration: sendCfg, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let action = self.onConfirmSend
            self.dismiss(animated: true) {
                action()
            }
        })
        sendBtn.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(bubble)
        self.view.addSubview(sendBtn)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 28),
            bubble.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.leadingAnchor, constant: 56),
            textLbl.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            textLbl.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            textLbl.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
            metaLbl.topAnchor.constraint(equalTo: textLbl.bottomAnchor, constant: 6),
            metaLbl.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            metaLbl.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            metaLbl.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            sendBtn.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 28),
            sendBtn.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
            sendBtn.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24),
            sendBtn.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}
