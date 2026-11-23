import Foundation
import UIKit
import LocalAuthentication
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import Display
import ItemListUI
import PresentationDataUtils
import ContextUI
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

// ============================================================================
// MediaTok Wave 13 — Battle-Tested Privacy, Control & Power Utilities:
//   #207 / .mute      — Live DM Auto-Delete of incoming opponent messages (for everyone / local)
//   #208 / .delme     — FaceID + Confirm protected selective wipe of own messages (DM / Groups / All)
//   #249 / .typing    — Real MTProto Fake Activity (typing / recording video / voice / sticker) visible in stock Telegram
//   #263 / .heavy     — Upgraded Heavy Media Size Filter (>10 / >50 / >100 MB, sorted heaviest-first)
//   #242 / .readonly  — Read-Only Lock (blocks sending messages, FaceID required to unlock)
// ============================================================================

private final class MTWave13Lock<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body(&self.value)
    }
}

public struct MTDmMuteRule: Codable, Equatable {
    public let peerId: Int64
    public let sinceTimestamp: Int32
    public let forEveryone: Bool

    private enum CodingKeys: String, CodingKey {
        case peerId
        case sinceTimestamp
        case forEveryone
    }

    public init(peerId: Int64, sinceTimestamp: Int32, forEveryone: Bool) {
        self.peerId = peerId
        self.sinceTimestamp = sinceTimestamp
        self.forEveryone = forEveryone
    }
}

private final class MTWeakAccountContextBox {
    weak var context: AccountContext?
}

public enum MTMediaTokWave13Tools {
    private static let muteStoreKey = "mediatok.wave13.dm_mute_rules.v1"
    private static let readOnlyKey = "mediatok.wave13.readonly_lock.v1"

    private static let muteTimerBox = MTWave13Lock<DispatchSourceTimer?>(nil)
    private static let muteContextBox = MTWave13Lock<AccountContext?>(nil)
    private static let activeContextBox = MTWave13Lock<MTWeakAccountContextBox>(MTWeakAccountContextBox())
    private static let lastReadOnlyNotifyBox = MTWave13Lock<TimeInterval>(0)
    private static let deletedCacheBox = MTWave13Lock<Set<MessageId>>([])

    private struct FakeTypingJob {
        let peerId: PeerId
        let activity: PeerInputActivity
        let expiresAt: Date
        let timer: DispatchSourceTimer
    }
    private static let typingJobsBox = MTWave13Lock<[Int64: FakeTypingJob]>([:])

    public static var isReadOnlyLocked: Bool {
        get { UserDefaults.standard.bool(forKey: readOnlyKey) }
        set { UserDefaults.standard.set(newValue, forKey: readOnlyKey) }
    }

    // MARK: - Registration

