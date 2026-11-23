import Foundation
import UIKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import UserNotifications
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import UndoUI
import WebPBinding
import MTCore
import MTHooks
import MTSettingsUI

// MARK: - 1. Chat Streaks (Огоньки 🔥 + Заморозка ❄️)

enum MTMediaTokStreaks {
    private static let lock = NSLock()
    private static var loaded = false
    private static var entries: [String: MTMediaTokCoreLogic.StreakRecord] = [:]
    private static var peerNames: [String: String] = [:]
    private static var seenIncomingIds: Set<Int32> = []

    private static func storageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("mediatok/mediatok/streaks.json")
    }

    private static func dayAndMonthKeys(for date: Date = Date()) -> (day: String, month: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 2026
        let m = c.month ?? 1
        let d = c.day ?? 1
        return (String(format: "%04d-%02d-%02d", y, m, d), String(format: "%04d-%02d", y, m))
    }

    private static func peerKey(_ peerId: PeerId) -> String {
        return "\(peerId.namespace._internalGetInt32Value())_\(peerId.id._internalGetInt64Value())"
    }

    private static func ensureLoadedLocked() {
        if MTMediaTokStreaks.loaded { return }
        MTMediaTokStreaks.loaded = true
        let primaryURL = MTMediaTokStreaks.storageURL()
        let backupURL = primaryURL.appendingPathExtension("bak")
        if let data = try? Data(contentsOf: primaryURL),
           let decoded = try? JSONDecoder().decode([String: MTMediaTokCoreLogic.StreakRecord].self, from: data) {
            MTMediaTokStreaks.entries = decoded
            return
        }
        if let bakData = try? Data(contentsOf: backupURL),
           let decoded = try? JSONDecoder().decode([String: MTMediaTokCoreLogic.StreakRecord].self, from: bakData) {
            MTMediaTokStreaks.entries = decoded
            try? bakData.write(to: primaryURL, options: [.atomic])
        }
    }

    private static func persistLocked() {
        let url = MTMediaTokStreaks.storageURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let previous = try? Data(contentsOf: url), !previous.isEmpty {
            let backupURL = url.appendingPathExtension("bak")
            try? previous.write(to: backupURL, options: [.atomic])
        }
        if let data = try? JSONEncoder().encode(MTMediaTokStreaks.entries) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    static func recordActivity(peerId: PeerId, peerTitle: String? = nil, isFreshMessage: Bool = true) -> (record: MTMediaTokCoreLogic.StreakRecord, usedFreeze: Bool, milestone: Int?) {
        let key = MTMediaTokStreaks.peerKey(peerId)
        let keys = MTMediaTokStreaks.dayAndMonthKeys()
        MTMediaTokStreaks.lock.lock()
        MTMediaTokStreaks.ensureLoadedLocked()
        if let peerTitle, !peerTitle.isEmpty {
            MTMediaTokStreaks.peerNames[key] = peerTitle
        }
        let existing = MTMediaTokStreaks.entries[key]
        if existing?.lastDayKey == keys.day && !isFreshMessage {
            let snap = existing!
            MTMediaTokStreaks.lock.unlock()
            return (snap, false, nil)
        }
        let res = MTMediaTokCoreLogic.applyStreakActivity(record: existing, dayKey: keys.day, monthKey: keys.month)
        MTMediaTokStreaks.entries[key] = res.updated
        MTMediaTokStreaks.persistLocked()
        MTMediaTokStreaks.lock.unlock()
        return (res.updated, res.usedFreeze, res.milestoneReached)
    }

    static func recordIncomingIfFresh(message: Message) {
        let ns = message.id.peerId.namespace
        guard ns == Namespaces.Peer.CloudUser || ns == Namespaces.Peer.CloudGroup else { return }
        let now = Date().timeIntervalSince1970
        guard abs(now - Double(message.timestamp)) <= 120.0 else { return }

        MTMediaTokStreaks.lock.lock()
        if MTMediaTokStreaks.seenIncomingIds.contains(message.id.id) {
            MTMediaTokStreaks.lock.unlock()
            return
        }
        if MTMediaTokStreaks.seenIncomingIds.count > 2048 {
            MTMediaTokStreaks.seenIncomingIds.removeAll()
        }
        MTMediaTokStreaks.seenIncomingIds.insert(message.id.id)
        MTMediaTokStreaks.lock.unlock()

        let title = message.peers[message.id.peerId]?.debugDisplayTitle
        _ = MTMediaTokStreaks.recordActivity(peerId: message.id.peerId, peerTitle: title)
    }

    static func record(for peerId: PeerId) -> MTMediaTokCoreLogic.StreakRecord? {
        let key = MTMediaTokStreaks.peerKey(peerId)
        MTMediaTokStreaks.lock.lock()
        MTMediaTokStreaks.ensureLoadedLocked()
        let rec = MTMediaTokStreaks.entries[key]
        MTMediaTokStreaks.lock.unlock()
        return rec
    }

    static func topStreaks(limit: Int = 20) -> [(peerKey: String, name: String, record: MTMediaTokCoreLogic.StreakRecord)] {
        MTMediaTokStreaks.lock.lock()
        MTMediaTokStreaks.ensureLoadedLocked()
        let snap = MTMediaTokStreaks.entries
        let names = MTMediaTokStreaks.peerNames
        MTMediaTokStreaks.lock.unlock()
        return snap.map { ($0.key, names[$0.key] ?? $0.key, $0.value) }
            .sorted {
                if $0.2.currentStreak != $1.2.currentStreak { return $0.2.currentStreak > $1.2.currentStreak }
                return $0.2.totalMessages > $1.2.totalMessages
            }
            .prefix(limit)
            .map { $0 }
    }

    static func renderStreakCardSticker(chatTitle: String, record: MTMediaTokCoreLogic.StreakRecord) -> UIImage {
        let size = CGSize(width: 512.0, height: 300.0)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: 16.0, y: 16.0, width: 480.0, height: 268.0)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 26.0)
            cg.saveGState()
            path.addClip()
            let colors = [UIColor(rgb: 0x1A1026).cgColor, UIColor(rgb: 0x3A120E).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                cg.drawLinearGradient(grad, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
            }
            cg.restoreGState()

            UIColor(rgb: 0xFF7B00).withAlphaComponent(0.85).setStroke()
            path.lineWidth = 3.0
            path.stroke()

            let tier = MTMediaTokCoreLogic.streakTierBadge(days: record.currentStreak)
            ("\(tier) MEDIATOK STREAK" as NSString).draw(at: CGPoint(x: 36.0, y: 34.0), withAttributes: [
                .font: UIFont.systemFont(ofSize: 16.0, weight: .heavy),
                .foregroundColor: UIColor(rgb: 0xFFB703)
            ])
            (chatTitle as NSString).draw(at: CGPoint(x: 36.0, y: 60.0), withAttributes: [
                .font: UIFont.systemFont(ofSize: 24.0, weight: .bold),
                .foregroundColor: UIColor.white
            ])
            ("\(record.currentStreak) дн. подряд" as NSString).draw(at: CGPoint(x: 36.0, y: 108.0), withAttributes: [
                .font: UIFont.systemFont(ofSize: 44.0, weight: .black),
                .foregroundColor: UIColor(rgb: 0xFF8800)
            ])
            ("Рекорд: \(record.bestStreak) дн. · Сообщений: \(record.totalMessages) · ❄️ \(record.freezesRemaining)/2" as NSString).draw(at: CGPoint(x: 36.0, y: 184.0), withAttributes: [
                .font: UIFont.systemFont(ofSize: 18.0, weight: .semibold),
                .foregroundColor: UIColor(white: 0.9, alpha: 1.0)
            ])
        }
    }
}

// MARK: - 2. iOS Clipboard History Manager (#78)

