import Foundation
import UIKit
import AudioToolbox
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
        otcBioScamGuardEnabled: false,
        exactReadTimestampEnabled: false
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
        guard cfg.firstCommentEnabled || cfg.promoSnipeEnabled || cfg.exactReadTimestampEnabled else {
            let existing = stateBox.withLock { st -> DispatchSourceTimer? in
                let old = st.workerTimer
                st.workerTimer = nil
                return old
            }
            existing?.cancel()
            return
        }

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
                    tx.scanTopMessages(peerId: linkedId, namespace: Namespaces.Message.Cloud, limit: 4) { m in
                        let isFromChannel = (m.forwardInfo?.author?.id == chPid || m.author?.id == chPid)
                        if isFromChannel, (nowSec - Int(m.timestamp)) < 25, m.flags.contains(.Incoming) {
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
        let vc = mtMakeNativeWave25HubController(context: context, currentPeerId: currentPeerId)
        mtPushNativeController(vc, context: context)
    }

    public static func presentInteractiveCommandHelp(context: AccountContext) {
        let vc = mtMakeNativeInteractiveHelpController(context: context)
        mtPushNativeController(vc, context: context)
    }
}

// MARK: - Wave 25 Native ItemListController

private func mtMakeNativeWave25HubController(context: AccountContext, currentPeerId: PeerId?) -> ItemListController {
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revCount = 0
    let bump: () -> Void = {
        revCount += 1
        revision.set(revCount)
    }
    weak var weakController: ItemListController?

    let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let cfg = MTMediaTokWave25Tools.loadConfig()
        var screen = MTNativeScreenModel(title: "Автоматизация чата")

        var fcRows: [MTNativeRow] = [
            MTNativeRow(id: "w25.fc.h", kind: .header("Авто-комментарий в каналах")),
            MTNativeRow(id: "w25.fc.on", kind: .toggle(title: "Авто-комментарий на новые посты", value: cfg.firstCommentEnabled, enabled: true)),
            MTNativeRow(id: "w25.fc.tpl", kind: .disclosure(title: "Шаблон со спин-вариантами", label: String(cfg.firstCommentSpinTemplate.prefix(16)), icon: nil, enabled: true))
        ]
        if let pid = currentPeerId, pid.namespace == Namespaces.Peer.CloudChannel {
            let isAdded = cfg.firstCommentChannelIds.contains(pid.toInt64())
            fcRows.append(MTNativeRow(
                id: "w25.fc.chan",
                kind: .action(title: isAdded ? "Убрать текущий канал (\(cfg.firstCommentChannelIds.count))" : "Добавить текущий канал (\(cfg.firstCommentChannelIds.count))", destructive: isAdded, enabled: true)
            ))
        }
        screen.sections.append(fcRows)

        screen.toggle["w25.fc.on"] = { isOn in
            var c = MTMediaTokWave25Tools.loadConfig()
            c.firstCommentEnabled = isOn
            MTMediaTokWave25Tools.saveConfig(c)
            bump()
        }
        screen.tap["w25.fc.tpl"] = {
            mtPresentNativePrompt(
                context: context,
                from: weakController,
                title: "Шаблон авто-комментария",
                subtitle: "Используйте {вариант1|вариант2} для рандомизации:",
                value: MTMediaTokWave25Tools.loadConfig().firstCommentSpinTemplate,
                placeholder: "{Сильно|По делу}, {ждём|плюсую}!",
                apply: { entered in
                    var c = MTMediaTokWave25Tools.loadConfig()
                    let trimmed = entered.trimmingCharacters(in: .whitespacesAndNewlines)
                    c.firstCommentSpinTemplate = trimmed.isEmpty ? MTWave25Config.default.firstCommentSpinTemplate : trimmed
                    MTMediaTokWave25Tools.saveConfig(c)
                    bump()
                }
            )
        }
        screen.tap["w25.fc.chan"] = {
            guard let pid = currentPeerId, pid.namespace == Namespaces.Peer.CloudChannel else { return }
            var c = MTMediaTokWave25Tools.loadConfig()
            let raw = pid.toInt64()
            if let idx = c.firstCommentChannelIds.firstIndex(of: raw) {
                c.firstCommentChannelIds.remove(at: idx)
                mtPresentNativeToast(context: context, from: weakController, text: "Канал убран")
            } else {
                c.firstCommentChannelIds.append(raw)
                mtPresentNativeToast(context: context, from: weakController, text: "Канал добавлен")
            }
            MTMediaTokWave25Tools.saveConfig(c)
            bump()
        }

        screen.sections.append([
            MTNativeRow(id: "w25.sec.h", kind: .header("Инструменты и защита")),
            MTNativeRow(id: "w25.promo", kind: .toggle(title: "Авто-перехват промокодов в буфер", value: cfg.promoSnipeEnabled, enabled: true)),
            MTNativeRow(id: "w25.otc", kind: .toggle(title: "Детектор подмены @username в БИО", value: cfg.otcBioScamGuardEnabled, enabled: true)),
            MTNativeRow(id: "w25.readts", kind: .toggle(title: "Точное время прочтения в ЛС", value: cfg.exactReadTimestampEnabled, enabled: true))
        ])

        screen.toggle["w25.promo"] = { isOn in
            var c = MTMediaTokWave25Tools.loadConfig()
            c.promoSnipeEnabled = isOn
            MTMediaTokWave25Tools.saveConfig(c)
            bump()
        }
        screen.toggle["w25.otc"] = { isOn in
            var c = MTMediaTokWave25Tools.loadConfig()
            c.otcBioScamGuardEnabled = isOn
            MTMediaTokWave25Tools.saveConfig(c)
            bump()
        }
        screen.toggle["w25.readts"] = { isOn in
            var c = MTMediaTokWave25Tools.loadConfig()
            c.exactReadTimestampEnabled = isOn
            MTMediaTokWave25Tools.saveConfig(c)
            bump()
        }

        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}

