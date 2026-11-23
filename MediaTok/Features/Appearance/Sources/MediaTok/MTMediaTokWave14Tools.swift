import Foundation
import UIKit
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
import MTFeaturesShared

// ============================================================================
// MediaTok Wave 14 — OSINT, Global Audit Log, Chat Export, Spellfix & Streamer Mode:
//   #219 / .osintuser  — Search all messages by a specific user across all shared groups & cache
//   #205/#244/#245     — Global Audit Log & Filter of Deleted/Edited messages (.deleted / .audit)
//   #272 / .exportchat — Standalone Dark HTML (with live search) / JSON / TXT chat exporter
//   #166 / .spell      — Offline Russian/English spellcheck (UITextChecker) + layout/punctuation fixer
//   #225 / .streamblur — Streamer Blur Mode with draggable floating privacy pill
//   #235 / .panicclean — Instant temporary, URLCache & Library/Caches purge
// ============================================================================

public enum MTMediaTokWave14Tools {
    private static var streamerOverlayWindow: UIView?

    public static func register() {
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave14Tools.interceptCommands(request)
        }, order: 36)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave14Tools.messageMenuItems(menuContext)
        }, order: 96)
    }

    // MARK: - Top VC Helper

    private static func topViewController() -> UIViewController? {
        return MTModalPresenter.topmostViewController()
    }

    // MARK: - Slash Commands

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix(".") else { return false }
        let lower = raw.lowercased()
        let peerId = request.chatLocation.peerId

        // #166 / .spell <text> (.layoutfix / .autocorrect) — avoids Wave 6 .fix collision
        let spellPrefixes = [".spell ", ".layoutfix ", ".autocorrect "]
        if let prefix = spellPrefixes.first(where: { lower.hasPrefix($0) }) {
            let body = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return false }
            let fixed = Self.fixTextSpellingAndPunctuation(body)
            request.replace(ChatTextInputState(inputText: NSAttributedString(string: fixed)))
            MTMediaTokWave5Tools.showToast(context: request.context, text: "Текст исправлен (.spell)")
            return true
        }
        if lower == ".spell" || lower == ".layoutfix" || lower == ".autocorrect" {
            request.replace(ChatTextInputState())
            MTMediaTokWave5Tools.showToast(context: request.context, text: "Использование: .spell <текст> (или .layoutfix <текст>)")
            return true
        }

        // #219 / .osintuser [query]
        if lower == ".osintuser" || lower.hasPrefix(".osintuser ") {
            let query = lower.hasPrefix(".osintuser ") ? String(raw.dropFirst(11)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                presentOsintUserSearch(context: request.context, targetAuthorId: nil, initialQuery: query)
            }
            return true
        }

        // #205 / #244 / #245 — Global Audit Log & Deleted Filter
        if lower == ".deleted" || lower == ".audit" || lower == ".auditlog" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                presentGlobalAuditLog(context: request.context, initialPeerId: peerId)
            }
            return true
        }

        // #272 — Autonomous Chat Export
        if lower == ".exportchat" || lower == ".export" {
            request.replace(ChatTextInputState())
            guard let peerId = peerId else { return true }
            DispatchQueue.main.async {
                presentExportFormatPicker(context: request.context, peerId: peerId)
            }
            return true
        }

        // #225 — Streamer Blur Mode (.streamblur / .sblur / .streamer — avoids Wave 8 .blur face-blur collision)
        if lower == ".streamblur" || lower == ".sblur" || lower == ".streamer" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                toggleStreamerBlur(context: request.context)
            }
            return true
        }

        // #235 — Panic Cache Clean
        if lower == ".panicclean" || lower == ".cleancache" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                presentPanicCleanAlert(context: request.context)
            }
            return true
        }

        return false
    }

    // MARK: - Context Menu (#219 All messages by author across chats)

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        let _ = menuContext
        return []
    }

    // MARK: - #166 Offline Spellcheck + Layout + Punctuation Fixer

    public static func fixTextSpellingAndPunctuation(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // 1. Auto-fix Russian typed on QWERTY English layout if mostly consonants/non-English
        let enToRu: [Character: Character] = [
            "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ъ",
            "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э",
            "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь", ",": "б", ".": "ю",
            "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З", "{": "Х", "}": "Ъ",
            "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж", "\"": "Э",
            "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь", "<": "Б", ">": "Ю"
        ]

        let hasCyrillic = text.unicodeScalars.contains { (0x0400 ... 0x04FF).contains($0.value) }
        let hasLatin = text.unicodeScalars.contains { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }
        let checker = UITextChecker()

        if !hasCyrillic && hasLatin {
            let ns = text as NSString
            let firstMisspelledEn = checker.rangeOfMisspelledWord(in: text, range: NSRange(location: 0, length: ns.length), startingAt: 0, wrap: false, language: "en_US")
            if firstMisspelledEn.location != NSNotFound {
                let converted = String(text.map { enToRu[$0] ?? $0 })
                let cns = converted as NSString
                let firstMisspelledRu = checker.rangeOfMisspelledWord(in: converted, range: NSRange(location: 0, length: cns.length), startingAt: 0, wrap: false, language: "ru_RU")
                if firstMisspelledRu.location == NSNotFound {
                    text = converted
                }
            }
        }

        // 2. Collapse repeated spaces & normalize punctuation spacing
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        for punct in [",", ".", "!", "?", ";", ":"] {
            text = text.replacingOccurrences(of: " \(punct)", with: punct)
        }

        // 3. Offline UITextChecker word-level correction
        let lang = text.unicodeScalars.contains(where: { (0x0400 ... 0x04FF).contains($0.value) }) ? "ru_RU" : "en_US"
        let mutable = NSMutableString(string: text)
        var offset = 0
        var iterations = 0
        while offset < mutable.length && iterations < 60 {
            iterations += 1
            let full = mutable as String
            let range = checker.rangeOfMisspelledWord(in: full, range: NSRange(location: 0, length: mutable.length), startingAt: offset, wrap: false, language: lang)
            if range.location == NSNotFound {
                break
            }
            if let guesses = checker.guesses(forWordRange: range, in: full, language: lang), let best = guesses.first {
                mutable.replaceCharacters(in: range, with: best)
                offset = range.location + (best as NSString).length
            } else {
                offset = range.location + range.length
            }
        }
        text = mutable as String

        // 4. Capitalize first letter
        if let first = text.first {
            text = String(first).uppercased() + text.dropFirst()
        }
        return text
    }

    // MARK: - #219 Present OSINT User Search

    public static func presentOsintUserSearch(context: AccountContext, targetAuthorId: PeerId?, initialQuery: String) {
        let vc = mtMakeNativeOsintUserSearchController(context: context, targetAuthorId: targetAuthorId, initialQuery: initialQuery)
        mtPushNativeController(vc, context: context)
    }

    // MARK: - #205 / #244 / #245 Present Global Audit Log

    public static func presentGlobalAuditLog(context: AccountContext, initialPeerId: PeerId?) {
        let vc = mtMakeNativeGlobalAuditLogController(context: context, initialPeerId: initialPeerId)
        mtPushNativeController(vc, context: context)
    }

    // MARK: - #272 Autonomous Chat Export (HTML / JSON / TXT)

    public static func presentExportFormatPicker(context: AccountContext, peerId: PeerId) {
        mtPresentNativeActionSheet(
            context: context,
            title: "Экспорт переписки",
            buttons: [
                (title: "HTML (Тёмная тема + поиск)", isDestructive: false, action: {
                    exportChat(context: context, peerId: peerId, format: "html")
                }),
                (title: "JSON (Структурированный архив)", isDestructive: false, action: {
                    exportChat(context: context, peerId: peerId, format: "json")
                }),
                (title: "TXT (Чистый текст)", isDestructive: false, action: {
                    exportChat(context: context, peerId: peerId, format: "txt")
                })
            ]
        )
    }

    private static func exportChat(context: AccountContext, peerId: PeerId, format: String) {
        MTMediaTokWave5Tools.showToast(context: context, text: "Собираю архив чата (\(format.uppercased()))...")
        let _ = (context.account.postbox.transaction { transaction -> (String, [(author: String, date: String, text: String, isDeleted: Bool)]) in
            let title = transaction.getPeer(peerId)?.debugDisplayTitle ?? "Chat"
            let df = DateFormatter()
            df.dateFormat = "dd.MM.yyyy HH:mm:ss"
            var rows: [(author: String, date: String, text: String, isDeleted: Bool)] = []
            transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 2500) { msg in
                let author = msg.author?.debugDisplayTitle ?? (msg.flags.contains(.Incoming) ? title : "Вы")
                let date = df.string(from: Date(timeIntervalSince1970: TimeInterval(msg.timestamp)))
                let isDeleted = msg.attributes.contains { $0 is MTDeletedMessageAttribute }
                var body = msg.text
                if body.isEmpty, !msg.media.isEmpty {
                    body = "[Медиафайл]"
                }
                if !body.isEmpty {
                    rows.append((author: author, date: date, text: body, isDeleted: isDeleted))
                }
                return true
            }
            return (title, rows.reversed())
        } |> deliverOnMainQueue).startStandalone(next: { chatTitle, rows in
            let safeName = chatTitle.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            let filename = "MediaTok_\(safeName)_\(Int(Date().timeIntervalSince1970)).\(format)"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            let output: String
            if format == "json" {
                let jsonItems: [[String: Any]] = rows.map {
                    ["author": $0.author, "date": $0.date, "text": $0.text, "deleted": $0.isDeleted]
                }
                if let data = try? JSONSerialization.data(withJSONObject: ["chat": chatTitle, "count": rows.count, "messages": jsonItems], options: [.prettyPrinted]),
                   let str = String(data: data, encoding: .utf8) {
                    output = str
                } else {
                    output = "{}"
                }
            } else if format == "txt" {
                var lines = ["=== MediaTok Chat Export: \(chatTitle) (\(rows.count) сообщений) ===\n"]
                for r in rows {
                    let tag = r.isDeleted ? " [УДАЛЕНО]" : ""
                    lines.append("[\(r.date)] \(r.author)\(tag): \(r.text)")
                }
                output = lines.joined(separator: "\n")
            } else {
                func escTitle(_ s: String) -> String {
                    return s.replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                        .replacingOccurrences(of: "\"", with: "&quot;")
                        .replacingOccurrences(of: "'", with: "&#39;")
                        .replacingOccurrences(of: "\r\n", with: " ")
                        .replacingOccurrences(of: "\n", with: " ")
                }
                func esc(_ s: String) -> String {
                    return escTitle(s)
                        .replacingOccurrences(of: "\n", with: "<br>")
                }
                var html = """
                <!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
                <title>MediaTok — \(escTitle(chatTitle))</title>
                <style>
                body{margin:0;background:#0b101b;color:#e8eefc;font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:16px}
                .hdr{position:sticky;top:0;background:rgba(11,16,27,.92);backdrop-filter:blur(12px);padding:12px 0;border-bottom:1px solid #1f2a40;margin-bottom:16px}
                input{width:100%;box-sizing:border-box;padding:10px 14px;border-radius:12px;border:1px solid #2b3a55;background:#131b2e;color:#fff;font-size:15px}
                .msg{background:#141d31;border:1px solid #22304d;border-radius:14px;padding:10px 14px;margin-bottom:10px}
                .del{border-color:#ff4d5a;background:#26131c}
                .meta{font-size:12px;color:#8aa0c9;margin-bottom:4px;display:flex;justify-content:space-between}
                .author{font-weight:600;color:#62a8ff}.txt{font-size:15px;line-height:1.45;word-break:break-word}
                </style></head><body>
                <div class="hdr"><h2 style="margin:0 0 8px 0">\(esc(chatTitle)) · \(rows.count) сообщ.</h2>
                <input id="q" placeholder="Поиск по переписке..." oninput="f()"></div><div id="list">
                """
                for r in rows {
                    let cls = r.isDeleted ? "msg del" : "msg"
                    let delBadge = r.isDeleted ? " · УДАЛЕНО" : ""
                    html += "<div class=\"\(cls)\"><div class=\"meta\"><span class=\"author\">\(esc(r.author))\(delBadge)</span><span>\(esc(r.date))</span></div><div class=\"txt\">\(esc(r.text))</div></div>\n"
                }
                html += """
                </div><script>function f(){var q=document.getElementById('q').value.toLowerCase();
                document.querySelectorAll('.msg').forEach(function(el){el.style.display=el.innerText.toLowerCase().includes(q)?'':'none';});}</script></body></html>
                """
                output = html
            }

            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
                if let top = topViewController() {
                    let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    share.completionWithItemsHandler = { _, _, _, _ in
                        try? FileManager.default.removeItem(at: url)
                    }
                    MTModalPresenter.presentOnTopmost(share, preferredRoot: top)
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            } catch {
                MTMediaTokWave5Tools.showToast(context: context, text: "Ошибка экспорта: \(error.localizedDescription)")
            }
        })
    }

    // MARK: - #225 Streamer Blur Mode

    public static func toggleStreamerBlur(context: AccountContext) {
        if let existing = streamerOverlayWindow {
            existing.removeFromSuperview()
            streamerOverlayWindow = nil
            MTMediaTokWave5Tools.showToast(context: context, text: "Режим Стримера (блюр) выключен")
            return
        }
        guard let window = MTModalPresenter.mainAppWindow() else {
            return
        }

        let overlay = MTStreamerBlurOverlayView(frame: window.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.onClose = {
            MTMediaTokWave14Tools.streamerOverlayWindow?.removeFromSuperview()
            MTMediaTokWave14Tools.streamerOverlayWindow = nil
        }
        window.addSubview(overlay)
        streamerOverlayWindow = overlay
        MTMediaTokWave5Tools.showToast(context: context, text: "Режим Стримера активен — нажми на плашку для переключения")
    }

    // MARK: - #235 Panic Cache Clean

    public static func presentPanicCleanAlert(context: AccountContext) {
        mtPresentNativeAlert(
            context: context,
            title: "Экстренная очистка кэша",
            text: "Очистить временные файлы, сетевой URLCache и локальный кэш MediaTok? Ваш вход в аккаунт сохранится.",
            confirmTitle: "Очистить сейчас",
            destructive: true,
            confirmAction: {
                DispatchQueue.global(qos: .userInitiated).async {
                    URLCache.shared.removeAllCachedResponses()
                    MTMediaTokCoreLogic.clearCryptoCache()
                    let fm = FileManager.default
                    var freedBytes: Int64 = 0

                    func itemSizeRecursively(_ url: URL) -> Int64 {
                        if let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                           vals.isDirectory != true {
                            return Int64(vals.fileSize ?? 0)
                        }
                        var total: Int64 = 0
                        if let en = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [], errorHandler: nil) {
                            for case let fileURL as URL in en {
                                if let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                                   vals.isRegularFile == true {
                                    total += Int64(vals.fileSize ?? 0)
                                }
                            }
                        }
                        return total
                    }

                    func clearDirectory(_ dir: URL, skipPrefixes: [String] = []) {
                        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) else {
                            return
                        }
                        for url in items {
                            let name = url.lastPathComponent.lowercased()
                            if skipPrefixes.contains(where: { name.hasPrefix($0) || name.contains($0) }) {
                                continue
                            }
                            freedBytes += itemSizeRecursively(url)
                            try? fm.removeItem(at: url)
                        }
                    }

                    clearDirectory(fm.temporaryDirectory)
                    if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
                        clearDirectory(cachesDir, skipPrefixes: ["com.apple.", "snapshots", "postbox", "telegram-data"])
                    }

                    let mb = Double(freedBytes) / (1024.0 * 1024.0)
                    DispatchQueue.main.async {
                        mtPresentNativeToast(context: context, text: String(format: "Кэш очищен (освобождено %.1f МБ)", mb))
                    }
                }
            }
        )
    }
}

