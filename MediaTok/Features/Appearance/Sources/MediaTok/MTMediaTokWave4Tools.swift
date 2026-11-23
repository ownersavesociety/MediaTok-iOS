import Foundation
import UIKit
import CoreImage
import ImageIO
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
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

/// MediaTok Wave 4 Power Tools for iOS:
/// 1) Live Video Wallpaper Sound (`MTMediaTokWallpaperSound`): optional looping audio track for chat video wallpapers.
/// 2) Instant Local Quote-Sticker Generator (`.q` & Message Menu `"💬 В стикер-цитату"`): renders transparent WebP quote stickers on device in 0.1s without bots.
/// 3) Chat Stats Card Sticker (`.stats`): renders a 512px transparent neon infographic sticker.
/// 4) Photo OCR (`"📋 Скопировать текст с фото"`) & Vision Subject Cutout Sticker (`"✨ В стикер без фона"`).
/// 5) Message Reminder (`"Напомнить о сообщении"` via local notification).
/// 6) Anti-IP-Logger Link Guard & AFK Auto-Responder.
enum MTMediaTokWave4Tools {
    private static let afkEnabledKey = "mediatok.afk.enabled.v1"
    private static let afkTextKey = "mediatok.afk.text.v1"
    private static let wallpaperSoundEnabledKey = "mediatok.wallpaper.sound.v1"

    private static var wallpaperAudioPlayer: AVAudioPlayer?
    private static let afkLock = NSLock()
    private static var lastAfkReplyAt: [Int64: TimeInterval] = [:]
    private static var activeChatPeerId: PeerId?
    private static var afkWatchDisposables: [Int64: Disposable] = [:]

    private static func attachAfkBackgroundWatcher(context: AccountContext) {
        let accountKey = context.account.peerId.toInt64()
        let disposable = context.account.stateManager.notificationMessages.start(next: { batches in
            guard MTMediaTokWave4Tools.isAfkEnabled else { return }
            for (messages, _, _, _) in batches {
                for message in messages {
                    MTMediaTokWave4Tools.handleIncomingForAfk(message: message, context: context)
                }
            }
        })
        MTMediaTokWave4Tools.afkLock.lock()
        let previous = MTMediaTokWave4Tools.afkWatchDisposables[accountKey]
        MTMediaTokWave4Tools.afkWatchDisposables[accountKey] = disposable
        MTMediaTokWave4Tools.afkLock.unlock()
        previous?.dispose()
    }

    private static func setActiveChat(_ peerId: PeerId?, active: Bool) {
        MTMediaTokWave4Tools.afkLock.lock()
        if active {
            MTMediaTokWave4Tools.activeChatPeerId = peerId
        } else if MTMediaTokWave4Tools.activeChatPeerId == peerId {
            MTMediaTokWave4Tools.activeChatPeerId = nil
        }
        MTMediaTokWave4Tools.afkLock.unlock()
    }

