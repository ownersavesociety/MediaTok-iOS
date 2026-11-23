import Foundation
import UIKit
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
        guard let message = menuContext.messages.first, let author = message.author else { return [] }
        let context = menuContext.context
        let authorId = author.id
        let authorName = author.debugDisplayTitle
        var entries: [MTMessageMenuEntry] = []

        if message.id.peerId.namespace != Namespaces.Peer.CloudUser {
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Все сообщения автора (OSINT)",
                icon: { theme in
                    return UIImage(systemName: "person.text.rectangle.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave14Tools.presentOsintUserSearch(context: context, targetAuthorId: authorId, initialQuery: authorName)
                }
            ))))
        }

        return entries
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
        guard let top = topViewController() else { return }
        let vc = MTOsintUserSearchController(context: context, targetAuthorId: targetAuthorId, initialQuery: initialQuery)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #205 / #244 / #245 Present Global Audit Log

    public static func presentGlobalAuditLog(context: AccountContext, initialPeerId: PeerId?) {
        guard let top = topViewController() else { return }
        let vc = MTGlobalAuditLogController(context: context, initialPeerId: initialPeerId)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #272 Autonomous Chat Export (HTML / JSON / TXT)

    public static func presentExportFormatPicker(context: AccountContext, peerId: PeerId) {
        guard let top = topViewController() else { return }
        let alert = UIAlertController(
            title: "Экспорт диалога",
            message: "Выберите формат автономного архива переписки:",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "HTML (Тёмная тема + живой поиск)", style: .default) { _ in
            exportChat(context: context, peerId: peerId, format: "html")
        })
        alert.addAction(UIAlertAction(title: "JSON (Структурированный архив)", style: .default) { _ in
            exportChat(context: context, peerId: peerId, format: "json")
        })
        alert.addAction(UIAlertAction(title: "TXT (Чистый текст)", style: .default) { _ in
            exportChat(context: context, peerId: peerId, format: "txt")
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        }
        top.present(alert, animated: true)
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
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
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
        guard let top = topViewController() else { return }
        let alert = UIAlertController(
            title: "Экстренная очистка кэша",
            message: "Очистить временные файлы, сетевой URLCache и локальный кэш MediaTok? Ваш вход в аккаунт сохранится.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Очистить сейчас", style: .destructive) { _ in
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
                    MTMediaTokWave5Tools.showToast(context: context, text: String(format: "Кэш очищен (освобождено %.1f МБ)", mb))
                }
            }
        })
        top.present(alert, animated: true)
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

// MARK: - #219 OSINT User Search Controller

private final class MTOsintUserSearchController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private struct FoundMsg {
        let chatTitle: String
        let authorName: String
        let text: String
        let dateText: String
        let isDeleted: Bool
    }

    private let context: AccountContext
    private var targetAuthorId: PeerId?
    private let initialQuery: String

    private var results: [FoundMsg] = []
    private let searchBar = UISearchBar()
    private let summaryLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(context: AccountContext, targetAuthorId: PeerId?, initialQuery: String) {
        self.context = context
        self.targetAuthorId = targetAuthorId
        self.initialQuery = initialQuery
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "OSINT Поиск сообщений"
        self.view.backgroundColor = .systemGroupedBackground

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Копировать", style: .plain, target: self, action: #selector(copyReportTapped))

        self.searchBar.placeholder = "Имя, @username или ID пользователя"
        self.searchBar.text = self.initialQuery
        self.searchBar.delegate = self
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false

        self.summaryLabel.font = .systemFont(ofSize: 13)
        self.summaryLabel.textColor = .secondaryLabel
        self.summaryLabel.textAlignment = .center
        self.summaryLabel.text = "Введите @username или имя для поиска по всем общим группам"
        self.summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.searchBar)
        self.view.addSubview(self.summaryLabel)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.searchBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.summaryLabel.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor, constant: 6),
            self.summaryLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.summaryLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.tableView.topAnchor.constraint(equalTo: self.summaryLabel.bottomAnchor, constant: 6),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        if self.targetAuthorId != nil || !self.initialQuery.isEmpty {
            self.runSearch(query: self.initialQuery)
        }
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func copyReportTapped() {
        guard !self.results.isEmpty else { return }
        let report = self.results.prefix(200).map { "[\($0.dateText)] [\($0.chatTitle)] \($0.authorName): \($0.text)" }.joined(separator: "\n")
        UIPasteboard.general.string = report
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Скопировано \(min(200, self.results.count)) сообщений")
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.targetAuthorId = nil
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        self.runSearch(query: searchBar.text ?? "")
    }

    private func runSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased().replacingOccurrences(of: "@", with: "")
        let exactId = self.targetAuthorId ?? Int64(needle).map { PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value($0)) }
        guard exactId != nil || !needle.isEmpty else {
            self.results = []
            self.summaryLabel.text = "Введите @username, имя или ID пользователя"
            self.tableView.reloadData()
            return
        }
        self.summaryLabel.text = "Сканирую все чаты, группы и кэш Anti-Delete..."

        let _ = (self.context.account.postbox.transaction { transaction -> [FoundMsg] in
            var hits: [FoundMsg] = []
            var seenPeers = Set<PeerId>()
            let df = DateFormatter()
            df.dateFormat = "dd.MM.yy HH:mm"

            for groupId in [PeerGroupId.root, PeerGroupId(rawValue: 1)] {
                if hits.count >= 400 { break }
                for entry in transaction.getTopChatListEntries(groupId: groupId, count: 100) {
                    if hits.count >= 400 { break }
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
                        return hits.count < 400
                    }
                }
            }
            return hits
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] list in
            guard let self else { return }
            self.results = list
            self.summaryLabel.text = "Найдено сообщений: \(list.count)"
            self.tableView.reloadData()
        })
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "osintCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "osintCell")
        let item = self.results[indexPath.row]
        let delTag = item.isDeleted ? " [УДАЛЕНО]" : ""
        cell.textLabel?.text = "\(item.chatTitle) · \(item.dateText)\(delTag)"
        cell.textLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        cell.textLabel?.textColor = item.isDeleted ? .systemRed : .label
        cell.detailTextLabel?.text = "\(item.authorName): \(item.text)"
        cell.detailTextLabel?.numberOfLines = 3
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = self.results[indexPath.row]
        UIPasteboard.general.string = item.text
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Сообщение скопировано")
    }
}

