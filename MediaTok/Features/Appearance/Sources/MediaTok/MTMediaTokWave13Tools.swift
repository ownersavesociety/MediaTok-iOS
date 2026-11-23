import Foundation
import UIKit
import LocalAuthentication
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
                MTMediaTokWave5Tools.showToast(context: ctx, text: "Режим «Только чтение» активен. Введите .unlock для снятия.")
            } else {
                let alert = UIAlertController(
                    title: "Режим «Только чтение»",
                    message: "Отправка сообщений и медиа заблокирована. Откройте любой чат и введите .unlock или снимите блокировку в Spotlight.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                MTModalPresenter.presentOnTopmost(alert)
            }
        }
    }

    // MARK: - Helpers

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
            // Device has no passcode/FaceID configured -> require explicit confirmation alert (fail-closed if no UI)
            DispatchQueue.main.async {
                guard MTModalPresenter.activeRootViewController() != nil else {
                    completion(false)
                    return
                }
                let alert = UIAlertController(
                    title: "Подтверждение безопасности",
                    message: "\(reason)\n\nНа устройстве не настроен FaceID или код-пароль. Подтвердить действие вручную?",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in
                    completion(false)
                })
                alert.addAction(UIAlertAction(title: "Подтвердить", style: .destructive) { _ in
                    completion(true)
                })
                MTModalPresenter.presentOnTopmost(alert)
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
                MTMediaTokWave5Tools.showToast(context: context, text: "Доступ к .delme отменён")
                return
            }
            guard let top = topViewController() else { return }
            let vc = MTDelMeSelectorController(context: context, currentPeerId: currentPeerId)
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .pageSheet
            top.present(nav, animated: true)
        }
    }

    // MARK: - #263 Heavy Media Size Filter Screen

    public static func presentHeavyMediaScreen(context: AccountContext, initialPeerId: PeerId?) {
        guard let top = topViewController() else { return }
        let vc = MTHeavyMediaFilterController(context: context, initialPeerId: initialPeerId)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #207 Active .mute Rules Manager UI

    public static func presentMuteManager(context: AccountContext) {
        let rules = loadMuteRules()
        if rules.isEmpty {
            let alert = UIAlertController(
                title: "Авто-снос входящих (.mute)",
                message: "Активных правил .mute нет.\n\nЧтобы включить авто-снос входящих в личном чате, введите .mute (или .mute local) либо используйте долгое нажатие на сообщение.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            MTModalPresenter.presentOnTopmost(alert)
            return
        }

        let _ = (context.account.postbox.transaction { transaction -> [(PeerId, String, Bool)] in
            return rules.values.map { rule in
                let pid = PeerId(rule.peerId)
                let title = transaction.getPeer(pid)?.debugDisplayTitle ?? "ID \(pid.id._internalGetInt64Value())"
                return (pid, title, rule.forEveryone)
            }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        } |> deliverOnMainQueue).startStandalone(next: { items in
            let sheet = UIAlertController(
                title: "Активные правила .mute (\(items.count))",
                message: "Нажмите на чат, чтобы снять авто-снос входящих:",
                preferredStyle: .actionSheet
            )
            for (pid, title, forEveryone) in items {
                let scope = forEveryone ? "у обоих" : "у себя"
                sheet.addAction(UIAlertAction(title: "Снять .mute: \(title) (\(scope))", style: .default) { _ in
                    disableMute(context: context, peerId: pid)
                })
            }
            sheet.addAction(UIAlertAction(title: "Снять .mute со всех", style: .destructive) { _ in
                saveMuteRules([:])
                muteTimerBox.withLock { timer in
                    timer?.cancel()
                    timer = nil
                }
                muteContextBox.withLock { $0 = nil }
                MTMediaTokWave5Tools.showToast(context: context, text: "Все правила .mute очищены")
            })
            sheet.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
            MTModalPresenter.presentOnTopmost(sheet)
        })
    }

    // MARK: - Wave 13 Control Center Modal (accessible from Hub / Palette)

    public static func presentControlCenter(context: AccountContext, currentPeerId: PeerId?) {
        let muteCount = loadMuteRules().count
        let alert = UIAlertController(
            title: "MediaTok Privacy & Control",
            message: "Быстрый доступ к инструментам контроля ЛС, безопасности и фильтра медиа.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: isReadOnlyLocked ? "Выключить «Только чтение» (FaceID)" : "Включить «Только чтение» (.readonly)", style: .default) { _ in
            toggleReadOnlyLock(context: context)
        })
        alert.addAction(UIAlertAction(title: "Авто-снос входящих .mute (\(muteCount))", style: .default) { _ in
            presentMuteManager(context: context)
        })
        alert.addAction(UIAlertAction(title: "Безопасный снос своих сообщений (.delme)", style: .destructive) { _ in
            presentDelMeGate(context: context, currentPeerId: currentPeerId)
        })
        alert.addAction(UIAlertAction(title: "Фильтр тяжёлых медиа по весу (.heavy)", style: .default) { _ in
            presentHeavyMediaScreen(context: context, initialPeerId: currentPeerId)
        })
        if let peerId = currentPeerId {
            alert.addAction(UIAlertAction(title: "Фейк «печатает...» на 10 мин", style: .default) { _ in
                startFakeActivity(context: context, peerId: peerId, activity: .typingText, label: "печатает...", minutes: 10)
            })
            alert.addAction(UIAlertAction(title: "Фейк «записывает видео...» на 10 мин", style: .default) { _ in
                startFakeActivity(context: context, peerId: peerId, activity: .recordingInstantVideo, label: "записывает видео...", minutes: 10)
            })
            alert.addAction(UIAlertAction(title: "Остановить фейк-статус", style: .default) { _ in
                stopFakeActivity(context: context, peerId: peerId)
            })
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTModalPresenter.presentOnTopmost(alert)
    }
}

// MARK: - #208 Selective .delme ViewController

private final class MTDelMeSelectorController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private struct ChatChoice {
        let peerId: PeerId
        let title: String
        let isGroup: Bool
        let isCurrent: Bool
    }

    private let context: AccountContext
    private let currentPeerId: PeerId?

    private var allChats: [ChatChoice] = []
    private var filteredChats: [ChatChoice] = []
    private var selectedPeerIds = Set<PeerId>()

    private let segment = UISegmentedControl(items: ["Все", "ЛС", "Группы"])
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let wipeButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    init(context: AccountContext, currentPeerId: PeerId?) {
        self.context = context
        self.currentPeerId = currentPeerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Снос своих сообщений (.delme)"
        self.view.backgroundColor = .systemGroupedBackground

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Выбрать все", style: .plain, target: self, action: #selector(selectAllTapped))

        self.segment.selectedSegmentIndex = 0
        self.segment.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        self.segment.translatesAutoresizingMaskIntoConstraints = false

        self.statusLabel.font = .systemFont(ofSize: 13)
        self.statusLabel.textColor = .secondaryLabel
        self.statusLabel.numberOfLines = 0
        self.statusLabel.textAlignment = .center
        self.statusLabel.text = "Выберите нужные ЛС или группы. Удалятся только ваши исходящие сообщения."
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        var cfg = UIButton.Configuration.filled()
        cfg.baseBackgroundColor = .systemRed
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .large
        cfg.title = "Удалить свои сообщения (0)"
        cfg.image = UIImage(systemName: "trash.fill")
        cfg.imagePadding = 8
        self.wipeButton.configuration = cfg
        self.wipeButton.addTarget(self, action: #selector(wipeTapped), for: .touchUpInside)
        self.wipeButton.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.segment)
        self.view.addSubview(self.statusLabel)
        self.view.addSubview(self.tableView)
        self.view.addSubview(self.wipeButton)

        NSLayoutConstraint.activate([
            self.segment.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 10),
            self.segment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.segment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.statusLabel.topAnchor.constraint(equalTo: self.segment.bottomAnchor, constant: 8),
            self.statusLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.statusLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.tableView.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 8),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.wipeButton.topAnchor, constant: -10),

            self.wipeButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.wipeButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.wipeButton.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            self.wipeButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        self.loadChats()
    }

    private func loadChats() {
        let current = self.currentPeerId
        let ownId = self.context.account.peerId
        let _ = (self.context.account.postbox.transaction { transaction -> [ChatChoice] in
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
                    result.append(ChatChoice(peerId: pid, title: title, isGroup: isGroup, isCurrent: pid == current))
                }
            }
            return result.sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] list in
            guard let self else { return }
            self.allChats = list
            if let current = self.currentPeerId, list.contains(where: { $0.peerId == current }) {
                self.selectedPeerIds.insert(current)
            }
            self.applyFilter()
        })
    }

    private func applyFilter() {
        switch self.segment.selectedSegmentIndex {
        case 1:
            self.filteredChats = self.allChats.filter { !$0.isGroup }
        case 2:
            self.filteredChats = self.allChats.filter { $0.isGroup }
        default:
            self.filteredChats = self.allChats
        }
        self.tableView.reloadData()
        self.updateButtonTitle()
    }

    private func updateButtonTitle() {
        var cfg = self.wipeButton.configuration ?? UIButton.Configuration.filled()
        cfg.title = "Удалить свои сообщения (\(self.selectedPeerIds.count))"
        self.wipeButton.configuration = cfg
        self.wipeButton.isEnabled = !self.selectedPeerIds.isEmpty
    }

    @objc private func filterChanged() {
        self.applyFilter()
    }

    @objc private func selectAllTapped() {
        let visibleIds = Set(self.filteredChats.map { $0.peerId })
        if visibleIds.isSubset(of: self.selectedPeerIds) {
            self.selectedPeerIds.subtract(visibleIds)
        } else {
            self.selectedPeerIds.formUnion(visibleIds)
        }
        self.tableView.reloadData()
        self.updateButtonTitle()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func wipeTapped() {
        guard !self.selectedPeerIds.isEmpty else { return }
        let count = self.selectedPeerIds.count
        let confirm = UIAlertController(
            title: "Финальное подтверждение",
            message: "Будут удалены ваши исходящие сообщения в \(count) выбранных чатах (для всех). Введите слово УДАЛИТЬ чтобы подтвердить.",
            preferredStyle: .alert
        )
        confirm.addTextField { tf in
            tf.placeholder = "УДАЛИТЬ"
            tf.autocapitalizationType = .allCharacters
        }
        confirm.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        confirm.addAction(UIAlertAction(title: "Снести", style: .destructive) { [weak self, weak confirm] _ in
            guard let self, let confirm else { return }
            let entered = (confirm.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard entered == "УДАЛИТЬ" || entered == "DELETE" else {
                self.statusLabel.text = "Неверное слово подтверждения. Удаление отменено."
                self.statusLabel.textColor = .systemOrange
                return
            }
            self.executeWipe(peerIds: Array(self.selectedPeerIds))
        })
        self.present(confirm, animated: true)
    }

    private func executeWipe(peerIds: [PeerId]) {
        self.wipeButton.isEnabled = false
        self.statusLabel.textColor = .systemRed
        self.statusLabel.text = "Сканирую и удаляю ваши сообщения..."
        let ctx = self.context

        let _ = (ctx.account.postbox.transaction { transaction -> [MessageId] in
            var ids: [MessageId] = []
            for pid in peerIds {
                transaction.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: 1500) { msg in
                    if !msg.flags.contains(.Incoming) {
                        ids.append(msg.id)
                    }
                    return true
                }
            }
            return ids
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] allIds in
            guard let self else { return }
            guard !allIds.isEmpty else {
                self.statusLabel.textColor = .secondaryLabel
                self.statusLabel.text = "Ваших локально загруженных сообщений в выбранных чатах не найдено."
                self.wipeButton.isEnabled = true
                return
            }
            let chunkSize = 100
            var offset = 0
            while offset < allIds.count {
                let end = min(allIds.count, offset + chunkSize)
                let slice = Array(allIds[offset ..< end])
                let _ = ctx.engine.messages.deleteMessagesInteractively(messageIds: slice, type: .forEveryone).startStandalone()
                offset = end
            }
            self.statusLabel.textColor = .systemGreen
            self.statusLabel.text = "Отправлено на удаление \(allIds.count) ваших сообщений в \(peerIds.count) чатах."
            MTMediaTokWave5Tools.showToast(context: ctx, text: ".delme: удалено \(allIds.count) сообщений")
            self.wipeButton.isEnabled = true
        })
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.filteredChats.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "delmeCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "delmeCell")
        let item = self.filteredChats[indexPath.row]
        cell.textLabel?.text = item.isCurrent ? "\(item.title) (текущий)" : item.title
        cell.detailTextLabel?.text = item.isGroup ? "Группа" : "Личный чат (ЛС)"
        cell.imageView?.image = UIImage(systemName: item.isGroup ? "person.3.fill" : "person.fill")
        cell.accessoryType = self.selectedPeerIds.contains(item.peerId) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = self.filteredChats[indexPath.row]
        if self.selectedPeerIds.contains(item.peerId) {
            self.selectedPeerIds.remove(item.peerId)
        } else {
            self.selectedPeerIds.insert(item.peerId)
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
        self.updateButtonTitle()
    }
}