// MARK: - #225 Draggable Streamer Blur View

private final class MTStreamerBlurOverlayView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let pillButton = UIButton(type: .system)
    private var isBlurred = true
    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear

        self.blurView.frame = self.bounds
        self.blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(self.blurView)

        var cfg = UIButton.Configuration.filled()
        cfg.baseBackgroundColor = UIColor(red: 0.12, green: 0.16, blue: 0.28, alpha: 0.92)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        cfg.title = "Стример: Блюр ВКЛ"
        cfg.image = UIImage(systemName: "eye.slash.fill")
        cfg.imagePadding = 6
        self.pillButton.configuration = cfg
        self.pillButton.frame = CGRect(x: max(16, (frame.width - 210) / 2), y: 90, width: 210, height: 40)
        self.pillButton.addTarget(self, action: #selector(toggleBlur), for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(closeTriggered(_:)))
        longPress.minimumPressDuration = 0.6
        self.pillButton.addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.pillButton.addGestureRecognizer(pan)

        self.addSubview(self.pillButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.pillButton.frame.contains(point) {
            return self.pillButton
        }
        return self.isBlurred ? self.blurView : nil
    }

    @objc private func toggleBlur() {
        self.isBlurred.toggle()
        self.blurView.isHidden = !self.isBlurred
        var cfg = self.pillButton.configuration ?? UIButton.Configuration.filled()
        cfg.title = self.isBlurred ? "Стример: Блюр ВКЛ" : "Стример: Блюр ВЫКЛ"
        cfg.image = UIImage(systemName: self.isBlurred ? "eye.slash.fill" : "eye.fill")
        self.pillButton.configuration = cfg
    }

    @objc private func closeTriggered(_ gr: UILongPressGestureRecognizer) {
        if gr.state == .began {
            self.onClose?()
        }
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        let delta = gr.translation(in: self)
        self.pillButton.center = CGPoint(
            x: min(max(105, self.pillButton.center.x + delta.x), self.bounds.width - 105),
            y: min(max(60, self.pillButton.center.y + delta.y), self.bounds.height - 60)
        )
        gr.setTranslation(.zero, in: self)
    }
}

