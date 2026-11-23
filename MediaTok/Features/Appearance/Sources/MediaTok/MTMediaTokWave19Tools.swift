import Foundation
import UIKit
import CoreMotion
import CryptoKit
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
// MediaTok Wave 19 — Password Account Nuke, Real Stars Donations, Physical Cyber-Lock,
//                    Breach Check, Screenshot Fail-Safe, Engine Flags & MediaTok Pro:
//   Custom (#1029) / .nukeall   — Wipe ALL chats & leave ALL channels by secret password + Creator Guard
//   #582 / .stars               — Real Telegram Stars paid reaction/donation via native Engine API
//   #801/#802/#803 / .cyberlock — Accelerometer Snatch Lock (>3.6G) + USB Cable Lockdown + Trusted Wi-Fi
//   #823 / .breach              — k-Anonymity SHA-1 HaveIBeenPwned breach checker (only 5-char prefix leaves device)
//   #828                        — Anti-Screenshot Self-Send Shield (warns if sending right after screenshotting same chat)
//   #504 / .novoice             — Auto-delete incoming voice/round video messages in DM from specific peer
//   #531 / .freezechat          — Freeze incoming notifications/unread bump per chat
//   #997 / .197                 — Experimental Engine Flags Tweaker
//   #999/#1000 / .pro/.wizard/.builder — MediaTok Pro License + 60s Setup Wizard + Custom Slash-Action Builder
// ============================================================================

private final class MTWave19Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body(&self.value)
    }
}

public struct MTCustomBuiltAction: Codable, Equatable {
    public let id: String
    public let triggerCommand: String   // e.g. ".hello"
    public let actionType: String       // "send_text", "fake_typing", "toast"
    public let payload: String

    private enum CodingKeys: String, CodingKey {
        case id, triggerCommand, actionType, payload
    }
}

public struct MTCyberLockConfig: Codable, Equatable {
    public var snatchProtectionEnabled: Bool
    public var usbLockdownEnabled: Bool
    public var antiSelfScreenshotEnabled: Bool
    public var protectCreatorChannelsOnNuke: Bool
    public var nukePasswordSha256: String
    public var nukeWhitelistPeerIds: [Int64] = []
    public var vipProFriendUserIds: [Int64] = []

    private enum CodingKeys: String, CodingKey {
        case snatchProtectionEnabled
        case usbLockdownEnabled
        case antiSelfScreenshotEnabled
        case protectCreatorChannelsOnNuke
        case nukePasswordSha256
        case nukeWhitelistPeerIds
        case vipProFriendUserIds
    }

    public static let `default` = MTCyberLockConfig(
        snatchProtectionEnabled: false,
        usbLockdownEnabled: false,
        antiSelfScreenshotEnabled: true,
        protectCreatorChannelsOnNuke: true,
        nukePasswordSha256: "",
        nukeWhitelistPeerIds: [],
        vipProFriendUserIds: []
    )
}

public enum MTMediaTokWave19Tools {
    private static let cyberConfigKey = "mediatok.wave19.cyber_config.v1"
    private static let noVoicePeersKey = "mediatok.wave19.novoice_peers.v1"
    private static let frozenPeersKey = "mediatok.wave19.frozen_peers.v1"
    private static let proActivatedKey = "mediatok.wave19.pro_active.v1"
    private static let customActionsKey = "mediatok.wave19.custom_actions.v1"
    private static let expFlagsKey = "mediatok.wave19.exp_flags.v1"

    private static let motionManager = CMMotionManager()
    private static let stateBox = MTWave19Box<(
        activePeerId: PeerId?,
        lastScreenshotPeerId: PeerId?,
        lastScreenshotTime: TimeInterval,
        bypassScreenshotOnce: Bool,
        isCurtainVisible: Bool,
        noVoiceTimer: DispatchSourceTimer?,
        frozenPeersCache: Set<Int64>,
        lastContext: AccountContext?,
        deletedVoiceIds: Set<MessageId>
    )>((nil, nil, 0, false, false, nil, [], nil, []))

    private static var lockCurtainView: UIView?

    // MARK: - Registration

