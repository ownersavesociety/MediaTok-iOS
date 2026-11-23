import Foundation
import UIKit
import CommonCrypto
import CoreMotion
import CryptoKit
import LocalAuthentication
import Security
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
        antiSelfScreenshotEnabled: false,
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
    fileprivate static let expFlagsKey = "mediatok.wave19.exp_flags.v1"

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
            if shouldWarn {
                mtPresentNativeAlert(
                    context: request.context,
                    title: "Стоп! Недавний скриншот этого чата",
                    text: "Вы меньше минуты назад сделали скриншот этой же переписки. Убедитесь, что не отправляете скрин обратно тому же собеседнику!",
                    confirmTitle: "Всё равно отправить",
                    destructive: false,
                    confirmAction: {
                        stateBox.withLock {
                            $0.bypassScreenshotOnce = true
                            $0.lastScreenshotPeerId = nil
                        }
                        proceed()
                    }
                )
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
        let controller = makeNukeAccountByPasswordController(context: context)
        mtPushNativeController(controller, context: context)
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
            tf.isSecureTextEntry = true
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
                    mtPresentNativeAlert(
                        context: context,
                        title: hits > 0 ? "Найдена утечка!" : "Чисто — утечек не найдено",
                        text: hits > 0
                            ? "Эта строка встречалась в слитых базах \(hits) раз(а). Немедленно замените её!"
                            : "Совпадений в глобальной базе HIBP (800+ млн записей) не обнаружено."
                    )
                }
            }.resume()
        })
        top.present(alert, animated: true)
    }

    // MARK: - #801/#802/#828 Cyber-Lock Settings

    public static func presentCyberLockSettings(context: AccountContext) {
        let controller = makeCyberLockController(context: context)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #997 (.197) Experimental Engine Flags Tweaker

    public static func presentExperimentalFlags(context: AccountContext) {
        let controller = makeExperimentalFlagsController(context: context)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #999 & #1000 MediaTok Pro + Wizard + Custom Action Builder

    public static func presentMediaTokProHub(context: AccountContext, peerId: PeerId?) {
        let controller = makeMediaTokProHubController(context: context, currentPeerId: peerId)
        mtPushNativeController(controller, context: context)
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

    private static let nukeKeychainService = "org.mediatok.wave19.nuke"
    private static let nukeKeychainAccount = "nuke_pbkdf2_v2"

    private static func deriveNukePbkdf2(password: String, salt: Data) -> Data? {
        let pwData = Data(password.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { outBuf in
            salt.withUnsafeBytes { saltBuf in
                pwData.withUnsafeBytes { pwBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwBuf.bindMemory(to: Int8.self).baseAddress,
                        pwData.count,
                        saltBuf.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        100_000,
                        outBuf.bindMemory(to: UInt8.self).baseAddress,
                        32
                    )
                }
            }
        }
        return status == kCCSuccess ? derived : nil
    }

    private static func loadNukeKeychainRecord() -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: nukeKeychainService,
            kSecAttrAccount as String: nukeKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }

    fileprivate static func storeNukePassword(_ plain: String) {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard let dk = deriveNukePbkdf2(password: plain, salt: salt) else { return }
        var blob = Data()
        blob.append(salt)
        blob.append(dk)
        let delQ: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: nukeKeychainService,
            kSecAttrAccount as String: nukeKeychainAccount
        ]
        SecItemDelete(delQ as CFDictionary)
        let addQ: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: nukeKeychainService,
            kSecAttrAccount as String: nukeKeychainAccount,
            kSecValueData as String: blob,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        _ = SecItemAdd(addQ as CFDictionary, nil)
    }

    fileprivate static func hasNukePassword(legacySha256: String) -> Bool {
        if let blob = loadNukeKeychainRecord(), blob.count == 48 {
            return true
        }
        return !legacySha256.isEmpty
    }

    fileprivate static func verifyNukePassword(_ plain: String, legacySha256: String) -> Bool {
        if let blob = loadNukeKeychainRecord(), blob.count == 48 {
            let salt = blob.prefix(16)
            let expected = blob.suffix(32)
            guard let actual = deriveNukePbkdf2(password: plain, salt: salt), actual.count == 32 else { return false }
            var diff: UInt8 = 0
            for i in 0 ..< 32 {
                diff |= actual[actual.startIndex + i] ^ expected[expected.startIndex + i]
            }
            return diff == 0
        }
        if !legacySha256.isEmpty && hashPassword(plain) == legacySha256 {
            // Auto-migrate legacy SHA-256 to salted PBKDF2 in Keychain
            storeNukePassword(plain)
            return true
        }
        return false
    }

    fileprivate static func hashPassword(_ plain: String) -> String {
        return sha256Hex("mt_nuke_v1:" + plain)
    }

    fileprivate static func presentTopAlert(_ alert: UIAlertController) {
        DispatchQueue.main.async {
            topViewController()?.present(alert, animated: true)
        }
    }
}