// MARK: - #219 OSINT User Search Native ItemListController

private func mtMakeNativeOsintUserSearchController(context: AccountContext, targetAuthorId: PeerId?, initialQuery: String) -> ItemListController {
    struct FoundMsg: Equatable {
        let chatTitle: String
        let authorName: String
        let text: String
        let dateText: String
        let isDeleted: Bool
    }
    struct OsintState {
        var query: String
        var targetId: PeerId?
        var results: [FoundMsg] = []
        var isSearching: Bool = false
    }

    let stateAtomic = Atomic<OsintState>(value: OsintState(query: initialQuery, targetId: targetAuthorId))
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revCount = 0
    let bump: () -> Void = {
        revCount += 1
        revision.set(revCount)
    }
    weak var weakController: ItemListController?

    let runSearch: () -> Void = {
        let snap = stateAtomic.modify { var n = $0; n.isSearching = true; return n }
        bump()

        let trimmed = snap.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased().replacingOccurrences(of: "@", with: "")
        let exactId = snap.targetId ?? Int64(needle).map { PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value($0)) }

        guard exactId != nil || !needle.isEmpty else {
            let _ = stateAtomic.modify { var n = $0; n.results = []; n.isSearching = false; return n }
            bump()
            return
        }

        let _ = (context.account.postbox.transaction { transaction -> [FoundMsg] in
            var hits: [FoundMsg] = []
            var seenPeers = Set<PeerId>()
            let df = DateFormatter()
            df.dateFormat = "dd.MM.yy HH:mm"

            for groupId in [PeerGroupId.root, PeerGroupId(rawValue: 1)] {
                if hits.count >= 300 { break }
                for entry in transaction.getTopChatListEntries(groupId: groupId, count: 100) {
                    if hits.count >= 300 { break }
                    if seenPeers.contains(entry.peerId) { continue }
                    seenPeers.insert(entry.peerId)
                    let chatTitle = entry.peer?.debugDisplayTitle ?? "Чат"

                    transaction.scanTopMessages(peerId: entry.peerId, namespace: Namespaces.Message.Cloud, limit: 250) { msg in
                        guard let author = msg.author else { return true }
                        var matched = false
                        if let exact = exactId, author.id == exact {
                            matched = true
                        } else if !needle.isEmpty {
                            let titleMatch = author.debugDisplayTitle.lowercased().contains(needle)
                            let unameMatch = (author.addressName?.lowercased().contains(needle) ?? false)
                            if titleMatch || unameMatch {
                                matched = true
                            }
                        }
                        if matched {
                            let body = msg.text.isEmpty ? "[Медиа]" : msg.text
                            let isDel = msg.attributes.contains { $0 is MTDeletedMessageAttribute }
                            hits.append(FoundMsg(
                                chatTitle: chatTitle,
                                authorName: author.debugDisplayTitle,
                                text: body,
                                dateText: df.string(from: Date(timeIntervalSince1970: TimeInterval(msg.timestamp))),
                                isDeleted: isDel
                            ))
                        }
                        return hits.count < 300
                    }
                }
            }
            return hits
        } |> deliverOnMainQueue).startStandalone(next: { list in
            let _ = stateAtomic.modify { var n = $0; n.results = list; n.isSearching = false; return n }
            bump()
        })
    }

    if targetAuthorId != nil || !initialQuery.isEmpty {
        runSearch()
    }

    let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let st = stateAtomic.with { $0 }
        var screen = MTNativeScreenModel(title: "Поиск сообщений автора")

        var searchRows: [MTNativeRow] = [
            MTNativeRow(id: "os.h", kind: .header("Параметры поиска")),
            MTNativeRow(id: "os.q", kind: .input(text: st.query, placeholder: "Имя, @username или ID пользователя")),
            MTNativeRow(id: "os.go", kind: .action(title: st.isSearching ? "Поиск..." : "Найти по общим чатам", destructive: false, enabled: !st.isSearching))
        ]
        if !st.results.isEmpty {
            searchRows.append(MTNativeRow(id: "os.copy", kind: .action(title: "Скопировать отчёт (\(st.results.count))", destructive: false, enabled: true)))
        }
        screen.sections.append(searchRows)

        screen.text["os.q"] = { v in let _ = stateAtomic.modify { var n = $0; n.query = v; n.targetId = nil; return n } }
        screen.tap["os.go"] = { runSearch() }
        screen.tap["os.copy"] = {
            let cur = stateAtomic.with { $0.results }
            guard !cur.isEmpty else { return }
            let report = cur.prefix(200).map { "[\($0.dateText)] [\($0.chatTitle)] \($0.authorName): \($0.text)" }.joined(separator: "\n")
            UIPasteboard.general.string = report
            mtPresentNativeToast(context: context, from: weakController, text: "Отчёт скопирован")
        }

        var resRows: [MTNativeRow] = [
            MTNativeRow(id: "os.r.h", kind: .header("Результаты (\(st.results.count))"))
        ]
        if st.results.isEmpty {
            resRows.append(MTNativeRow(id: "os.empty", kind: .info(st.isSearching ? "Сканирование групп..." : "Сообщений пока не найдено")))
        } else {
            for (idx, item) in st.results.prefix(150).enumerated() {
                let rowId = "os.m.\(idx)"
                let delTag = item.isDeleted ? " [Удалено]" : ""
                resRows.append(MTNativeRow(
                    id: rowId,
                    kind: .info("\(item.chatTitle) • \(item.dateText)\(delTag)\n\(item.authorName): \(item.text)")
                ))
                screen.tap[rowId] = {
                    UIPasteboard.general.string = item.text
                    mtPresentNativeToast(context: context, from: weakController, text: "Текст скопирован")
                }
            }
        }
        screen.sections.append(resRows)
        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}

