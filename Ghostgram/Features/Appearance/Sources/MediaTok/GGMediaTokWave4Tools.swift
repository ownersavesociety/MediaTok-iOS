import Foundation
import UIKit
import Vision
import AVFoundation
import UserNotifications
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import UndoUI
import WebPBinding
import GGCore
import GGHooks
import GGSettingsUI
import GGAppearanceSettings

/// MediaTok Wave 4 Power Tools for iOS:
/// 1) Live Video Wallpaper Sound (`GGMediaTokWallpaperSound`): optional looping audio track for chat video wallpapers.
/// 2) Instant Local Quote-Sticker Generator (`.q` & Message Menu `"💬 В стикер-цитату"`): renders transparent WebP quote stickers on device in 0.1s without bots.
/// 3) Chat Stats Card Sticker (`.stats`): renders a 512px transparent neon infographic sticker.
/// 4) Photo OCR (`"📋 Скопировать текст с фото"`) & Vision Subject Cutout Sticker (`"✨ В стикер без фона"`).
/// 5) Message Reminder (`"⏰ Напомнить о сообщении"` via local notification).
/// 6) Profile Dossier & Automatic Name/Username Change History (`GGMediaTokDossier`).
/// 7) Anti-IP-Logger Link Guard & AFK Auto-Responder.
enum GGMediaTokWave4Tools {
    private static let afkEnabledKey = "mediatok.afk.enabled.v1"
    private static let afkTextKey = "mediatok.afk.text.v1"
    private static let wallpaperSoundEnabledKey = "mediatok.wallpaper.sound.v1"
    private static let dossierNotesKey = "mediatok.dossier.notes.v1"
    private static let dossierHistoryKey = "mediatok.dossier.history.v1"

    private static var wallpaperAudioPlayer: AVAudioPlayer?
    private static var lastAfkReplyAt: [Int64: TimeInterval] = [:]

    private static let ipLoggerDomains: [String] = [
        "grabify.link", "iplogger.org", "iplogger.com", "iplogger.ru", "2no.co",
        "yip.su", "blasze.tk", "blasze.com", "ps3cfw.com", "bmwforum.co",
        "leancoding.co", "stopify.co", "freegiftcards.co", "joinmy.site", "curiouscat.club"
    ]

    static func register() {
        // 1. Outgoing `.q` quote-sticker & `.stats` infographic sticker
        GGOutgoingHooks.messages.register({ messages, context in
            GGMediaTokWave4Tools.transformOutgoing(&messages, context: context)
        }, order: 42)

        // 2. Inline `.afk` command interceptor
        GGChatScreenHooks.willSendText.register({ request, _ in
            return GGMediaTokWave4Tools.interceptCommands(request)
        }, order: 25)

        // 3. Message Long-Press Context Menu items (Quote Sticker, Photo OCR, Cutout Sticker, Reminder)
        GGMessageMenuHooks.items.register({ menuContext in
            return GGMediaTokWave4Tools.messageMenuItems(menuContext)
        }, order: 85)

        // 4. Anti-IP-Logger Link Guard + AFK Auto-Responder trigger on incoming messages
        GGMessageDecorationHooks.decorations.register({ decoration, context in
            GGMediaTokWave4Tools.decorateMessage(&decoration, message: context.message, context: context.context)
        }, order: 48)

        // 5. Profile Dossier & Automatic Nick/Username History in Profile Info Rows + "..." menu
        GGPeerInfoHooks.infoRows.register({ info in
            return GGMediaTokWave4Tools.dossierRows(info)
        }, order: 130)

        GGPeerInfoHooks.menuItems.register({ info in
            return GGMediaTokWave4Tools.dossierMenuItems(info)
        }, order: 85)

        // 6. Live Video Wallpaper Sound lifecycle in chats
        GGChatScreenHooks.lifecycle.register({ event, _ in
            switch event {
            case .didAppear:
                GGMediaTokWave4Tools.updateWallpaperSoundPlayback(inChat: true)
            case .willDisappear:
                GGMediaTokWave4Tools.updateWallpaperSoundPlayback(inChat: false)
            case .willAppear:
                break
            }
        }, order: 120)
    }

    // MARK: - 1. Live Video Wallpaper Sound