// MARK: - Custom Order (#1029): Native ItemListController for Total Account Wipe by Password

private func makeNukeAccountByPasswordController(context: AccountContext) -> ViewController {
    struct NukeScreenState: Equatable {
        var config: MTCyberLockConfig
        var statusNote: String?
        var isRunning: Bool
    }
    let statePromise = ValuePromise(NukeScreenState(config: MTMediaTokWave19Tools.loadCyberConfig(), statusNote: nil, isRunning: false), ignoreRepeated: true)
    let stateValue = Atomic(value: NukeScreenState(config: MTMediaTokWave19Tools.loadCyberConfig(), statusNote: nil, isRunning: false))
    let updateState: ((inout NukeScreenState) -> Void) -> Void = { f in
        let next = stateValue.modify { current in
            var copy = current
            f(&copy)
            return copy
        }
        statePromise.set(next)
    }

    let modelSignal = statePromise.get()
    |> map { state -> MTNativeScreenModel in
        var model = MTNativeScreenModel(title: "Снос всех чатов и ТГК")
        let hasPass = MTMediaTokWave19Tools.hasNukePassword(legacySha256: state.config.nukePasswordSha256)
        let infoText: String
        if let statusNote = state.statusNote {
            infoText = statusNote
        } else if !hasPass {
            infoText = "Сначала задайте персональный пароль. Без верного пароля кнопка сноса не сработает."
        } else {
            infoText = "Пароль защищён (PBKDF2-HMAC-SHA256 в Keychain). По нажатию кнопки и вводу пароля клиент выйдет из всех ТГК/групп и удалит все переписки."
        }

        let wlCount = state.config.nukeWhitelistPeerIds.count
        model.sections = [
            [
                MTNativeRow(id: "hdr_guard", kind: .header("Защита при сносе")),
                MTNativeRow(id: "info", kind: .info(infoText)),
                MTNativeRow(id: "creator_guard", kind: .toggle(title: "Не удалять мои каналы/группы (Создатель)", value: state.config.protectCreatorChannelsOnNuke, enabled: !state.isRunning)),
                MTNativeRow(id: "ftr_guard", kind: .footer("Чатов в неприкосновенном Белом списке (.nukewhite): \(wlCount)"))
            ],
            [
                MTNativeRow(id: "hdr_pass", kind: .header("Секретный пароль (Keychain)")),
                MTNativeRow(id: "set_pass", kind: .action(title: hasPass ? "Изменить пароль сноса" : "Задать секретный пароль сноса", destructive: false, enabled: !state.isRunning)),
                MTNativeRow(id: "run_nuke", kind: .action(title: "Удалить ВСЕ чаты и выйти из ВСЕХ ТГК", destructive: true, enabled: hasPass && !state.isRunning)),
                MTNativeRow(id: "ftr_nuke", kind: .footer("Действие необратимо удалит личные переписки у обоих собеседников и выйдет из групп и каналов."))
            ]
        ]

        model.toggle["creator_guard"] = { isOn in
            updateState { st in
                st.config.protectCreatorChannelsOnNuke = isOn
                MTMediaTokWave19Tools.saveCyberConfig(st.config)
            }
        }

        model.tap["set_pass"] = {
            let alert = UIAlertController(title: "Задать пароль сноса", message: "Придумайте надёжный пароль (минимум 4 символа):", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.placeholder = "Секретный пароль"
                tf.isSecureTextEntry = true
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak alert] _ in
                let p = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard p.count >= 4 else {
                    mtPresentNativeToast(context: context, text: "Минимум 4 символа")
                    return
                }
                MTMediaTokWave19Tools.storeNukePassword(p)
                updateState { st in
                    st.config.nukePasswordSha256 = ""
                    st.statusNote = nil
                    MTMediaTokWave19Tools.saveCyberConfig(st.config)
                }
                mtPresentNativeToast(context: context, text: "Пароль экстренного сноса сохранён в Keychain")
            })
            MTMediaTokWave19Tools.presentTopAlert(alert)
        }

        model.tap["run_nuke"] = {
            let currentCfg = stateValue.with { $0.config }
            guard MTMediaTokWave19Tools.hasNukePassword(legacySha256: currentCfg.nukePasswordSha256) else {
                mtPresentNativeToast(context: context, text: "Сначала задайте секретный пароль!")
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
            alert.addAction(UIAlertAction(title: "СНЕСТИ ВСЁ", style: .destructive) { [weak alert] _ in
                let entered = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let snapCfg = stateValue.with { $0.config }
                guard MTMediaTokWave19Tools.verifyNukePassword(entered, legacySha256: snapCfg.nukePasswordSha256) else {
                    mtPresentNativeToast(context: context, text: "Неверный пароль! Снос отменён.")
                    return
                }
                updateState { $0.isRunning = true }
                let keepCreator = snapCfg.protectCreatorChannelsOnNuke
                let whiteSet = Set(snapCfg.nukeWhitelistPeerIds)
                let ownId = context.account.peerId
                let _ = (context.account.postbox.transaction { transaction -> [PeerId] in
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
                } |> deliverOnMainQueue).startStandalone(next: { peerIds in
                    for pid in peerIds {
                        let _ = context.engine.peers.removePeerChat(peerId: pid, reportChatSpam: false, deleteGloballyIfPossible: true).startStandalone()
                    }
                    updateState { st in
                        st.isRunning = false
                        st.statusNote = "Выполнено: отправлено на удаление и выход \(peerIds.count) чатов и каналов."
                    }
                    mtPresentNativeToast(context: context, text: "Снесено \(peerIds.count) чатов и ТГК")
                })
            })
            MTMediaTokWave19Tools.presentTopAlert(alert)
        }

        return model
    }
    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #801/#802/#828 Native ItemListController for Cyber-Lock Settings

