import Foundation
import UIKit
import AudioToolbox
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
// MediaTok Wave 25 — Live Userbot Sniper, OTC Bio-Scam Guard & Scroll Return:
//   #1002/#1003 / .firstcom — Auto-First-Comment Sniper on selected channels with spin-syntax randomizer
//   #1005 / .promosnipe     — Regex Promo-Code & Voucher Auto-Catcher (instant clipboard + sound alert)
//   #1065 / .otcguard       — OTC Bio Fake-@username Scam Detector (red alert banner on spoofed guarantor bio)
//   #1037                   — Exact Read-Receipt Timestamp Sniffer in DM ("Прочитано в 18:42:09")
//   #1346                   — Quick "Back to Last Read Position" jump helper in chats
//   #1440 / .help           — Interactive Russian Slash-Commands Reference Hub (all Wave 4..25 commands)
// ============================================================================

private final class MTWave25Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body(&self.value)
    }
}

public struct MTWave25Config: Codable, Equatable {
    public var firstCommentEnabled: Bool
    public var firstCommentChannelIds: [Int64]
    public var firstCommentSpinTemplate: String
    public var promoSnipeEnabled: Bool
    public var promoRegexPattern: String
    public var otcBioScamGuardEnabled: Bool
    public var exactReadTimestampEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case firstCommentEnabled
        case firstCommentChannelIds
        case firstCommentSpinTemplate
        case promoSnipeEnabled
        case promoRegexPattern
        case otcBioScamGuardEnabled
        case exactReadTimestampEnabled
    }

    public static let `default` = MTWave25Config(
        firstCommentEnabled: false,
        firstCommentChannelIds: [],
        firstCommentSpinTemplate: "{Сильно|По делу|Топ}, {ждём продолжения|плюсую|чётко}!",
        promoSnipeEnabled: false,
        promoRegexPattern: "(?i)(?:promo|код|ваучер|voucher)[:\\s#-]*([A-Z0-9_-]{5,18})",
        otcBioScamGuardEnabled: true,
        exactReadTimestampEnabled: true
    )
}

public enum MTMediaTokWave25Tools {
    private static let configKey = "mediatok.wave25.config.v1"
    private static let readTimesKey = "mediatok.wave25.read_timestamps.v1"

    private static let stateBox = MTWave25Box<(
        cachedConfig: MTWave25Config,
        lastContext: AccountContext?,
        workerTimer: DispatchSourceTimer?,
        seenPostIds: Set<MessageId>,
        seenPromoIds: Set<MessageId>,
        checkedReadMsgIds: Set<MessageId>,
        warnedOtcPeers: Set<PeerId>
    )>((.default, nil, nil, [], [], [], []))

    // MARK: - Registration