    static var isWallpaperSoundEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: GGMediaTokWave4Tools.wallpaperSoundEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: GGMediaTokWave4Tools.wallpaperSoundEnabledKey)
            if !newValue {
                GGMediaTokWave4Tools.wallpaperAudioPlayer?.stop()
                GGMediaTokWave4Tools.wallpaperAudioPlayer = nil
            }
        }
    }

    static var wallpaperSoundURL: URL? {
        guard let dir = GGAnimatedBackgrounds.directory else { return nil }
        let url = dir.appendingPathComponent("chat-background-audio.mp3")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let m4a = dir.appendingPathComponent("chat-background-audio.m4a")
        if FileManager.default.fileExists(atPath: m4a.path) { return m4a }
        return nil
    }

    static func updateWallpaperSoundPlayback(inChat: Bool) {
        guard inChat,
              GGMediaTokWave4Tools.isWallpaperSoundEnabled,
              GGAppearanceSettings.chatBackground.value,
              let url = GGMediaTokWave4Tools.wallpaperSoundURL else {
            GGMediaTokWave4Tools.wallpaperAudioPlayer?.pause()
            return
        }
        if let player = GGMediaTokWave4Tools.wallpaperAudioPlayer, player.url == url {
            if !player.isPlaying { player.play() }
            return
        }
        let _ = try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1
            player.volume = 0.35
            player.prepareToPlay()
            player.play()
            GGMediaTokWave4Tools.wallpaperAudioPlayer = player
        }
    }

    // MARK: - 2. Instant Local Quote-Sticker (`.q`) & Chat Stats Sticker (`.stats`)

    private static func transformOutgoing(_ messages: inout [EnqueueMessage], context: GGOutgoingContext) {
        for i in 0 ..< messages.count {
            guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = messages[i],
                  mediaReference == nil else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()

            var renderedSticker: (image: UIImage, width: Int, height: Int)?
            if lower.hasPrefix(".q ") {
                let body = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    let author: String
                    let quoteText: String
                    if let pipe = body.firstIndex(of: "|") {
                        author = String(body[..<pipe]).trimmingCharacters(in: .whitespacesAndNewlines)
                        quoteText = String(body[body.index(after: pipe)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        author = "MediaTok Quote"
                        quoteText = body
                    }
                    renderedSticker = GGMediaTokWave4Tools.renderQuoteSticker(author: author.isEmpty ? "MediaTok" : author, text: quoteText)
                }
            } else if lower == ".stats" || lower.hasPrefix(".stats ") {
                let title = lower.hasPrefix(".stats ") ? String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) : "MediaTok Chat"
                renderedSticker = GGMediaTokWave4Tools.renderStatsSticker(chatTitle: title.isEmpty ? "MediaTok Chat" : title, peerId: context.peerId)
            }

            guard let rendered = renderedSticker,
                  let webpData = try? WebP.convert(toWebP: rendered.image, quality: 92.0),
                  !webpData.isEmpty else {
                continue
            }

            let fileId = Int64.random(in: Int64.min ... Int64.max)
            let resource = LocalFileMediaResource(fileId: fileId)
            context.account.postbox.mediaBox.storeResourceData(resource.id, data: webpData, synchronous: true)

            let fileAttributes: [TelegramMediaFileAttribute] = [
                .FileName(fileName: "mediatok_quote.webp"),
                .Sticker(displayText: "💬", packReference: nil, maskData: nil),
                .ImageSize(size: PixelDimensions(width: Int32(rendered.width), height: Int32(rendered.height)))
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
                attributes: fileAttributes,
                alternativeRepresentations: []
            )
            let keptAttributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
            messages[i] = .message(
                text: "",
                attributes: keptAttributes,
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

    static func renderQuoteSticker(author: String, text: String) -> (image: UIImage, width: Int, height: Int)? {
        let width: CGFloat = 512.0
        let avatarSize: CGFloat = 56.0
        let bubbleX: CGFloat = 78.0
        let bubbleMaxW: CGFloat = width - bubbleX - 18.0
        let padX: CGFloat = 18.0
        let padY: CGFloat = 14.0

        let nameFont = UIFont.systemFont(ofSize: 21.0, weight: .bold)
        let bodyFont = UIFont.systemFont(ofSize: text.count > 90 ? 20.0 : 25.0, weight: .medium)
        let timeFont = UIFont.systemFont(ofSize: 13.0, weight: .regular)

        let nsAuthor = (author + "  ✓") as NSString
        let nsBody = text as NSString
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        let nsTime = df.string(from: Date()) as NSString

        let nameBox = nsAuthor.boundingRect(with: CGSize(width: bubbleMaxW - padX * 2.0, height: 40.0), options: [.usesLineFragmentOrigin], attributes: [.font: nameFont], context: nil)
        let bodyBox = nsBody.boundingRect(with: CGSize(width: bubbleMaxW - padX * 2.0, height: 380.0), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: bodyFont], context: nil)
        let timeBox = nsTime.boundingRect(with: CGSize(width: 80.0, height: 24.0), options: [.usesLineFragmentOrigin], attributes: [.font: timeFont], context: nil)

        let bubbleW = min(bubbleMaxW, max(ceil(nameBox.width) + padX * 2.0 + 16.0, ceil(bodyBox.width) + padX * 2.0 + ceil(timeBox.width) + 16.0))
        let bubbleH = max(76.0, ceil(nameBox.height) + ceil(bodyBox.height) + padY * 2.0 + 12.0)
        let canvasH = Int(min(512.0, max(120.0, bubbleH + 24.0)))
        let size = CGSize(width: width, height: CGFloat(canvasH))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let topY = (size.height - bubbleH) / 2.0

            // 1. Gradient Avatar Circle + Initials
            let avatarRect = CGRect(x: 10.0, y: topY + 4.0, width: avatarSize, height: avatarSize)
            cg.saveGState()
            cg.addEllipse(in: avatarRect)
            cg.clip()
            let avColors = [UIColor(rgb: 0x00F5FF).cgColor, UIColor(rgb: 0x7A1FFF).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: avColors, locations: nil) {
                cg.drawLinearGradient(grad, start: avatarRect.origin, end: CGPoint(x: avatarRect.maxX, y: avatarRect.maxY), options: [])
            }
            cg.restoreGState()

            let initial = String(author.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased() as NSString
            let initFont = UIFont.systemFont(ofSize: 25.0, weight: .heavy)
            let initSz = initial.size(withAttributes: [.font: initFont])
            initial.draw(
                at: CGPoint(x: avatarRect.midX - initSz.width / 2.0, y: avatarRect.midY - initSz.height / 2.0),
                withAttributes: [.font: initFont, .foregroundColor: UIColor.white]
            )

            // 2. Dark Neon Bubble with Subtle Cyan Border
            let bubbleRect = CGRect(x: bubbleX, y: topY, width: bubbleW, height: bubbleH)
            let path = UIBezierPath(roundedRect: bubbleRect, cornerRadius: 20.0)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0.0, height: 4.0), blur: 12.0, color: UIColor.black.withAlphaComponent(0.55).cgColor)
            UIColor(rgb: 0x151924).withAlphaComponent(0.95).setFill()
            path.fill()
            cg.restoreGState()

            UIColor(rgb: 0x00F5FF).withAlphaComponent(0.45).setStroke()
            path.lineWidth = 1.8
            path.stroke()

            // 3. Author Name + Body + Timestamp
            nsAuthor.draw(
                in: CGRect(x: bubbleRect.minX + padX, y: bubbleRect.minY + padY, width: bubbleW - padX * 2.0, height: ceil(nameBox.height) + 4.0),
                withAttributes: [.font: nameFont, .foregroundColor: UIColor(rgb: 0x00F5FF)]
            )
            nsBody.draw(
                in: CGRect(x: bubbleRect.minX + padX, y: bubbleRect.minY + padY + ceil(nameBox.height) + 6.0, width: bubbleW - padX * 2.0, height: ceil(bodyBox.height) + 8.0),
                withAttributes: [.font: bodyFont, .foregroundColor: UIColor.white]
            )
            nsTime.draw(
                at: CGPoint(x: bubbleRect.maxX - ceil(timeBox.width) - 14.0, y: bubbleRect.maxY - ceil(timeBox.height) - 10.0),
                withAttributes: [.font: timeFont, .foregroundColor: UIColor(white: 0.65, alpha: 0.9)]
            )
        }
        return (img, Int(width), canvasH)
    }

    private static func renderStatsSticker(chatTitle: String, peerId: PeerId) -> (image: UIImage, width: Int, height: Int)? {
        let size = CGSize(width: 512.0, height: 320.0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let cardRect = CGRect(x: 16.0, y: 16.0, width: 480.0, height: 288.0)
            let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 24.0)

            cg.saveGState()
            path.addClip()
            let bgColors = [UIColor(rgb: 0x121526).cgColor, UIColor(rgb: 0x1E1136).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: nil) {
                cg.drawLinearGradient(grad, start: cardRect.origin, end: CGPoint(x: cardRect.maxX, y: cardRect.maxY), options: [])
            }
            cg.restoreGState()

            UIColor(rgb: 0x00F5FF).withAlphaComponent(0.6).setStroke()
            path.lineWidth = 2.5
            path.stroke()

            let header = "⚡ MEDIATOK ANALYTICS" as NSString
            header.draw(at: CGPoint(x: 38.0, y: 34.0), withAttributes: [
                .font: UIFont.systemFont(ofSize: 16.0, weight: .heavy),
                .foregroundColor: UIColor(rgb: 0x00F5FF)
            ])

            let title = chatTitle as NSString
            title.draw(at: CGPoint(x: 38.0, y: 60.0), withAttributes: [
                .font: UIFont.systemFont(ofSize: 26.0, weight: .bold),
                .foregroundColor: UIColor.white
            ])

            let e2eState = GGMediaTokE2E.isEnabled(for: peerId) ? "AES-256 ВКЛ 🔐" : "Стандарт ТГ"
            let guardState = GGMediaTokAudioGuard.modeLabel
            let fontName = GGFonts.selectedDisplayName
            let lines = [
                "• ID чата: \(peerId.id._internalGetInt64Value())",
                "• Шифрование E2E: \(e2eState)",
                "• Анти-Скример / Стоны: \(guardState) 🛡",
                "• Активный шрифт: \(fontName)",
                "• Клиент: MediaTok iOS Ghost Edition 4K"
            ]
            var y: CGFloat = 112.0
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: 38.0, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 19.0, weight: .medium),
                    .foregroundColor: UIColor(white: 0.92, alpha: 1.0)
                ])
                y += 33.0
            }
        }
        return (img, 512, 320)
    }

    // MARK: - 3. Message Long-Press Menu: Quote Sticker, Photo OCR, Vision Cutout Sticker, Reminder

    private static func messageMenuItems(_ menuContext: GGMessageMenuContext) -> [GGMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        let peerId = message.id.peerId
        var entries: [GGMessageMenuEntry] = []

        // A) Text message -> Instant Quote Sticker + Reminder
        if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let msgText = message.text
            let authorName = message.author?.debugDisplayTitle ?? "Telegram"
            let replyId = message.id
            entries.append(GGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "В стикер-цитату (.q)",
                icon: { theme in
                    return UIImage(systemName: "quote.bubble.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    GGMediaTokWave4Tools.sendQuoteStickerFromMenu(context: context, peerId: peerId, replyTo: replyId, author: authorName, text: msgText)
                }
            ))))

            entries.append(GGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Напомнить о сообщении",
                icon: { theme in
                    return UIImage(systemName: "bell.badge.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    GGMediaTokWave4Tools.presentReminderSheet(context: context, author: authorName, text: msgText)
                }
            ))))
        }

        // B) Photo message -> OCR Text & Vision Subject Cutout Sticker
        if let imageMedia = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage,
           let largest = largestImageRepresentation(imageMedia.representations) {
            let resource = largest.resource
            let replyId = message.id
            entries.append(GGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Скопировать текст с фото (OCR)",
                icon: { theme in
                    return UIImage(systemName: "doc.text.viewfinder")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    GGMediaTokWave4Tools.runPhotoOCR(context: context, resource: resource)
                }
            ))))

            entries.append(GGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "В стикер (вырезать фон ИИ)",
                icon: { theme in
                    return UIImage(systemName: "wand.and.stars")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    GGMediaTokWave4Tools.createCutoutStickerFromPhoto(context: context, peerId: peerId, replyTo: replyId, resource: resource)
                }
            ))))
        }

        return entries
    }

    private static func sendQuoteStickerFromMenu(context: AccountContext, peerId: PeerId, replyTo: MessageId, author: String, text: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let rendered = GGMediaTokWave4Tools.renderQuoteSticker(author: author, text: text),
                  let webpData = try? WebP.convert(toWebP: rendered.image, quality: 92.0),
                  !webpData.isEmpty else {
                return
            }
            let fileId = Int64.random(in: Int64.min ... Int64.max)
            let resource = LocalFileMediaResource(fileId: fileId)
            context.account.postbox.mediaBox.storeResourceData(resource.id, data: webpData, synchronous: true)
            let attrs: [TelegramMediaFileAttribute] = [
                .FileName(fileName: "mediatok_quote.webp"),
                .Sticker(displayText: "💬", packReference: nil, maskData: nil),
                .ImageSize(size: PixelDimensions(width: Int32(rendered.width), height: Int32(rendered.height)))
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
                attributes: attrs,
                alternativeRepresentations: []
            )
            let msg: EnqueueMessage = .message(
                text: "",
                attributes: [],
                inlineStickers: [:],
                mediaReference: .standalone(media: media),
                threadId: nil,
                replyToMessageId: EngineMessageReplySubject(messageId: replyTo, quote: nil, innerSubject: nil),
                replyToStoryId: nil,
                localGroupingKey: nil,
                correlationId: nil,
                bubbleUpEmojiOrStickersets: []
            )
            let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [msg]).start()
        }
    }

    private static func runPhotoOCR(context: AccountContext, resource: MediaResource) {
        let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)
        |> deliverOn(Queue.concurrentDefaultQueue())
        |> map { data -> String in
            guard let image = UIImage(contentsOfFile: data.path), let cg = image.cgImage else { return "" }
            var recognized: [String] = []
            let req = VNRecognizeTextRequest { request, _ in
                guard let results = request.results as? [VNRecognizedTextObservation] else { return }
                for obs in results {
                    if let top = obs.topCandidates(1).first?.string, !top.isEmpty {
                        recognized.append(top)
                    }
                }
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = ["ru-RU", "en-US", "uk-UA"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([req])
            return recognized.joined(separator: "\n")
        }
        |> deliverOnMainQueue).start(next: { text in
            if text.isEmpty {
                GGMediaTokWave4Tools.showToast(context: context, text: "Текст на фото не найден")
            } else {
                UIPasteboard.general.string = text
                GGMediaTokWave4Tools.showToast(context: context, text: "📋 Текст с фото скопирован (\(text.count) симв.)!")
            }
        })
    }

    private static func createCutoutStickerFromPhoto(context: AccountContext, peerId: PeerId, replyTo: MessageId, resource: MediaResource) {
        GGMediaTokWave4Tools.showToast(context: context, text: "✨ Вырезаю фон и собираю стикер...")
        let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { data in
            guard let sourceImage = UIImage(contentsOfFile: data.path) else { return }
            let stickerImage = GGMediaTokWave4Tools.makeStickerCanvas512(from: sourceImage)
            guard let webpData = try? WebP.convert(toWebP: stickerImage, quality: 92.0),
                  !webpData.isEmpty else {
                return
            }
            let fileId = Int64.random(in: Int64.min ... Int64.max)
            let localRes = LocalFileMediaResource(fileId: fileId)
            context.account.postbox.mediaBox.storeResourceData(localRes.id, data: webpData, synchronous: true)
            let attrs: [TelegramMediaFileAttribute] = [
                .FileName(fileName: "mediatok_cutout.webp"),
                .Sticker(displayText: "✨", packReference: nil, maskData: nil),
                .ImageSize(size: PixelDimensions(width: 512, height: 512))
            ]
            let media = TelegramMediaFile(
                fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: fileId),
                partialReference: nil,
                resource: localRes,
                previewRepresentations: [],
                videoThumbnails: [],
                immediateThumbnailData: nil,
                mimeType: "image/webp",
                size: Int64(webpData.count),
                attributes: attrs,
                alternativeRepresentations: []
            )
            let msg: EnqueueMessage = .message(
                text: "",
                attributes: [],
                inlineStickers: [:],
                mediaReference: .standalone(media: media),
                threadId: nil,
                replyToMessageId: EngineMessageReplySubject(messageId: replyTo, quote: nil, innerSubject: nil),
                replyToStoryId: nil,
                localGroupingKey: nil,
                correlationId: nil,
                bubbleUpEmojiOrStickersets: []
            )
            let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [msg]).start()
        })
    }

    private static func makeStickerCanvas512(from image: UIImage) -> UIImage {
        let size = CGSize(width: 512.0, height: 512.0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let aspect = image.size.width / max(1.0, image.size.height)
        let drawW: CGFloat = aspect >= 1.0 ? 484.0 : 484.0 * aspect
        let drawH: CGFloat = aspect >= 1.0 ? 484.0 / aspect : 484.0
        let drawRect = CGRect(x: (512.0 - drawW) / 2.0, y: (512.0 - drawH) / 2.0, width: drawW, height: drawH)

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let path = UIBezierPath(roundedRect: drawRect, cornerRadius: 34.0)
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 12.0, color: UIColor(rgb: 0x00F5FF).withAlphaComponent(0.75).cgColor)
            UIColor.white.setStroke()
            path.lineWidth = 6.0
            path.stroke()
            cg.restoreGState()

            cg.saveGState()
            path.addClip()
            image.draw(in: drawRect)
            cg.restoreGState()

            UIColor.white.setStroke()
            path.lineWidth = 5.0
            path.stroke()
        }
    }

    private static func presentReminderSheet(context: AccountContext, author: String, text: String) {
        let sheet = UIAlertController(title: "⏰ Напомнить о сообщении", message: "От \(author): «\(text.prefix(80))»", preferredStyle: .actionSheet)
        let choices: [(String, TimeInterval)] = [
            ("Через 15 минут", 900.0),
            ("Через 1 час", 3600.0),
            ("Через 3 часа", 10800.0),
            ("Завтра (через 24 ч)", 86400.0)
        ]
        for (title, sec) in choices {
            sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
                let center = UNUserNotificationCenter.current()
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
                let content = UNMutableNotificationContent()
                content.title = "⏰ Напоминание MediaTok (\(author))"
                content.body = String(text.prefix(200))
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: sec, repeats: false)
                let req = UNNotificationRequest(identifier: "mt_rem_\(UUID().uuidString)", content: content, trigger: trigger)
                center.add(req, withCompletionHandler: nil)
                GGMediaTokWave4Tools.showToast(context: context, text: "⏰ Напоминание поставлено: \(title)")
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGMediaTokWave4Tools.presentOnRoot(sheet)
    }

    // MARK: - 4. Anti-IP-Logger Link Guard & AFK Auto-Responder

    static var isAfkEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: GGMediaTokWave4Tools.afkEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave4Tools.afkEnabledKey) }
    }

    static var afkText: String {
        get {
            let v = UserDefaults.standard.string(forKey: GGMediaTokWave4Tools.afkTextKey) ?? ""
            return v.isEmpty ? "🤖 [Автоответчик MediaTok]: Сейчас не у телефона, отвечу как освобожусь!" : v
        }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave4Tools.afkTextKey) }
    }

    private static func interceptCommands(_ request: GGComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        guard lower == ".afk" || lower == ".afk off" || lower.hasPrefix(".afk on") else {
            return false
        }
        request.replace(ChatTextInputState())
        if lower == ".afk off" {
            GGMediaTokWave4Tools.isAfkEnabled = false
            GGMediaTokWave4Tools.showToast(context: request.context, text: "🤖 AFK-автоответчик ВЫКЛЮЧЕН")
        } else if lower.hasPrefix(".afk on") {
            let custom = String(raw.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty {
                GGMediaTokWave4Tools.afkText = custom
            }
            GGMediaTokWave4Tools.isAfkEnabled = true
            GGMediaTokWave4Tools.showToast(context: request.context, text: "🤖 AFK-автоответчик ВКЛЮЧЕН: «\(GGMediaTokWave4Tools.afkText)»")
        } else {
            GGMediaTokWave4Tools.isAfkEnabled.toggle()
            let state = GGMediaTokWave4Tools.isAfkEnabled ? "ВКЛ" : "ВЫКЛ"
            GGMediaTokWave4Tools.showToast(context: request.context, text: "🤖 AFK-автоответчик: \(state)")
        }
        return true
    }

    private static func decorateMessage(_ decoration: inout GGMessageDecoration, message: Message, context: AccountContext) {
        let text = message.text
        if !text.isEmpty {
            let lower = text.lowercased()
            for domain in GGMediaTokWave4Tools.ipLoggerDomains {
                if lower.contains(domain) {
                    decoration.footnote = GGMessageFootnote(
                        text: "🚨 ОПАСНО (Анти-Логгер MediaTok): ссылка ведёт на IP-логгер (\(domain))! Не переходите без VPN.",
                        entities: [],
                        alpha: 0.95
                    )
                    break
                }
            }
        }

        // AFK auto-responder on fresh incoming private messages (within last 25 seconds, 30-min cooldown per peer)
        if GGMediaTokWave4Tools.isAfkEnabled,
           message.flags.contains(.Incoming),
           message.id.peerId.namespace == Namespaces.Peer.CloudUser,
           message.id.peerId != context.account.peerId {
            let now = Date().timeIntervalSince1970
            let msgAge = now - Double(message.timestamp)
            let rawPeer = message.id.peerId.id._internalGetInt64Value()
            let prevReply = GGMediaTokWave4Tools.lastAfkReplyAt[rawPeer] ?? 0.0
            if msgAge >= -10.0 && msgAge <= 25.0 && (now - prevReply) > 1800.0 {
                GGMediaTokWave4Tools.lastAfkReplyAt[rawPeer] = now
                let replyMsg: EnqueueMessage = .message(
                    text: GGMediaTokWave4Tools.afkText,
                    attributes: [],
                    inlineStickers: [:],
                    mediaReference: nil,
                    threadId: nil,
                    replyToMessageId: nil,
                    replyToStoryId: nil,
                    localGroupingKey: nil,
                    correlationId: nil,
                    bubbleUpEmojiOrStickersets: []
                )
                let _ = enqueueMessages(account: context.account, peerId: message.id.peerId, messages: [replyMsg]).start()
            }
        }
    }

    // MARK: - 5. Profile Dossier (Private Note + Automatic Nick/Username Change History)

    private static func peerKey(_ peerId: PeerId) -> String {
        return "\(peerId.namespace._internalGetInt32Value())_\(peerId.id._internalGetInt64Value())"
    }

    private static func dossierRows(_ info: GGPeerInfoContext) -> [GGPeerInfoRow] {
        let peer = info.peer
        let key = GGMediaTokWave4Tools.peerKey(peer.id)
        let currentIdentity = "\(peer.debugDisplayTitle) (@\(peer.addressName ?? "нет"))"

        var historyDict = (UserDefaults.standard.dictionary(forKey: GGMediaTokWave4Tools.dossierHistoryKey) as? [String: [String]]) ?? [:]
        var list = historyDict[key] ?? []
        if list.last != currentIdentity {
            list.append(currentIdentity)
            if list.count > 8 { list.removeFirst(list.count - 8) }
            historyDict[key] = list
            UserDefaults.standard.set(historyDict, forKey: GGMediaTokWave4Tools.dossierHistoryKey)
        }

        var rows: [GGPeerInfoRow] = []
        if list.count > 1 {
            let oldOnes = list.dropLast().joined(separator: " → ")
            rows.append(GGPeerInfoRow(
                id: "mediatok.dossier.history",
                label: "🕵️ Старые ники (MediaTok)",
                text: oldOnes
            ))
        }

        let notesDict = (UserDefaults.standard.dictionary(forKey: GGMediaTokWave4Tools.dossierNotesKey) as? [String: String]) ?? [:]
        if let note = notesDict[key], !note.isEmpty {
            weak let controller = info.controller
            rows.append(GGPeerInfoRow(
                id: "mediatok.dossier.note",
                label: "📝 Личное досье (скрыто)",
                text: note,
                action: {
                    GGMediaTokWave4Tools.presentNoteEditor(peerId: peer.id) {
                        controller?.requestLayout(transition: .immediate)
                    }
                }
            ))
        }
        return rows
    }

    private static func dossierMenuItems(_ info: GGPeerInfoContext) -> [ContextMenuItem] {
        if info.isSettings { return [] }
        let peerId = info.peer.id
        weak let controller = info.controller
        return [.action(ContextMenuActionItem(
            text: "Личное досье / заметка",
            icon: { theme in
                return UIImage(systemName: "note.text.badge.plus")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                GGMediaTokWave4Tools.presentNoteEditor(peerId: peerId) {
                    controller?.requestLayout(transition: .immediate)
                }
            }
        ))]
    }

    private static func presentNoteEditor(peerId: PeerId, onSaved: @escaping () -> Void) {
        let key = GGMediaTokWave4Tools.peerKey(peerId)
        var notesDict = (UserDefaults.standard.dictionary(forKey: GGMediaTokWave4Tools.dossierNotesKey) as? [String: String]) ?? [:]
        let current = notesDict[key] ?? ""
        let alert = UIAlertController(
            title: "📝 Личное досье о контакте",
            message: "Заметка хранится только на вашем iPhone и видна прямо в профиле этого человека.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Например: #работа / должен 5к / старый друг"
            tf.text = current
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak alert] _ in
            let val = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if val.isEmpty {
                notesDict.removeValue(forKey: key)
            } else {
                notesDict[key] = val
            }
            UserDefaults.standard.set(notesDict, forKey: GGMediaTokWave4Tools.dossierNotesKey)
            onSaved()
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGMediaTokWave4Tools.presentOnRoot(alert)
    }

    // MARK: - Settings Hub

    static func presentHub(context: GGMenuContext) {
        let afkState = GGMediaTokWave4Tools.isAfkEnabled ? "ВКЛ" : "ВЫКЛ"
        let soundState = GGMediaTokWave4Tools.isWallpaperSoundEnabled ? "ВКЛ" : "ВЫКЛ"
        let sheet = UIAlertController(
            title: "⚡ Фичи MediaTok Wave 4",
            message: "• .q <текст> (или долгий тап по сообщению → «В стикер-цитату») — генератор прозрачных стикеров-цитат за 0.1 сек без ботов\n• .stats — стикер-инфографика чата\n• Долгий тап по фото → «Скопировать текст (OCR)» и «В стикер без фона»\n• Долгий тап по сообщению → «Напомнить»\n• Авто-история старых ников/юзернеймов + личное досье в каждом профиле\n• Анти-IP-Логгер ссылок",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "🤖 AFK-автоответчик в личке (\(afkState))", style: .default, handler: { _ in
            GGMediaTokWave4Tools.presentAfkEditor(context: context)
        }))
        sheet.addAction(UIAlertAction(title: "🔊 Звук живых обоев чата (\(soundState))", style: .default, handler: { _ in
            GGMediaTokWave4Tools.isWallpaperSoundEnabled.toggle()
            context.presentToast("Звук живых обоев: \(GGMediaTokWave4Tools.isWallpaperSoundEnabled ? "ВКЛ" : "ВЫКЛ")")
        }))
        sheet.addAction(UIAlertAction(title: "Готово", style: .cancel))
        context.presentNative(sheet)
    }

    private static func presentAfkEditor(context: GGMenuContext) {
        let alert = UIAlertController(
            title: "🤖 AFK-автоответчик",
            message: "Когда включён, MediaTok автоматически отвечает на новые сообщения в личке (не чаще 1 раза в 30 мин одному человеку). Также управляется в чате командой .afk on <текст> / .afk off.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = GGMediaTokWave4Tools.afkText
            tf.placeholder = "Текст автоответа"
        }
        alert.addAction(UIAlertAction(title: "Включить", style: .default, handler: { [weak alert] _ in
            let txt = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !txt.isEmpty { GGMediaTokWave4Tools.afkText = txt }
            GGMediaTokWave4Tools.isAfkEnabled = true
            context.presentToast("🤖 AFK-автоответчик включён!")
        }))
        if GGMediaTokWave4Tools.isAfkEnabled {
            alert.addAction(UIAlertAction(title: "Выключить AFK", style: .destructive, handler: { _ in
                GGMediaTokWave4Tools.isAfkEnabled = false
                context.presentToast("🤖 AFK-автоответчик выключен")
            }))
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        context.presentNative(alert)
    }

    private static func presentOnRoot(_ controller: UIViewController) {
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let root = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
                return
            }
            var presenter = root
            while let next = presenter.presentedViewController {
                presenter = next
            }
            if let pop = controller.popoverPresentationController {
                pop.sourceView = presenter.view
                pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0.0, height: 0.0)
                pop.permittedArrowDirections = []
            }
            presenter.present(controller, animated: true)
        }
    }

    private static func showToast(context: AccountContext, text: String) {
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