enum MTMediaTokClipboard {
    private static let enabledKey = "mediatok.clipboard.enabled.v1"
    private static let lock = NSLock()
    private static var loaded = false
    private static var items: [ClipItem] = []
    private static var lastChangeCount: Int = -1
    private static var observers: [NSObjectProtocol] = []

    struct ClipItem: Codable, Equatable {
        let id: String
        var text: String
        var pinned: Bool
        var updatedAt: Int64
    }

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: MTMediaTokClipboard.enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: MTMediaTokClipboard.enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokClipboard.enabledKey) }
    }

    private static func storageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("mediatok/mediatok/clipboard_history.json")
    }

    private static func ensureLoadedLocked() {
        if MTMediaTokClipboard.loaded { return }
        MTMediaTokClipboard.loaded = true
        guard let data = try? Data(contentsOf: MTMediaTokClipboard.storageURL()),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else {
            return
        }
        MTMediaTokClipboard.items = decoded
    }

    private static func persistLocked() {
        let url = MTMediaTokClipboard.storageURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(MTMediaTokClipboard.items) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    static func startObserving() {
        guard MTMediaTokClipboard.observers.isEmpty else { return }
        let o1 = NotificationCenter.default.addObserver(forName: UIPasteboard.changedNotification, object: nil, queue: .main) { _ in
            MTMediaTokClipboard.captureCurrentPasteboard(forceRead: true)
        }
        MTMediaTokClipboard.observers.append(o1)
    }

    static func captureCurrentPasteboard(forceRead: Bool = false) {
        guard MTMediaTokClipboard.isEnabled else { return }
        let pb = UIPasteboard.general
        let cc = pb.changeCount
        guard forceRead || cc != MTMediaTokClipboard.lastChangeCount else { return }
        MTMediaTokClipboard.lastChangeCount = cc
        guard pb.hasStrings, let raw = pb.string else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 4000,
              !trimmed.hasPrefix(MTMediaTokCoreLogic.prefixV2),
              !trimmed.hasPrefix(MTMediaTokCoreLogic.prefixV1) else {
            return
        }
        MTMediaTokClipboard.addSnippet(raw)
    }

    static func addSnippet(_ text: String) {
        let now = Int64(Date().timeIntervalSince1970)
        MTMediaTokClipboard.lock.lock()
        MTMediaTokClipboard.ensureLoadedLocked()
        if let existingIdx = MTMediaTokClipboard.items.firstIndex(where: { $0.text == text }) {
            var item = MTMediaTokClipboard.items.remove(at: existingIdx)
            item.updatedAt = now
            MTMediaTokClipboard.items.insert(item, at: 0)
        } else {
            MTMediaTokClipboard.items.insert(ClipItem(id: UUID().uuidString, text: text, pinned: false, updatedAt: now), at: 0)
        }
        // Keep pinned + up to 30 most recent
        let pinned = MTMediaTokClipboard.items.filter { $0.pinned }
        let unpinned = Array(MTMediaTokClipboard.items.filter { !$0.pinned }.prefix(30))
        MTMediaTokClipboard.items = pinned + unpinned
        MTMediaTokClipboard.persistLocked()
        MTMediaTokClipboard.lock.unlock()
    }

    static func allItems() -> [ClipItem] {
        MTMediaTokClipboard.lock.lock()
        MTMediaTokClipboard.ensureLoadedLocked()
        let snap = MTMediaTokClipboard.items
        MTMediaTokClipboard.lock.unlock()
        return snap.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    static func togglePin(id: String) {
        MTMediaTokClipboard.lock.lock()
        MTMediaTokClipboard.ensureLoadedLocked()
        if let idx = MTMediaTokClipboard.items.firstIndex(where: { $0.id == id }) {
            MTMediaTokClipboard.items[idx].pinned.toggle()
            MTMediaTokClipboard.persistLocked()
        }
        MTMediaTokClipboard.lock.unlock()
    }

    static func clearUnpinned() {
        MTMediaTokClipboard.lock.lock()
        MTMediaTokClipboard.ensureLoadedLocked()
        MTMediaTokClipboard.items = MTMediaTokClipboard.items.filter { $0.pinned }
        MTMediaTokClipboard.persistLocked()
        MTMediaTokClipboard.lock.unlock()
    }
}

private final class MTClipboardHistoryViewController: UITableViewController {
    private var entries: [MTMediaTokClipboard.ClipItem] = []
    private let onPick: ((String) -> Void)?

    init(onPick: ((String) -> Void)?) {
        self.onPick = onPick
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = .dark
        MTMediaTokClipboard.captureCurrentPasteboard(forceRead: true)
        self.title = "📋 Буфер обмена MediaTok"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Очистить", style: .plain, target: self, action: #selector(self.clearTapped))
        self.reload()
    }

    private func reload() {
        self.entries = MTMediaTokClipboard.allItems()
        self.tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(1, self.entries.count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "clip") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "clip")
        if self.entries.isEmpty {
            cell.textLabel?.text = "История буфера пуста"
            cell.detailTextLabel?.text = "Копируйте текст — MediaTok сохранит последние 30 фрагментов"
            cell.selectionStyle = .none
            return cell
        }
        let item = self.entries[indexPath.row]
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.text = (item.pinned ? "📌 " : "") + item.text
        cell.detailTextLabel?.text = item.pinned ? "Закреплено (нажми чтобы вставить/скопировать)" : "Нажмите — вставить · Свайп — закрепить"
        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < self.entries.count else { return }
        let text = self.entries[indexPath.row].text
        UIPasteboard.general.string = text
        self.onPick?(text)
        self.dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.row < self.entries.count else { return nil }
        let item = self.entries[indexPath.row]
        let pin = UIContextualAction(style: .normal, title: item.pinned ? "Открепить" : "📌 Закрепить") { [weak self] _, _, done in
            MTMediaTokClipboard.togglePin(id: item.id)
            self?.reload()
            done(true)
        }
        pin.backgroundColor = .systemOrange
        return UISwipeActionsConfiguration(actions: [pin])
    }

    @objc private func clearTapped() {
        MTMediaTokClipboard.clearUnpinned()
        self.reload()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}

// MARK: - 3. Main Wave 5 Entry Point & Guards / Metadata Stripper / Cards / Games / Updater

enum MTMediaTokWave5Tools {
    private static let stripMetaKey = "mediatok.privacy.stripFileMeta.v1"
    private static let confirmForwardKey = "mediatok.guard.confirmForward.v1"
    private static let confirmPhotoSendKey = "mediatok.guard.confirmPhotoSend.v1"
    private static let streaksEnabledKey = "mediatok.streaks.enabled.v1"
    static let premiumEmojiKey = "mediatok.premium_emoji.enabled.v1"

    private static let guardLock = NSLock()
    private static var confirmedPhotoIds: Set<Int64> = []

    static var isPremiumEmojiEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: MTMediaTokWave5Tools.premiumEmojiKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: MTMediaTokWave5Tools.premiumEmojiKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave5Tools.premiumEmojiKey) }
    }

    static func resetPremiumEmojiStatus(context: AccountContext) {
        let pid = context.account.peerId.toInt64()
        UserDefaults.standard.removeObject(forKey: "mediatok.premium_emoji.status_file.\(pid)")
    }

    static func presentPremiumEmojiSheet(context: MTMenuContext) {
        let enabled = MTMediaTokWave5Tools.isPremiumEmojiEnabled
        let sheet = UIAlertController(
            title: "✨ Премиум Эмодзи",
            message: enabled
                ? "Включено: все паки Премиум-эмодзи разблокированы в клавиатуре и поиске, отправляются в любые чаты без подписки (анимируются у всех в MediaTok, в обычном Telegram — чистый эмодзи), а в профиле можно выбрать любой эмодзи-статус."
                : "Выключено: стандартное поведение Telegram для Премиум-эмодзи.",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: enabled ? "Выключить Премиум Эмодзи" : "✨ Включить Премиум Эмодзи", style: .default, handler: { _ in
            MTMediaTokWave5Tools.isPremiumEmojiEnabled.toggle()
            context.presentToast(MTMediaTokWave5Tools.isPremiumEmojiEnabled ? "✨ Премиум Эмодзи включены!" : "Премиум Эмодзи выключены")
        }))
        sheet.addAction(UIAlertAction(title: "🧹 Сбросить эмодзи-статус в профиле", style: .destructive, handler: { _ in
            MTMediaTokWave5Tools.resetPremiumEmojiStatus(context: context.context)
            context.presentToast("Эмодзи-статус профиля сброшен")
        }))
        sheet.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        context.presentNative(sheet)
    }

    static var isStreaksEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave5Tools.streaksEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave5Tools.streaksEnabledKey) }
    }

    static var isStripFileMetaEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: MTMediaTokWave5Tools.stripMetaKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: MTMediaTokWave5Tools.stripMetaKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave5Tools.stripMetaKey) }
    }

    static var isConfirmForwardEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave5Tools.confirmForwardKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave5Tools.confirmForwardKey) }
    }

    static var isConfirmPhotoSendEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave5Tools.confirmPhotoSendKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave5Tools.confirmPhotoSendKey) }
    }

    static func register() {
        MTMediaTokClipboard.startObserving()

        // 1. Outgoing `.card` & `.streak card` sticker generator
        MTOutgoingHooks.messages.register({ messages, context in
            MTMediaTokWave5Tools.transformStickers(&messages, context: context)
        }, order: 43)

        // 2. File Metadata Stripper (EXIF/GPS/PDF author scrubber on outgoing non-sticker files)
        MTOutgoingHooks.messages.register({ messages, context in
            MTMediaTokWave5Tools.stripOutgoingFileMetadata(&messages, context: context)
        }, order: 45)

        // 3. Photo Send Confirmation Guard (runs BEFORE watermark/metadata mutating hooks at order 44-45!)
        MTOutgoingHooks.messages.register({ messages, context in
            MTMediaTokWave5Tools.guardPhotoSend(&messages, context: context)
        }, order: 10)

        // 4. Forward Confirmation Guard (runs before restriction bypass at order -50 and chains on confirm)
        MTOutgoingHooks.forwardCopies.register({ account, messages in
            return MTMediaTokWave5Tools.confirmForwardIfNeeded(account: account, messages: messages)
        }, order: -50)

        // 5. Outgoing Streak Tracker
        MTOutgoingHooks.didEnqueue.register({ context, ids in
            guard MTMediaTokWave5Tools.isStreaksEnabled, ids.contains(where: { $0 != nil }) else { return }
            let ns = context.peerId.namespace
            guard ns == Namespaces.Peer.CloudUser || ns == Namespaces.Peer.CloudGroup else { return }
            _ = MTMediaTokStreaks.recordActivity(peerId: context.peerId)
        }, order: 60)

        // 6. Incoming APK/EXE/RLO Trojan File Inspector + Fresh Streak Update
        MTMessageDecorationHooks.decorations.register({ decoration, context in
            MTMediaTokWave5Tools.decorateIncoming(&decoration, message: context.message)
        }, order: 49)

        // 7. Inline commands `.streak` & `.clip`
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave5Tools.interceptCommands(request)
        }, order: 22)

        // 8. Profile Streak Row
        MTPeerInfoHooks.infoRows.register({ info in
            return MTMediaTokWave5Tools.profileStreakRows(info)
        }, order: 125)

        // 9. Send Button Long-Press Menu: Char/Word Counter (#71), Clipboard History (#78), Clean File
        MTChatScreenHooks.sendMenuItems.register({ sendContext in
            return MTMediaTokWave5Tools.sendMenuItems(sendContext)
        }, order: 72)
    }

    // MARK: Inline Commands & Send Menu

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        if lower == ".clip" || lower == ".clipboard" {
            request.replace(ChatTextInputState())
            MTMediaTokWave5Tools.presentClipboardPicker { picked in
                request.replace(ChatTextInputState(inputText: NSAttributedString(string: picked)))
            }
            return true
        }
        if lower == ".streak" || lower == ".огонек" {
            guard MTMediaTokWave5Tools.isStreaksEnabled else {
                request.replace(ChatTextInputState())
                MTMediaTokWave5Tools.showToast(context: request.context, text: "Серии общения выключены. Включить можно в меню MediaTok → Wave 5.")
                return true
            }
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            if let rec = MTMediaTokStreaks.record(for: peerId) {
                MTMediaTokWave5Tools.showToast(context: request.context, text: "Серия общения: \(rec.currentStreak) дн. (рекорд: \(rec.bestStreak), заморозок: \(rec.freezesRemaining)/2).")
            } else {
                MTMediaTokWave5Tools.showToast(context: request.context, text: "Серия ещё не начата — отправьте сообщение.")
            }
            return true
        }
        return false
    }

    private static func sendMenuItems(_ sendContext: MTSendMenuContext) -> [ContextMenuItem] {
        var entries: [ContextMenuItem] = []

        // #71: Live character / word / message limit counter
        let plain = sendContext.inputText.string
        if !plain.isEmpty {
            let chars = plain.count
            let words = plain.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            entries.append(.action(ContextMenuActionItem(
                text: "Символов: \(chars)/4096 · Слов: \(words)",
                icon: { theme in
                    return UIImage(systemName: "textformat.123")?.withTintColor(theme.contextMenu.secondaryColor, renderingMode: .alwaysOriginal)
                },
                action: { contextController, _ in
                    contextController?.dismiss(completion: nil)
                }
            )))
        }

        // #78: Clipboard History Manager
        MTMediaTokClipboard.captureCurrentPasteboard(forceRead: false)
        let clipCount = MTMediaTokClipboard.allItems().count
        let replaceInput = sendContext.replaceInput
        let existingInput = sendContext.inputText
        let dismiss = sendContext.dismiss
        entries.append(.action(ContextMenuActionItem(
            text: "Буфер обмена (\(clipCount))",
            icon: { theme in
                return UIImage(systemName: "doc.on.clipboard")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave5Tools.presentClipboardPicker { picked in
                    let mutable = NSMutableAttributedString(attributedString: existingInput)
                    if mutable.length > 0 {
                        mutable.append(NSAttributedString(string: " "))
                    }
                    mutable.append(NSAttributedString(string: picked))
                    replaceInput(mutable)
                }
            }
        )))

        // Pick & send clean document without metadata
        let ctx = sendContext.context
        let pid = sendContext.peerId
        entries.append(.action(ContextMenuActionItem(
            text: "Файл без EXIF / PDF-меты",
            icon: { theme in
                return UIImage(systemName: "checkmark.shield")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave5Tools.presentCleanDocumentSender(context: ctx, peerId: pid)
            }
        )))
        return entries
    }

    // MARK: `.card` & `.streak card` WebP Generators

    private static func transformStickers(_ messages: inout [EnqueueMessage], context: MTOutgoingContext) {
        for i in 0 ..< messages.count {
            guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = messages[i],
                  mediaReference == nil else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            var renderedImg: UIImage?
            var fileName = "mediatok_card.webp"
            var emoji = "🃏"

            if let card = MTMediaTokCoreLogic.parseCardCommand(trimmed) {
                renderedImg = MTMediaTokWave5Tools.renderInfoCardSticker(card)
                emoji = "💳"
            } else if lower == ".streak card" {
                let rec = MTMediaTokStreaks.record(for: context.peerId) ?? MTMediaTokCoreLogic.StreakRecord(currentStreak: 1, bestStreak: 1, lastDayKey: "", freezesRemaining: 2, freezeMonthKey: "", totalMessages: 1)
                renderedImg = MTMediaTokStreaks.renderStreakCardSticker(chatTitle: "Огонёк MediaTok", record: rec)
                fileName = "mediatok_streak.webp"
                emoji = "🔥"
            }

            guard let img = renderedImg,
                  let webpData = try? WebP.convert(toWebP: img, quality: 90.0),
                  !webpData.isEmpty else {
                continue
            }
            let fileId = Int64.random(in: Int64.min ... Int64.max)
            let resource = LocalFileMediaResource(fileId: fileId)
            context.account.postbox.mediaBox.storeResourceData(resource.id, data: webpData, synchronous: true)

            let fileAttrs: [TelegramMediaFileAttribute] = [
                .FileName(fileName: fileName),
                .Sticker(displayText: emoji, packReference: nil, maskData: nil),
                .ImageSize(size: PixelDimensions(width: Int32(img.size.width), height: Int32(img.size.height)))
            ]
            let media = TelegramMediaFile(
                fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: fileId),
                partialReference: nil,
                resource: resource,
                previewRepresentations: [],
                videoThumbnails: [],
                immediateThumbnailData: nil,
                mimeType: "image/webp",
                size: Int64(webpData.count),
                attributes: fileAttrs,
                alternativeRepresentations: []
            )
            let keptAttrs = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
            messages[i] = .message(
                text: "",
                attributes: keptAttrs,
                inlineStickers: inlineStickers,
                mediaReference: .standalone(media: media),
                threadId: threadId,
                replyToMessageId: replyToMessageId,
                replyToStoryId: replyToStoryId,
                localGroupingKey: localGroupingKey,
                correlationId: correlationId,
                bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets
            )
        }
    }

    static func renderInfoCardSticker(_ payload: MTMediaTokCoreLogic.CardPayload) -> UIImage {
        let width: CGFloat = 512.0
        let height: CGFloat = min(512.0, max(220.0, CGFloat(130 + payload.lines.count * 38)))
        let size = CGSize(width: width, height: height)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: 16.0, y: 16.0, width: width - 32.0, height: height - 32.0)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 24.0)
            cg.saveGState()
            path.addClip()
            let colors = [UIColor(rgb: 0x0D1321).cgColor, UIColor(rgb: 0x1D2D44).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                cg.drawLinearGradient(grad, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
            }
            cg.restoreGState()

            UIColor(rgb: 0x00F5FF).withAlphaComponent(0.7).setStroke()
            path.lineWidth = 2.5
            path.stroke()

            (payload.title as NSString).draw(at: CGPoint(x: 38.0, y: 36.0), withAttributes: [
                .font: UIFont.systemFont(ofSize: 28.0, weight: .heavy),
                .foregroundColor: UIColor(rgb: 0x00F5FF)
            ])
            var y: CGFloat = 76.0
            if !payload.subtitle.isEmpty {
                (payload.subtitle as NSString).draw(at: CGPoint(x: 38.0, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 19.0, weight: .semibold),
                    .foregroundColor: UIColor(white: 0.78, alpha: 1.0)
                ])
                y += 34.0
            }
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.15).cgColor)
            cg.setLineWidth(1.0)
            cg.move(to: CGPoint(x: 38.0, y: y))
            cg.addLine(to: CGPoint(x: width - 38.0, y: y))
            cg.strokePath()
            y += 14.0

            for line in payload.lines {
                ("• \(line)" as NSString).draw(in: CGRect(x: 38.0, y: y, width: width - 76.0, height: 32.0), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18.0, weight: .medium),
                    .foregroundColor: UIColor.white
                ])
                y += 34.0
            }
        }
    }

    // MARK: Outgoing File Metadata Stripper (EXIF / GPS / PDF Metadata)

    private static func stripOutgoingFileMetadata(_ messages: inout [EnqueueMessage], context: MTOutgoingContext) {
        guard MTMediaTokWave5Tools.isStripFileMetaEnabled else { return }
        for i in 0 ..< messages.count {
            guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = messages[i],
                  let mediaRef = mediaReference,
                  case let .standalone(media) = mediaRef,
                  let file = media as? TelegramMediaFile,
                  !file.isSticker else {
                continue
            }
            let localPath: String?
            if let refRes = file.resource as? LocalFileReferenceMediaResource {
                localPath = refRes.localFilePath
            } else {
                localPath = context.account.postbox.mediaBox.completedResourcePath(file.resource)
            }
            let ext = ((file.fileName ?? "") as NSString).pathExtension.lowercased()
            let mime = file.mimeType.lowercased()
            let isPdf = (mime == "application/pdf" || ext == "pdf")
            let isStaticImage = (mime == "image/jpeg" || mime == "image/png" || mime == "image/heic" || mime == "image/tiff"
                || ["jpg", "jpeg", "png", "heic", "tiff", "tif"].contains(ext))
            guard isPdf || isStaticImage, let path = localPath else {
                continue
            }
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            guard fileSize > 0, fileSize <= 40 * 1024 * 1024,
                  let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  !rawData.isEmpty else {
                continue
            }

            var strippedData: Data?
            var updatedMime = file.mimeType
            var updatedAttrs = file.attributes

            if isPdf {
                strippedData = MTMediaTokWave5Tools.stripPdfMetadata(rawData)
            } else if isStaticImage {
                let preferPng = (mime == "image/png" || ext == "png")
                strippedData = MTMediaTokWave5Tools.stripImageMetadata(rawData, preferPng: preferPng)
                if strippedData != nil && !preferPng && (mime == "image/heic" || mime == "image/tiff" || ["heic", "tiff", "tif"].contains(ext)) {
                    updatedMime = "image/jpeg"
                    updatedAttrs = file.attributes.map { attr in
                        if case let .FileName(fn) = attr {
                            let stem = (fn as NSString).deletingPathExtension
                            return .FileName(fileName: "\(stem).jpg")
                        }
                        return attr
                    }
                }
            }

            guard let cleanData = strippedData, !cleanData.isEmpty else { continue }
            let newFileId = Int64.random(in: Int64.min ... Int64.max)
            let newRes = LocalFileMediaResource(fileId: newFileId)
            context.account.postbox.mediaBox.storeResourceData(newRes.id, data: cleanData, synchronous: true)

            let updatedFile = TelegramMediaFile(
                fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: newFileId),
                partialReference: nil,
                resource: newRes,
                previewRepresentations: file.previewRepresentations,
                videoThumbnails: file.videoThumbnails,
                immediateThumbnailData: file.immediateThumbnailData,
                mimeType: updatedMime,
                size: Int64(cleanData.count),
                attributes: updatedAttrs,
                alternativeRepresentations: []
            )
            messages[i] = .message(
                text: text,
                attributes: attributes,
                inlineStickers: inlineStickers,
                mediaReference: .standalone(media: updatedFile),
                threadId: threadId,
                replyToMessageId: replyToMessageId,
                replyToStoryId: replyToStoryId,
                localGroupingKey: localGroupingKey,
                correlationId: correlationId,
                bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets
            )
        }
    }

    static func stripImageMetadata(_ data: Data, preferPng: Bool) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(src) == 1 else {
            return nil // Skip animated GIF/WebP so animation & MIME are never corrupted
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let maxSide = max(
            (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0,
            (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        )
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(maxSide > 0 ? maxSide : 4096, 4096))
        ]
        guard let orientedCG = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        let uti = (preferPng ? UTType.png : UTType.jpeg).identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(out, uti, 1, nil) else {
            return nil
        }
        let destOpts: CFDictionary? = preferPng ? nil : ([kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
        CGImageDestinationAddImage(dest, orientedCG, destOpts)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    static func stripPdfMetadata(_ data: Data) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData),
              let doc = CGPDFDocument(provider),
              doc.numberOfPages > 0,
              doc.numberOfPages <= 80,
              let firstPage = doc.page(at: 1) else {
            return nil
        }
        let firstBounds = firstPage.getBoxRect(.mediaBox)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "",
            kCGPDFContextAuthor as String: "",
            kCGPDFContextTitle as String: ""
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds, format: format)
        return renderer.pdfData { ctx in
            for idx in 1 ... doc.numberOfPages {
                guard let page = doc.page(at: idx) else { continue }
                let pageBounds = page.getBoxRect(.mediaBox)
                ctx.beginPage(withBounds: pageBounds, pageInfo: [:])
                let cg = ctx.cgContext
                cg.saveGState()
                cg.setFillColor(UIColor.white.cgColor)
                cg.fill(pageBounds)
                cg.translateBy(x: 0.0, y: pageBounds.height)
                cg.scaleBy(x: 1.0, y: -1.0)
                cg.drawPDFPage(page)
                cg.restoreGState()
            }
        }
    }

    // MARK: Incoming Malware / RLO Inspector & Fresh Streak Tracking

    private static func decorateIncoming(_ decoration: inout MTMessageDecoration, message: Message) {
        if MTMediaTokWave5Tools.isStreaksEnabled && message.flags.contains(.Incoming) {
            MTMediaTokStreaks.recordIncomingIfFresh(message: message)
        }
        for m in message.media {
            if let file = m as? TelegramMediaFile, !file.isSticker {
                let name = file.fileName ?? ""
                if let threat = MTMediaTokCoreLogic.inspectIncomingDocument(fileName: name, mimeType: file.mimeType) {
                    if decoration.footnote == nil {
                        let prefix = threat.isCritical ? "🚨 ОПАСНЫЙ ФАЙЛ" : "⚠️ Подозрительный файл"
                        decoration.footnote = MTMessageFootnote(
                            text: "\(prefix) (MediaTok): \(threat.reason)",
                            entities: [],
                            alpha: 0.96
                        )
                    }
                    break
                }
            }
        }
    }

    private static func profileStreakRows(_ info: MTPeerInfoContext) -> [MTPeerInfoRow] {
        if info.isSettings || !MTMediaTokWave5Tools.isStreaksEnabled { return [] }
        guard let rec = MTMediaTokStreaks.record(for: info.peer.id) else { return [] }
        let context = info.context
        return [MTPeerInfoRow(
            id: "mediatok.streak",
            label: "Серия общения",
            text: "\(rec.currentStreak) дн. (рекорд \(rec.bestStreak))",
            rightLabel: "\(rec.totalMessages) сообщ.",
            action: {
                MTMediaTokWave5Tools.presentStreaksLeaderboard(context: context)
            }
        )]
    }

    // MARK: Confirmation Guards (Forwards & Photos)

    private static func guardPhotoSend(_ messages: inout [EnqueueMessage], context: MTOutgoingContext) {
        guard MTMediaTokWave5Tools.isConfirmPhotoSendEnabled else { return }
        var unconfirmedIds: [Int64] = []

        MTMediaTokWave5Tools.guardLock.lock()
        for msg in messages {
            if case let .message(_, _, _, mediaRef, _, _, _, _, _, _) = msg,
               let unwrappedRef = mediaRef,
               case let .standalone(media) = unwrappedRef,
               let img = media as? TelegramMediaImage,
               !MTMediaTokWave5Tools.confirmedPhotoIds.contains(img.imageId.id) {
                unconfirmedIds.append(img.imageId.id)
            }
        }
        if !unconfirmedIds.isEmpty {
            if MTMediaTokWave5Tools.confirmedPhotoIds.count > 256 {
                MTMediaTokWave5Tools.confirmedPhotoIds.removeAll()
            }
            for id in unconfirmedIds {
                MTMediaTokWave5Tools.confirmedPhotoIds.insert(id)
            }
        }
        MTMediaTokWave5Tools.guardLock.unlock()

        guard !unconfirmedIds.isEmpty else { return }
        let heldMessages = messages
        messages = []
        let count = unconfirmedIds.count

        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "📸 Подтвердить отправку фото (\(count))?",
                message: "Защита MediaTok от случайной отправки снимка или фото из галереи.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Отправить", style: .default, handler: { _ in
                _ = enqueueMessages(account: context.account, peerId: context.peerId, messages: heldMessages).start()
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            MTMediaTokWave5Tools.presentOnRoot(alert)
        }
    }

    private static func confirmForwardIfNeeded(account: Account, messages: [EnqueueMessage]) -> Signal<[EnqueueMessage], NoError>? {
        guard MTMediaTokWave5Tools.isConfirmForwardEnabled else { return nil }
        let forwardCount = messages.reduce(0) { acc, m in
            if case .forward = m { return acc + 1 }
            return acc
        }
        guard forwardCount > 0 else { return nil }

        return Signal { subscriber in
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "📤 Подтвердить пересылку (\(forwardCount))?",
                    message: "Защита MediaTok от случайного пересыла не в тот чат.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Переслать", style: .default, handler: { _ in
                    var delegated: Signal<[EnqueueMessage], NoError>?
                    for handler in MTOutgoingHooks.forwardCopies.handlers.dropFirst() {
                        if let sig = handler(account, messages) {
                            delegated = sig
                            break
                        }
                    }
                    let finalSig = delegated ?? .single(messages)
                    let _ = finalSig.start(next: { finalMsgs in
                        subscriber.putNext(finalMsgs)
                        subscriber.putCompletion()
                    })
                }))
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: { _ in
                    subscriber.putNext([])
                    subscriber.putCompletion()
                }))
                MTMediaTokWave5Tools.presentOnRoot(alert)
            }
            return EmptyDisposable
        }
    }

    // MARK: Hub, Clean File Picker, Mini-Games & Updater

    fileprivate static var docDelegateHolder: MTCleanDocSenderCoordinator?

    private static func presentCleanDocumentSender(context: AccountContext, peerId: PeerId) {
        DispatchQueue.main.async {
            let coord = MTCleanDocSenderCoordinator(context: context, peerId: peerId)
            MTMediaTokWave5Tools.docDelegateHolder = coord
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .pdf], asCopy: true)
            picker.allowsMultipleSelection = false
            picker.delegate = coord
            MTMediaTokWave5Tools.presentOnRoot(picker)
        }
    }

    static func presentClipboardPicker(onPick: ((String) -> Void)?) {
        DispatchQueue.main.async {
            let vc = MTClipboardHistoryViewController(onPick: onPick)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            MTMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    static func presentStreaksLeaderboard(context: AccountContext) {
        DispatchQueue.main.async {
            let top = MTMediaTokStreaks.topStreaks(limit: 15)
            let body: String
            if top.isEmpty {
                body = "Активных огоньков пока нет. Общайтесь каждый день чтобы копить серию! Каждый месяц выдаётся 2 заморозки ❄️."
            } else {
                body = top.enumerated().map { idx, row in
                    let tier = MTMediaTokCoreLogic.streakTierBadge(days: row.record.currentStreak)
                    return "\(idx + 1). \(row.name) — \(tier) \(row.record.currentStreak) дн. (рекорд \(row.record.bestStreak), ❄️ \(row.record.freezesRemaining)/2)"
                }.joined(separator: "\n")
            }
            let alert = UIAlertController(title: "🔥 Огоньки общения MediaTok", message: body, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            MTMediaTokWave5Tools.presentOnRoot(alert)
        }
    }

    static func presentMiniGamesHub() {
        DispatchQueue.main.async {
            let vc = MTMiniGamesHubViewController()
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .fullScreen
            MTMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    static func presentUpdateChecker() {
        DispatchQueue.main.async {
            let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
            let repoSourceUrl = "https://github.com/ownersavesociety/MediaTok-iOS/releases/latest/download/apps.json"
            let loading = UIAlertController(
                title: "🔄 Обновления MediaTok iOS",
                message: "Текущая сборка: b\(currentBuild)\nПроверяю GitHub Releases...",
                preferredStyle: .alert
            )
            loading.addAction(UIAlertAction(title: "Скопировать ESign/SideStore репо", style: .default, handler: { _ in
                UIPasteboard.general.string = repoSourceUrl
            }))
            loading.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
            MTMediaTokWave5Tools.presentOnRoot(loading)

            guard let apiUrl = URL(string: "https://api.github.com/repos/ownersavesociety/MediaTok-iOS/releases/latest") else { return }
            var req = URLRequest(url: apiUrl, timeoutInterval: 10.0)
            req.setValue("MediaTok/Updater", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { [weak loading] data, _, _ in
                guard let data,
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let tag = obj["tag_name"] as? String else {
                    return
                }
                let htmlUrlStr = obj["html_url"] as? String ?? "https://github.com/ownersavesociety/MediaTok-iOS/releases/latest"
                DispatchQueue.main.async {
                    loading?.message = "Текущая сборка: b\(currentBuild)\nПоследний релиз: \(tag)\n\nESign / Feather / SideStore Source URL:\n\(repoSourceUrl)"
                    if let url = URL(string: htmlUrlStr) {
                        loading?.addAction(UIAlertAction(title: "Открыть релиз GitHub", style: .default, handler: { _ in
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }))
                    }
                }
            }.resume()
        }
    }

    static func presentHub(context: MTMenuContext) {
        let topCount = MTMediaTokStreaks.topStreaks(limit: 5).first?.record.currentStreak ?? 0
        let clipCount = MTMediaTokClipboard.allItems().count
        let streaksState = MTMediaTokWave5Tools.isStreaksEnabled ? "ВКЛ" : "ВЫКЛ"
        let metaState = MTMediaTokWave5Tools.isStripFileMetaEnabled ? "ВКЛ" : "ВЫКЛ"
        let fwdState = MTMediaTokWave5Tools.isConfirmForwardEnabled ? "ВКЛ" : "ВЫКЛ"
        let photoState = MTMediaTokWave5Tools.isConfirmPhotoSendEnabled ? "ВКЛ" : "ВЫКЛ"

        let sheet = UIAlertController(
            title: "MediaTok Wave 5 — Инструменты",
            message: "Команды: /s [запрос], /s! [тег], .card Заг | Подзаг | Стр, .streak, .clip, .q, .stats, .c, .color, .e2e",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Серии общения (огонёк): \(streaksState)", style: .default, handler: { _ in
            MTMediaTokWave5Tools.isStreaksEnabled.toggle()
            context.presentToast("Серии общения: \(MTMediaTokWave5Tools.isStreaksEnabled ? "ВКЛ" : "ВЫКЛ")")
        }))
        sheet.addAction(UIAlertAction(title: "Список серий общения (макс: \(topCount) дн.)", style: .default, handler: { _ in
            MTMediaTokWave5Tools.presentStreaksLeaderboard(context: context.context)
        }))
        sheet.addAction(UIAlertAction(title: "📋 Буфер обмена (\(clipCount) фрагм.)", style: .default, handler: { _ in
            MTMediaTokWave5Tools.presentClipboardPicker(onPick: nil)
        }))
        sheet.addAction(UIAlertAction(title: "🧹 Вырезать EXIF/PDF-мету из файлов: \(metaState)", style: .default, handler: { _ in
            MTMediaTokWave5Tools.isStripFileMetaEnabled.toggle()
            context.presentToast("Очистка метаданных файлов: \(MTMediaTokWave5Tools.isStripFileMetaEnabled ? "ВКЛ" : "ВЫКЛ")")
        }))
        sheet.addAction(UIAlertAction(title: "📤 Подтверждать пересылку: \(fwdState)", style: .default, handler: { _ in
            MTMediaTokWave5Tools.isConfirmForwardEnabled.toggle()
            context.presentToast("Подтверждение пересылки: \(MTMediaTokWave5Tools.isConfirmForwardEnabled ? "ВКЛ" : "ВЫКЛ")")
        }))
        sheet.addAction(UIAlertAction(title: "📸 Подтверждать отправку фото: \(photoState)", style: .default, handler: { _ in
            MTMediaTokWave5Tools.isConfirmPhotoSendEnabled.toggle()
            context.presentToast("Подтверждение фото: \(MTMediaTokWave5Tools.isConfirmPhotoSendEnabled ? "ВКЛ" : "ВЫКЛ")")
        }))
        sheet.addAction(UIAlertAction(title: "🎮 Офлайн мини-игры (2048 & Змейка)", style: .default, handler: { _ in
            MTMediaTokWave5Tools.presentMiniGamesHub()
        }))
        sheet.addAction(UIAlertAction(title: "🔄 Обновления и ESign-репо (apps.json)", style: .default, handler: { _ in
            MTMediaTokWave5Tools.presentUpdateChecker()
        }))
        sheet.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        context.presentNative(sheet)
    }

    static func presentOnRoot(_ controller: UIViewController) {
        MTModalPresenter.presentOnTopmost(controller)
    }

    static func showToast(context: AccountContext, text: String) {
        DispatchQueue.main.async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let overlay = UndoOverlayController(
                presentationData: presentationData,
                content: .info(title: nil, text: text, timeout: nil, customUndoText: nil),
                elevatedLayout: false,
                action: { _ in return false }
            )
            context.sharedContext.mainWindow?.present(overlay, on: .root)
        }
    }
}

private final class MTCleanDocSenderCoordinator: NSObject, UIDocumentPickerDelegate {
    private let context: AccountContext
    private let peerId: PeerId

    init(context: AccountContext, peerId: PeerId) {
        self.context = context
        self.peerId = peerId
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        MTMediaTokWave5Tools.docDelegateHolder = nil
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        MTMediaTokWave5Tools.docDelegateHolder = nil
        guard let url = urls.first else { return }
        let ctx = self.context
        let pid = self.peerId
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0, fileSize <= 40 * 1024 * 1024 else {
            try? FileManager.default.removeItem(at: url)
            MTMediaTokWave5Tools.showToast(context: ctx, text: "Файл слишком большой для очистки (макс. 40 МБ)")
            return
        }
        MTMediaTokWave5Tools.showToast(context: ctx, text: "🧹 Очищаю метаданные файла...")
        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let rawData = try? Data(contentsOf: url), !rawData.isEmpty else { return }
            let cleanData: Data?
            let mime: String
            if ext == "pdf" {
                cleanData = MTMediaTokWave5Tools.stripPdfMetadata(rawData)
                mime = "application/pdf"
            } else {
                cleanData = MTMediaTokWave5Tools.stripImageMetadata(rawData, preferPng: ext == "png")
                mime = ext == "png" ? "image/png" : "image/jpeg"
            }
            guard let finalData = cleanData, !finalData.isEmpty else {
                DispatchQueue.main.async {
                    MTMediaTokWave5Tools.showToast(context: ctx, text: "❌ Не удалось очистить метаданные — отправка отменена")
                }
                return
            }
            let fileId = Int64.random(in: Int64.min ... Int64.max)
            let resource = LocalFileMediaResource(fileId: fileId)
            ctx.account.postbox.mediaBox.storeResourceData(resource.id, data: finalData, synchronous: true)
            let media = TelegramMediaFile(
                fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: fileId),
                partialReference: nil,
                resource: resource,
                previewRepresentations: [],
                videoThumbnails: [],
                immediateThumbnailData: nil,
                mimeType: mime,
                size: Int64(finalData.count),
                attributes: [.FileName(fileName: "clean_\(name)")],
                alternativeRepresentations: []
            )
            let msg: EnqueueMessage = .message(
                text: "",
                attributes: [],
                inlineStickers: [:],
                mediaReference: .standalone(media: media),
                threadId: nil,
                replyToMessageId: nil,
                replyToStoryId: nil,
                localGroupingKey: nil,
                correlationId: nil,
                bubbleUpEmojiOrStickersets: []
            )
            DispatchQueue.main.async {
                _ = enqueueMessages(account: ctx.account, peerId: pid, messages: [msg]).start()
                MTMediaTokWave5Tools.showToast(context: ctx, text: "🧹 Файл очищен от EXIF/GPS/метаданных и отправлен!")
            }
        }
    }
}