    public static func register() {
        let initial = loadConfigFromDisk()
        stateBox.withLock { $0.cachedConfig = initial }

        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave25Tools.interceptCommands(request)
        }, order: 47)

        MTChatScreenHooks.lifecycle.register({ event, screen in
            if event == .didAppear {
                MTMediaTokWave25Tools.stateBox.withLock { $0.lastContext = screen.context }
                MTMediaTokWave25Tools.armWorkerIfNeeded(context: screen.context)
                if let pid = screen.chatLocation.peerId, pid.namespace == Namespaces.Peer.CloudUser {
                    MTMediaTokWave25Tools.inspectOtcBioScamIfNeeded(context: screen.context, peerId: pid)
                }
            }
        }, order: 47)

        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTMediaTokWave25Tools.stateBox.withLock { $0.lastContext = context }
            MTMediaTokWave25Tools.armWorkerIfNeeded(context: context)
        }, order: 48)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave25Tools.messageMenuItems(menuContext)
        }, order: 103)
    }

    // MARK: - Persistence

    private static func loadConfigFromDisk() -> MTWave25Config {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let decoded = try? JSONDecoder().decode(MTWave25Config.self, from: data) else {
            return .default
        }
        return decoded
    }

    public static func loadConfig() -> MTWave25Config {
        return stateBox.withLock { $0.cachedConfig }
    }

    public static func saveConfig(_ cfg: MTWave25Config) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        stateBox.withLock { $0.cachedConfig = cfg }
        if let ctx = stateBox.withLock({ $0.lastContext }) {
            armWorkerIfNeeded(context: ctx)
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

    // MARK: - Spin-Syntax Randomizer (#1003)

    public static func expandSpinSyntax(_ template: String) -> String {
        var result = template
        guard let regex = try? NSRegularExpression(pattern: "\\{([^{}]+)\\}") else {
            return template
        }
        for _ in 0 ..< 10 {
            let ns = result as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: result, options: [], range: range), match.numberOfRanges >= 2 else {
                break
            }
            let inner = ns.substring(with: match.range(at: 1))
            let options = inner.split(separator: "|").map(String.init)
            let pick = options.randomElement() ?? inner
            result = ns.replacingCharacters(in: match.range, with: pick)
        }
        return result
    }

    // MARK: - Slash Commands

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix(".") else { return false }
        let lower = raw.lowercased()
        let peerId = request.chatLocation.peerId

        if lower == ".firstcom" || lower == ".promosnipe" || lower == ".otcguard" || lower == ".wave25" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                presentWave25Hub(context: request.context, currentPeerId: peerId)
            }
            return true
        }
        if lower == ".help" || lower == ".commands" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                presentInteractiveCommandHelp(context: request.context)
            }
            return true
        }
        return false
    }

    // MARK: - #1065 OTC Fake-@username-in-Bio Scam Guard

    private static func inspectOtcBioScamIfNeeded(context: AccountContext, peerId: PeerId) {
        guard loadConfig().otcBioScamGuardEnabled, peerId != context.account.peerId else { return }
        let alreadyWarned = stateBox.withLock { $0.warnedOtcPeers.contains(peerId) }
        guard !alreadyWarned else { return }

        let _ = (context.account.postbox.transaction { tx -> (username: String?, about: String?) in
            let peer = tx.getPeer(peerId) as? TelegramUser
            let cached = tx.getPeerCachedData(peerId: peerId) as? CachedUserData
            return (peer?.addressName, cached?.about)
        } |> deliverOnMainQueue).startStandalone(next: { info in
            let realUser = (info.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let about = (info.about ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Classic OTC scam: hidden/empty real @username, but a fake "@guarantor_name" planted in Bio!
            guard realUser.isEmpty, !about.isEmpty else { return }
            let hasAtTag = about.range(of: "@[A-Za-z0-9_]{4,32}", options: .regularExpression) != nil
            guard hasAtTag else { return }

            stateBox.withLock { _ = $0.warnedOtcPeers.insert(peerId) }
            guard let top = topViewController() else { return }
            let alert = UIAlertController(
                title: "ОСТОРОЖНО: OTC-СКАМ В БИО (#1065)!",
                message: "У этого собеседника СКРЫТ настоящий @username, но в графе «О себе» вписан чужой тег:\n\n«\(String(about.prefix(120)))»\n\nТак мошенники выдают себя за гарантов и покупателей в OTC-сделках! Всегда проверяйте числовой User ID!",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Понял, буду осторожен", style: .destructive))
            top.present(alert, animated: true)
            MTMediaTokWave23Tools.appendAutomationLog(module: "OTC Анти-Скам #1065", detail: "Пойман фейковый @ник в БИО при скрытом юзернейме", savedSeconds: 300)
        })
    }

    // MARK: - #1037 Exact Read Timestamp Menu Item

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let msg = menuContext.messages.first, !msg.flags.contains(.Incoming), msg.id.peerId.namespace == Namespaces.Peer.CloudUser else {
            return []
        }
        let key = "\(msg.id.peerId.toInt64())_\(msg.id.id)"
        let map = (UserDefaults.standard.dictionary(forKey: readTimesKey) as? [String: Int]) ?? [:]
        guard let readUnix = map[key] else { return [] }

        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss (dd.MM)"
        let formatted = df.string(from: Date(timeIntervalSince1970: TimeInterval(readUnix)))
        return [MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
            text: "Прочитано в \(formatted) (#1037)",
            icon: { theme in
                return UIImage(systemName: "checkmark.circle.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { _, f in
                f(.default)
                UIPasteboard.general.string = "Прочитано в \(formatted)"
                MTMediaTokWave5Tools.showToast(context: menuContext.context, text: "Точное время прочтения скопировано: \(formatted)")
            }
        )))]
    }

    // MARK: - Background Worker (#1002 First-Comment, #1005 Promo Sniper, #1037 Read Sniffer)

    private static func armWorkerIfNeeded(context: AccountContext) {
        let cfg = loadConfig()
        guard cfg.firstCommentEnabled || cfg.promoSnipeEnabled || cfg.exactReadTimestampEnabled else { return }

        let shouldStart = stateBox.withLock { st -> Bool in
            st.lastContext = context
            return st.workerTimer == nil
        }
        guard shouldStart else { return }

        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + 2.0, repeating: 2.0)
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

        // 1. #1037 Exact Read Timestamp Sniffer for recent outgoing DMs
        if cfg.exactReadTimestampEnabled {
            let _ = (context.account.postbox.transaction { tx -> [(String, Int)] in
                var newlyRead: [(String, Int)] = []
                let top = tx.getTopChatListEntries(groupId: .root, count: 12)
                for entry in top where entry.peerId.namespace == Namespaces.Peer.CloudUser {
                    guard let readState = tx.getCombinedPeerReadState(entry.peerId) else { continue }
                    tx.scanTopMessages(peerId: entry.peerId, namespace: Namespaces.Message.Cloud, limit: 4) { m in
                        if !m.flags.contains(.Incoming) && (nowSec - Int(m.timestamp)) < 3600 {
                            if readState.isOutgoingMessageIndexRead(m.index) {
                                newlyRead.append(("\(m.id.peerId.toInt64())_\(m.id.id)", nowSec))
                            }
                        }
                        return true
                    }
                }
                return newlyRead
            } |> deliverOnMainQueue).startStandalone(next: { pairs in
                guard !pairs.isEmpty else { return }
                var map = (UserDefaults.standard.dictionary(forKey: readTimesKey) as? [String: Int]) ?? [:]
                var changed = false
                for (k, ts) in pairs where map[k] == nil {
                    map[k] = ts
                    changed = true
                }
                if changed {
                    if map.count > 400 {
                        let sorted = map.sorted { $0.value > $1.value }.prefix(300)
                        map = Dictionary(uniqueKeysWithValues: sorted.map { ($0.key, $0.value) })
                    }
                    UserDefaults.standard.set(map, forKey: readTimesKey)
                }
            })
        }

        // 2. #1005 Promo-Code Regex Sniper across top channels
        if cfg.promoSnipeEnabled, let regex = try? NSRegularExpression(pattern: cfg.promoRegexPattern) {
            let _ = (context.account.postbox.transaction { tx -> [(MessageId, String)] in
                var matches: [(MessageId, String)] = []
                let top = tx.getTopChatListEntries(groupId: .root, count: 25)
                for entry in top where entry.peerId.namespace == Namespaces.Peer.CloudChannel {
                    tx.scanTopMessages(peerId: entry.peerId, namespace: Namespaces.Message.Cloud, limit: 2) { m in
                        if (nowSec - Int(m.timestamp)) < 90, !m.text.isEmpty {
                            let ns = m.text as NSString
                            if let hit = regex.firstMatch(in: m.text, options: [], range: NSRange(location: 0, length: ns.length)) {
                                let codeRange = hit.numberOfRanges >= 2 ? hit.range(at: 1) : hit.range
                                matches.append((m.id, ns.substring(with: codeRange)))
                            }
                        }
                        return true
                    }
                }
                return matches
            } |> deliverOnMainQueue).startStandalone(next: { found in
                for (mid, code) in found {
                    let isNew = stateBox.withLock { st -> Bool in
                        if st.seenPromoIds.contains(mid) { return false }
                        st.seenPromoIds.insert(mid)
                        return true
                    }
                    if isNew {
                        UIPasteboard.general.string = code
                        AudioServicesPlaySystemSound(1007)
                        MTMediaTokWave5Tools.showToast(context: context, text: "ПРОМОКОД ПОЙМАН (#1005) и скопирован: \(code)")
                        MTMediaTokWave23Tools.appendAutomationLog(module: "Промо-снайпер #1005", detail: "Пойман код \(code)", savedSeconds: 45)
                    }
                }
            })
        }

        // 3. #1002/#1003 Auto-First-Comment Sniper on selected channels with linked discussion groups
        if cfg.firstCommentEnabled, !cfg.firstCommentChannelIds.isEmpty {
            let targets = cfg.firstCommentChannelIds
            let tpl = cfg.firstCommentSpinTemplate
            let _ = (context.account.postbox.transaction { tx -> [(MessageId, PeerId)] in
                var jobs: [(MessageId, PeerId)] = []
                for rawId in targets {
                    let chPid = PeerId(rawId)
                    guard let cached = tx.getPeerCachedData(peerId: chPid) as? CachedChannelData,
                          case let .known(maybeLinked) = cached.linkedDiscussionPeerId,
                          let linkedId = maybeLinked else { continue }
                    tx.scanTopMessages(peerId: linkedId, namespace: Namespaces.Message.Cloud, limit: 2) { m in
                        if (nowSec - Int(m.timestamp)) < 25, m.flags.contains(.Incoming) {
                            jobs.append((m.id, linkedId))
                            return false
                        }
                        return true
                    }
                }
                return jobs
            } |> deliverOnMainQueue).startStandalone(next: { jobs in
                for (postMsgId, linkedGroupId) in jobs {
                    let shouldPost = stateBox.withLock { st -> Bool in
                        if st.seenPostIds.contains(postMsgId) { return false }
                        st.seenPostIds.insert(postMsgId)
                        return true
                    }
                    guard shouldPost else { continue }
                    let delaySec = Double.random(in: 0.4 ... 1.4)
                    let commentText = expandSpinSyntax(tpl)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delaySec) {
                        let reply = EngineMessageReplySubject(messageId: postMsgId, quote: nil, innerSubject: nil)
                        let _ = enqueueMessages(account: context.account, peerId: linkedGroupId, messages: [
                            .message(text: commentText, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: reply, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                        ]).startStandalone()
                        MTMediaTokWave23Tools.appendAutomationLog(module: "Первонах #1002", detail: "Отправлен спин-коммент: \(commentText)", savedSeconds: 30)
                    }
                }
            })
        }
    }

    // MARK: - Screens

    public static func presentWave25Hub(context: AccountContext, currentPeerId: PeerId?) {
        guard let top = topViewController() else { return }
        let vc = MTWave25HubController(context: context, currentPeerId: currentPeerId)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    public static func presentInteractiveCommandHelp(context: AccountContext) {
        guard let top = topViewController() else { return }
        let vc = MTInteractiveHelpController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }
}