    public static func register() {
        let initialFrozen = Set((UserDefaults.standard.array(forKey: frozenPeersKey) as? [Int64]) ?? [])
        stateBox.withLock { $0.frozenPeersCache = initialFrozen }

        MTChatScreenHooks.willSendText.register({ request, proceed in
            return MTMediaTokWave19Tools.interceptSend(request, proceed: proceed)
        }, order: 41)

        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTMediaTokWave19Tools.stateBox.withLock { $0.lastContext = context }
            MTMediaTokWave19Tools.armNoVoiceWatcherIfNeeded(context: context)
            let ownUid = context.account.peerId.id._internalGetInt64Value()
            let vipList = MTMediaTokWave19Tools.loadCyberConfig().vipProFriendUserIds
            if vipList.contains(ownUid) {
                MTMediaTokWave19Tools.isProActive = true
            }
        }, order: 42)

        MTChatScreenHooks.lifecycle.register({ event, screen in
            MTMediaTokWave19Tools.handleChatLifecycle(event: event, screen: screen)
        }, order: 42)

        MTChatScreenHooks.hidesMessage.register({ message, _, _ in
            let pidRaw = message.id.peerId.toInt64()
            let frozen = MTMediaTokWave19Tools.stateBox.withLock { $0.frozenPeersCache.contains(pidRaw) }
            guard frozen else { return false }
            let freezeMap = (UserDefaults.standard.dictionary(forKey: "mediatok.wave19.frozen_since.v1") as? [String: Int]) ?? [:]
            if let since = freezeMap["\(pidRaw)"], message.flags.contains(.Incoming), Int(message.timestamp) >= since {
                return true
            }
            return false
        }, order: 55)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave19Tools.messageMenuItems(menuContext)
        }, order: 98)

        setupSystemObservers()
        refreshMotionMonitoring()
    }

    // MARK: - Config Persistence

    public static func loadCyberConfig() -> MTCyberLockConfig {
        guard let data = UserDefaults.standard.data(forKey: cyberConfigKey),
              let cfg = try? JSONDecoder().decode(MTCyberLockConfig.self, from: data) else {
            return .default
        }
        return cfg
    }

    public static func saveCyberConfig(_ cfg: MTCyberLockConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: cyberConfigKey)
        }
        refreshMotionMonitoring()
    }

    public static var isProActive: Bool {
        get { UserDefaults.standard.bool(forKey: proActivatedKey) }
        set { UserDefaults.standard.set(newValue, forKey: proActivatedKey) }
    }

    public static func loadCustomActions() -> [MTCustomBuiltAction] {
        guard let data = UserDefaults.standard.data(forKey: customActionsKey),
              let arr = try? JSONDecoder().decode([MTCustomBuiltAction].self, from: data) else {
            return []
        }
        return arr
    }

    public static func saveCustomActions(_ items: [MTCustomBuiltAction]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: customActionsKey)
        }
    }

    private static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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

    // MARK: - #801/#802/#828 System Observers (Screenshot, USB Cable, Snatch Gyro/Accel)

    private static func setupSystemObservers() {
        UIDevice.current.isBatteryMonitoringEnabled = true

        NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { _ in
            stateBox.withLock { st in
                if let active = st.activePeerId {
                    st.lastScreenshotPeerId = active
                    st.lastScreenshotTime = Date().timeIntervalSince1970
                }
            }
        }

        var lastBatteryState = UIDevice.current.batteryState
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { _ in
            let state = UIDevice.current.batteryState
            let wasUnplugged = (lastBatteryState == .unplugged)
            lastBatteryState = state
            if wasUnplugged && (state == .charging || state == .full) {
                let cfg = loadCyberConfig()
                if cfg.usbLockdownEnabled {
                    engageEmergencyLockCurtain(reason: "Обнаружено подключение кабеля USB (USB Lockdown #802)")
                }
            }
        }
    }

    private static func refreshMotionMonitoring() {
        let cfg = loadCyberConfig()
        if cfg.snatchProtectionEnabled {
            guard motionManager.isAccelerometerAvailable, !motionManager.isAccelerometerActive else { return }
            motionManager.accelerometerUpdateInterval = 0.08
            motionManager.startAccelerometerUpdates(to: .main) { data, _ in
                guard let acc = data?.acceleration else { return }
                let mag = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)
                if mag > 3.65 {
                    engageEmergencyLockCurtain(reason: "Зафиксирован резкий рывок устройства (Snatch Lock #801)")
                }
            }
        } else if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
    }

    public static func engageEmergencyLockCurtain(reason: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                engageEmergencyLockCurtain(reason: reason)
            }
            return
        }
        let already = stateBox.withLock { st -> Bool in
            if st.isCurtainVisible { return true }
            st.isCurtainVisible = true
            return false
        }
        if already { return }

        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
            stateBox.withLock { $0.isCurtainVisible = false }
            return
        }

        window.endEditing(true)
        let curtain = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        curtain.frame = window.bounds
        curtain.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        icon.tintColor = .systemRed
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLbl = UILabel()
        titleLbl.text = "Экстренная блокировка MediaTok"
        titleLbl.font = .systemFont(ofSize: 20, weight: .bold)
        titleLbl.textColor = .white

        let subLbl = UILabel()
        subLbl.text = reason
        subLbl.font = .systemFont(ofSize: 14)
        subLbl.textColor = .lightGray
        subLbl.numberOfLines = 0
        subLbl.textAlignment = .center

        var btnCfg = UIButton.Configuration.filled()
        btnCfg.title = "Разблокировать по FaceID / Паролю"
        btnCfg.image = UIImage(systemName: "faceid")
        btnCfg.imagePadding = 8
        btnCfg.cornerStyle = .capsule
        let unlockBtn = UIButton(configuration: btnCfg, primaryAction: UIAction { _ in
            let la = LAContext()
            var err: NSError?
            let pol: LAPolicy = la.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) ? .deviceOwnerAuthentication : .deviceOwnerAuthenticationWithBiometrics
            if la.canEvaluatePolicy(pol, error: &err) {
                la.evaluatePolicy(pol, localizedReason: "Разблокировать MediaTok после срабатывания защиты") { ok, _ in
                    DispatchQueue.main.async {
                        if ok {
                            lockCurtainView?.removeFromSuperview()
                            lockCurtainView = nil
                            stateBox.withLock { $0.isCurtainVisible = false }
                        }
                    }
                }
            } else {
                lockCurtainView?.removeFromSuperview()
                lockCurtainView = nil
                stateBox.withLock { $0.isCurtainVisible = false }
            }
        })

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(titleLbl)
        stack.addArrangedSubview(subLbl)
        stack.addArrangedSubview(unlockBtn)
        curtain.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
            stack.centerXAnchor.constraint(equalTo: curtain.contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: curtain.contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: curtain.contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: curtain.contentView.trailingAnchor, constant: -28)
        ])

        window.addSubview(curtain)
        lockCurtainView = curtain
    }

    private static func handleChatLifecycle(event: MTChatScreenEvent, screen: MTChatScreen) {
        let pid = screen.chatLocation.peerId
        stateBox.withLock { st in
            st.lastContext = screen.context
            if event == .didAppear {
                st.activePeerId = pid
            } else if event == .willDisappear, st.activePeerId == pid {
                st.activePeerId = nil
            }
        }
        if event == .didAppear {
            armNoVoiceWatcherIfNeeded(context: screen.context)
        }
    }

    // MARK: - Command & Anti-Screenshot Send Interception

    private static func interceptSend(_ request: MTComposedTextRequest, proceed: @escaping () -> Void) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let peerId = request.chatLocation.peerId

        // 1. Check Custom Action Builder (#1000) user-defined commands first (if Pro active)
        if isProActive, raw.hasPrefix(".") {
            for act in loadCustomActions() where act.triggerCommand.lowercased() == lower {
                request.replace(ChatTextInputState())
                executeCustomAction(act, context: request.context, peerId: peerId)
                return true
            }
        }

        // 2. Built-in Wave 19 Slash Commands
        if raw.hasPrefix(".") {
            if lower == ".nukeall" || lower == ".wipeaccount" {
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentNukeAllScreen(context: request.context) }
                return true
            }
            if lower == ".cyberlock" || lower == ".snatch" {
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentCyberLockSettings(context: request.context) }
                return true
            }
            if lower == ".breach" || lower.hasPrefix(".breach ") {
                let arg = lower.hasPrefix(".breach ") ? String(raw.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentBreachChecker(context: request.context, initialQuery: arg) }
                return true
            }
            if lower == ".novoice" {
                request.replace(ChatTextInputState())
                if let pid = peerId { toggleNoVoiceInDm(context: request.context, peerId: pid) }
                return true
            }
            if lower == ".freezechat" {
                request.replace(ChatTextInputState())
                if let pid = peerId { toggleFreezeChat(context: request.context, peerId: pid) }
                return true
            }
            if lower == ".197" || lower == ".flags" || lower == ".expflags" {
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentExperimentalFlags(context: request.context) }
                return true
            }
            if lower == ".pro" || lower == ".wizard" || lower == ".builder" {
                request.replace(ChatTextInputState())
                DispatchQueue.main.async { presentMediaTokProHub(context: request.context, peerId: peerId) }
                return true
            }
        }

        // 3. #828 Anti-Self-Screenshot Fail Guard (if user took a screenshot of THIS chat < 75s ago)
        if loadCyberConfig().antiSelfScreenshotEnabled, let pid = peerId {
            let shouldWarn = stateBox.withLock { st -> Bool in
                if st.bypassScreenshotOnce {
                    st.bypassScreenshotOnce = false
                    return false
                }
                guard st.lastScreenshotPeerId == pid else { return false }
                return (Date().timeIntervalSince1970 - st.lastScreenshotTime) < 75.0
            }
            if shouldWarn, let top = topViewController() {
                let alert = UIAlertController(
                    title: "Стоп! Недавний скриншот этого чата (#828)",
                    message: "Вы меньше минуты назад сделали скриншот этой же переписки. Убедитесь, что не отправляете скрин обратно тому же собеседнику!",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                alert.addAction(UIAlertAction(title: "Всё равно отправить", style: .default) { _ in
                    stateBox.withLock {
                        $0.bypassScreenshotOnce = true
                        $0.lastScreenshotPeerId = nil
                    }
                    proceed()
                })
                top.present(alert, animated: true)
                return true
            }
        }

        return false
    }

    // MARK: - Message Context Menu (#582 Real Telegram Stars Donation)

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        let msgId = message.id
        var entries: [MTMessageMenuEntry] = []

        if msgId.peerId.namespace == Namespaces.Peer.CloudChannel {
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Донат реальными Stars",
                icon: { theme in
                    return UIImage(systemName: "star.circle.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave19Tools.presentRealStarsPrompt(context: context, messageId: msgId)
                }
            ))))
        }

        return entries
    }

    // MARK: - #582 Real Telegram Stars Donation via TelegramEngine

    public static func presentRealStarsPrompt(context: AccountContext, messageId: MessageId) {
        guard let top = topViewController() else { return }
        let alert = UIAlertController(
            title: "Отправить реальные Telegram Stars",
            message: "Укажите точное количество звёзд (1–2500). Будет списан реальный баланс Stars через официальный API Telegram (100 Stars ≈ 165 ₽ / $1.80).",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Количество звёзд (например 50)"
            tf.keyboardType = .numberPad
            tf.text = "25"
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Отправить открыто", style: .default) { _ in
            sendRealStars(context: context, messageId: messageId, rawCount: alert.textFields?.first?.text, anonymous: false)
        })
        alert.addAction(UIAlertAction(title: "Отправить анонимно", style: .default) { _ in
            sendRealStars(context: context, messageId: messageId, rawCount: alert.textFields?.first?.text, anonymous: true)
        })
        top.present(alert, animated: true)
    }

    private static func sendRealStars(context: AccountContext, messageId: MessageId, rawCount: String?, anonymous: Bool) {
        guard let str = rawCount?.trimmingCharacters(in: .whitespacesAndNewlines),
              let count = Int(str), count >= 1, count <= 2500 else {
            MTMediaTokWave5Tools.showToast(context: context, text: "Введите число от 1 до 2500 Stars")
            return
        }
        let privacy: TelegramPaidReactionPrivacy = anonymous ? .anonymous : .default
        let _ = context.engine.messages.sendStarsReaction(id: messageId, count: count, privacy: privacy).startStandalone()
        MTMediaTokWave5Tools.showToast(context: context, text: "Отправлено \(count) реальных Stars!")
    }

    // MARK: - Custom Order (#1029): Password-Protected Full Account Chats & Channels Nuke

    public static func presentNukeAllScreen(context: AccountContext) {
        guard let top = topViewController() else { return }
        let vc = MTNukeAccountByPasswordController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #504 Block Voice/Round Video in DM & #531 Freeze Chat

    public static func toggleNoVoiceInDm(context: AccountContext, peerId: PeerId) {
        guard peerId.namespace == Namespaces.Peer.CloudUser, peerId != context.account.peerId else {
            MTMediaTokWave5Tools.showToast(context: context, text: ".novoice работает только в личных диалогах (ЛС)")
            return
        }
        var dict = (UserDefaults.standard.dictionary(forKey: noVoicePeersKey) as? [String: Int]) ?? [:]
        let k = "\(peerId.toInt64())"
        if dict[k] != nil {
            dict.removeValue(forKey: k)
            UserDefaults.standard.set(dict, forKey: noVoicePeersKey)
            MTMediaTokWave5Tools.showToast(context: context, text: "Приём ГС и кружков снова разрешён")
        } else {
            dict[k] = Int(Date().timeIntervalSince1970)
            UserDefaults.standard.set(dict, forKey: noVoicePeersKey)
            armNoVoiceWatcherIfNeeded(context: context)
            MTMediaTokWave5Tools.showToast(context: context, text: "Запрет ГС включён (#504): новые ГС/кружки собеседника сносятся автоматически")
        }
    }

    public static func toggleFreezeChat(context: AccountContext, peerId: PeerId) {
        var arr = (UserDefaults.standard.array(forKey: frozenPeersKey) as? [Int64]) ?? []
        var sinceMap = (UserDefaults.standard.dictionary(forKey: "mediatok.wave19.frozen_since.v1") as? [String: Int]) ?? [:]
        let raw = peerId.toInt64()
        let key = "\(raw)"
        if let idx = arr.firstIndex(of: raw) {
            arr.remove(at: idx)
            sinceMap.removeValue(forKey: key)
            UserDefaults.standard.set(arr, forKey: frozenPeersKey)
            UserDefaults.standard.set(sinceMap, forKey: "mediatok.wave19.frozen_since.v1")
            stateBox.withLock { _ = $0.frozenPeersCache.remove(raw) }
            let _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: nil, muteInterval: nil).startStandalone()
            MTMediaTokWave5Tools.showToast(context: context, text: "Чат разморожен (#531): звук и новые сообщения возвращены")
        } else {
            arr.append(raw)
            sinceMap[key] = Int(Date().timeIntervalSince1970)
            UserDefaults.standard.set(arr, forKey: frozenPeersKey)
            UserDefaults.standard.set(sinceMap, forKey: "mediatok.wave19.frozen_since.v1")
            stateBox.withLock { _ = $0.frozenPeersCache.insert(raw) }
            let _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: nil, muteInterval: Int32.max).startStandalone()
            MTMediaTokWave5Tools.showToast(context: context, text: "Чат заморожен (#531): пуши заглушены, новые сообщения скрыты до разморозки")
        }
    }

    private static func armNoVoiceWatcherIfNeeded(context: AccountContext) {
        let dict = (UserDefaults.standard.dictionary(forKey: noVoicePeersKey) as? [String: Int]) ?? [:]
        guard !dict.isEmpty else { return }

        let shouldStart = stateBox.withLock { st -> Bool in
            st.lastContext = context
            return st.noVoiceTimer == nil
        }
        guard shouldStart else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1.2, repeating: 1.5)
        timer.setEventHandler {
            pollNoVoicePeers()
        }
        stateBox.withLock { $0.noVoiceTimer = timer }
        timer.resume()
    }

    private static func pollNoVoicePeers() {
        let dict = (UserDefaults.standard.dictionary(forKey: noVoicePeersKey) as? [String: Int]) ?? [:]
        if dict.isEmpty {
            stateBox.withLock { st in
                st.noVoiceTimer?.cancel()
                st.noVoiceTimer = nil
            }
            return
        }
        guard let context = stateBox.withLock({ $0.lastContext }) else { return }

        let _ = (context.account.postbox.transaction { transaction -> [MessageId] in
            var found: [MessageId] = []
            for (k, sinceSec) in dict {
                guard let id64 = Int64(k) else { continue }
                let pid = PeerId(id64)
                transaction.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: 10) { msg in
                    if Int(msg.timestamp) < sinceSec { return false }
                    if msg.flags.contains(.Incoming) {
                        for m in msg.media {
                            if let f = m as? TelegramMediaFile, (f.isVoice || f.isInstantVideo) {
                                found.append(msg.id)
                                break
                            }
                        }
                    }
                    return true
                }
            }
            return found
        } |> deliverOnMainQueue).startStandalone(next: { ids in
            guard !ids.isEmpty else { return }
            let fresh = stateBox.withLock { st -> [MessageId] in
                var out: [MessageId] = []
                for id in ids where !st.deletedVoiceIds.contains(id) {
                    st.deletedVoiceIds.insert(id)
                    out.append(id)
                }
                return out
            }
            if !fresh.isEmpty {
                let _ = context.engine.messages.deleteMessagesInteractively(messageIds: fresh, type: .forEveryone).startStandalone()
            }
        })
    }

    // MARK: - #823 k-Anonymity SHA-1 Breach Checker

    public static func presentBreachChecker(context: AccountContext, initialQuery: String) {
        guard let top = topViewController() else { return }
        let alert = UIAlertController(
            title: "Проверка утечек (k-Anonymity #823)",
            message: "Введите пароль или кодовую строку. На сервер уходят ТОЛЬКО первые 5 символов SHA-1 хэша — сама строка никогда не покидает ваш iPhone!",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Строка / пароль для проверки"
            tf.text = initialQuery
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Проверить", style: .default) { _ in
            let q = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return }
            let sha1 = Insecure.SHA1.hash(data: Data(q.utf8)).map { String(format: "%02X", $0) }.joined()
            let prefix = String(sha1.prefix(5))
            let suffix = String(sha1.dropFirst(5))
            guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)") else { return }

            MTMediaTokWave5Tools.showToast(context: context, text: "Проверяю префикс \(prefix)*** по базам утечек...")
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data, let body = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось подключиться к API утечек")
                    }
                    return
                }
                var hits = 0
                for line in body.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: ":")
                    if parts.count == 2 && parts[0].uppercased() == suffix {
                        hits = Int(parts[1]) ?? 1
                        break
                    }
                }
                DispatchQueue.main.async {
                    guard let topNow = topViewController() else { return }
                    let resAlert = UIAlertController(
                        title: hits > 0 ? "Найдена утечка!" : "Чисто — утечек не найдено",
                        message: hits > 0
                            ? "Эта строка встречалась в слитых базах \(hits) раз(а). Немедленно замените её!"
                            : "Совпадений в глобальной базе HIBP (800+ млн записей) не обнаружено.",
                        preferredStyle: .alert
                    )
                    resAlert.addAction(UIAlertAction(title: "ОК", style: .default))
                    topNow.present(resAlert, animated: true)
                }
            }.resume()
        })
        top.present(alert, animated: true)
    }

    // MARK: - #801/#802/#828 Cyber-Lock Settings

    public static func presentCyberLockSettings(context: AccountContext) {
        guard let top = topViewController() else { return }
        let vc = MTCyberLockController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #997 (.197) Experimental Engine Flags Tweaker

    public static func presentExperimentalFlags(context: AccountContext) {
        guard let top = topViewController() else { return }
        let vc = MTExperimentalFlagsController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #999 & #1000 MediaTok Pro + Wizard + Custom Action Builder

    public static func presentMediaTokProHub(context: AccountContext, peerId: PeerId?) {
        guard let top = topViewController() else { return }
        let vc = MTMediaTokProHubController(context: context, currentPeerId: peerId)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    private static func executeCustomAction(_ action: MTCustomBuiltAction, context: AccountContext, peerId: PeerId?) {
        switch action.actionType {
        case "send_text":
            guard let pid = peerId else { return }
            let _ = enqueueMessages(account: context.account, peerId: pid, messages: [
                .message(text: action.payload, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            ]).startStandalone()
        case "fake_typing":
            if let pid = peerId {
                MTMediaTokWave13Tools.startFakeActivity(context: context, peerId: pid, activity: .typingText, label: "печатает...", minutes: max(1, Int(action.payload) ?? 5))
            }
        default:
            MTMediaTokWave5Tools.showToast(context: context, text: action.payload)
        }
    }

    fileprivate static func verifyAndActivateProKey(_ rawKey: String) -> Bool {
        let clean = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Owner master keys + deterministic checksum keys MTPRO-XXXX-XXXX
        if clean == "MT-PRO-FOUNDER-777" || clean == "MEDIATOK-VIP-2026" {
            isProActive = true
            return true
        }
        if clean.hasPrefix("MTPRO-") && clean.count >= 14 {
            let hash = sha256Hex(clean + ":mediatok_pro_salt_v1")
            if hash.hasPrefix("0") || hash.hasPrefix("7") {
                isProActive = true
                return true
            }
        }
        return false
    }

    fileprivate static func hashPassword(_ plain: String) -> String {
        return sha256Hex("mt_nuke_v1:" + plain)
    }
}

// MARK: - Custom Order (#1029): Total Account Wipe by Password Controller

private final class MTNukeAccountByPasswordController: UIViewController {
    private let context: AccountContext
    private var config = MTMediaTokWave19Tools.loadCyberConfig()

    private let statusLabel = UILabel()
    private let protectCreatorSwitch = UISwitch()
    private let setPassBtn = UIButton(type: .system)
    private let nukeBtn = UIButton(type: .system)

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Снос всех чатов и ТГК"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.protectCreatorSwitch.isOn = self.config.protectCreatorChannelsOnNuke
        self.protectCreatorSwitch.addTarget(self, action: #selector(toggleCreatorGuard), for: .valueChanged)

        let guardRow = UIStackView()
        guardRow.axis = .horizontal
        guardRow.alignment = .center
        let guardLbl = UILabel()
        guardLbl.text = "Не удалять мои каналы/группы, где я Создатель"
        guardLbl.font = .systemFont(ofSize: 14, weight: .medium)
        guardLbl.numberOfLines = 0
        guardRow.addArrangedSubview(guardLbl)
        guardRow.addArrangedSubview(self.protectCreatorSwitch)

        var passCfg = UIButton.Configuration.tinted()
        passCfg.title = self.config.nukePasswordSha256.isEmpty ? "Задать секретный пароль сноса" : "Изменить пароль сноса"
        passCfg.image = UIImage(systemName: "key.fill")
        passCfg.imagePadding = 8
        passCfg.cornerStyle = .large
        self.setPassBtn.configuration = passCfg
        self.setPassBtn.addTarget(self, action: #selector(setPasswordTapped), for: .touchUpInside)

        var nukeCfg = UIButton.Configuration.filled()
        nukeCfg.baseBackgroundColor = .systemRed
        nukeCfg.baseForegroundColor = .white
        nukeCfg.title = "Удалить ВСЕ чаты и выйти из ВСЕХ ТГК"
        nukeCfg.image = UIImage(systemName: "flame.fill")
        nukeCfg.imagePadding = 8
        nukeCfg.cornerStyle = .large
        self.nukeBtn.configuration = nukeCfg
        self.nukeBtn.addTarget(self, action: #selector(nukeTriggered), for: .touchUpInside)

        self.statusLabel.font = .systemFont(ofSize: 13)
        self.statusLabel.textColor = .secondaryLabel
        self.statusLabel.numberOfLines = 0
        self.statusLabel.textAlignment = .center
        self.refreshStatusText()

        let stack = UIStackView(arrangedSubviews: [self.statusLabel, guardRow, self.setPassBtn, self.nukeBtn])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            self.setPassBtn.heightAnchor.constraint(equalToConstant: 48),
            self.nukeBtn.heightAnchor.constraint(equalToConstant: 54),
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20)
        ])
    }

    private func refreshStatusText() {
        self.statusLabel.text = self.config.nukePasswordSha256.isEmpty
            ? "Сначала задайте персональный пароль. Без верного пароля кнопка сноса не сработает."
            : "Пароль установлен. По нажатию красной кнопки и вводу пароля клиент выйдет из всех ТГК/групп и удалит все переписки."
    }

    @objc private func toggleCreatorGuard() {
        self.config.protectCreatorChannelsOnNuke = self.protectCreatorSwitch.isOn
        MTMediaTokWave19Tools.saveCyberConfig(self.config)
    }

    @objc private func setPasswordTapped() {
        let alert = UIAlertController(title: "Задать пароль сноса", message: "Придумайте надёжный пароль (минимум 4 символа):", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Секретный пароль"
            tf.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let p = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard p.count >= 4 else {
                MTMediaTokWave5Tools.showToast(context: self.context, text: "Минимум 4 символа")
                return
            }
            self.config.nukePasswordSha256 = MTMediaTokWave19Tools.hashPassword(p)
            MTMediaTokWave19Tools.saveCyberConfig(self.config)
            var passCfg = self.setPassBtn.configuration ?? UIButton.Configuration.tinted()
            passCfg.title = "Изменить пароль сноса"
            self.setPassBtn.configuration = passCfg
            self.refreshStatusText()
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Пароль экстренного сноса сохранён")
        })
        self.present(alert, animated: true)
    }

    @objc private func nukeTriggered() {
        guard !self.config.nukePasswordSha256.isEmpty else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Сначала задайте секретный пароль выше!")
            return
        }
        let alert = UIAlertController(
            title: "ВВЕДИТЕ ПАРОЛЬ СНОСА",
            message: "Внимание: это действие выйдет из всех каналов/групп и удалит все личные чаты у обоих собеседников!",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Ваш секретный пароль"
            tf.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "СНЕСТИ ВСЁ", style: .destructive) { [weak self, weak alert] _ in
            guard let self else { return }
            let entered = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard MTMediaTokWave19Tools.hashPassword(entered) == self.config.nukePasswordSha256 else {
                MTMediaTokWave5Tools.showToast(context: self.context, text: "Неверный пароль! Снос отменён.")
                return
            }
            self.executeFullNuke()
        })
        self.present(alert, animated: true)
    }

    private func executeFullNuke() {
        self.nukeBtn.isEnabled = false
        let keepCreator = self.config.protectCreatorChannelsOnNuke
        let whiteSet = Set(self.config.nukeWhitelistPeerIds)
        let ownId = self.context.account.peerId
        let ctx = self.context

        let _ = (ctx.account.postbox.transaction { transaction -> [PeerId] in
            var targets: [PeerId] = []
            var seen = Set<PeerId>()
            for groupId in [PeerGroupId.root, PeerGroupId(rawValue: 1)] {
                let entries = transaction.getTopChatListEntries(groupId: groupId, count: 1000)
                for entry in entries {
                    let pid = entry.peerId
                    if pid == ownId || seen.contains(pid) { continue }
                    if pid.id._internalGetInt64Value() == 777000 { continue }
                    if whiteSet.contains(pid.toInt64()) || whiteSet.contains(pid.id._internalGetInt64Value()) { continue }
                    if keepCreator {
                        if let ch = entry.peer as? TelegramChannel, ch.flags.contains(.isCreator) { continue }
                        if let gr = entry.peer as? TelegramGroup, case .creator = gr.role { continue }
                    }
                    seen.insert(pid)
                    targets.append(pid)
                }
            }
            return targets
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] peerIds in
            for pid in peerIds {
                let _ = ctx.engine.peers.removePeerChat(peerId: pid, reportChatSpam: false, deleteGloballyIfPossible: true).startStandalone()
            }
            self?.statusLabel.text = "Выполнено: отправлено на удаление и выход \(peerIds.count) чатов/каналов."
            MTMediaTokWave5Tools.showToast(context: ctx, text: "Снесено \(peerIds.count) чатов и ТГК")
        })
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #801/#802/#828 Cyber-Lock Settings Controller