private func makeCyberLockController(context: AccountContext) -> ViewController {
    let initial = MTMediaTokWave19Tools.loadCyberConfig()
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let updateConfig: ((inout MTCyberLockConfig) -> Void) -> Void = { f in
        let next = stateValue.modify { current in
            var copy = current
            f(&copy)
            return copy
        }
        MTMediaTokWave19Tools.saveCyberConfig(next)
        statePromise.set(next)
    }

    let modelSignal = statePromise.get()
    |> map { cfg -> MTNativeScreenModel in
        var model = MTNativeScreenModel(title: "Физическая Киберзащита")
        model.sections = [
            [
                MTNativeRow(id: "hdr_phys", kind: .header("Датчики устройства")),
                MTNativeRow(id: "snatch", kind: .toggle(title: "Snatch Lock (рывок >3.6G)", value: cfg.snatchProtectionEnabled, enabled: true)),
                MTNativeRow(id: "usb", kind: .toggle(title: "USB Lockdown (подключение кабеля)", value: cfg.usbLockdownEnabled, enabled: true)),
                MTNativeRow(id: "ftr_phys", kind: .footer("Мгновенно закрывает интерфейс экраном блокировки с разблокировкой по FaceID / паролю iOS."))
            ],
            [
                MTNativeRow(id: "hdr_chat", kind: .header("Защита переписки")),
                MTNativeRow(id: "antiscreen", kind: .toggle(title: "Анти-Скриншот в тот же чат", value: cfg.antiSelfScreenshotEnabled, enabled: true)),
                MTNativeRow(id: "ftr_chat", kind: .footer("Предупреждает при отправке сообщения в течение 75 секунд после скриншота этой же переписки."))
            ],
            [
                MTNativeRow(id: "hdr_tools", kind: .header("Проверка безопасности")),
                MTNativeRow(id: "breach", kind: .action(title: "Проверить пароль на утечки (k-Anonymity)", destructive: false, enabled: true)),
                MTNativeRow(id: "test_lock", kind: .action(title: "Проверить шторку блокировки сейчас", destructive: false, enabled: true))
            ]
        ]

        model.toggle["snatch"] = { val in
            updateConfig { $0.snatchProtectionEnabled = val }
        }
        model.toggle["usb"] = { val in
            updateConfig { $0.usbLockdownEnabled = val }
        }
        model.toggle["antiscreen"] = { val in
            updateConfig { $0.antiSelfScreenshotEnabled = val }
        }
        model.tap["breach"] = {
            MTMediaTokWave19Tools.presentBreachChecker(context: context, initialQuery: "")
        }
        model.tap["test_lock"] = {
            MTMediaTokWave19Tools.engageEmergencyLockCurtain(reason: "Тестовая проверка шторки безопасности MediaTok")
        }
        return model
    }
    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #997 (.197) Native ItemListController for Experimental Engine Flags

private func makeExperimentalFlagsController(context: AccountContext) -> ViewController {
    let defaultFlags: [String: Bool] = [
        "parallel_chunk_fetch": true,
        "disable_call_rating_modal": true
    ]
    let initialFlags = (UserDefaults.standard.dictionary(forKey: MTMediaTokWave19Tools.expFlagsKey) as? [String: Bool]) ?? defaultFlags
    let statePromise = ValuePromise(initialFlags, ignoreRepeated: true)
    let stateValue = Atomic(value: initialFlags)

    let items: [(key: String, title: String, footer: String)] = [
        ("parallel_chunk_fetch", "Ускоренная предзагрузка чанков медиа", "Включает многопоточное чтение крупных медиафайлов (>1 МБ) в сетевом движке."),
        ("disable_call_rating_modal", "Отключить окно оценки звонка", "Подавляет всплывающее модальное окно оценки качества после завершения вызова.")
    ]

    let modelSignal = statePromise.get()
    |> map { flags -> MTNativeScreenModel in
        var model = MTNativeScreenModel(title: "Экспериментальные флаги")
        var sections: [[MTNativeRow]] = []
        for item in items {
            sections.append([
                MTNativeRow(id: "flag_\(item.key)", kind: .toggle(title: item.title, value: flags[item.key] ?? false, enabled: true)),
                MTNativeRow(id: "ftr_\(item.key)", kind: .footer(item.footer))
            ])
            model.toggle["flag_\(item.key)"] = { isOn in
                let next = stateValue.modify { current in
                    var copy = current
                    copy[item.key] = isOn
                    return copy
                }
                UserDefaults.standard.set(next, forKey: MTMediaTokWave19Tools.expFlagsKey)
                statePromise.set(next)
            }
        }
        model.sections = sections
        return model
    }
    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #999 & #1000 Native ItemListController for MediaTok Pro Hub

private func makeMediaTokProHubController(context: AccountContext, currentPeerId: PeerId?) -> ViewController {
    struct ProHubState: Equatable {
        var isPro: Bool
        var actions: [MTCustomBuiltAction]
    }
    let initial = ProHubState(isPro: MTMediaTokWave19Tools.isProActive, actions: MTMediaTokWave19Tools.loadCustomActions())
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let updateState: ((inout ProHubState) -> Void) -> Void = { f in
        let next = stateValue.modify { current in
            var copy = current
            f(&copy)
            return copy
        }
        statePromise.set(next)
    }

    let promptActivateKey: () -> Void = {
        mtPresentNativePrompt(
            context: context,
            title: "Активация MediaTok Pro",
            subtitle: "Введите лицензионный ключ подписки:",
            placeholder: "MTPRO-XXXX-XXXX",
            apply: { rawKey in
                if MTMediaTokWave19Tools.verifyAndActivateProKey(rawKey) {
                    updateState { $0.isPro = true }
                    mtPresentNativeToast(context: context, text: "MediaTok Pro активирован!")
                } else {
                    mtPresentNativeToast(context: context, text: "Неверный ключ лицензии MediaTok Pro")
                }
            }
        )
    }

    let modelSignal = statePromise.get()
    |> map { state -> MTNativeScreenModel in
        var model = MTNativeScreenModel(title: "MediaTok Pro")

        var statusSection: [MTNativeRow] = [
            MTNativeRow(id: "hdr_status", kind: .header("Статус лицензии")),
            MTNativeRow(id: "status_info", kind: .info(state.isPro
                ? "Статус: MediaTok Pro АКТИВЕН. Доступны Мастер быстрой настройки и Конструктор слэш-команд."
                : "Статус: Free. Для Мастера сборки и Конструктора слэш-команд активируйте ключ MediaTok Pro."))
        ]
        if !state.isPro {
            statusSection.append(MTNativeRow(id: "activate_pro", kind: .action(title: "Ввести ключ подписки MediaTok Pro", destructive: false, enabled: true)))
        }

        var toolsSection: [MTNativeRow] = [
            MTNativeRow(id: "hdr_tools", kind: .header("Инструменты Pro")),
            MTNativeRow(id: "wizard", kind: .action(title: "Мастер быстрой настройки (1 тап)", destructive: false, enabled: true)),
            MTNativeRow(id: "add_cmd", kind: .action(title: "Создать свою слэш-команду", destructive: false, enabled: true))
        ]
        if let currentPeerId {
            toolsSection.append(MTNativeRow(id: "freeze_peer", kind: .action(title: "Заморозить / разморозить текущий чат", destructive: false, enabled: true)))
            model.tap["freeze_peer"] = {
                MTMediaTokWave19Tools.toggleFreezeChat(context: context, peerId: currentPeerId)
            }
        }

        var customSection: [MTNativeRow] = [
            MTNativeRow(id: "hdr_cmds", kind: .header("Мои слэш-команды"))
        ]
        if state.actions.isEmpty {
            customSection.append(MTNativeRow(id: "empty_cmds", kind: .footer("Пользовательских команд пока нет. Создайте команду вроде .рекв для мгновенной отправки текста.")))
        } else {
            for act in state.actions {
                let rowId = "act_\(act.id)"
                customSection.append(MTNativeRow(id: rowId, kind: .disclosure(title: act.triggerCommand, label: String(act.payload.prefix(24)), icon: nil, enabled: true)))
                model.tap[rowId] = {
                    mtPresentNativeActionSheet(
                        context: context,
                        title: "\(act.triggerCommand)\n\(act.payload)",
                        buttons: [
                            (title: "Скопировать текст", isDestructive: false, action: {
                                UIPasteboard.general.string = act.payload
                                mtPresentNativeToast(context: context, text: "Текст команды скопирован")
                            }),
                            (title: "Удалить команду", isDestructive: true, action: {
                                updateState { st in
                                    st.actions.removeAll { $0.id == act.id }
                                    MTMediaTokWave19Tools.saveCustomActions(st.actions)
                                }
                                mtPresentNativeToast(context: context, text: "Команда \(act.triggerCommand) удалена")
                            })
                        ]
                    )
                }
            }
        }

        model.sections = [statusSection, toolsSection, customSection]

        model.tap["activate_pro"] = {
            promptActivateKey()
        }

        model.tap["wizard"] = {
            guard stateValue.with({ $0.isPro }) else {
                promptActivateKey()
                return
            }
            mtPresentNativeActionSheet(
                context: context,
                title: "Выберите готовый профиль настроек MediaTok:",
                buttons: [
                    (title: "Полный Стелс и Защита", isDestructive: false, action: {
                        var cyber = MTMediaTokWave19Tools.loadCyberConfig()
                        cyber.snatchProtectionEnabled = true
                        cyber.antiSelfScreenshotEnabled = true
                        MTMediaTokWave19Tools.saveCyberConfig(cyber)
                        var ui = MTMediaTokWave17Tools.loadConfig()
                        ui.antiTelemetryEnabled = true
                        MTMediaTokWave17Tools.saveConfig(ui)
                        mtPresentNativeToast(context: context, text: "Профиль «Полный Стелс» применён!")
                    }),
                    (title: "Флекс, Стекло и NFT", isDestructive: false, action: {
                        var fx = MTMediaTokWave15Tools.loadFxConfig()
                        fx.avatarFrameStyle = "neon"
                        fx.nickEffectStyle = "glow"
                        MTMediaTokWave15Tools.saveFxConfig(fx)
                        var ui = MTMediaTokWave17Tools.loadConfig()
                        ui.glassBubblesEnabled = true
                        ui.bubbleRadiusPt = 22.0
                        ui.localPremiumEmoji = true
                        MTMediaTokWave17Tools.saveConfig(ui)
                        mtPresentNativeToast(context: context, text: "Профиль «Флекс, Стекло и NFT» применён!")
                    }),
                    (title: "Минимализм и Чистая лента", isDestructive: false, action: {
                        var ui = MTMediaTokWave17Tools.loadConfig()
                        ui.hideServiceMessages = true
                        MTMediaTokWave17Tools.saveConfig(ui)
                        var g = MTMediaTokWave18Tools.loadConfig()
                        g.adFilterEnabled = true
                        MTMediaTokWave18Tools.saveConfig(g)
                        mtPresentNativeToast(context: context, text: "Профиль «Минимализм и Чистая лента» применён!")
                    })
                ]
            )
        }

        model.tap["add_cmd"] = {
            guard stateValue.with({ $0.isPro }) else {
                promptActivateKey()
                return
            }
            mtPresentNativePrompt(
                context: context,
                title: "Шаг 1: Слэш-команда",
                subtitle: "Например .рекв или .привет",
                placeholder: ".рекв",
                apply: { rawCmd in
                    var cmd = rawCmd.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cmd.isEmpty else { return }
                    if !cmd.hasPrefix(".") { cmd = "." + cmd }
                    mtPresentNativePrompt(
                        context: context,
                        title: "Шаг 2: Текст авто-отправки",
                        subtitle: "Команда: \(cmd)",
                        placeholder: "Текст сообщения",
                        apply: { rawBody in
                            let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !body.isEmpty else { return }
                            let item = MTCustomBuiltAction(id: UUID().uuidString, triggerCommand: cmd, actionType: "send_text", payload: body)
                            updateState { st in
                                st.actions.insert(item, at: 0)
                                MTMediaTokWave19Tools.saveCustomActions(st.actions)
                            }
                            mtPresentNativeToast(context: context, text: "Команда \(cmd) создана!")
                        }
                    )
                }
            )
        }

        return model
    }
    return mtMakeNativeListController(context: context, model: modelSignal)
}