// MARK: - #205 / #244 / #245 Global Audit Log Controller

private final class MTGlobalAuditLogController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private struct AuditRow {
        let chatTitle: String
        let authorName: String
        let currentText: String
        let previousText: String?
        let dateText: String
        let isDeleted: Bool
        let isEdited: Bool
    }

    private let context: AccountContext
    private let initialPeerId: PeerId?

    private var allRows: [AuditRow] = []
    private var visibleRows: [AuditRow] = []

    private let scopeSegment = UISegmentedControl(items: ["Текущий чат", "Все чаты"])
    private let typeSegment = UISegmentedControl(items: ["Все", "Удалённые", "Изменённые"])
    private let searchBar = UISearchBar()
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
        self.title = "Журнал удалений и правок"
        self.view.backgroundColor = .systemGroupedBackground

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.scopeSegment.selectedSegmentIndex = (self.initialPeerId != nil) ? 0 : 1
        if self.initialPeerId == nil {
            self.scopeSegment.setEnabled(false, forSegmentAt: 0)
        }
        self.scopeSegment.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        self.scopeSegment.translatesAutoresizingMaskIntoConstraints = false

        self.typeSegment.selectedSegmentIndex = 0
        self.typeSegment.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        self.typeSegment.translatesAutoresizingMaskIntoConstraints = false

        self.searchBar.placeholder = "Поиск по тексту или автору..."
        self.searchBar.delegate = self
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false

        self.summaryLabel.font = .systemFont(ofSize: 13)
        self.summaryLabel.textColor = .secondaryLabel
        self.summaryLabel.textAlignment = .center
        self.summaryLabel.text = "Загружаю журнал Anti-Delete..."
        self.summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.scopeSegment)
        self.view.addSubview(self.typeSegment)
        self.view.addSubview(self.searchBar)
        self.view.addSubview(self.summaryLabel)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.scopeSegment.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            self.scopeSegment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.scopeSegment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.typeSegment.topAnchor.constraint(equalTo: self.scopeSegment.bottomAnchor, constant: 8),
            self.typeSegment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.typeSegment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.searchBar.topAnchor.constraint(equalTo: self.typeSegment.bottomAnchor, constant: 4),
            self.searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.summaryLabel.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor, constant: 4),
            self.summaryLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.summaryLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.tableView.topAnchor.constraint(equalTo: self.summaryLabel.bottomAnchor, constant: 6),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.loadAudit()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func scopeChanged() {
        self.loadAudit()
    }

    @objc private func filterChanged() {
        self.applyFilters()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.applyFilters()
    }

    private func loadAudit() {
        let singlePeer: PeerId? = (self.scopeSegment.selectedSegmentIndex == 0) ? self.initialPeerId : nil
        self.summaryLabel.text = "Сканирую базу Anti-Delete..."

        let _ = (self.context.account.postbox.transaction { transaction -> [AuditRow] in
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
                if found.count >= 600 { break }
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
                    return found.count < 600
                }
            }
            return found
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] rows in
            guard let self else { return }
            self.allRows = rows
            self.applyFilters()
        })
    }

    private func applyFilters() {
        let q = (self.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.visibleRows = self.allRows.filter { row in
            switch self.typeSegment.selectedSegmentIndex {
            case 1 where !row.isDeleted: return false
            case 2 where !row.isEdited: return false
            default: break
            }
            if !q.isEmpty {
                let hay = "\(row.chatTitle) \(row.authorName) \(row.currentText) \(row.previousText ?? "")".lowercased()
                return hay.contains(q)
            }
            return true
        }
        self.summaryLabel.text = "Записей в журнале: \(self.visibleRows.count)"
        self.tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.visibleRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "auditCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "auditCell")
        let item = self.visibleRows[indexPath.row]
        let badge = item.isDeleted ? "УДАЛЕНО" : "ИЗМЕНЕНО"
        cell.textLabel?.text = "[\(badge)] \(item.chatTitle) · \(item.dateText)"
        cell.textLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        cell.textLabel?.textColor = item.isDeleted ? .systemRed : .systemOrange
        if let prev = item.previousText, !prev.isEmpty {
            cell.detailTextLabel?.text = "\(item.authorName)\nБыло: \(prev)\nСтало: \(item.currentText)"
        } else {
            cell.detailTextLabel?.text = "\(item.authorName): \(item.currentText)"
        }
        cell.detailTextLabel?.numberOfLines = 4
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = self.visibleRows[indexPath.row]
        let copyText = item.previousText.map { "Было: \($0)\nСтало: \(item.currentText)" } ?? item.currentText
        UIPasteboard.general.string = copyText
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Запись скопирована")
    }
}