// MARK: - #205 / #244 / #245 Global Audit Log Native ItemListController

private func mtMakeNativeGlobalAuditLogController(context: AccountContext, initialPeerId: PeerId?) -> ItemListController {
    struct AuditRow: Equatable {
        let chatTitle: String
        let authorName: String
        let currentText: String
        let previousText: String?
        let dateText: String
        let isDeleted: Bool
        let isEdited: Bool
    }
    struct AuditState {
        var allRows: [AuditRow] = []
        var singleChatOnly: Bool
        var filterType: Int = 0 // 0=All, 1=Deleted, 2=Edited
        var query: String = ""
        var isLoading: Bool = true
    }

    let stateAtomic = Atomic<AuditState>(value: AuditState(singleChatOnly: initialPeerId != nil))
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revCount = 0
    let bump: () -> Void = {
        revCount += 1
        revision.set(revCount)
    }
    weak var weakController: ItemListController?

    let loadAudit: () -> Void = {
        let singleOnly = stateAtomic.modify { var n = $0; n.isLoading = true; return n }.singleChatOnly
        bump()
        let singlePeer = singleOnly ? initialPeerId : nil

        let _ = (context.account.postbox.transaction { transaction -> [AuditRow] in
            var found: [AuditRow] = []
            var peers: [(PeerId, String)] = []
            if let single = singlePeer {
                peers.append((single, transaction.getPeer(single)?.debugDisplayTitle ?? "Текущий чат"))
            } else {
                var seen = Set<PeerId>()
                for groupId in [PeerGroupId.root, PeerGroupId(rawValue: 1)] {
                    for entry in transaction.getTopChatListEntries(groupId: groupId, count: 80) {
                        if seen.contains(entry.peerId) { continue }
                        seen.insert(entry.peerId)
                        peers.append((entry.peerId, entry.peer?.debugDisplayTitle ?? "Чат"))
                    }
                }
            }
            let df = DateFormatter()
            df.dateFormat = "dd.MM.yy HH:mm"
            let limit = (singlePeer != nil) ? 1500 : 150
            for (pid, title) in peers {
                if found.count >= 400 { break }
                transaction.scanTopMessages(peerId: pid, namespace: Namespaces.Message.Cloud, limit: limit) { msg in
                    var isDel = false
                    var prevText: String? = nil
                    for attr in msg.attributes {
                        if attr is MTDeletedMessageAttribute {
                            isDel = true
                        } else if let edit = attr as? MTEditHistoryMessageAttribute, !edit.versions.isEmpty {
                            prevText = edit.versions.last?.text
                        }
                    }
                    if isDel || prevText != nil {
                        let author = msg.author?.debugDisplayTitle ?? title
                        let body = msg.text.isEmpty ? "[Медиа]" : msg.text
                        found.append(AuditRow(
                            chatTitle: title,
                            authorName: author,
                            currentText: body,
                            previousText: prevText,
                            dateText: df.string(from: Date(timeIntervalSince1970: TimeInterval(msg.timestamp))),
                            isDeleted: isDel,
                            isEdited: prevText != nil
                        ))
                    }
                    return found.count < 400
                }
            }
            return found
        } |> deliverOnMainQueue).startStandalone(next: { rows in
            let _ = stateAtomic.modify { var n = $0; n.allRows = rows; n.isLoading = false; return n }
            bump()
        })
    }

    loadAudit()

    let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let st = stateAtomic.with { $0 }
        let q = st.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visible = st.allRows.filter { row in
            if st.filterType == 1 && !row.isDeleted { return false }
            if st.filterType == 2 && !row.isEdited { return false }
            if !q.isEmpty {
                let hay = "\(row.chatTitle) \(row.authorName) \(row.currentText) \(row.previousText ?? "")".lowercased()
                return hay.contains(q)
            }
            return true
        }
        let typeTitle = st.filterType == 1 ? "Только удалённые" : (st.filterType == 2 ? "Только изменённые" : "Все события")

        var screen = MTNativeScreenModel(title: "Журнал удалений и правок")

        var fRows: [MTNativeRow] = [
            MTNativeRow(id: "au.f.h", kind: .header("Фильтры")),
            MTNativeRow(id: "au.type", kind: .disclosure(title: "Тип записей", label: typeTitle, icon: nil, enabled: true))
        ]
        if initialPeerId != nil {
            fRows.append(MTNativeRow(id: "au.scope", kind: .toggle(title: "Только текущий чат", value: st.singleChatOnly, enabled: true)))
        }
        fRows.append(MTNativeRow(id: "au.q", kind: .input(text: st.query, placeholder: "Фильтр по тексту или автору...")))
        screen.sections.append(fRows)

        screen.tap["au.type"] = {
            mtPresentNativeActionSheet(context: context, from: weakController, title: "Тип записей", buttons: [
                (title: "Все события", isDestructive: false, action: { let _ = stateAtomic.modify { var n = $0; n.filterType = 0; return n }; bump() }),
                (title: "Только удалённые", isDestructive: false, action: { let _ = stateAtomic.modify { var n = $0; n.filterType = 1; return n }; bump() }),
                (title: "Только изменённые", isDestructive: false, action: { let _ = stateAtomic.modify { var n = $0; n.filterType = 2; return n }; bump() })
            ])
        }
        screen.toggle["au.scope"] = { isOn in
            let _ = stateAtomic.modify { var n = $0; n.singleChatOnly = isOn; return n }
            loadAudit()
        }
        screen.text["au.q"] = { v in
            let _ = stateAtomic.modify { var n = $0; n.query = v; return n }
            bump()
        }

        var lRows: [MTNativeRow] = [
            MTNativeRow(id: "au.l.h", kind: .header("Записи (\(visible.count))"))
        ]
        if visible.isEmpty {
            lRows.append(MTNativeRow(id: "au.empty", kind: .info(st.isLoading ? "Загрузка журнала..." : "Записей не найдено")))
        } else {
            for (idx, item) in visible.prefix(150).enumerated() {
                let rowId = "au.i.\(idx)"
                let tag = item.isDeleted ? "Удалено" : "Изменено"
                let detail: String
                if let prev = item.previousText, !prev.isEmpty {
                    detail = "[\(tag)] \(item.chatTitle) • \(item.dateText)\n\(item.authorName)\nБыло: \(prev)\nСтало: \(item.currentText)"
                } else {
                    detail = "[\(tag)] \(item.chatTitle) • \(item.dateText)\n\(item.authorName): \(item.currentText)"
                }
                lRows.append(MTNativeRow(id: rowId, kind: .info(detail)))
                screen.tap[rowId] = {
                    let copyText = item.previousText.map { "Было: \($0)\nСтало: \(item.currentText)" } ?? item.currentText
                    UIPasteboard.general.string = copyText
                    mtPresentNativeToast(context: context, from: weakController, text: "Запись скопирована")
                }
            }
        }
        screen.sections.append(lRows)
        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}