// MARK: - Wave 25 Settings Controller

private final class MTWave25HubController: UIViewController {
    private let context: AccountContext
    private let currentPeerId: PeerId?
    private var cfg = MTMediaTokWave25Tools.loadConfig()

    private let firstComSwitch = UISwitch()
    private let promoSwitch = UISwitch()
    private let otcSwitch = UISwitch()
    private let readTsSwitch = UISwitch()
    private let templateField = UITextField()

    init(context: AccountContext, currentPeerId: PeerId?) {
        self.context = context
        self.currentPeerId = currentPeerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Юзербот, Первонах и OTC-Щит"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(saveTapped))

        self.firstComSwitch.isOn = self.cfg.firstCommentEnabled
        self.promoSwitch.isOn = self.cfg.promoSnipeEnabled
        self.otcSwitch.isOn = self.cfg.otcBioScamGuardEnabled
        self.readTsSwitch.isOn = self.cfg.exactReadTimestampEnabled

        self.templateField.text = self.cfg.firstCommentSpinTemplate
        self.templateField.placeholder = "{Сильно|По делу}, {ждём|плюсую}!"
        self.templateField.borderStyle = .roundedRect
        self.templateField.backgroundColor = .secondarySystemGroupedBackground

        var addChanCfg = UIButton.Configuration.tinted()
        addChanCfg.title = "Добавить / убрать текущий канал в Первонах (\(self.cfg.firstCommentChannelIds.count))"
        addChanCfg.image = UIImage(systemName: "bolt.bubble.fill")
        addChanCfg.imagePadding = 8
        addChanCfg.cornerStyle = .large
        let addChanBtn = UIButton(configuration: addChanCfg, primaryAction: UIAction { [weak self] _ in
            guard let self, let pid = self.currentPeerId, pid.namespace == Namespaces.Peer.CloudChannel else {
                if let ctx = self?.context {
                    MTMediaTokWave5Tools.showToast(context: ctx, text: "Откройте нужный канал и вызовите .firstcom")
                }
                return
            }
            let raw = pid.toInt64()
            if let idx = self.cfg.firstCommentChannelIds.firstIndex(of: raw) {
                self.cfg.firstCommentChannelIds.remove(at: idx)
                MTMediaTokWave5Tools.showToast(context: self.context, text: "Канал убран из Авто-Первонаха")
            } else {
                self.cfg.firstCommentChannelIds.append(raw)
                MTMediaTokWave5Tools.showToast(context: self.context, text: "Канал добавлен в Авто-Первонах (#1002)!")
            }
        })

        let stack = UIStackView(arrangedSubviews: [
            makeRow("Авто-Первонах со спин-рандомом (#1002/#1003)", self.firstComSwitch),
            self.templateField,
            addChanBtn,
            makeRow("Авто-перехват промокодов в буфер (#1005)", self.promoSwitch),
            makeRow("Детектор OTC-скама «чужой @ник в БИО» (#1065)", self.otcSwitch),
            makeRow("Точная секунда прочтения в ЛС (#1037)", self.readTsSwitch)
        ])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            self.templateField.heightAnchor.constraint(equalToConstant: 44),
            addChanBtn.heightAnchor.constraint(equalToConstant: 46),
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16)
        ])
    }

    private func makeRow(_ title: String, _ sw: UISwitch) -> UIView {
        let r = UIStackView()
        r.axis = .horizontal
        r.alignment = .center
        r.spacing = 8
        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 13.5)
        l.numberOfLines = 0
        r.addArrangedSubview(l)
        r.addArrangedSubview(sw)
        return r
    }

    @objc private func saveTapped() {
        self.cfg.firstCommentEnabled = self.firstComSwitch.isOn
        self.cfg.firstCommentSpinTemplate = (self.templateField.text ?? "").isEmpty ? MTWave25Config.default.firstCommentSpinTemplate : (self.templateField.text ?? "")
        self.cfg.promoSnipeEnabled = self.promoSwitch.isOn
        self.cfg.otcBioScamGuardEnabled = self.otcSwitch.isOn
        self.cfg.exactReadTimestampEnabled = self.readTsSwitch.isOn
        MTMediaTokWave25Tools.saveConfig(self.cfg)
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Настройки Юзербота сохранены!")
        self.dismiss(animated: true)
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #1440 Interactive Command Reference (.help)

private final class MTInteractiveHelpController: UITableViewController {
    private let context: AccountContext
    private let commands: [(cmd: String, desc: String)] = [
        (".cmd", "Главная Палитра всех функций MediaTok (Spotlight)"),
        (".tonpay", "Перевод TON по адресу с комментом (Tonkeeper & xRocket)"),
        (".ios27bar", "Вкл/выкл перелив верхней шапки iOS 27 Liquid Glass"),
        (".jbcheck", "Анти-Джейлбрейк и проверка чистоты песочницы iOS"),
        (".nukeall", "Снос всех чатов и выход из ТГК по секретному паролю"),
        (".nukewhite", "Добавить текущий чат в Белый список защиты от сноса"),
        (".prostore", "MediaTok Pro (@tribute, VIP-друзья по ID, анти-кряк, журнал)"),
        (".shaders", "Живые 60fps Metal GPU шейдеры, 3D гироскоп и локальные обои"),
        (".procam", "Pro-кружки: DualCam Фронт+Тыл, Таймлапс 2x/4x/8x, кольцевой свет"),
        (".music", "Офлайн Музыкальный Хаб + плеер в стиле Apple Music"),
        (".songlink", "Найти трек на всех площадках (Apple Music / Spotify / Яндекс)"),
        (".nftmarket", "Арбитраж подарков по 4 маркетам + наценка за чёрный/золотой фон"),
        (".searchall", "Поиск сообщений сразу по ВСЕМ подключённым аккаунтам"),
        (".dork", "Дорк-поиск в чате (from: has:file size:>10mb -спам)"),
        (".purgeme 20", "Быстро удалить свои последние 20 сообщений в чате"),
        (".clonechan", "Клонировать посты канала в хронологическом порядке"),
        (".joinfilter", "Умный фильтр заявок в закрытый ТГК от спам-ботов"),
        (".firstcom", "Авто-Первонах со спин-текстом, промо-снайпер и OTC-щит"),
        (".bincheck", "Проверка банковской карты по Луну + определение банка по BIN"),
        (".snipeuser", "Фоновый снайпер освобождения занятого @username"),
        (".cyberlock", "Snatch Lock (>3.6G рывок), USB Lockdown и Анти-Скрин"),
        (".wave20", "Скрытие звонков CallKit из iPhone, секундомер печатает, DC-точка"),
        (".macros", "Быстрые сокращения ;аббр при отправке сообщений"),
        (".ghost1m", "Тихая отправка + снос у обоих через 1 мин после прочтения"),
        (".novoice", "Запрет входящих голосовых и кружков от собеседника в ЛС"),
        (".197", "Экспериментальные флаги ускорения движка Telegram")
    ]

    init(context: AccountContext) {
        self.context = context
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Все команды MediaTok (.help)"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.commands.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "helpCmdCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "helpCmdCell")
        let item = self.commands[indexPath.row]
        cell.textLabel?.text = item.cmd
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        cell.textLabel?.textColor = .systemBlue
        cell.detailTextLabel?.text = item.desc
        cell.detailTextLabel?.numberOfLines = 0
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let cmd = self.commands[indexPath.row].cmd
        UIPasteboard.general.string = cmd
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Команда \(cmd) скопирована!")
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}