// MARK: - 4. Offline Mini-Games Hub (2048 Neon + Neon Snake)

private final class MTMiniGamesHubViewController: UIViewController {
    private let segmented = UISegmentedControl(items: ["2048 Neon", "Змейка 🐍", "Сапёр 💣"])
    private let container = UIView()
    private let game2048 = GG2048View()
    private let snakeGame = MTSnakeView()
    private var minesweeperVC: MTMinesweeperViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = .dark
        self.title = "🎮 Офлайн-игры MediaTok"
        self.view.backgroundColor = UIColor(rgb: 0x0B0F17)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closeTapped))

        self.segmented.selectedSegmentIndex = 0
        self.segmented.backgroundColor = UIColor(rgb: 0x161D2E)
        self.segmented.selectedSegmentTintColor = UIColor(rgb: 0x00F5FF)
        self.segmented.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        self.segmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        self.segmented.addTarget(self, action: #selector(self.tabChanged), for: .valueChanged)
        self.segmented.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.segmented)

        self.container.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.container)

        self.game2048.translatesAutoresizingMaskIntoConstraints = false
        self.snakeGame.translatesAutoresizingMaskIntoConstraints = false
        self.container.addSubview(self.game2048)
        self.container.addSubview(self.snakeGame)

        NSLayoutConstraint.activate([
            self.segmented.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 10.0),
            self.segmented.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            self.segmented.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),
            self.container.topAnchor.constraint(equalTo: self.segmented.bottomAnchor, constant: 12.0),
            self.container.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.container.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.container.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            self.game2048.topAnchor.constraint(equalTo: self.container.topAnchor),
            self.game2048.leadingAnchor.constraint(equalTo: self.container.leadingAnchor),
            self.game2048.trailingAnchor.constraint(equalTo: self.container.trailingAnchor),
            self.game2048.bottomAnchor.constraint(equalTo: self.container.bottomAnchor),
            self.snakeGame.topAnchor.constraint(equalTo: self.container.topAnchor),
            self.snakeGame.leadingAnchor.constraint(equalTo: self.container.leadingAnchor),
            self.snakeGame.trailingAnchor.constraint(equalTo: self.container.trailingAnchor),
            self.snakeGame.bottomAnchor.constraint(equalTo: self.container.bottomAnchor)
        ])

        self.tabChanged()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.snakeGame.stopTimer()
    }

    @objc private func tabChanged() {
        let idx = self.segmented.selectedSegmentIndex
        if idx == 2 && self.minesweeperVC == nil {
            let ms = MTMinesweeperViewController()
            ms.overrideUserInterfaceStyle = .dark
            self.addChild(ms)
            ms.view.translatesAutoresizingMaskIntoConstraints = false
            self.container.addSubview(ms.view)
            NSLayoutConstraint.activate([
                ms.view.topAnchor.constraint(equalTo: self.container.topAnchor),
                ms.view.leadingAnchor.constraint(equalTo: self.container.leadingAnchor),
                ms.view.trailingAnchor.constraint(equalTo: self.container.trailingAnchor),
                ms.view.bottomAnchor.constraint(equalTo: self.container.bottomAnchor)
            ])
            ms.didMove(toParent: self)
            self.minesweeperVC = ms
        }
        self.game2048.isHidden = (idx != 0)
        self.snakeGame.isHidden = (idx != 1)
        self.minesweeperVC?.view.isHidden = (idx != 2)
        if idx == 1 {
            self.snakeGame.ensureRunning()
        } else {
            self.snakeGame.stopTimer()
        }
    }

    @objc private func closeTapped() {
        self.snakeGame.stopTimer()
        self.dismiss(animated: true)
    }
}