    static func register() {
        // 1. Outgoing `.q` quote-sticker & `.stats` infographic sticker
        MTOutgoingHooks.messages.register({ messages, context in
            MTMediaTokWave4Tools.transformOutgoing(&messages, context: context)
        }, order: 42)

        // 2. Inline `.afk` command interceptor
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave4Tools.interceptCommands(request)
        }, order: 25)

        // 3. Message Long-Press Context Menu items (Quote Sticker, Photo OCR, Cutout Sticker, Reminder)
        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave4Tools.messageMenuItems(menuContext)
        }, order: 85)

        // 4. Anti-IP-Logger Link Guard
        MTMessageDecorationHooks.decorations.register({ decoration, context in
            MTMediaTokWave4Tools.decorateMessage(&decoration, message: context.message, context: context.context)
        }, order: 48)

        // 4b. Background AFK Auto-Responder on real incoming notificationMessages stream (works even with chat closed)
        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTMediaTokWave4Tools.attachAfkBackgroundWatcher(context: context)
        }, order: 49)

        // 5. Live Video Wallpaper Sound & active chat tracking for AFK
        MTChatScreenHooks.lifecycle.register({ event, screen in
            switch event {
            case .didAppear:
                MTMediaTokWave4Tools.setActiveChat(screen.chatLocation.peerId, active: true)
                MTMediaTokWave4Tools.updateWallpaperSoundPlayback(inChat: true)
            case .willDisappear:
                MTMediaTokWave4Tools.setActiveChat(screen.chatLocation.peerId, active: false)
                MTMediaTokWave4Tools.updateWallpaperSoundPlayback(inChat: false)
            case .willAppear:
                break
            }
        }, order: 120)
    }

    // MARK: - 1. Live Video Wallpaper Sound

    static var isWallpaperSoundEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave4Tools.wallpaperSoundEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: MTMediaTokWave4Tools.wallpaperSoundEnabledKey)
            if !newValue {
                MTMediaTokWave4Tools.wallpaperAudioPlayer?.stop()
                MTMediaTokWave4Tools.wallpaperAudioPlayer = nil
            }
        }
    }

    static var wallpaperSoundURL: URL? {
        guard let dir = MTAnimatedBackgrounds.directory else { return nil }
        let url = dir.appendingPathComponent("chat-background-audio.mp3")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let m4a = dir.appendingPathComponent("chat-background-audio.m4a")
        if FileManager.default.fileExists(atPath: m4a.path) { return m4a }
        return nil
    }

    static func updateWallpaperSoundPlayback(inChat: Bool) {
        guard inChat,
              MTMediaTokWave4Tools.isWallpaperSoundEnabled,
              MTAppearanceSettings.chatBackground.value,
              let url = MTMediaTokWave4Tools.wallpaperSoundURL else {
            MTMediaTokWave4Tools.wallpaperAudioPlayer?.pause()
            return
        }
        if let player = MTMediaTokWave4Tools.wallpaperAudioPlayer, player.url == url {
            if !player.isPlaying { player.play() }
            return
        }
        let _ = try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1
            player.volume = 0.35
            player.prepareToPlay()
            player.play()
            MTMediaTokWave4Tools.wallpaperAudioPlayer = player
        }
    }

    // MARK: - 2. Instant Local Quote-Sticker (`.q`) & Chat Stats Sticker (`.stats`)

    private static func transformOutgoing(_ messages: inout [EnqueueMessage], context: MTOutgoingContext) {
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
                    if !quoteText.isEmpty {
                        renderedSticker = MTMediaTokWave4Tools.renderQuoteSticker(author: author.isEmpty ? "MediaTok" : author, text: quoteText)
                    }
                }
            } else if lower == ".stats" || lower.hasPrefix(".stats ") {
                let title = lower.hasPrefix(".stats ") ? String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) : "MediaTok Chat"
                renderedSticker = MTMediaTokWave4Tools.renderStatsSticker(chatTitle: title.isEmpty ? "MediaTok Chat" : title, peerId: context.peerId)
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

            let guardState = MTMediaTokAudioGuard.modeLabel
            let fontName = MTFonts.selectedDisplayName
            let lines = [
                "• ID чата: \(peerId.id._internalGetInt64Value())",
                "• Анти-Скример / Стоны: \(guardState) 🛡",
                "• Активный шрифт: \(fontName)",
                "• Клиент: MediaTok iOS 4K"
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

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        let peerId = message.id.peerId
        var entries: [MTMessageMenuEntry] = []

        // A) Pure text message -> Instant Quote Sticker
        if message.media.isEmpty && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let msgText = message.text
            let authorName = message.author?.debugDisplayTitle ?? "Telegram"
            let replyId = message.id
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "В стикер-цитату",
                icon: { theme in
                    return UIImage(systemName: "quote.bubble.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave4Tools.sendQuoteStickerFromMenu(context: context, peerId: peerId, replyTo: replyId, author: authorName, text: msgText)
                }
            ))))
        }

        // B) Photo message -> Vision Subject Cutout Sticker + Fixed Photo OCR (#159)
        if let imageMedia = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage,
           let largest = largestImageRepresentation(imageMedia.representations) {
            let resource = largest.resource
            let replyId = message.id
            let targetMessage = message
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Распознать текст (OCR)",
                icon: { theme in
                    return UIImage(systemName: "doc.text.viewfinder")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave4Tools.runPhotoOCR(context: context, message: targetMessage, imageMedia: imageMedia, resource: resource)
                }
            ))))
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Вырезать объект в стикер",
                icon: { theme in
                    return UIImage(systemName: "wand.and.stars")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave4Tools.createCutoutStickerFromPhoto(context: context, message: targetMessage, imageMedia: imageMedia, peerId: peerId, replyTo: replyId, resource: resource)
                }
            ))))
        }

        // C) Message Reminder -> Local Notification
        let remText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remText.isEmpty || !message.media.isEmpty {
            let remAuthor = message.author?.debugDisplayTitle ?? "Telegram"
            let remPreview = remText.isEmpty ? "[Медиа]" : remText
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Напомнить",
                icon: { theme in
                    return UIImage(systemName: "bell.badge.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave4Tools.presentReminderSheet(context: context, author: remAuthor, text: remPreview)
                }
            ))))
        }

        return entries
    }

    private static func sendQuoteStickerFromMenu(context: AccountContext, peerId: PeerId, replyTo: MessageId, author: String, text: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let rendered = MTMediaTokWave4Tools.renderQuoteSticker(author: author, text: text),
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

    private static func cgOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private final class MTOcrLinesBox: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) {
            self.lock.lock()
            self.lines.append(line)
            self.lock.unlock()
        }
        func joined() -> String {
            self.lock.lock()
            let out = self.lines.joined(separator: "\n")
            self.lock.unlock()
            return out
        }
    }

    private final class MTWave4DisposableBox: @unchecked Sendable {
        private let disposable = MetaDisposable()
        func set(_ d: Disposable?) { self.disposable.set(d) }
        func dispose() { self.disposable.dispose() }
    }

    private enum MTPhotoOcrResult: Sendable {
        case text(String)
        case empty
        case timeout
        case error(String)
    }

    private static func runPhotoOCR(context: AccountContext, message: Message, imageMedia: TelegramMediaImage, resource: MediaResource) {
        MTMediaTokWave4Tools.showToast(context: context, text: "Распознаю текст с фото (Vision OCR)...")
        let fetchBox = MTWave4DisposableBox()
        fetchBox.set(fetchedMediaResource(
            mediaBox: context.account.postbox.mediaBox,
            userLocation: .peer(message.id.peerId),
            userContentType: .image,
            reference: ImageMediaReference.message(message: MessageReference(message), media: imageMedia).resourceReference(resource)
        ).startStandalone())

        let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)
        |> timeout(15.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(MediaResourceData(path: "", offset: 0, size: 0, complete: false)))
        |> deliverOn(Queue.concurrentDefaultQueue())
        |> map { data -> MTPhotoOcrResult in
            fetchBox.dispose()
            guard data.complete, !data.path.isEmpty else { return .timeout }
            guard let image = UIImage(contentsOfFile: data.path) else {
                return .error("Не удалось прочитать изображение")
            }
            let cgImage: CGImage?
            if let direct = image.cgImage {
                cgImage = direct
            } else {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1.0
                let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                }
                cgImage = rendered.cgImage
            }
            guard let cg = cgImage else {
                return .error("Не удалось декодировать CGImage")
            }
            let linesBox = MTOcrLinesBox()
            let req = VNRecognizeTextRequest { request, _ in
                guard let results = request.results as? [VNRecognizedTextObservation] else { return }
                for obs in results {
                    if let top = obs.topCandidates(1).first?.string, !top.isEmpty {
                        linesBox.append(top)
                    }
                }
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = ["ru-RU", "en-US", "uk-UA"]
            let orientation = MTMediaTokWave4Tools.cgOrientation(from: image.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            do {
                try handler.perform([req])
            } catch {
                return .error(error.localizedDescription)
            }
            let text = linesBox.joined()
            return text.isEmpty ? .empty : .text(text)
        }
        |> deliverOnMainQueue).startStandalone(next: { result in
            switch result {
            case .timeout:
                MTMediaTokWave4Tools.showToast(context: context, text: "Таймаут загрузки фото (15 сек)")
            case let .error(reason):
                MTMediaTokWave4Tools.showToast(context: context, text: "Ошибка OCR: \(reason)")
            case .empty:
                MTMediaTokWave4Tools.showToast(context: context, text: "Текст на фото не найден")
            case let .text(text):
                UIPasteboard.general.string = text
                MTMediaTokWave4Tools.showToast(context: context, text: "Текст с фото скопирован (\(text.count) симв.)")
                let preview = text.count > 900 ? String(text.prefix(900)) + "\n..." : text
                mtPresentNativeActionSheet(
                    context: context,
                    title: "Распознанный текст (OCR):\n\(preview)",
                    buttons: [
                        (title: "Скопировать", isDestructive: false, action: {
                            UIPasteboard.general.string = text
                        }),
                        (title: "Поделиться", isDestructive: false, action: {
                            let share = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                            MTModalPresenter.presentOnTopmost(share)
                        })
                    ]
                )
            }
        })
    }

    private static func createCutoutStickerFromPhoto(context: AccountContext, message: Message, imageMedia: TelegramMediaImage, peerId: PeerId, replyTo: MessageId, resource: MediaResource) {
        MTMediaTokWave4Tools.showToast(context: context, text: "✨ Вырезаю фон и собираю стикер...")
        let fetchBox = MTWave4DisposableBox()
        fetchBox.set(fetchedMediaResource(
            mediaBox: context.account.postbox.mediaBox,
            userLocation: .peer(peerId),
            userContentType: .image,
            reference: ImageMediaReference.message(message: MessageReference(message), media: imageMedia).resourceReference(resource)
        ).startStandalone())

        let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)
        |> timeout(15.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(MediaResourceData(path: "", offset: 0, size: 0, complete: false)))
        |> deliverOn(Queue.concurrentDefaultQueue())).startStandalone(next: { data in
            fetchBox.dispose()
            guard data.complete, !data.path.isEmpty else {
                MTMediaTokWave4Tools.showToast(context: context, text: "Таймаут загрузки фото (15 сек)")
                return
            }
            guard let sourceImage = UIImage(contentsOfFile: data.path) else {
                MTMediaTokWave4Tools.showToast(context: context, text: "Не удалось прочитать фото для стикера")
                return
            }
            let stickerImage = MTMediaTokWave4Tools.makeStickerCanvas512(from: sourceImage)
            guard let webpData = try? WebP.convert(toWebP: stickerImage, quality: 92.0),
                  !webpData.isEmpty else {
                MTMediaTokWave4Tools.showToast(context: context, text: "Ошибка конвертации стикера в WebP")
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
            let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [msg]).startStandalone()
        })
    }

    private static func cgImageOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private static func makeStickerCanvas512(from image: UIImage) -> UIImage {
        var subjectImage = image
        var hasTransparentCutout = false

        if #available(iOS 17.0, *) {
            let resolvedCgImage: CGImage?
            if let direct = image.cgImage {
                resolvedCgImage = direct
            } else {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1.0
                let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                }
                resolvedCgImage = rendered.cgImage
            }
            if let cgImage = resolvedCgImage {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let orientation = MTMediaTokWave4Tools.cgImageOrientation(from: image.imageOrientation)
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                if (try? handler.perform([request])) != nil,
                   let obs = request.results?.first,
                   let maskedBuffer = try? obs.generateMaskedImage(
                       ofInstances: obs.allInstances,
                       from: handler,
                       croppedToInstancesExtent: true
                   ) {
                    let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
                    let ciContext = CIContext(options: nil)
                    if let outCG = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                        subjectImage = UIImage(cgImage: outCG)
                        hasTransparentCutout = true
                    }
                }
            }
        }

        let size = CGSize(width: 512.0, height: 512.0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let aspect = subjectImage.size.width / max(1.0, subjectImage.size.height)
        let maxSide: CGFloat = hasTransparentCutout ? 472.0 : 484.0
        let drawW: CGFloat = aspect >= 1.0 ? maxSide : maxSide * aspect
        let drawH: CGFloat = aspect >= 1.0 ? maxSide / aspect : maxSide
        let drawRect = CGRect(x: (512.0 - drawW) / 2.0, y: (512.0 - drawH) / 2.0, width: drawW, height: drawH)

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            if hasTransparentCutout {
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 10.0, color: UIColor.white.withAlphaComponent(0.88).cgColor)
                subjectImage.draw(in: drawRect)
                cg.restoreGState()
                subjectImage.draw(in: drawRect)
            } else {
                let path = UIBezierPath(roundedRect: drawRect, cornerRadius: 34.0)
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 12.0, color: UIColor(rgb: 0x00F5FF).withAlphaComponent(0.75).cgColor)
                UIColor.white.setStroke()
                path.lineWidth = 6.0
                path.stroke()
                cg.restoreGState()

                cg.saveGState()
                path.addClip()
                subjectImage.draw(in: drawRect)
                cg.restoreGState()

                UIColor.white.setStroke()
                path.lineWidth = 5.0
                path.stroke()
            }
        }
    }

    private static func presentReminderSheet(context: AccountContext, author: String, text: String) {
        let choices: [(String, TimeInterval)] = [
            ("Через 15 минут", 900.0),
            ("Через 1 час", 3600.0),
            ("Через 3 часа", 10800.0),
            ("Завтра (через 24 ч)", 86400.0)
        ]
        let buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = choices.map { title, sec in
            (title: title, isDestructive: false, action: {
                let center = UNUserNotificationCenter.current()
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if !granted {
                        MTMediaTokWave4Tools.showToast(context: context, text: "⚠️ Включите уведомления MediaTok в Настройках iPhone")
                        return
                    }
                    let content = UNMutableNotificationContent()
                    content.title = "⏰ Напоминание MediaTok (\(author))"
                    content.body = String(text.prefix(200))
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: sec, repeats: false)
                    let req = UNNotificationRequest(identifier: "mt_rem_\(UUID().uuidString)", content: content, trigger: trigger)
                    center.add(req) { error in
                        if error != nil {
                            MTMediaTokWave4Tools.showToast(context: context, text: "⚠️ Ошибка планирования напоминания")
                        } else {
                            MTMediaTokWave4Tools.showToast(context: context, text: "⏰ Напоминание поставлено: \(title)")
                        }
                    }
                }
            })
        }
        mtPresentNativeActionSheet(
            context: context,
            title: "⏰ Напомнить о сообщении\nОт \(author): «\(text.prefix(80))»",
            buttons: buttons
        )
    }

    // MARK: - 4. Anti-IP-Logger Link Guard & AFK Auto-Responder

    static var isAfkEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave4Tools.afkEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave4Tools.afkEnabledKey) }
    }

    static var afkText: String {
        get {
            let v = UserDefaults.standard.string(forKey: MTMediaTokWave4Tools.afkTextKey) ?? ""
            return v.isEmpty ? "[Автоответчик MediaTok]: Сейчас не у телефона, отвечу как освобожусь." : v
        }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave4Tools.afkTextKey) }
    }

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        guard lower == ".afk" || lower == ".afk off" || lower.hasPrefix(".afk on") else {
            return false
        }
        request.replace(ChatTextInputState())
        if lower == ".afk off" {
            MTMediaTokWave4Tools.isAfkEnabled = false
            MTMediaTokWave4Tools.showToast(context: request.context, text: "AFK-автоответчик выключен")
        } else if lower.hasPrefix(".afk on") {
            let custom = String(raw.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty {
                MTMediaTokWave4Tools.afkText = custom
            }
            MTMediaTokWave4Tools.isAfkEnabled = true
            MTMediaTokWave4Tools.showToast(context: request.context, text: "AFK-автоответчик включён: «\(MTMediaTokWave4Tools.afkText)»")
        } else {
            MTMediaTokWave4Tools.isAfkEnabled.toggle()
            let state = MTMediaTokWave4Tools.isAfkEnabled ? "ВКЛ" : "ВЫКЛ"
            MTMediaTokWave4Tools.showToast(context: request.context, text: "AFK-автоответчик: \(state)")
        }
        return true
    }

    private static func decorateMessage(_ decoration: inout MTMessageDecoration, message: Message, context: AccountContext) {
        let _ = context
        let text = message.text
        var extraUrls: [String] = []
        for attr in message.attributes {
            if let entitiesAttr = attr as? TextEntitiesMessageAttribute {
                for entity in entitiesAttr.entities {
                    if case let .TextUrl(url) = entity.type {
                        extraUrls.append(url)
                    }
                }
            }
        }
        if !text.isEmpty || !extraUrls.isEmpty {
            if let domain = MTMediaTokCoreLogic.detectIpLoggerHost(text: text, extraUrls: extraUrls) {
                decoration.footnote = MTMessageFootnote(
                    text: "ОПАСНО (Анти-Логгер MediaTok): ссылка ведёт на IP-логгер (\(domain)). Не переходите без VPN.",
                    entities: [],
                    alpha: 0.95
                )
            }
        }
    }

    /// Background AFK auto-responder driven by `AccountStateManager.notificationMessages`
    /// so incoming private messages receive a reply even when the chat is not open.
    private static func handleIncomingForAfk(message: Message, context: AccountContext) {
        guard MTMediaTokWave4Tools.isAfkEnabled,
              message.flags.contains(.Incoming),
              message.id.peerId.namespace == Namespaces.Peer.CloudUser,
              message.id.peerId != context.account.peerId else {
            return
        }
        let isBotAuthor = (message.author as? TelegramUser)?.botInfo != nil
        let isBotPeer = (message.peers[message.id.peerId] as? TelegramUser)?.botInfo != nil
        guard !isBotAuthor && !isBotPeer else { return }

        let now = Date().timeIntervalSince1970
        let msgAge = now - Double(message.timestamp)
        guard msgAge >= -10.0 && msgAge <= 45.0 else { return }

        let rawPeer = message.id.peerId.id._internalGetInt64Value()
        var shouldSendReply = false
        MTMediaTokWave4Tools.afkLock.lock()
        let isActiveOpenChat = (MTMediaTokWave4Tools.activeChatPeerId == message.id.peerId)
        if !isActiveOpenChat {
            let prevReply = MTMediaTokWave4Tools.lastAfkReplyAt[rawPeer] ?? 0.0
            if (now - prevReply) > 1800.0 {
                if MTMediaTokWave4Tools.lastAfkReplyAt.count > 512 {
                    MTMediaTokWave4Tools.lastAfkReplyAt.removeAll()
                }
                MTMediaTokWave4Tools.lastAfkReplyAt[rawPeer] = now
                shouldSendReply = true
            }
        }
        MTMediaTokWave4Tools.afkLock.unlock()

        if shouldSendReply {
            let replyMsg: EnqueueMessage = .message(
                text: MTMediaTokWave4Tools.afkText,
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

    // MARK: - Settings Hub

    static func presentHub(context: MTMenuContext) {
        let afkState = MTMediaTokWave4Tools.isAfkEnabled ? "ВКЛ" : "ВЫКЛ"
        let soundState = MTMediaTokWave4Tools.isWallpaperSoundEnabled ? "ВКЛ" : "ВЫКЛ"
        var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = [
            (title: "AFK-автоответчик в личке (\(afkState))", isDestructive: false, action: {
                MTMediaTokWave4Tools.presentAfkEditor(context: context)
            }),
            (title: "Звук живых обоев чата (\(soundState))", isDestructive: false, action: {
                MTMediaTokWave4Tools.isWallpaperSoundEnabled.toggle()
                context.presentToast("Звук живых обоев: \(MTMediaTokWave4Tools.isWallpaperSoundEnabled ? "ВКЛ" : "ВЫКЛ")")
            })
        ]
        if MTMediaTokWave4Tools.isAfkEnabled {
            buttons.append((title: "Выключить AFK-автоответчик", isDestructive: true, action: {
                MTMediaTokWave4Tools.isAfkEnabled = false
                context.presentToast("AFK-автоответчик выключен")
            }))
        }
        context.presentActionSheet(
            title: "Фичи MediaTok Wave 4\n• .q <текст> — стикер-цитата за 0.1 сек\n• .stats — инфографика чата\n• Фото → OCR и стикер без фона\n• Сообщение → Напомнить",
            buttons: buttons
        )
    }

    private static func presentAfkEditor(context: MTMenuContext) {
        context.presentPrompt(
            title: "AFK-автоответчик",
            subtitle: "Автоответ в личке (не чаще 1 раза в 30 мин). Пустая строка выключает AFK.",
            value: MTMediaTokWave4Tools.afkText,
            placeholder: "Текст автоответа"
        ) { entered in
            let txt = entered.trimmingCharacters(in: .whitespacesAndNewlines)
            if txt.isEmpty {
                MTMediaTokWave4Tools.isAfkEnabled = false
                context.presentToast("AFK-автоответчик выключен")
            } else {
                MTMediaTokWave4Tools.afkText = txt
                MTMediaTokWave4Tools.isAfkEnabled = true
                context.presentToast("AFK-автоответчик включён")
            }
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