    public static func register() {
        // Order 1 so Read-Only Lock & Wave 13 commands intercept before regular sending
        MTChatScreenHooks.willSendText.register({ request, _ in
            MTMediaTokWave13Tools.activeContextBox.withLock { $0.context = request.context }
            return MTMediaTokWave13Tools.interceptSend(request)
        }, order: 1)

        // #242 Read-Only Lock blocks ALL outgoing media, stickers, GIFs, voice/video notes, forwards
        MTOutgoingHooks.messages.register({ messages, _ in
            if MTMediaTokWave13Tools.isReadOnlyLocked, !messages.isEmpty {
                messages.removeAll()
                MTMediaTokWave13Tools.notifyReadOnlyBlocked()
            }
        }, order: 1)

        // #242 Read-Only Lock blocks outgoing calls
        MTCallHooks.outgoingCall.register({ request, _ in
            MTMediaTokWave13Tools.activeContextBox.withLock { $0.context = request.context }
            if MTMediaTokWave13Tools.isReadOnlyLocked {
                MTMediaTokWave5Tools.showToast(context: request.context, text: "Режим «Только чтение» активен. Введите .unlock для снятия.")
                return true
            }
            return false
        }, order: 1)

        // Arm .mute watcher on cold start as soon as root controllers load
        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTMediaTokWave13Tools.activeContextBox.withLock { $0.context = context }
            MTMediaTokWave13Tools.armMuteWatcherIfNeeded(context: context)
        }, order: 40)

        MTChatScreenHooks.lifecycle.register({ event, screen in
            if event == .didAppear {
                MTMediaTokWave13Tools.activeContextBox.withLock { $0.context = screen.context }
                MTMediaTokWave13Tools.armMuteWatcherIfNeeded(context: screen.context)
            }
        }, order: 40)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave13Tools.messageMenuItems(menuContext)
        }, order: 95)
    }

    private static func notifyReadOnlyBlocked() {
        let now = Date().timeIntervalSince1970
        let shouldNotify = lastReadOnlyNotifyBox.withLock { last -> Bool in
            if now - last >= 1.5 {
                last = now
                return true
            }
            return false
        }
        guard shouldNotify else { return }
        DispatchQueue.main.async {
            if let ctx = activeContextBox.withLock({ $0.context }) {
                mtPresentNativeToast(context: ctx, text: "Режим «Только чтение» активен. Введите .unlock для снятия.")
            }
        }
    }

    // MARK: - Helpers

    private static func authenticateBiometricsOrPasscode(reason: String, completion: @escaping (Bool) -> Void) {
        let laContext = LAContext()
        var error: NSError?
        let policy: LAPolicy = laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics
        if laContext.canEvaluatePolicy(policy, error: &error) {
            laContext.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        } else {
            // Device has no passcode/FaceID configured -> require explicit native confirmation alert (fail-closed if no context/UI)
            DispatchQueue.main.async {
                guard let ctx = activeContextBox.withLock({ $0.context }),
                      MTModalPresenter.activeRootViewController() != nil else {
                    completion(false)
                    return
                }
                let presentationData = ctx.sharedContext.currentPresentationData.with { $0 }
                let alert = textAlertController(
                    context: ctx,
                    title: "Подтверждение безопасности",
                    text: "\(reason)\n\nНа устройстве не настроен FaceID или код-пароль. Подтвердить действие вручную?",
                    actions: [
                        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
                            completion(false)
                        }),
                        TextAlertAction(type: .destructiveAction, title: "Подтвердить", action: {
                            completion(true)
                        })
                    ],
                    dismissOnOutsideTap: false
                )
                mtPresentContainableOverlay(alert, context: ctx)
            }
        }
    }

    // MARK: - Command & Read-Only Interception

    private static func interceptSend(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let peerId = request.chatLocation.peerId

        // Allow unlocking Read-Only Mode via .unlock / .readonly
        if lower == ".readonly" || lower == ".unlock" || lower == ".lock" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                toggleReadOnlyLock(context: request.context)
            }
            return true
        }

        // #242 Read-Only Lock blocks all outgoing messages
        if isReadOnlyLocked {
            MTMediaTokWave5Tools.showToast(context: request.context, text: "Режим «Только чтение» активен. Введите .unlock для снятия по FaceID.")
            return true
        }

        guard raw.hasPrefix(".") else { return false }

        // #207 / .mute in DM
        if lower == ".mute" || lower == ".mute local" || lower == ".mute all" {
            request.replace(ChatTextInputState())
            guard let peerId = peerId else { return true }
            let forEveryone = (lower != ".mute local")
            enableMute(context: request.context, peerId: peerId, forEveryone: forEveryone)
            return true
        }
        if lower == ".unmute" {
            request.replace(ChatTextInputState())
            guard let peerId = peerId else { return true }
            disableMute(context: request.context, peerId: peerId)
            return true
        }

        // #208 / .delme
        if lower == ".delme" || lower == ".wipe" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                presentDelMeGate(context: request.context, currentPeerId: peerId)
            }
            return true
        }

        // #249 / Fake Typing / Recording Activity visible in stock Telegram
        if lower == ".stoptyping" || lower == ".stopfake" {
            request.replace(ChatTextInputState())
            if let peerId = peerId {
                stopFakeActivity(context: request.context, peerId: peerId)
            }
            return true
        }
        if lower == ".typing" || lower.hasPrefix(".typing ") {
            request.replace(ChatTextInputState())
            if let peerId = peerId {
                let mins = parseMinutes(from: lower, defaultMinutes: 5)
                startFakeActivity(context: request.context, peerId: peerId, activity: .typingText, label: "печатает...", minutes: mins)
            }
            return true
        }
        if lower == ".recvideo" || lower.hasPrefix(".recvideo ") {
            request.replace(ChatTextInputState())
            if let peerId = peerId {
                let mins = parseMinutes(from: lower, defaultMinutes: 5)
                startFakeActivity(context: request.context, peerId: peerId, activity: .recordingInstantVideo, label: "записывает видео...", minutes: mins)
            }
            return true
        }
        if lower == ".recvoice" || lower.hasPrefix(".recvoice ") {
            request.replace(ChatTextInputState())
            if let peerId = peerId {
                let mins = parseMinutes(from: lower, defaultMinutes: 5)
                startFakeActivity(context: request.context, peerId: peerId, activity: .recordingVoice, label: "записывает ГС...", minutes: mins)
            }
            return true
        }
        if lower == ".sticker" || lower.hasPrefix(".sticker ") {
            request.replace(ChatTextInputState())
            if let peerId = peerId {
                let mins = parseMinutes(from: lower, defaultMinutes: 5)
                startFakeActivity(context: request.context, peerId: peerId, activity: .choosingSticker, label: "выбирает стикер...", minutes: mins)
            }
            return true
        }

        // #263 / Heavy Media Size Filter
        if lower == ".heavy" || lower == ".media" || lower == ".bigfiles" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                presentHeavyMediaScreen(context: request.context, initialPeerId: peerId)
            }
            return true
        }

        return false
    }

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        let peerId = message.id.peerId
        var entries: [MTMessageMenuEntry] = []

        // Quick toggle for .mute in private chats (DMs)
        if peerId.namespace == Namespaces.Peer.CloudUser && peerId != context.account.peerId {
            let muted = isMuted(peerId: peerId)
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: muted ? "Снять .mute (авто-снос)" : "Авто-снос входящих (.mute)",
                icon: { theme in
                    let name = muted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    return UIImage(systemName: name)?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    if muted {
                        disableMute(context: context, peerId: peerId)
                    } else {
                        enableMute(context: context, peerId: peerId, forEveryone: true)
                    }
                }
            ))))
        }

        return entries
    }

    // MARK: - #242 Read-Only Lock

    public static func toggleReadOnlyLock(context: AccountContext) {
        if isReadOnlyLocked {
            authenticateBiometricsOrPasscode(reason: "Отключить режим «Только чтение» в MediaTok") { ok in
                if ok {
                    isReadOnlyLocked = false
                    MTMediaTokWave5Tools.showToast(context: context, text: "Режим «Только чтение» выключен")
                } else {
                    MTMediaTokWave5Tools.showToast(context: context, text: "Отмена: режим «Только чтение» остался активен")
                }
            }
        } else {
            isReadOnlyLocked = true
            MTMediaTokWave5Tools.showToast(context: context, text: "Режим «Только чтение» включён (отправка заблокирована)")
        }
    }

    // MARK: - #207 / .mute Live Incoming Auto-Delete

    public static func loadMuteRules() -> [Int64: MTDmMuteRule] {
        guard let data = UserDefaults.standard.data(forKey: muteStoreKey),
              let arr = try? JSONDecoder().decode([MTDmMuteRule].self, from: data) else {
            return [:]
        }
        var dict: [Int64: MTDmMuteRule] = [:]
        for item in arr {
            dict[item.peerId] = item
        }
        return dict
    }

    private static func saveMuteRules(_ dict: [Int64: MTDmMuteRule]) {
        let arr = Array(dict.values)
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: muteStoreKey)
        }
    }

    public static func isMuted(peerId: PeerId) -> Bool {
        return loadMuteRules()[peerId.toInt64()] != nil
    }

    public static func enableMute(context: AccountContext, peerId: PeerId, forEveryone: Bool) {
        guard peerId.namespace == Namespaces.Peer.CloudUser, peerId != context.account.peerId else {
            MTMediaTokWave5Tools.showToast(context: context, text: ".mute работает только в личных чатах (ЛС)")
            return
        }
        var rules = loadMuteRules()
        let serverNow = Int32(context.account.network.globalTime)
        let now = serverNow > 0 ? serverNow : Int32(Date().timeIntervalSince1970)
        rules[peerId.toInt64()] = MTDmMuteRule(peerId: peerId.toInt64(), sinceTimestamp: now, forEveryone: forEveryone)
        saveMuteRules(rules)
        armMuteWatcherIfNeeded(context: context)
        let modeText = forEveryone ? "у обоих" : "только у себя"
        MTMediaTokWave5Tools.showToast(context: context, text: ".mute включён: новые сообщения собеседника будут удаляться \(modeText)")
    }

    public static func disableMute(context: AccountContext, peerId: PeerId) {
        var rules = loadMuteRules()
        rules.removeValue(forKey: peerId.toInt64())
        saveMuteRules(rules)
        if rules.isEmpty {
            muteTimerBox.withLock { timer in
                timer?.cancel()
                timer = nil
            }
            muteContextBox.withLock { $0 = nil }
        }
        MTMediaTokWave5Tools.showToast(context: context, text: ".mute выключен для этого чата")
    }

    public static func armMuteWatcherIfNeeded(context: AccountContext) {
        let rules = loadMuteRules()
        guard !rules.isEmpty else {
            muteContextBox.withLock { $0 = nil }
            return
        }
        muteContextBox.withLock { $0 = context }

        let alreadyRunning = muteTimerBox.withLock { $0 != nil }
        if alreadyRunning { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1.0, repeating: 1.2)
        timer.setEventHandler {
            MTMediaTokWave13Tools.pollMutedPeers()
        }
        muteTimerBox.withLock { existing in
            existing?.cancel()
            existing = timer
        }
        timer.resume()
    }

    private static func pollMutedPeers() {
        let rules = loadMuteRules()
        if rules.isEmpty {
            muteTimerBox.withLock { timer in
                timer?.cancel()
                timer = nil
            }
            muteContextBox.withLock { $0 = nil }
            return
        }
        guard let context = muteContextBox.withLock({ $0 }) else { return }

        let _ = (context.account.postbox.transaction { transaction -> [(MessageId, Bool)] in
            var toDelete: [(MessageId, Bool)] = []
            for rule in rules.values {
                let peerId = PeerId(rule.peerId)
                transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 15) { msg in
                    if msg.timestamp < rule.sinceTimestamp {
                        return false
                    }
                    if msg.flags.contains(.Incoming) {
                        toDelete.append((msg.id, rule.forEveryone))
                    }
                    return true
                }
            }
            return toDelete
        } |> deliverOnMainQueue).startStandalone(next: { targets in
            guard !targets.isEmpty else { return }
            var everyoneIds: [MessageId] = []
            var localIds: [MessageId] = []
            deletedCacheBox.withLock { seen in
                for (id, forEveryone) in targets {
                    if seen.contains(id) { continue }
                    seen.insert(id)
                    if forEveryone {
                        everyoneIds.append(id)
                    } else {
                        localIds.append(id)
                    }
                }
                if seen.count > 2000 {
                    seen.removeAll(keepingCapacity: true)
                }
            }
            if !everyoneIds.isEmpty {
                let _ = context.engine.messages.deleteMessagesInteractively(messageIds: everyoneIds, type: .forEveryone).startStandalone()
            }
            if !localIds.isEmpty {
                let _ = context.engine.messages.deleteMessagesInteractively(messageIds: localIds, type: .forLocalPeer).startStandalone()
            }
        })
    }

    // MARK: - #249 Fake Input Activity (Visible in Stock Telegram)

    private static func parseMinutes(from lower: String, defaultMinutes: Int) -> Int {
        let parts = lower.split(separator: " ")
        guard parts.count >= 2 else { return defaultMinutes }
        let token = String(parts[1]).replacingOccurrences(of: "m", with: "").replacingOccurrences(of: "м", with: "")
        if let n = Int(token), n > 0 {
            return min(180, n)
        }
        return defaultMinutes
    }

    public static func startFakeActivity(context: AccountContext, peerId: PeerId, activity: PeerInputActivity, label: String, minutes: Int) {
        let key = peerId.toInt64()
        let expiresAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let space = PeerActivitySpace(peerId: peerId, category: .global)

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: 4.5)
        timer.setEventHandler {
            if Date() >= expiresAt {
                stopFakeActivity(context: context, peerId: peerId, silent: true)
                return
            }
            context.account.updateLocalInputActivity(peerId: space, activity: activity, isPresent: true)
        }

        typingJobsBox.withLock { map in
            if let old = map[key] {
                old.timer.cancel()
            }
            map[key] = FakeTypingJob(peerId: peerId, activity: activity, expiresAt: expiresAt, timer: timer)
        }
        timer.resume()
        MTMediaTokWave5Tools.showToast(context: context, text: "Статус «\(label)» запущен на \(minutes) мин (видно всем). Стоп: .stoptyping")
    }

    public static func stopFakeActivity(context: AccountContext, peerId: PeerId, silent: Bool = false) {
        let key = peerId.toInt64()
        let removed = typingJobsBox.withLock { map -> FakeTypingJob? in
            let job = map.removeValue(forKey: key)
            job?.timer.cancel()
            return job
        }
        if let job = removed {
            let space = PeerActivitySpace(peerId: job.peerId, category: .global)
            context.account.updateLocalInputActivity(peerId: space, activity: job.activity, isPresent: false)
        }
        if !silent {
            MTMediaTokWave5Tools.showToast(context: context, text: "Фейк-статус остановлен")
        }
    }

    // MARK: - #208 Protected .delme (FaceID + Selective DM / Groups / All)

    public static func presentDelMeGate(context: AccountContext, currentPeerId: PeerId?) {
        authenticateBiometricsOrPasscode(reason: "Подтвердите личность для открытия .delme (удаление сообщений)") { ok in
            guard ok else {
                mtPresentNativeToast(context: context, text: "Доступ к .delme отменён")
                return
            }
            let vc = mtMakeNativeDelMeController(context: context, currentPeerId: currentPeerId)
            mtPushNativeController(vc, context: context)
        }
    }

    // MARK: - #263 Heavy Media Size Filter Screen

    public static func presentHeavyMediaScreen(context: AccountContext, initialPeerId: PeerId?) {
        let vc = mtMakeNativeHeavyMediaController(context: context, initialPeerId: initialPeerId)
        mtPushNativeController(vc, context: context)
    }

    // MARK: - #207 Active .mute Rules Manager UI

    public static func presentMuteManager(context: AccountContext) {
        let rules = loadMuteRules()
        if rules.isEmpty {
            mtPresentNativeAlert(
                context: context,
                title: "Авто-снос входящих (.mute)",
                text: "Активных правил .mute нет.\n\nЧтобы включить авто-снос входящих в личном чате, введите .mute или используйте долгое нажатие на сообщение."
            )
            return
        }

        let _ = (context.account.postbox.transaction { transaction -> [(PeerId, String, Bool)] in
            return rules.values.map { rule in
                let pid = PeerId(rule.peerId)
                let title = transaction.getPeer(pid)?.debugDisplayTitle ?? "ID \(pid.id._internalGetInt64Value())"
                return (pid, title, rule.forEveryone)
            }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        } |> deliverOnMainQueue).startStandalone(next: { items in
            var btns: [(title: String, isDestructive: Bool, action: () -> Void)] = items.map { pid, title, forEveryone in
                let scope = forEveryone ? "у обоих" : "у себя"
                return (title: "Снять .mute: \(title) (\(scope))", isDestructive: false, action: {
                    disableMute(context: context, peerId: pid)
                })
            }
            btns.append((title: "Снять .mute со всех", isDestructive: true, action: {
                saveMuteRules([:])
                muteTimerBox.withLock { timer in
                    timer?.cancel()
                    timer = nil
                }
                muteContextBox.withLock { $0 = nil }
                mtPresentNativeToast(context: context, text: "Все правила .mute очищены")
            }))
            mtPresentNativeActionSheet(context: context, title: "Активные правила .mute (\(items.count))", buttons: btns)
        })
    }

    // MARK: - Wave 13 Control Center Modal

    public static func presentControlCenter(context: AccountContext, currentPeerId: PeerId?) {
        let muteCount = loadMuteRules().count
        var btns: [(title: String, isDestructive: Bool, action: () -> Void)] = [
            (title: isReadOnlyLocked ? "Выключить «Только чтение»" : "Включить «Только чтение» (.readonly)", isDestructive: false, action: {
                toggleReadOnlyLock(context: context)
            }),
            (title: "Авто-снос входящих .mute (\(muteCount))", isDestructive: false, action: {
                presentMuteManager(context: context)
            }),
            (title: "Фильтр тяжёлых медиа (.heavy)", isDestructive: false, action: {
                presentHeavyMediaScreen(context: context, initialPeerId: currentPeerId)
            })
        ]
        if let peerId = currentPeerId {
            btns.append((title: "Фейк «печатает...» на 10 мин", isDestructive: false, action: {
                startFakeActivity(context: context, peerId: peerId, activity: .typingText, label: "печатает...", minutes: 10)
            }))
            btns.append((title: "Фейк «записывает кружок...» на 10 мин", isDestructive: false, action: {
                startFakeActivity(context: context, peerId: peerId, activity: .recordingInstantVideo, label: "записывает видео...", minutes: 10)
            }))
            btns.append((title: "Остановить фейк-статус", isDestructive: false, action: {
                stopFakeActivity(context: context, peerId: peerId)
            }))
        }
        btns.append((title: "Снос своих сообщений (.delme)", isDestructive: true, action: {
            presentDelMeGate(context: context, currentPeerId: currentPeerId)
        }))
        mtPresentNativeActionSheet(context: context, title: "Приватность и управление чатом", buttons: btns)
    }
}