// MARK: - #1440 Interactive Command Reference (.help) — Native ItemListController

private func mtMakeNativeInteractiveHelpController(context: AccountContext) -> ItemListController {
    let commands: [(cmd: String, desc: String)] = [
        (".cmd", "Палитра всех функций MediaTok (Spotlight)"),
        (".tonpay", "Перевод TON по адресу с комментарием (Tonkeeper и xRocket)"),
        (".jbcheck", "Диагностика целостности песочницы iOS"),
        (".nukeall", "Снос чатов по секретному паролю"),
        (".nukewhite", "Добавить текущий чат в белый список защиты"),
        (".shaders", "Metal GPU-шейдеры, 3D гироскоп и локальные обои"),
        (".procam", "Pro-кружки: две камеры DualCam, таймлапс, кольцевой свет"),
        (".music", "Офлайн медиатека треков"),
        (".songlink", "Найти трек на всех площадках (Apple Music / Spotify / Яндекс)"),
        (".searchall", "Поиск сообщений сразу по всем аккаунтам"),
        (".dork", "Расширенный поиск в чате (from: has:file size:>10mb)"),
        (".purgeme 20", "Быстро удалить свои последние 20 сообщений"),
        (".clonechan", "Клонировать посты канала в хронологическом порядке"),
        (".joinfilter", "Фильтр заявок в закрытый канал от спам-ботов"),
        (".firstcom", "Авто-комментарий, ловец промокодов и защита БИО"),
        (".bincheck", "Проверка банковской карты по Луну и BIN"),
        (".snipeuser", "Фоновый монитор освобождения @username"),
        (".cyberlock", "Блокировка при рывке из рук и USB-защита"),
        (".wave20", "Скрытие звонков из Недавних iPhone и секундомер набора"),
        (".macros", "Быстрые макросы автозамены ;ключ"),
        (".ghost1m", "Тихая отправка с удалением через 1 мин после прочтения"),
        (".novoice", "Запрет входящих голосовых и кружков в ЛС"),
        (".weather off", "Полностью выключить погоду профиля")
    ]

    weak var weakController: ItemListController?
    let modelSignal: Signal<MTNativeScreenModel, NoError> = .single({
        var screen = MTNativeScreenModel(title: "Справочник команд (.help)")
        var rows: [MTNativeRow] = [
            MTNativeRow(id: "help.h", kind: .header("Нажмите на команду для копирования"))
        ]
        for (idx, item) in commands.enumerated() {
            let rowId = "help.\(idx)"
            rows.append(MTNativeRow(id: rowId, kind: .disclosure(title: item.cmd, label: item.desc, icon: nil, enabled: true)))
            screen.tap[rowId] = {
                UIPasteboard.general.string = item.cmd
                mtPresentNativeToast(context: context, from: weakController, text: "Скопировано: \(item.cmd)")
            }
        }
        screen.sections.append(rows)
        return screen
    }())

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}