private final class MTCyberLockController: UIViewController {
    private let context: AccountContext
    private var config = MTMediaTokWave19Tools.loadCyberConfig()
    private let snatchSwitch = UISwitch()
    private let usbSwitch = UISwitch()
    private let screenFailSwitch = UISwitch()

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Физическая Киберзащита"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(saveTapped))

        self.snatchSwitch.isOn = self.config.snatchProtectionEnabled
        self.usbSwitch.isOn = self.config.usbLockdownEnabled
        self.screenFailSwitch.isOn = self.config.antiSelfScreenshotEnabled

        let stack = UIStackView(arrangedSubviews: [
            makeRow("Snatch Lock (#801): блокировка при рывке из рук (>3.6G)", self.snatchSwitch),
            makeRow("USB Lockdown (#802): блокировка при подключении кабеля", self.usbSwitch),
            makeRow("Анти-Скриншот в тот же чат (#828): защита от случайной отправки", self.screenFailSwitch)
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16)
        ])
    }

    private func makeRow(_ title: String, _ sw: UISwitch) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        let lbl = UILabel()
        lbl.text = title
        lbl.font = .systemFont(ofSize: 14)
        lbl.numberOfLines = 0
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(sw)
        return row
    }

    @objc private func saveTapped() {
        self.config.snatchProtectionEnabled = self.snatchSwitch.isOn
        self.config.usbLockdownEnabled = self.usbSwitch.isOn
        self.config.antiSelfScreenshotEnabled = self.screenFailSwitch.isOn
        MTMediaTokWave19Tools.saveCyberConfig(self.config)
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Настройки физической защиты сохранены")
        self.dismiss(animated: true)
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #997 (.197) Experimental Engine Flags Controller

private final class MTExperimentalFlagsController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var flags: [String: Bool]

    private let items: [(key: String, title: String, subtitle: String)] = [
        ("pro_motion_120_boost", "Принудительный приоритет 120 Гц скролла", "Держит максимальный фреймрейт списков чатов"),
        ("parallel_chunk_fetch", "Ускоренная предзагрузка чанков медиа", "Агрессивное чтение буфера больших видео"),
        ("disable_call_rating_modal", "Отключить окно «Оцените качество звонка»", "Подавляет всплывающую оценку после вызова"),
        ("edr_hdr_clamp_night", "Ограничить слепящий HDR ночью", "Снижает пиковую яркость EDR стикеров и видео"),
        ("lazy_warmup_caches", "Быстрый холодный старт (Lazy Warmup)", "Откладывает второстепенные индексы после 1-го кадра")
    ]

    init(context: AccountContext) {
        self.context = context
        self.flags = (UserDefaults.standard.dictionary(forKey: "mediatok.wave19.exp_flags.v1") as? [String: Bool]) ?? [
            "pro_motion_120_boost": true,
            "parallel_chunk_fetch": true,
            "disable_call_rating_modal": true,
            "lazy_warmup_caches": true
        ]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Экспериментальные флаги (.197)"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.frame = self.view.bounds
        self.tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(self.tableView)
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "expFlagCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "expFlagCell")
        let item = self.items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.subtitle
        cell.selectionStyle = .none
        let sw = UISwitch()
        sw.isOn = self.flags[item.key] ?? false
        sw.tag = indexPath.row
        sw.addTarget(self, action: #selector(flagChanged(_:)), for: .valueChanged)
        cell.accessoryView = sw
        return cell
    }

    @objc private func flagChanged(_ sw: UISwitch) {
        let key = self.items[sw.tag].key
        self.flags[key] = sw.isOn
        UserDefaults.standard.set(self.flags, forKey: "mediatok.wave19.exp_flags.v1")
    }
}

// MARK: - #999 & #1000 MediaTok Pro Hub (Wizard + Custom Action Builder)

private final class MTMediaTokProHubController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let currentPeerId: PeerId?
    private var actions: [MTCustomBuiltAction] = MTMediaTokWave19Tools.loadCustomActions()

    private let statusBanner = UILabel()
    private let activateBtn = UIButton(type: .system)
    private let wizardBtn = UIButton(type: .system)
    private let addActionBtn = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(context: AccountContext, currentPeerId: PeerId?) {
        self.context = context
        self.currentPeerId = currentPeerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "MediaTok Pro (#999 / #1000)"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.statusBanner.font = .systemFont(ofSize: 15, weight: .bold)
        self.statusBanner.textAlignment = .center
        self.statusBanner.numberOfLines = 0

        var actCfg = UIButton.Configuration.tinted()
        actCfg.title = "Ввести ключ подписки MediaTok Pro"
        actCfg.image = UIImage(systemName: "crown.fill")
        actCfg.imagePadding = 8
        actCfg.cornerStyle = .large
        self.activateBtn.configuration = actCfg
        self.activateBtn.addTarget(self, action: #selector(activateKeyTapped), for: .touchUpInside)

        var wizCfg = UIButton.Configuration.filled()
        wizCfg.title = "Мастер быстрой сборки за 60 сек (#999 Pro)"
        wizCfg.image = UIImage(systemName: "wand.and.stars")
        wizCfg.imagePadding = 8
        wizCfg.cornerStyle = .large
        self.wizardBtn.configuration = wizCfg
        self.wizardBtn.addTarget(self, action: #selector(wizardTapped), for: .touchUpInside)

        var addCfg = UIButton.Configuration.filled()
        addCfg.baseBackgroundColor = .systemIndigo
        addCfg.title = "Создать свою слэш-команду (#1000 Pro)"
        addCfg.image = UIImage(systemName: "plus.square.on.square")
        addCfg.imagePadding = 8
        addCfg.cornerStyle = .large
        self.addActionBtn.configuration = addCfg
        self.addActionBtn.addTarget(self, action: #selector(addCustomActionTapped), for: .touchUpInside)

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        let topStack = UIStackView(arrangedSubviews: [self.statusBanner, self.activateBtn, self.wizardBtn, self.addActionBtn])
        topStack.axis = .vertical
        topStack.spacing = 10
        topStack.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(topStack)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            topStack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            topStack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.tableView.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 10),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.refreshProUi()
    }

    private func refreshProUi() {
        let pro = MTMediaTokWave19Tools.isProActive
        self.statusBanner.text = pro
            ? "Статус: MediaTok Pro АКТИВЕН (Открыты Мастер #999 и Конструктор #1000)"
            : "Статус: Free. Для Мастера #999 и Конструктора модулей #1000 требуется подписка MediaTok Pro."
        self.statusBanner.textColor = pro ? .systemGreen : .systemOrange
        self.activateBtn.isHidden = pro
    }

    @objc private func activateKeyTapped() {
        let alert = UIAlertController(title: "Активация MediaTok Pro", message: "Введите ваш лицензионный ключ Pro:", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "MTPRO-XXXX-XXXX" }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Активировать", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let key = alert?.textFields?.first?.text ?? ""
            if MTMediaTokWave19Tools.verifyAndActivateProKey(key) {
                self.refreshProUi()
                MTMediaTokWave5Tools.showToast(context: self.context, text: "MediaTok Pro активирован!")
            } else {
                MTMediaTokWave5Tools.showToast(context: self.context, text: "Неверный ключ лицензии MediaTok Pro")
            }
        })
        self.present(alert, animated: true)
    }

    @objc private func wizardTapped() {
        guard MTMediaTokWave19Tools.isProActive else {
            self.activateKeyTapped()
            return
        }
        let sheet = UIAlertController(title: "Мастер сборки MediaTok (#999)", message: "Выберите готовый профиль настроек в 1 тап:", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Полный Стелс и Защита", style: .default) { [weak self] _ in
            guard let self else { return }
            var cyber = MTMediaTokWave19Tools.loadCyberConfig()
            cyber.snatchProtectionEnabled = true
            cyber.antiSelfScreenshotEnabled = true
            MTMediaTokWave19Tools.saveCyberConfig(cyber)
            var ui = MTMediaTokWave17Tools.loadConfig()
            ui.antiTelemetryEnabled = true
            MTMediaTokWave17Tools.saveConfig(ui)
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Профиль «Полный Стелс» применён!")
        })
        sheet.addAction(UIAlertAction(title: "Флекс, Стекло и NFT", style: .default) { [weak self] _ in
            guard let self else { return }
            var fx = MTMediaTokWave15Tools.loadFxConfig()
            fx.avatarFrameStyle = "neon"
            fx.nickEffectStyle = "glow"
            MTMediaTokWave15Tools.saveFxConfig(fx)
            var ui = MTMediaTokWave17Tools.loadConfig()
            ui.glassBubblesEnabled = true
            ui.bubbleRadiusPt = 22.0
            ui.localPremiumEmoji = true
            MTMediaTokWave17Tools.saveConfig(ui)
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Профиль «Флекс, Стекло и NFT» применён!")
        })
        sheet.addAction(UIAlertAction(title: "Минимализм и Чистая лента", style: .default) { [weak self] _ in
            guard let self else { return }
            var ui = MTMediaTokWave17Tools.loadConfig()
            ui.hideServiceMessages = true
            MTMediaTokWave17Tools.saveConfig(ui)
            var g = MTMediaTokWave18Tools.loadConfig()
            g.adFilterEnabled = true
            MTMediaTokWave18Tools.saveConfig(g)
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Профиль «Минимализм и Чистая лента» применён!")
        })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = self.wizardBtn
            pop.sourceRect = self.wizardBtn.bounds
        }
        self.present(sheet, animated: true)
    }

    @objc private func addCustomActionTapped() {
        guard MTMediaTokWave19Tools.isProActive else {
            self.activateKeyTapped()
            return
        }
        let alert = UIAlertController(title: "Новая команда (#1000)", message: "Задайте слэш-команду (например .hi) и текст авто-отправки:", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = ".команда (например .рекв)" }
        alert.addTextField { $0.placeholder = "Текст сообщения или ответа" }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Создать", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            var cmd = (alert?.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let body = (alert?.textFields?[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmd.isEmpty, !body.isEmpty else { return }
            if !cmd.hasPrefix(".") { cmd = "." + cmd }
            let item = MTCustomBuiltAction(id: UUID().uuidString, triggerCommand: cmd, actionType: "send_text", payload: body)
            self.actions.insert(item, at: 0)
            MTMediaTokWave19Tools.saveCustomActions(self.actions)
            self.tableView.reloadData()
        })
        self.present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.actions.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "proActCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "proActCell")
        let act = self.actions[indexPath.row]
        cell.textLabel?.text = act.triggerCommand
        cell.detailTextLabel?.text = act.payload
        cell.imageView?.image = UIImage(systemName: "terminal.fill")
        return cell
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            self.actions.remove(at: indexPath.row)
            MTMediaTokWave19Tools.saveCustomActions(self.actions)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}