private final class GG2048View: UIView {
    private var board = [Int](repeating: 0, count: 16)
    private var score = 0
    private let bestKey = "mediatok.game.2048.best"
    private let scoreLabel = UILabel()
    private var tileLabels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupUI()
        self.resetGame()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        self.scoreLabel.font = UIFont.monospacedSystemFont(ofSize: 18.0, weight: .bold)
        self.scoreLabel.textColor = UIColor(rgb: 0x00F5FF)
        self.scoreLabel.textAlignment = .center
        self.scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.scoreLabel)

        let grid = UIView()
        grid.backgroundColor = UIColor(rgb: 0x161D2E)
        grid.layer.cornerRadius = 16.0
        grid.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(grid)

        let restart = UIButton(type: .system)
        restart.setTitle("🔄 Новая игра", for: .normal)
        restart.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .bold)
        restart.tintColor = UIColor(rgb: 0x00F5FF)
        restart.addTarget(self, action: #selector(self.resetGame), for: .touchUpInside)
        restart.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(restart)

        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 8.0
        rows.distribution = .fillEqually
        rows.translatesAutoresizingMaskIntoConstraints = false
        grid.addSubview(rows)

        for _ in 0 ..< 4 {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8.0
            row.distribution = .fillEqually
            for _ in 0 ..< 4 {
                let lbl = UILabel()
                lbl.textAlignment = .center
                lbl.font = UIFont.systemFont(ofSize: 22.0, weight: .heavy)
                lbl.layer.cornerRadius = 10.0
                lbl.clipsToBounds = true
                row.addArrangedSubview(lbl)
                self.tileLabels.append(lbl)
            }
            rows.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            self.scoreLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 12.0),
            self.scoreLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            grid.topAnchor.constraint(equalTo: self.scoreLabel.bottomAnchor, constant: 18.0),
            grid.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            grid.widthAnchor.constraint(equalTo: self.widthAnchor, constant: -36.0),
            grid.heightAnchor.constraint(equalTo: grid.widthAnchor),
            rows.topAnchor.constraint(equalTo: grid.topAnchor, constant: 10.0),
            rows.leadingAnchor.constraint(equalTo: grid.leadingAnchor, constant: 10.0),
            rows.trailingAnchor.constraint(equalTo: grid.trailingAnchor, constant: -10.0),
            rows.bottomAnchor.constraint(equalTo: grid.bottomAnchor, constant: -10.0),
            restart.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20.0),
            restart.centerXAnchor.constraint(equalTo: self.centerXAnchor)
        ])

        for dir: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
            let g = UISwipeGestureRecognizer(target: self, action: #selector(self.handleSwipe(_:)))
            g.direction = dir
            self.addGestureRecognizer(g)
        }
    }

    @objc private func resetGame() {
        self.board = [Int](repeating: 0, count: 16)
        self.score = 0
        self.spawnTile()
        self.spawnTile()
        self.render()
    }

    private func spawnTile() {
        let empty = self.board.indices.filter { self.board[$0] == 0 }
        guard let pick = empty.randomElement() else { return }
        self.board[pick] = Int.random(in: 0 ..< 10) == 0 ? 4 : 2
    }

    private func slideRow(_ line: [Int]) -> (out: [Int], gained: Int) {
        let nonZero = line.filter { $0 != 0 }
        var merged: [Int] = []
        var gained = 0
        var i = 0
        while i < nonZero.count {
            if i + 1 < nonZero.count && nonZero[i] == nonZero[i + 1] {
                let val = nonZero[i] * 2
                merged.append(val)
                gained += val
                i += 2
            } else {
                merged.append(nonZero[i])
                i += 1
            }
        }
        while merged.count < 4 { merged.append(0) }
        return (merged, gained)
    }

    @objc private func handleSwipe(_ g: UISwipeGestureRecognizer) {
        let old = self.board
        var totalGain = 0
        for idx in 0 ..< 4 {
            var line: [Int] = []
            for step in 0 ..< 4 {
                switch g.direction {
                case .left: line.append(self.board[idx * 4 + step])
                case .right: line.append(self.board[idx * 4 + (3 - step)])
                case .up: line.append(self.board[step * 4 + idx])
                default: line.append(self.board[(3 - step) * 4 + idx])
                }
            }
            let res = self.slideRow(line)
            totalGain += res.gained
            for step in 0 ..< 4 {
                switch g.direction {
                case .left: self.board[idx * 4 + step] = res.out[step]
                case .right: self.board[idx * 4 + (3 - step)] = res.out[step]
                case .up: self.board[step * 4 + idx] = res.out[step]
                default: self.board[(3 - step) * 4 + idx] = res.out[step]
                }
            }
        }
        if self.board != old {
            self.score += totalGain
            let best = max(self.score, UserDefaults.standard.integer(forKey: self.bestKey))
            UserDefaults.standard.set(best, forKey: self.bestKey)
            self.spawnTile()
            self.render()
        }
    }

    private func render() {
        let best = max(self.score, UserDefaults.standard.integer(forKey: self.bestKey))
        self.scoreLabel.text = "Счёт: \(self.score)   |   Рекорд: \(best)"
        for i in 0 ..< 16 {
            let v = self.board[i]
            let lbl = self.tileLabels[i]
            lbl.text = v == 0 ? "" : "\(v)"
            lbl.textColor = v <= 4 ? UIColor.white : UIColor(rgb: 0x0B0F17)
            switch v {
            case 0: lbl.backgroundColor = UIColor(rgb: 0x222C42)
            case 2: lbl.backgroundColor = UIColor(rgb: 0x2C3E50); lbl.textColor = .white
            case 4: lbl.backgroundColor = UIColor(rgb: 0x3D5A80); lbl.textColor = .white
            case 8: lbl.backgroundColor = UIColor(rgb: 0x00B4D8)
            case 16: lbl.backgroundColor = UIColor(rgb: 0x00F5FF)
            case 32: lbl.backgroundColor = UIColor(rgb: 0x80FFDB)
            case 64: lbl.backgroundColor = UIColor(rgb: 0xFFB703)
            case 128: lbl.backgroundColor = UIColor(rgb: 0xFB8500)
            case 256: lbl.backgroundColor = UIColor(rgb: 0xFF4D8D)
            default: lbl.backgroundColor = UIColor(rgb: 0xC77DFF)
            }
        }
    }
}