// MARK: - #263 Upgraded Heavy Media Size Filter ViewController

private final class MTHeavyMediaFilterController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private struct MediaItem {
        let messageId: MessageId
        let chatTitle: String
        let fileName: String
        let kindIcon: String
        let sizeBytes: Int64
        let timestamp: Int32
    }

    private let context: AccountContext
    private let initialPeerId: PeerId?

    private var allItems: [MediaItem] = []
    private var visibleItems: [MediaItem] = []

    private let scopeSegment = UISegmentedControl(items: ["Текущий чат", "Все чаты"])
    private let sizeSegment = UISegmentedControl(items: ["Все", ">10 МБ", ">50 МБ", ">100 МБ"])
    private let summaryLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(context: AccountContext, initialPeerId: PeerId?) {
        self.context = context
        self.initialPeerId = initialPeerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Фильтр медиа по весу"
        self.view.backgroundColor = .systemGroupedBackground

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.scopeSegment.selectedSegmentIndex = (self.initialPeerId != nil) ? 0 : 1
        if self.initialPeerId == nil {
            self.scopeSegment.setEnabled(false, forSegmentAt: 0)
        }
        self.scopeSegment.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        self.scopeSegment.translatesAutoresizingMaskIntoConstraints = false

        self.sizeSegment.selectedSegmentIndex = 0
        self.sizeSegment.addTarget(self, action: #selector(thresholdChanged), for: .valueChanged)
        self.sizeSegment.translatesAutoresizingMaskIntoConstraints = false

        self.summaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        self.summaryLabel.textColor = .secondaryLabel
        self.summaryLabel.textAlignment = .center
        self.summaryLabel.text = "Сканирую вложения..."
        self.summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.scopeSegment)
        self.view.addSubview(self.sizeSegment)
        self.view.addSubview(self.summaryLabel)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.scopeSegment.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 10),
            self.scopeSegment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.scopeSegment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.sizeSegment.topAnchor.constraint(equalTo: self.scopeSegment.bottomAnchor, constant: 8),
            self.sizeSegment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.sizeSegment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.summaryLabel.topAnchor.constraint(equalTo: self.sizeSegment.bottomAnchor, constant: 8),
            self.summaryLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.summaryLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.tableView.topAnchor.constraint(equalTo: self.summaryLabel.bottomAnchor, constant: 8),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.reloadScan()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func scopeChanged() {
        self.reloadScan()
    }

    @objc private func thresholdChanged() {
        self.applyThreshold()
    }

    private func reloadScan() {
        let singlePeer: PeerId? = (self.scopeSegment.selectedSegmentIndex == 0) ? self.initialPeerId : nil
        self.summaryLabel.text = "Сканирую тяжёлые файлы..."

        let _ = (self.context.account.postbox.transaction { transaction -> [MediaItem] in
            var found: [MediaItem] = []
            var peersToScan: [(PeerId, String)] = []
            if let single = singlePeer {
                let title = transaction.getPeer(single)?.debugDisplayTitle ?? "Текущий чат"
                peersToScan.append((single, title))
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
                if found.count >= 1200 { break }
                transaction.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: perPeerLimit) { msg in
                    for media in msg.media {
                        if let file = media as? TelegramMediaFile, let size = file.size, size > 0 {
                            let icon: String
                            if file.isVideo || file.isInstantVideo {
                                icon = "video.fill"
                            } else if file.isMusic || file.isVoice {
                                icon = "waveform"
                            } else {
                                icon = "doc.fill"
                            }
                            let name = file.fileName ?? (file.isVideo ? "Видео" : (file.isVoice ? "Голосовое" : "Файл"))
                            found.append(MediaItem(
                                messageId: msg.id,
                                chatTitle: title,
                                fileName: name,
                                kindIcon: icon,
                                sizeBytes: size,
                                timestamp: msg.timestamp
                            ))
                        }
                    }
                    return found.count < 1200
                }
            }
            return found.sorted { $0.sizeBytes > $1.sizeBytes }
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] items in
            guard let self else { return }
            self.allItems = items
            self.applyThreshold()
        })
    }

    private func applyThreshold() {
        let minBytes: Int64
        switch self.sizeSegment.selectedSegmentIndex {
        case 1: minBytes = 10 * 1024 * 1024
        case 2: minBytes = 50 * 1024 * 1024
        case 3: minBytes = 100 * 1024 * 1024
        default: minBytes = 0
        }
        self.visibleItems = self.allItems.filter { $0.sizeBytes >= minBytes }
        let totalBytes = self.visibleItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
        self.summaryLabel.text = "Найдено: \(self.visibleItems.count) файлов · Общий вес: \(Self.formatBytes(totalBytes)) (сначала самые тяжёлые)"
        self.tableView.reloadData()
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1024.0 {
            return String(format: "%.2f ГБ", mb / 1024.0)
        }
        if mb >= 1.0 {
            return String(format: "%.1f МБ", mb)
        }
        return String(format: "%.0f КБ", Double(bytes) / 1024.0)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.visibleItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "heavyMediaCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "heavyMediaCell")
        let item = self.visibleItems[indexPath.row]
        cell.textLabel?.text = item.fileName
        cell.detailTextLabel?.text = "\(item.chatTitle) · \(Self.formatBytes(item.sizeBytes))"
        cell.imageView?.image = UIImage(systemName: item.kindIcon)

        let badge = UILabel()
        badge.text = Self.formatBytes(item.sizeBytes)
        badge.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        badge.textColor = item.sizeBytes >= 50 * 1024 * 1024 ? .systemRed : .systemBlue
        badge.sizeToFit()
        cell.accessoryView = badge
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = self.visibleItems[indexPath.row]
        let alert = UIAlertController(
            title: item.fileName,
            message: "Чат: \(item.chatTitle)\nРазмер: \(Self.formatBytes(item.sizeBytes))",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Удалить у себя", style: .destructive) { [weak self] _ in
            guard let self else { return }
            let _ = self.context.engine.messages.deleteMessagesInteractively(messageIds: [item.messageId], type: .forLocalPeer).startStandalone()
            self.allItems.removeAll { $0.messageId == item.messageId }
            self.applyThreshold()
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let pop = alert.popoverPresentationController, let cell = tableView.cellForRow(at: indexPath) {
            pop.sourceView = cell
            pop.sourceRect = cell.bounds
        }
        self.present(alert, animated: true)
    }
}