// MARK: - #208 Selective .delme Native ItemListController

private func mtMakeNativeDelMeController(context: AccountContext, currentPeerId: PeerId?) -> ItemListController {
    struct ChatChoice: Equatable {
        let peerId: PeerId
        let title: String
        let isGroup: Bool
        let isCurrent: Bool
    }
    struct DelMeState {
        var allChats: [ChatChoice] = []
        var filterMode: Int = 0 // 0=All, 1=DM, 2=Groups
        var selectedPeerIds: Set<PeerId> = []
        var statusText: String = "Выберите ЛС или группы. Удалятся только ваши исходящие сообщения."
        var isWorking: Bool = false
    }

    let stateAtomic = Atomic<DelMeState>(value: DelMeState())
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revCount = 0
    let bump: () -> Void = {
        revCount += 1
        revision.set(revCount)
    }
    weak var weakController: ItemListController?

    let ownId = context.account.peerId
    let _ = (context.account.postbox.transaction { transaction -> [ChatChoice] in
        var result: [ChatChoice] = []
        var seen = Set<PeerId>()
        for groupId in [PeerGroupId.root, PeerGroupId(rawValue: 1)] {
            let entries = transaction.getTopChatListEntries(groupId: groupId, count: 150)
            for entry in entries {
                let pid = entry.peerId
                if seen.contains(pid) || pid == ownId { continue }
                seen.insert(pid)
                let isGroup: Bool
                if pid.namespace == Namespaces.Peer.CloudUser {
                    isGroup = false
                } else if pid.namespace == Namespaces.Peer.CloudGroup || pid.namespace == Namespaces.Peer.CloudChannel {
                    if let ch = entry.peer as? TelegramChannel, case .broadcast = ch.info {
                        continue
                    }
                    isGroup = true
                } else {
                    continue
                }
                let title = entry.peer?.debugDisplayTitle ?? "Чат \(pid.id._internalGetInt64Value())"
                result.append(ChatChoice(peerId: pid, title: title, isGroup: isGroup, isCurrent: pid == currentPeerId))
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    } |> deliverOnMainQueue).startStandalone(next: { list in
        let _ = stateAtomic.modify { st in
            var next = st
            next.allChats = list
            if let current = currentPeerId, list.contains(where: { $0.peerId == current }) {
                next.selectedPeerIds.insert(current)
            }
            return next
        }
        bump()
    })

    let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let st = stateAtomic.with { $0 }
        let filtered: [ChatChoice]
        switch st.filterMode {
        case 1: filtered = st.allChats.filter { !$0.isGroup }
        case 2: filtered = st.allChats.filter { $0.isGroup }
        default: filtered = st.allChats
        }
        let filterTitle = st.filterMode == 1 ? "Только ЛС" : (st.filterMode == 2 ? "Только группы" : "Все чаты")

        var screen = MTNativeScreenModel(title: "Снос своих сообщений")

        screen.sections.append([
            MTNativeRow(id: "dm.ctrl.h", kind: .header("Фильтр и выполнение")),
            MTNativeRow(id: "dm.filter", kind: .disclosure(title: "Показывать", label: filterTitle, icon: nil, enabled: true)),
            MTNativeRow(id: "dm.selall", kind: .action(title: "Выбрать / снять видимые (\(filtered.count))", destructive: false, enabled: !filtered.isEmpty)),
            MTNativeRow(id: "dm.wipe", kind: .action(title: st.isWorking ? "Удаление..." : "Удалить свои сообщения (\(st.selectedPeerIds.count))", destructive: true, enabled: !st.selectedPeerIds.isEmpty && !st.isWorking)),
            MTNativeRow(id: "dm.ctrl.f", kind: .footer(st.statusText))
        ])

        screen.tap["dm.filter"] = {
            mtPresentNativeActionSheet(context: context, from: weakController, title: "Фильтр чатов", buttons: [
                (title: "Все чаты", isDestructive: false, action: { let _ = stateAtomic.modify { var n = $0; n.filterMode = 0; return n }; bump() }),
                (title: "Только ЛС", isDestructive: false, action: { let _ = stateAtomic.modify { var n = $0; n.filterMode = 1; return n }; bump() }),
                (title: "Только группы", isDestructive: false, action: { let _ = stateAtomic.modify { var n = $0; n.filterMode = 2; return n }; bump() })
            ])
        }
        screen.tap["dm.selall"] = {
            let visibleIds = Set(filtered.map(\.peerId))
            let _ = stateAtomic.modify { s in
                var n = s
                if visibleIds.isSubset(of: n.selectedPeerIds) {
                    n.selectedPeerIds.subtract(visibleIds)
                } else {
                    n.selectedPeerIds.formUnion(visibleIds)
                }
                return n
            }
            bump()
        }
        screen.tap["dm.wipe"] = {
            let targets = Array(stateAtomic.with { $0.selectedPeerIds })
            guard !targets.isEmpty else { return }
            mtPresentNativePrompt(
                context: context,
                from: weakController,
                title: "Подтверждение удаления",
                subtitle: "Введите слово УДАЛИТЬ для сноса ваших сообщений в \(targets.count) чатах (для всех):",
                value: "",
                placeholder: "УДАЛИТЬ",
                apply: { entered in
                    let up = entered.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    guard up == "УДАЛИТЬ" || up == "DELETE" else {
                        mtPresentNativeToast(context: context, from: weakController, text: "Неверное слово подтверждения")
                        return
                    }
                    let _ = stateAtomic.modify { var n = $0; n.isWorking = true; n.statusText = "Сканирование и удаление..."; return n }
                    bump()
                    let _ = (context.account.postbox.transaction { transaction -> [MessageId] in
                        var ids: [MessageId] = []
                        for pid in targets {
                            transaction.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: 1500) { msg in
                                if !msg.flags.contains(.Incoming) {
                                    ids.append(msg.id)
                                }
                                return true
                            }
                        }
                        return ids
                    } |> deliverOnMainQueue).startStandalone(next: { allIds in
                        guard !allIds.isEmpty else {
                            let _ = stateAtomic.modify { var n = $0; n.isWorking = false; n.statusText = "Ваших локально загруженных сообщений не найдено."; return n }
                            bump()
                            return
                        }
                        var offset = 0
                        while offset < allIds.count {
                            let end = min(allIds.count, offset + 100)
                            let slice = Array(allIds[offset ..< end])
                            let _ = context.engine.messages.deleteMessagesInteractively(messageIds: slice, type: .forEveryone).startStandalone()
                            offset = end
                        }
                        let _ = stateAtomic.modify { var n = $0; n.isWorking = false; n.statusText = "Отправлено на удаление \(allIds.count) сообщений."; return n }
                        bump()
                        mtPresentNativeToast(context: context, from: weakController, text: "Удалено \(allIds.count) сообщений")
                    })
                }
            )
        }

        var chatRows: [MTNativeRow] = [
            MTNativeRow(id: "dm.list.h", kind: .header("Чаты (\(filtered.count))"))
        ]
        for item in filtered {
            let rowId = "dm.c.\(item.peerId.toInt64())"
            let checked = st.selectedPeerIds.contains(item.peerId)
            chatRows.append(MTNativeRow(
                id: rowId,
                kind: .check(
                    title: item.isCurrent ? "\(item.title) (текущий)" : item.title,
                    subtitle: item.isGroup ? "Группа" : "Личный чат",
                    checked: checked
                )
            ))
            screen.tap[rowId] = {
                let _ = stateAtomic.modify { s in
                    var n = s
                    if n.selectedPeerIds.contains(item.peerId) {
                        n.selectedPeerIds.remove(item.peerId)
                    } else {
                        n.selectedPeerIds.insert(item.peerId)
                    }
                    return n
                }
                bump()
            }
        }
        screen.sections.append(chatRows)
        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}

// MARK: - #263 Upgraded Heavy Media Size Filter Native ItemListController

private func mtFormatHeavyBytes(_ bytes: Int64) -> String {
    let mb = Double(bytes) / (1024.0 * 1024.0)
    if mb >= 1024.0 {
        return String(format: "%.2f ГБ", mb / 1024.0)
    }
    if mb >= 1.0 {
        return String(format: "%.1f МБ", mb)
    }
    return String(format: "%.0f КБ", Double(bytes) / 1024.0)
}

private func mtMakeNativeHeavyMediaController(context: AccountContext, initialPeerId: PeerId?) -> ItemListController {
    struct MediaItem: Equatable {
        let messageId: MessageId
        let chatTitle: String
        let fileName: String
        let sizeBytes: Int64
    }
    struct HeavyState {
        var allItems: [MediaItem] = []
        var singleChatOnly: Bool
        var minMb: Int = 0 // 0, 10, 50, 100
        var isLoading: Bool = true
    }

    let stateAtomic = Atomic<HeavyState>(value: HeavyState(singleChatOnly: initialPeerId != nil))
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revCount = 0
    let bump: () -> Void = {
        revCount += 1
        revision.set(revCount)
    }
    weak var weakController: ItemListController?

    let runScan: () -> Void = {
        let singleOnly = stateAtomic.modify { var n = $0; n.isLoading = true; return n }.singleChatOnly
        bump()
        let singlePeer = singleOnly ? initialPeerId : nil

        let _ = (context.account.postbox.transaction { transaction -> [MediaItem] in
            var found: [MediaItem] = []
            var peersToScan: [(PeerId, String)] = []
            if let single = singlePeer {
                peersToScan.append((single, transaction.getPeer(single)?.debugDisplayTitle ?? "Текущий чат"))
            } else {
                var seen = Set<PeerId>()
                for groupId in [PeerGroupId.root, PeerGroupId(rawValue: 1)] {
                    for entry in transaction.getTopChatListEntries(groupId: groupId, count: 60) {
                        if seen.contains(entry.peerId) { continue }
                        seen.insert(entry.peerId)
                        peersToScan.append((entry.peerId, entry.peer?.debugDisplayTitle ?? "Чат"))
                    }
                }
            }
            let perPeerLimit = (singlePeer != nil) ? 1500 : 120
            for (pid, title) in peersToScan {
                if found.count >= 800 { break }
                transaction.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: perPeerLimit) { msg in
                    for media in msg.media {
                        if let file = media as? TelegramMediaFile, let size = file.size, size > 0 {
                            let name = file.fileName ?? (file.isVideo ? "Видео" : (file.isVoice ? "Голосовое" : "Файл"))
                            found.append(MediaItem(messageId: msg.id, chatTitle: title, fileName: name, sizeBytes: size))
                        }
                    }
                    return found.count < 800
                }
            }
            return found.sorted { $0.sizeBytes > $1.sizeBytes }
        } |> deliverOnMainQueue).startStandalone(next: { items in
            let _ = stateAtomic.modify { var n = $0; n.allItems = items; n.isLoading = false; return n }
            bump()
        })
    }

    runScan()

    let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let st = stateAtomic.with { $0 }
        let minBytes = Int64(st.minMb) * 1024 * 1024
        let visible = st.allItems.filter { $0.sizeBytes >= minBytes }
        let totalBytes = visible.reduce(Int64(0)) { $0 + $1.sizeBytes }

        var screen = MTNativeScreenModel(title: "Тяжёлые медиа")

        var filterRows: [MTNativeRow] = [
            MTNativeRow(id: "hm.f.h", kind: .header("Параметры поиска")),
            MTNativeRow(id: "hm.size", kind: .disclosure(title: "Минимальный размер", label: st.minMb == 0 ? "Все файлы" : "> \(st.minMb) МБ", icon: nil, enabled: true))
        ]
        if initialPeerId != nil {
            filterRows.append(MTNativeRow(id: "hm.scope", kind: .toggle(title: "Только текущий чат", value: st.singleChatOnly, enabled: true)))
        }
        filterRows.append(MTNativeRow(id: "hm.f.foot", kind: .footer("Найдено: \(visible.count) файлов • Общий вес: \(mtFormatHeavyBytes(totalBytes))")))
        screen.sections.append(filterRows)

        screen.tap["hm.size"] = {
            let opts = [0, 10, 50, 100]
            let btns = opts.map { mb in
                (title: mb == 0 ? "Все файлы" : "> \(mb) МБ", isDestructive: false, action: {
                    let _ = stateAtomic.modify { var n = $0; n.minMb = mb; return n }
                    bump()
                })
            }
            mtPresentNativeActionSheet(context: context, from: weakController, title: "Минимальный вес файла", buttons: btns)
        }
        screen.toggle["hm.scope"] = { isOn in
            let _ = stateAtomic.modify { var n = $0; n.singleChatOnly = isOn; return n }
            runScan()
        }

        var fileRows: [MTNativeRow] = [
            MTNativeRow(id: "hm.l.h", kind: .header("Файлы по убыванию веса"))
        ]
        if visible.isEmpty {
            fileRows.append(MTNativeRow(id: "hm.empty", kind: .info(st.isLoading ? "Сканирование вложений..." : "Файлов не найдено")))
        } else {
            for (idx, item) in visible.prefix(150).enumerated() {
                let rowId = "hm.i.\(idx)"
                fileRows.append(MTNativeRow(
                    id: rowId,
                    kind: .disclosure(title: item.fileName, label: "\(item.chatTitle) • \(mtFormatHeavyBytes(item.sizeBytes))", icon: nil, enabled: true)
                ))
                screen.tap[rowId] = {
                    mtPresentNativeActionSheet(context: context, from: weakController, title: "\(item.fileName) (\(mtFormatHeavyBytes(item.sizeBytes)))", buttons: [
                        (title: "Удалить сообщение у себя", isDestructive: true, action: {
                            let _ = context.engine.messages.deleteMessagesInteractively(messageIds: [item.messageId], type: .forLocalPeer).startStandalone()
                            let _ = stateAtomic.modify { s in
                                var n = s
                                n.allItems.removeAll { $0.messageId == item.messageId }
                                return n
                            }
                            bump()
                        })
                    ])
                }
            }
        }
        screen.sections.append(fileRows)
        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}