private final class MTSnakeView: UIView {
    private let gridSize = 16
    private var snake: [(x: Int, y: Int)] = [(8, 8), (7, 8), (6, 8)]
    private var dir: (dx: Int, dy: Int) = (1, 0)
    private var food: (x: Int, y: Int) = (12, 8)
    private var score = 0
    private let bestKey = "mediatok.game.snake.best"
    private var timer: Foundation.Timer?
    private let scoreLabel = UILabel()
    private let boardView = UIView()
    private var cells: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.stopTimer()
    }

    private func setupUI() {
        self.scoreLabel.font = UIFont.monospacedSystemFont(ofSize: 18.0, weight: .bold)
        self.scoreLabel.textColor = UIColor(rgb: 0x00FF87)
        self.scoreLabel.textAlignment = .center
        self.scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.scoreLabel)

        self.boardView.backgroundColor = UIColor(rgb: 0x161D2E)
        self.boardView.layer.cornerRadius = 14.0
        self.boardView.clipsToBounds = true
        self.boardView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.boardView)

        let total = self.gridSize * self.gridSize
        for _ in 0 ..< total {
            let v = UIView()
            v.layer.cornerRadius = 3.0
            self.boardView.addSubview(v)
            self.cells.append(v)
        }

        let restart = UIButton(type: .system)
        restart.setTitle("🔄 Рестарт змейки", for: .normal)
        restart.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .bold)
        restart.tintColor = UIColor(rgb: 0x00FF87)
        restart.addTarget(self, action: #selector(self.resetGame), for: .touchUpInside)
        restart.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(restart)

        NSLayoutConstraint.activate([
            self.scoreLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 12.0),
            self.scoreLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.boardView.topAnchor.constraint(equalTo: self.scoreLabel.bottomAnchor, constant: 16.0),
            self.boardView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.boardView.widthAnchor.constraint(equalTo: self.widthAnchor, constant: -36.0),
            self.boardView.heightAnchor.constraint(equalTo: self.boardView.widthAnchor),
            restart.topAnchor.constraint(equalTo: self.boardView.bottomAnchor, constant: 18.0),
            restart.centerXAnchor.constraint(equalTo: self.centerXAnchor)
        ])

        for d: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
            let g = UISwipeGestureRecognizer(target: self, action: #selector(self.handleSwipe(_:)))
            g.direction = d
            self.addGestureRecognizer(g)
        }
        self.resetGame()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = self.boardView.bounds.width
        guard side > 32.0 else { return }
        let cellSide = side / CGFloat(self.gridSize)
        for y in 0 ..< self.gridSize {
            for x in 0 ..< self.gridSize {
                self.cells[y * self.gridSize + x].frame = CGRect(
                    x: CGFloat(x) * cellSide + 1.0,
                    y: CGFloat(y) * cellSide + 1.0,
                    width: cellSide - 2.0,
                    height: cellSide - 2.0
                )
            }
        }
    }

    func ensureRunning() {
        if self.timer != nil { return }
        self.timer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }

    @objc private func resetGame() {
        self.snake = [(8, 8), (7, 8), (6, 8)]
        self.dir = (1, 0)
        self.food = (12, 8)
        self.score = 0
        self.render()
        if !self.isHidden {
            self.ensureRunning()
        }
    }

    @objc private func handleSwipe(_ g: UISwipeGestureRecognizer) {
        switch g.direction {
        case .left where self.dir.dx != 1: self.dir = (-1, 0)
        case .right where self.dir.dx != -1: self.dir = (1, 0)
        case .up where self.dir.dy != 1: self.dir = (0, -1)
        case .down where self.dir.dy != -1: self.dir = (0, 1)
        default: break
        }
    }

    private func tick() {
        guard !self.isHidden else { return }
        let head = self.snake[0]
        let nx = (head.x + self.dir.dx + self.gridSize) % self.gridSize
        let ny = (head.y + self.dir.dy + self.gridSize) % self.gridSize
        if self.snake.contains(where: { $0.x == nx && $0.y == ny }) {
            self.resetGame()
            return
        }
        self.snake.insert((nx, ny), at: 0)
        if nx == self.food.x && ny == self.food.y {
            self.score += 1
            let best = max(self.score, UserDefaults.standard.integer(forKey: self.bestKey))
            UserDefaults.standard.set(best, forKey: self.bestKey)
            var candidates: [(Int, Int)] = []
            for y in 0 ..< self.gridSize {
                for x in 0 ..< self.gridSize where !self.snake.contains(where: { $0.x == x && $0.y == y }) {
                    candidates.append((x, y))
                }
            }
            if let f = candidates.randomElement() { self.food = f }
        } else {
            self.snake.removeLast()
        }
        self.render()
    }

    private func render() {
        let best = max(self.score, UserDefaults.standard.integer(forKey: self.bestKey))
        self.scoreLabel.text = "Очки: \(self.score)   |   Рекорд: \(best)"
        for v in self.cells {
            v.backgroundColor = UIColor(rgb: 0x1D263B)
        }
        self.cells[self.food.y * self.gridSize + self.food.x].backgroundColor = UIColor(rgb: 0xFF3B5C)
        for (idx, seg) in self.snake.enumerated() {
            let color = (idx == 0) ? UIColor(rgb: 0x00F5FF) : UIColor(rgb: 0x00FF87)
            self.cells[seg.y * self.gridSize + seg.x].backgroundColor = color
        }
    }
}
