import Foundation
import UIKit
import AVFoundation
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import Display
import ItemListUI
import SwiftSignalKit
import ContextUI
import UndoUI
import WebPBinding
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

/// MediaTok Wave 6 Mega-Pack (all non-rejected user-approved features):
/// - #58 Call Confirm Guard (MTCallHooks.outgoingCall)
/// - #163 Interactive Scratch Messages (end-to-end wire format + real finger-erase foil canvas!)
/// - #59 Semi-Transparent Photo Watermark on outgoing photos
/// - #62 Keyboard Layout Auto-Fixer (.fix / .ghbdtn + message long-press fixer)
/// - #65 Instant QR Code WebP Sticker (.qr + Send menu)
/// - #170 Wheel of Fortune (.wheel), #176 Private 1-on-1 Poll (.poll), #177 Split Bill (.split), #166 Time Capsule (.capsule)
/// - #45 Anti-Phishing & Homograph Link Guard + #188 Channel Ad-Blocker (MTMessageDecorationHooks.decorations)
/// - #61 Custom Snippets / Macros (.sn add/del/list/expand + Send menu)
/// - #64 Mini-Wiki / Dictionary (.wiki / .def)
/// - #66 Safe URL Unshortener (.unshort + message long-press menu)
/// - #121 BYOK Gemini AI Assistant (.ai reusing Keychain key from /stickers)
/// - #162 Graffiti Neon Drawing Board (Send menu -> sends 512px WebP sticker!)
/// - #48 Privacy Screen ("Защита от плеча" frosted veil overlay)
/// - #198 Per-Chat Local Scratchpad (.note + Send menu)
/// - #191 Dev Inspector & #193 JSON Pretty-Viewer (message long-press menu)
/// - #20 Extract Audio (.m4a) from Video/Circle (message long-press menu)
/// - #168 MediaTok Achievements System (12 badges + tiers)
/// - #110 Bottom Bar / Tab Bar Studio
/// - #164 Neon Minesweeper (Сапёр 8x8)
/// - #169 MediaTok Wrapped & #199 Self-Diagnostics
public enum MTMediaTokWave6Tools {
    private static let callConfirmKey = "mediatok.guard.callConfirm.v1"
    private static let watermarkEnabledKey = "mediatok.watermark.enabled.v1"
    private static let watermarkTagKey = "mediatok.watermark.tag.v1"
    private static let adBlockKey = "mediatok.adblock.enabled.v1"
    private static let snippetsKey = "mediatok.snippets.v1"
    private static let notesPrefixKey = "mediatok.chat_note.v1."
    private static let unlockedAchievementsKey = "mediatok.achievements.unlocked.v1"

    private static var privacyVeilView: UIVisualEffectView?

    public static var isCallConfirmEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave6Tools.callConfirmKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave6Tools.callConfirmKey) }
    }

    public static var isWatermarkEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave6Tools.watermarkEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave6Tools.watermarkEnabledKey) }
    }

    public static var customWatermarkTag: String {
        get { return UserDefaults.standard.string(forKey: MTMediaTokWave6Tools.watermarkTagKey) ?? "MediaTok" }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave6Tools.watermarkTagKey) }
    }

    public static var isAdBlockEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: MTMediaTokWave6Tools.adBlockKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: MTMediaTokWave6Tools.adBlockKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave6Tools.adBlockKey) }
    }

    public static func register() {
        // 1. Call Confirm Guard (#58)
        MTCallHooks.outgoingCall.register({ req, proceed in
            guard MTMediaTokWave6Tools.isCallConfirmEnabled else { return false }
            DispatchQueue.main.async {
                let callType = req.isVideo ? "видеозвонок" : "аудиозвонок"
                let alert = UIAlertController(
                    title: "📞 Подтверждение звонка",
                    message: "Вы действительно хотите начать \(callType)?",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Позвонить", style: .default, handler: { _ in
                    MTMediaTokWave6Tools.unlockAchievement(.callGuard)
                    proceed()
                }))
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                MTMediaTokWave5Tools.presentOnRoot(alert)
            }
            return true
        }, order: 90)

        // 2. Inline Text Commands (.fix, .ghbdtn, .sn, .wiki, .def, .unshort, .ai, .note, .mood, .wish)
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave6Tools.interceptCommands(request)
        }, order: 24)

        // 3. Outgoing Text Stage: .scratch wire encoding (#163) + Night Owl achievement
        MTOutgoingHooks.textStages.register({ outgoing, _ in
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 3 && hour < 5 {
                MTMediaTokWave6Tools.unlockAchievement(.nightOwl)
            }
            if let scratch = MTMediaTokCoreLogic.parseScratchCommand(outgoing.text) {
                outgoing.text = MTMediaTokCoreLogic.encodeScratchWireMessage(scratch)
                outgoing.entities = []
                MTMediaTokWave6Tools.unlockAchievement(.mediatokOg)
            }
        }, order: 90)

        // 4. Outgoing Sticker Generators (.qr, .wheel, .poll, .split, .capsule)
        MTOutgoingHooks.messages.register({ messages, context in
            MTMediaTokWave6Tools.transformWave6Stickers(&messages, context: context)
        }, order: 42)

        // 5. Outgoing Photo Watermark Stamper (#59)
        MTOutgoingHooks.messages.register({ messages, context in
            MTMediaTokWave6Tools.applyWatermarkIfEnabled(&messages, context: context)
        }, order: 44)

        // 6. Message Decorations: Anti-Phishing (#45), Channel Ad-Blocker (#188), Scratch Wire Display (#163)
        MTMessageDecorationHooks.decorations.register({ decoration, context in
            MTMediaTokWave6Tools.decorateMessage(&decoration, message: context.message)
        }, order: 50)

        // 7. Send Button Long-Press Menu: Scratch, QR, Graffiti, Snippets, Note, Privacy Screen, Watermark
        MTChatScreenHooks.sendMenuItems.register({ sendContext in
            return MTMediaTokWave6Tools.sendMenuItems(sendContext)
        }, order: 76)

        // 8. Message Long-Press Menu: Scratch Foil Reveal, Layout Fixer, Unshort URL, Dev/JSON Inspector, Extract Audio
        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave6Tools.messageMenuItems(menuContext)
        }, order: 88)
    }

    // MARK: - Inline Commands

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }

        // .fix / .ghbdtn (#62)
        if let fixed = MTMediaTokCoreLogic.parseFixCommand(raw) {
            if !fixed.isEmpty {
                request.replace(ChatTextInputState(inputText: NSAttributedString(string: fixed)))
                MTMediaTokWave5Tools.showToast(context: request.context, text: "⌨️ Раскладка исправлена — нажми отправить!")
                return true
            }
            return false
        }

        // .sn snippets (#61)
        if let snCmd = MTMediaTokCoreLogic.parseSnippetCommand(raw) {
            request.replace(ChatTextInputState())
            switch snCmd {
            case .list:
                MTMediaTokWave6Tools.presentSnippetsSheet(context: request.context) { value in
                    request.replace(ChatTextInputState(inputText: NSAttributedString(string: value)))
                }
            case let .add(key, value):
                var map = MTMediaTokWave6Tools.loadSnippets()
                map[key] = value
                MTMediaTokWave6Tools.saveSnippets(map)
                MTMediaTokWave5Tools.showToast(context: request.context, text: "⚡ Сниппет «\(key)» сохранён (.sn \(key))")
            case let .remove(key):
                var map = MTMediaTokWave6Tools.loadSnippets()
                map.removeValue(forKey: key)
                MTMediaTokWave6Tools.saveSnippets(map)
                MTMediaTokWave5Tools.showToast(context: request.context, text: "🗑️ Сниппет «\(key)» удалён")
            case let .expand(key):
                let map = MTMediaTokWave6Tools.loadSnippets()
                if let val = map[key] {
                    request.replace(ChatTextInputState(inputText: NSAttributedString(string: val)))
                } else {
                    MTMediaTokWave5Tools.showToast(context: request.context, text: "Сниппет «\(key)» не найден. Добавь: .sn add \(key) текст")
                }
            }
            return true
        }

        // .wiki / .def (#64)
        if let query = MTMediaTokCoreLogic.parsePrefixPayload(raw, prefixes: [".wiki ", ".def "], maxLen: 120) {
            request.replace(ChatTextInputState())
            MTMediaTokWave6Tools.fetchWikiSummary(query: query, context: request.context) { text in
                request.replace(ChatTextInputState(inputText: NSAttributedString(string: text)))
            }
            return true
        }

        // .unshort (#66)
        if let shortUrl = MTMediaTokCoreLogic.parsePrefixPayload(raw, prefixes: [".unshort "], maxLen: 400) {
            request.replace(ChatTextInputState())
            MTMediaTokWave6Tools.unshortenUrl(shortUrl, context: request.context)
            return true
        }

        // .ai (#121 BYOK Gemini)
        if let prompt = MTMediaTokCoreLogic.parsePrefixPayload(raw, prefixes: [".ai "], maxLen: 1000) {
            request.replace(ChatTextInputState())
            MTMediaTokWave6Tools.runByokAiPrompt(prompt, context: request.context) { reply in
                request.replace(ChatTextInputState(inputText: NSAttributedString(string: reply)))
            }
            return true
        }

        // .note (#198 Per-chat local scratchpad)
        let lower = raw.lowercased()
        if lower == ".note" || lower.hasPrefix(".note ") {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            let body = lower.hasPrefix(".note ") ? String(raw.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if body.isEmpty {
                MTMediaTokWave6Tools.presentChatNoteEditor(peerId: peerId, context: request.context)
            } else {
                let existing = MTMediaTokWave6Tools.chatNote(for: peerId)
                let merged = existing.isEmpty ? body : "\(existing)\n• \(body)"
                MTMediaTokWave6Tools.setChatNote(merged, for: peerId)
                MTMediaTokWave5Tools.showToast(context: request.context, text: "📝 Заметка сохранена для этого чата (.note чтобы открыть)")
            }
            return true
        }

        // .mood (#31)
        if let mood = MTMediaTokCoreLogic.parseMoodCommand(raw) {
            request.replace(ChatTextInputState())
            UserDefaults.standard.set("\(mood.emoji) \(mood.text)", forKey: "mediatok.profile.mood")
            MTMediaTokWave5Tools.showToast(context: request.context, text: "✨ Настроение обновлено: \(mood.emoji) \(mood.text)")
            return true
        }

        // .wish (#178)
        if let wish = MTMediaTokCoreLogic.parseWishCommand(raw) {
            request.replace(ChatTextInputState())
            var wishes = UserDefaults.standard.stringArray(forKey: "mediatok.profile.wishes") ?? []
            wishes.append(wish)
            UserDefaults.standard.set(wishes, forKey: "mediatok.profile.wishes")
            MTMediaTokWave5Tools.showToast(context: request.context, text: "🎁 Добавлено в вишлист (\(wishes.count)): \(wish)")
            return true
        }

        return false
    }

    // MARK: - Outgoing Sticker Generators (.qr, .wheel, .poll, .split, .capsule)

    private static func transformWave6Stickers(_ messages: inout [EnqueueMessage], context: MTOutgoingContext) {
        for i in 0 ..< messages.count {
            guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = messages[i],
                  mediaReference == nil else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            var renderedImg: UIImage?
            var fileName = "mediatok_w6.webp"
            var emoji = "✨"

            if let qrText = MTMediaTokCoreLogic.parseQrCommand(trimmed) {
                renderedImg = MTMediaTokWave6Tools.renderQrStickerImage(text: qrText)
                fileName = "mediatok_qr.webp"
                emoji = "🔲"
            } else if let options = MTMediaTokCoreLogic.parseWheelCommand(trimmed) {
                let winner = options.randomElement() ?? options[0]
                let card = MTMediaTokCoreLogic.CardPayload(
                    title: "🎡 Колесо Фортуны",
                    subtitle: "Выпало: \(winner) 🏆",
                    lines: options.prefix(6).map { $0 == winner ? "👉 \($0) [ПОБЕДА]" : "• \($0)" }
                )
                renderedImg = MTMediaTokWave5Tools.renderInfoCardSticker(card)
                fileName = "mediatok_wheel.webp"
                emoji = "🎡"
            } else if let poll = MTMediaTokCoreLogic.parsePollCommand(trimmed) {
                let card = MTMediaTokCoreLogic.CardPayload(
                    title: "📊 Опрос 1-на-1",
                    subtitle: poll.question,
                    lines: poll.options.prefix(6).enumerated().map { "[\($0.offset + 1)] \($0.element)" }
                )
                renderedImg = MTMediaTokWave5Tools.renderInfoCardSticker(card)
                fileName = "mediatok_poll.webp"
                emoji = "📊"
            } else if let split = MTMediaTokCoreLogic.parseSplitBillCommand(trimmed) {
                let card = MTMediaTokCoreLogic.CardPayload(
                    title: "💰 Сплит счёта",
                    subtitle: "Итого: \(Int(split.total)) ₽ на \(split.peopleCount) чел.",
                    lines: [
                        "С каждого: \(split.perPerson) ₽",
                        "MediaTok Split Bill"
                    ]
                )
                renderedImg = MTMediaTokWave5Tools.renderInfoCardSticker(card)
                fileName = "mediatok_split.webp"
                emoji = "💰"
            } else if let cap = MTMediaTokCoreLogic.parseTimeCapsuleCommand(trimmed) {
                let card = MTMediaTokCoreLogic.CardPayload(
                    title: "⏳ Капсула времени",
                    subtitle: "Открыть: \(cap.unlockDateStr)",
                    lines: [
                        "🔒 Запечатано в MediaTok",
                        String(cap.message.prefix(120))
                    ]
                )
                renderedImg = MTMediaTokWave5Tools.renderInfoCardSticker(card)
                fileName = "mediatok_capsule.webp"
                emoji = "⏳"
            }

            guard let img = renderedImg,
                  let webpData = try? WebP.convert(toWebP: img, quality: 90.0),
                  !webpData.isEmpty else {
                continue
            }

            let media = MTMediaTokWave6Tools.makeStickerMedia(account: context.account, webpData: webpData, size: img.size, fileName: fileName, emoji: emoji)
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
            MTMediaTokWave6Tools.unlockAchievement(.mediatokOg)
        }
    }

    static func makeStickerMedia(account: Account, webpData: Data, size: CGSize, fileName: String, emoji: String) -> TelegramMediaFile {
        let fileId = Int64.random(in: Int64.min ... Int64.max)
        let resource = LocalFileMediaResource(fileId: fileId)
        account.postbox.mediaBox.storeResourceData(resource.id, data: webpData, synchronous: true)
        let fileAttrs: [TelegramMediaFileAttribute] = [
            .FileName(fileName: fileName),
            .Sticker(displayText: emoji, packReference: nil, maskData: nil),
            .ImageSize(size: PixelDimensions(width: Int32(size.width), height: Int32(size.height)))
        ]
        return TelegramMediaFile(
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
    }

    // MARK: - Outgoing Photo Watermark (#59)

    private static func applyWatermarkIfEnabled(_ messages: inout [EnqueueMessage], context: MTOutgoingContext) {
        guard MTMediaTokWave6Tools.isWatermarkEnabled else { return }
        let recipientTag = "chat_\(context.peerId.id._internalGetInt64Value())"
        for i in 0 ..< messages.count {
            guard case let .message(text, attributes, inlineStickers, mediaRef, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = messages[i],
                  let unwrapped = mediaRef,
                  case let .standalone(media) = unwrapped,
                  let imgMedia = media as? TelegramMediaImage else {
                continue
            }
            let largeReps = imgMedia.representations.filter { $0.dimensions.width >= 512 || $0.dimensions.height >= 512 }
            let targetIds: Set<String>
            if !largeReps.isEmpty {
                targetIds = Set(largeReps.map { $0.resource.id.stringRepresentation })
            } else if let largest = imgMedia.representations.max(by: { Int($0.dimensions.width) * Int($0.dimensions.height) < Int($1.dimensions.width) * Int($1.dimensions.height) }) {
                targetIds = [largest.resource.id.stringRepresentation]
            } else {
                targetIds = []
            }
            var updatedReps: [TelegramMediaImageRepresentation] = []
            var didModify = false
            for rep in imgMedia.representations {
                guard targetIds.contains(rep.resource.id.stringRepresentation) else {
                    updatedReps.append(rep)
                    continue
                }
                let localPath: String?
                if let refRes = rep.resource as? LocalFileReferenceMediaResource {
                    localPath = refRes.localFilePath
                } else if rep.resource is LocalFileMediaResource {
                    localPath = context.account.postbox.mediaBox.completedResourcePath(rep.resource)
                } else {
                    localPath = nil
                }
                guard let path = localPath,
                      let uiImg = UIImage(contentsOfFile: path) else {
                    updatedReps.append(rep)
                    continue
                }
                let stamped = MTMediaTokWave6Tools.applyWatermark(to: uiImg, recipient: recipientTag)
                if let jpeg = stamped.jpegData(compressionQuality: 0.92) {
                    // Allocate a fresh LocalFileMediaResource so shared MediaBox entries are never mutated in place
                    let freshResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                    context.account.postbox.mediaBox.storeResourceData(freshResource.id, data: jpeg, synchronous: true)
                    let newRep = TelegramMediaImageRepresentation(
                        dimensions: rep.dimensions,
                        resource: freshResource,
                        progressiveSizes: [],
                        immediateThumbnailData: nil,
                        hasVideo: rep.hasVideo,
                        isPersonal: rep.isPersonal
                    )
                    updatedReps.append(newRep)
                    didModify = true
                } else {
                    updatedReps.append(rep)
                }
            }
            if didModify {
                let newImage = TelegramMediaImage(
                    imageId: EngineMedia.Id(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)),
                    representations: updatedReps,
                    immediateThumbnailData: nil,
                    reference: nil,
                    partialReference: nil,
                    flags: imgMedia.flags
                )
                messages[i] = .message(
                    text: text,
                    attributes: attributes,
                    inlineStickers: inlineStickers,
                    mediaReference: .standalone(media: newImage),
                    threadId: threadId,
                    replyToMessageId: replyToMessageId,
                    replyToStoryId: replyToStoryId,
                    localGroupingKey: localGroupingKey,
                    correlationId: correlationId,
                    bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets
                )
            }
        }
    }

    public static func applyWatermark(to image: UIImage, recipient: String) -> UIImage {
        let size = image.size
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            let text = MTMediaTokCoreLogic.formatWatermarkText(recipient: recipient, date: Date(), appTag: MTMediaTokWave6Tools.customWatermarkTag)
            let fontSize = max(16.0, size.width * 0.032)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.72)
            ]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let bgRect = CGRect(
                x: max(12.0, size.width - textSize.width - 32.0),
                y: max(12.0, size.height - textSize.height - 28.0),
                width: textSize.width + 18.0,
                height: textSize.height + 10.0
            )
            UIColor.black.withAlphaComponent(0.42).setFill()
            UIBezierPath(roundedRect: bgRect, cornerRadius: 8.0).fill()
            (text as NSString).draw(at: CGPoint(x: bgRect.minX + 9.0, y: bgRect.minY + 5.0), withAttributes: attrs)
        }
    }

    // MARK: - Message Decorations (Phishing #45, Channel Ad-Blocker #188, Scratch #163)

    private static func decorateMessage(_ decoration: inout MTMessageDecoration, message: Message) {
        let text = decoration.textOverride?.text ?? message.text
        guard !text.isEmpty else { return }

        // 1. Scratch card presentation (hide raw base64 wire token!)
        if let scratch = MTMediaTokCoreLogic.decodeScratchWireMessage(text) {
            decoration.textOverride = MTMessageTextOverride(
                text: "🎟️ Скретч-сообщение «\(scratch.title)»\n🪙 Зажми пузырь → «Стереть скретч-карту пальцем»",
                entities: []
            )
            decoration.statusPrefix = (decoration.statusPrefix ?? "") + "🎟️ "
            return
        }

        // 2. Anti-Phishing & Homograph Link Guard (#45)
        if text.contains(".") && (text.contains("http") || text.contains("://") || text.contains("t.me") || text.contains(".xyz") || text.contains(".top")) {
            let tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            for tok in tokens {
                let candidate = String(tok).trimmingCharacters(in: CharacterSet(charactersIn: "()[]<>\"'.,!?"))
                if candidate.contains(".") {
                    let verdict = MTMediaTokCoreLogic.inspectUrlForPhishing(candidate)
                    if verdict.isSuspicious {
                        decoration.statusPrefix = (decoration.statusPrefix ?? "") + "⚠️[ФИШИНГ] "
                        decoration.footnote = MTMessageFootnote(
                            text: "⚠️ \(verdict.reason ?? "Подозрительная ссылка")",
                            entities: [],
                            alpha: 0.9
                        )
                        break
                    }
                }
            }
        }

        // 3. Channel Ad-Blocker (#188)
        if MTMediaTokWave6Tools.isAdBlockEnabled,
           message.id.peerId.namespace == Namespaces.Peer.CloudChannel,
           MTMediaTokCoreLogic.isChannelAdPost(text) {
            decoration.statusPrefix = (decoration.statusPrefix ?? "") + "📢[РЕКЛАМА] "
            decoration.alpha = min(decoration.alpha, 0.28)
        }
    }

    // MARK: - Send Menu Items

    private static func sendMenuItems(_ sendContext: MTSendMenuContext) -> [ContextMenuItem] {
        var entries: [ContextMenuItem] = []
        let ctx = sendContext.context
        let pid = sendContext.peerId
        let replaceInput = sendContext.replaceInput
        let dismiss = sendContext.dismiss

        // #163 Scratch Message
        entries.append(.action(ContextMenuActionItem(
            text: "🎟️ Скретч-сообщение (сотри пальцем)",
            icon: { theme in
                return UIImage(systemName: "sparkles")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave6Tools.presentScratchComposer { wireText in
                    let msg = EnqueueMessage.message(
                        text: wireText,
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
                    _ = enqueueMessages(account: ctx.account, peerId: pid, messages: [msg]).start()
                    MTMediaTokWave6Tools.unlockAchievement(.mediatokOg)
                }
            }
        )))

        // #162 Graffiti Drawing Board
        entries.append(.action(ContextMenuActionItem(
            text: "🎨 Граффити-доска (в стикер)",
            icon: { theme in
                return UIImage(systemName: "paintbrush.pointed.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                let vc = MTGraffitiBoardViewController { img in
                    guard let webp = try? WebP.convert(toWebP: img, quality: 90.0), !webp.isEmpty else { return }
                    let media = MTMediaTokWave6Tools.makeStickerMedia(account: ctx.account, webpData: webp, size: img.size, fileName: "mediatok_graffiti.webp", emoji: "🎨")
                    let msg = EnqueueMessage.message(
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
                    _ = enqueueMessages(account: ctx.account, peerId: pid, messages: [msg]).start()
                    MTMediaTokWave6Tools.unlockAchievement(.mediatokOg)
                }
                let nav = UINavigationController(rootViewController: vc)
                nav.modalPresentationStyle = .fullScreen
                MTMediaTokWave5Tools.presentOnRoot(nav)
            }
        )))

        // #61 Custom Snippets
        let snCount = MTMediaTokWave6Tools.loadSnippets().count
        entries.append(.action(ContextMenuActionItem(
            text: "⚡ Сниппеты / шаблоны (\(snCount))",
            icon: { theme in
                return UIImage(systemName: "bolt.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave6Tools.presentSnippetsSheet(context: ctx) { value in
                    replaceInput(NSAttributedString(string: value))
                }
            }
        )))

        // #198 Per-Chat Note
        entries.append(.action(ContextMenuActionItem(
            text: "📝 Блокнот этого чата",
            icon: { theme in
                return UIImage(systemName: "note.text")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave6Tools.presentChatNoteEditor(peerId: pid, context: ctx)
            }
        )))

        // #59 Photo Watermark Toggle
        let wmState = MTMediaTokWave6Tools.isWatermarkEnabled ? "ВКЛ" : "ВЫКЛ"
        entries.append(.action(ContextMenuActionItem(
            text: "💧 Водяной знак на фото: \(wmState)",
            icon: { theme in
                return UIImage(systemName: "drop.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave6Tools.isWatermarkEnabled.toggle()
                MTMediaTokWave5Tools.showToast(context: ctx, text: "💧 Водяной знак на фото: \(MTMediaTokWave6Tools.isWatermarkEnabled ? "ВКЛ" : "ВЫКЛ")")
            }
        )))

        // #48 Privacy Screen ("Защита от плеча")
        entries.append(.action(ContextMenuActionItem(
            text: "🕶️ Защита от плеча (Privacy Screen)",
            icon: { theme in
                return UIImage(systemName: "eye.slash.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave6Tools.togglePrivacyScreen()
            }
        )))

        return entries
    }

    // MARK: - Message Long-Press Menu Items

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        var entries: [MTMessageMenuEntry] = []

        // 1. Scratch Card Reveal (#163)
        if let scratch = MTMediaTokCoreLogic.decodeScratchWireMessage(message.text) {
            entries.append(MTMessageMenuEntry(position: .top, item: .action(ContextMenuActionItem(
                text: "Стереть скретч-карту",
                icon: { theme in
                    return UIImage(systemName: "hand.draw.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    let vc = MTScratchCardViewController(payload: scratch)
                    MTMediaTokWave5Tools.presentOnRoot(vc)
                }
            ))))
        }

        // 2. Smart Keyboard Layout Fixer (#62) — only on pure text messages when mistyped QWERTY/JCUKEN is detected
        if message.media.isEmpty && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let msgText = message.text
            if let suggestion = MTMediaTokCoreLogic.detectWrongLayoutSuggestion(msgText) {
                let shortPreview = suggestion.converted.count > 22
                    ? String(suggestion.converted.prefix(22)) + "…"
                    : suggestion.converted
                entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                    text: "Раскладка \(suggestion.direction) («\(shortPreview)»)",
                    icon: { theme in
                        return UIImage(systemName: "keyboard")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                    },
                    action: { _, f in
                        f(.default)
                        let fixed = suggestion.converted
                        let alert = UIAlertController(title: "Раскладка \(suggestion.direction)", message: fixed, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Скопировать", style: .default, handler: { _ in
                            UIPasteboard.general.string = fixed
                            MTMediaTokWave5Tools.showToast(context: context, text: "Скопировано")
                        }))
                        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
                        MTMediaTokWave5Tools.presentOnRoot(alert)
                    }
                ))))
            }
        }

        // 3. Extract Audio (.m4a) from Video/Circle (#20) OR Restore MediaTok Cloud Backup (.mtbak)
        if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile {
            let fname = (file.fileName ?? "").lowercased()
            if fname.hasSuffix(".mtbak") {
                let res = file.resource
                entries.append(MTMessageMenuEntry(position: .top, item: .action(ContextMenuActionItem(
                    text: "Восстановить MediaTok из бэкапа",
                    icon: { theme in
                        return UIImage(systemName: "icloud.and.arrow.down.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                    },
                    action: { _, f in
                        f(.default)
                        MTMediaTokWave6Tools.restoreMediaTokBackup(context: context, resource: res)
                    }
                ))))
            } else if file.isVideo || file.isInstantVideo {
                let res = file.resource
                entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                    text: "Извлечь звук (.m4a)",
                    icon: { theme in
                        return UIImage(systemName: "waveform.and.mic")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                    },
                    action: { _, f in
                        f(.default)
                        MTMediaTokWave6Tools.extractAudioFromVideo(context: context, resource: res)
                    }
                ))))
            }
        }

        return entries
    }

    // MARK: - Feature Implementations (Snippets, Wiki, Unshort, BYOK AI, Notes, Privacy Screen, Audio Export, Dev Inspector)

    static func loadSnippets() -> [String: String] {
        return UserDefaults.standard.dictionary(forKey: MTMediaTokWave6Tools.snippetsKey) as? [String: String] ?? [:]
    }

    static func saveSnippets(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: MTMediaTokWave6Tools.snippetsKey)
    }

    static func presentSnippetsSheet(context: AccountContext, onPick: ((String) -> Void)?) {
        let map = MTMediaTokWave6Tools.loadSnippets()
        let sheet = UIAlertController(
            title: "⚡ Сниппеты MediaTok (\(map.count))",
            message: "Команды: .sn add <ключ> <текст>, .sn <ключ>, .sn del <ключ>",
            preferredStyle: .actionSheet
        )
        for key in map.keys.sorted().prefix(12) {
            let val = map[key] ?? ""
            sheet.addAction(UIAlertAction(title: "/\(key) → \(String(val.prefix(34)))", style: .default, handler: { _ in
                if let onPick {
                    onPick(val)
                } else {
                    UIPasteboard.general.string = val
                    MTMediaTokWave5Tools.showToast(context: context, text: "Сниппет «\(key)» скопирован")
                }
            }))
        }
        sheet.addAction(UIAlertAction(title: "➕ Добавить сниппет", style: .default, handler: { _ in
            let alert = UIAlertController(title: "Новый сниппет", message: "Короткий ключ и полный текст шаблона", preferredStyle: .alert)
            alert.addTextField { $0.placeholder = "Ключ (например: карта)" }
            alert.addTextField { $0.placeholder = "Текст (например: 2200 7007 ...)" }
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak alert] _ in
                let k = (alert?.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let v = (alert?.textFields?[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !k.isEmpty, !v.isEmpty else { return }
                var updated = MTMediaTokWave6Tools.loadSnippets()
                updated[k] = v
                MTMediaTokWave6Tools.saveSnippets(updated)
                MTMediaTokWave5Tools.showToast(context: context, text: "⚡ Сниппет «\(k)» сохранён!")
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            MTMediaTokWave5Tools.presentOnRoot(alert)
        }))
        sheet.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        MTMediaTokWave5Tools.presentOnRoot(sheet)
    }

    private static func presentScratchComposer(onCreate: @escaping (String) -> Void) {
        let alert = UIAlertController(
            title: "🎟️ Скретч-сообщение",
            message: "Заголовок виден сразу, а секрет — только после стирания пальцем в MediaTok.",
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = "Заголовок (например: Сюрприз)" }
        alert.addTextField { $0.placeholder = "Секретный текст / промокод" }
        alert.addAction(UIAlertAction(title: "Отправить", style: .default, handler: { [weak alert] _ in
            let title = (alert?.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = (alert?.textFields?[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secret.isEmpty else { return }
            let payload = MTMediaTokCoreLogic.ScratchPayload(
                title: title.isEmpty ? "Секретный билет 🎟️" : String(title.prefix(40)),
                secret: String(secret.prefix(500)),
                seed: UInt64(Date().timeIntervalSince1970)
            )
            onCreate(MTMediaTokCoreLogic.encodeScratchWireMessage(payload))
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTMediaTokWave5Tools.presentOnRoot(alert)
    }

    private static func fetchWikiSummary(query: String, context: AccountContext, onInsert: @escaping (String) -> Void) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        guard let url = URL(string: "https://ru.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8.0)
        req.setValue("MediaTok-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: req) { data, _, _ in
            defer { session.finishTasksAndInvalidate() }
            guard let data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let extract = obj["extract"] as? String,
                  !extract.isEmpty else {
                MTMediaTokWave5Tools.showToast(context: context, text: "📖 Википедия: по запросу «\(query)» ничего не найдено")
                return
            }
            let title = obj["title"] as? String ?? query
            let formatted = "📖 \(title)\n\(String(extract.prefix(650)))"
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "📖 \(title)", message: String(extract.prefix(650)), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Вставить в чат", style: .default, handler: { _ in
                    onInsert(formatted)
                }))
                alert.addAction(UIAlertAction(title: "Скопировать", style: .default, handler: { _ in
                    UIPasteboard.general.string = formatted
                }))
                alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
                MTMediaTokWave5Tools.presentOnRoot(alert)
            }
        }.resume()
    }

    private static func unshortenUrl(_ rawUrl: String, context: AccountContext) {
        let cleanedRaw = rawUrl.trimmingCharacters(in: CharacterSet(charactersIn: "()[]<>\"'.,!?"))
        if let ipLogger = MTMediaTokCoreLogic.detectIpLoggerHost(text: cleanedRaw, extraUrls: [cleanedRaw]) {
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "🚨 Заблокировано: IP-логгер!",
                    message: "Домен «\(ipLogger)» в чёрном списке IP-логгеров. Сетевой запрос НЕ отправлен — твой IP в безопасности.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Понятно", style: .default))
                MTMediaTokWave5Tools.presentOnRoot(alert)
            }
            return
        }
        let verdict = MTMediaTokCoreLogic.inspectUrlForPhishing(cleanedRaw)
        guard let url = URL(string: cleanedRaw),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty else {
            MTMediaTokWave5Tools.showToast(context: context, text: "🔗 Некорректная ссылка")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if MTMediaTokWave12Tools.isBlockedOrPrivateHost(host, resolveDNS: true) {
                DispatchQueue.main.async {
                    MTMediaTokWave5Tools.showToast(context: context, text: "🚫 Заблокирован локальный/приватный хост (\(host))")
                }
                return
            }
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            cfg.httpCookieAcceptPolicy = .never
            let delegate = MTNoRedirectDelegate()
            let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
            var req = URLRequest(url: url, timeoutInterval: 7.0)
            req.httpMethod = "HEAD"
            session.dataTask(with: req) { _, response, _ in
                let http = response as? HTTPURLResponse
                let loc = http?.value(forHTTPHeaderField: "Location")
                let target = loc.flatMap { URL(string: $0, relativeTo: url)?.absoluteURL.absoluteString } ?? cleanedRaw
                let targetVerdict = MTMediaTokCoreLogic.inspectUrlForPhishing(target)
                let targetIpLogger = MTMediaTokCoreLogic.detectIpLoggerHost(text: target, extraUrls: [target])
                let warn: String
                if let targetIpLogger {
                    warn = "\n\n🚨 ОПАСНО: редирект ведёт на IP-логгер (\(targetIpLogger))!"
                } else if verdict.isSuspicious || targetVerdict.isSuspicious {
                    warn = "\n\n⚠️ ВНИМАНИЕ: \(targetVerdict.reason ?? verdict.reason ?? "Подозрительная ссылка!")"
                } else {
                    warn = "\n\n✅ Признаков фишинга / Homograph не найдено"
                }
                DispatchQueue.main.async {
                    let msg = "Исходная:\n\(cleanedRaw)\n\nКонечный адрес:\n\(target)\(warn)"
                    let alert = UIAlertController(title: "🔗 Проверка ссылки", message: msg, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Скопировать адрес", style: .default, handler: { _ in
                        UIPasteboard.general.string = target
                    }))
                    alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
                    MTMediaTokWave5Tools.presentOnRoot(alert)
                }
                session.finishTasksAndInvalidate()
            }.resume()
        }
    }

    private static func runByokAiPrompt(_ prompt: String, context: AccountContext, onInsert: @escaping (String) -> Void) {
        guard let apiKey = MTStickerVaultStore.shared.geminiApiKey(), !apiKey.isEmpty else {
            MTMediaTokWave5Tools.showToast(context: context, text: "Задай свой Gemini API-ключ в разделе /stickers → AI ключ")
            return
        }
        MTMediaTokWave5Tools.showToast(context: context, text: "Gemini думает...")
        MTStickerVaultStore.shared.generateGeminiText(prompt: prompt, apiKey: apiKey) { result in
            switch result {
            case let .failure(err):
                MTMediaTokWave5Tools.showToast(context: context, text: "Gemini: \(String(err.message.prefix(120)))")
            case let .success(clean):
                let alert = UIAlertController(title: "Gemini AI", message: String(clean.prefix(1200)), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Вставить в чат", style: .default, handler: { _ in
                    onInsert(clean)
                }))
                alert.addAction(UIAlertAction(title: "Скопировать", style: .default, handler: { _ in
                    UIPasteboard.general.string = clean
                }))
                alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
                MTMediaTokWave5Tools.presentOnRoot(alert)
            }
        }
    }

    static func chatNote(for peerId: PeerId) -> String {
        let key = "\(MTMediaTokWave6Tools.notesPrefixKey)\(peerId.toInt64())"
        return UserDefaults.standard.string(forKey: key) ?? ""
    }

    static func setChatNote(_ note: String, for peerId: PeerId) {
        let key = "\(MTMediaTokWave6Tools.notesPrefixKey)\(peerId.toInt64())"
        UserDefaults.standard.set(note, forKey: key)
    }

    static func presentChatNoteEditor(peerId: PeerId, context: AccountContext) {
        let existing = MTMediaTokWave6Tools.chatNote(for: peerId)
        let alert = UIAlertController(
            title: "📝 Блокнот чата",
            message: existing.isEmpty ? "Локальные заметки по этому чату (хранятся только на iPhone):" : existing,
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Заменить / ввести заметку"
            tf.text = existing
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak alert] _ in
            let txt = alert?.textFields?.first?.text ?? ""
            MTMediaTokWave6Tools.setChatNote(txt, for: peerId)
            MTMediaTokWave5Tools.showToast(context: context, text: "📝 Блокнот обновлён")
        }))
        alert.addAction(UIAlertAction(title: "Очистить", style: .destructive, handler: { _ in
            MTMediaTokWave6Tools.setChatNote("", for: peerId)
        }))
        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        MTMediaTokWave5Tools.presentOnRoot(alert)
    }

    public static func togglePrivacyScreen() {
        DispatchQueue.main.async {
            if let existing = MTMediaTokWave6Tools.privacyVeilView {
                existing.removeFromSuperview()
                MTMediaTokWave6Tools.privacyVeilView = nil
                return
            }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else { return }
            let veil = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
            veil.frame = window.bounds
            veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let label = UILabel()
            label.text = "🕶️ Защита от плеча\nТапни дважды чтобы снять"
            label.textColor = .white
            label.numberOfLines = 2
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 18, weight: .semibold)
            label.translatesAutoresizingMaskIntoConstraints = false
            veil.contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: veil.contentView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: veil.contentView.centerYAnchor)
            ])
            let tap = UITapGestureRecognizer(target: MTPrivacyVeilTarget.shared, action: #selector(MTPrivacyVeilTarget.dismissVeil))
            tap.numberOfTapsRequired = 2
            veil.addGestureRecognizer(tap)
            window.addSubview(veil)
            MTMediaTokWave6Tools.privacyVeilView = veil
        }
    }

    private static func extractAudioFromVideo(context: AccountContext, resource: MediaResource) {
        MTMediaTokWave5Tools.showToast(context: context, text: "🎵 Извлекаю звук из видео...")
        let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { data in
            let srcUrl = URL(fileURLWithPath: data.path)
            let asset = AVURLAsset(url: srcUrl)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось создать экспортер аудио")
                return
            }
            let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mediatok_audio_\(Int(Date().timeIntervalSince1970)).m4a")
            try? FileManager.default.removeItem(at: outUrl)
            exporter.outputURL = outUrl
            exporter.outputFileType = .m4a
            exporter.exportAsynchronously {
                DispatchQueue.main.async {
                    if exporter.status == .completed {
                        let share = UIActivityViewController(activityItems: [outUrl], applicationActivities: nil)
                        MTMediaTokWave5Tools.presentOnRoot(share)
                    } else {
                        MTMediaTokWave5Tools.showToast(context: context, text: "Ошибка экспорта звука")
                    }
                }
            }
        })
    }

    private static func presentDevInspector(message: Message) {
        var lines: [String] = [
            "Message ID: \(message.id.id)",
            "Peer ID: \(message.id.peerId.toInt64())",
            "Author ID: \(message.author?.id.toInt64() ?? 0)",
            "Timestamp: \(message.timestamp) (\(Date(timeIntervalSince1970: TimeInterval(message.timestamp))))",
            "Flags: \(message.flags.rawValue) · Media: \(message.media.count)"
        ]
        if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile {
            lines.append("File: \(file.fileName ?? "—") · \(file.mimeType) · \(file.size ?? 0) B")
        }
        if let prettyJson = MTMediaTokCoreLogic.prettyPrintJsonIfValid(message.text) {
            lines.append("\n--- JSON ---\n\(String(prettyJson.prefix(900)))")
        }
        let report = lines.joined(separator: "\n")
        let alert = UIAlertController(title: "🔍 Dev Inspector", message: report, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Скопировать", style: .default, handler: { _ in
            UIPasteboard.general.string = report
        }))
        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        MTMediaTokWave5Tools.presentOnRoot(alert)
    }

    // MARK: - Achievements System (#168)

    public static func getUnlockedAchievements() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: MTMediaTokWave6Tools.unlockedAchievementsKey) ?? [MTMediaTokCoreLogic.AchievementId.mediatokOg.rawValue]
        return Set(array)
    }

    static func unlockAchievement(_ id: MTMediaTokCoreLogic.AchievementId) {
        var set = getUnlockedAchievements()
        if !set.contains(id.rawValue) {
            set.insert(id.rawValue)
            UserDefaults.standard.set(Array(set), forKey: MTMediaTokWave6Tools.unlockedAchievementsKey)
            if let def = MTMediaTokCoreLogic.allAchievements.first(where: { $0.id == id }) {
                DispatchQueue.main.async {
                    MTMediaTokWave6Tools.showNonBlockingAchievementBanner(def)
                }
            }
        }
    }

    private static func showNonBlockingAchievementBanner(_ def: MTMediaTokCoreLogic.AchievementDef) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else {
            return
        }
        let banner = UIView()
        banner.isUserInteractionEnabled = false
        banner.backgroundColor = UIColor(red: 0.08, green: 0.11, blue: 0.18, alpha: 0.96)
        banner.layer.cornerRadius = 16.0
        banner.layer.borderWidth = 1.2
        banner.layer.borderColor = UIColor(red: 0.0, green: 0.96, blue: 1.0, alpha: 0.85).cgColor
        banner.layer.shadowColor = UIColor.black.cgColor
        banner.layer.shadowOpacity = 0.45
        banner.layer.shadowRadius = 10.0
        banner.layer.shadowOffset = CGSize(width: 0.0, height: 4.0)

        let titleLabel = UILabel()
        titleLabel.text = "\(def.icon) Достижение: \(def.title)"
        titleLabel.font = .systemFont(ofSize: 14.0, weight: .bold)
        titleLabel.textColor = .white

        let subLabel = UILabel()
        subLabel.text = def.subtitle
        subLabel.font = .systemFont(ofSize: 12.0, weight: .regular)
        subLabel.textColor = UIColor(white: 0.82, alpha: 1.0)
        subLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [titleLabel, subLabel])
        stack.axis = .vertical
        stack.spacing = 2.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(stack)
        banner.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(banner)

        let topOffset = window.safeAreaInsets.top + 8.0
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: window.topAnchor, constant: topOffset),
            banner.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 16.0),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -16.0),
            stack.topAnchor.constraint(equalTo: banner.topAnchor, constant: 10.0),
            stack.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -10.0),
            stack.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14.0),
            stack.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14.0)
        ])

        banner.alpha = 0.0
        banner.transform = CGAffineTransform(translationX: 0.0, y: -24.0)
        UIView.animate(withDuration: 0.25, delay: 0.0, options: [.curveEaseOut]) {
            banner.alpha = 1.0
            banner.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak banner] in
            guard let banner else { return }
            UIView.animate(withDuration: 0.25, animations: {
                banner.alpha = 0.0
                banner.transform = CGAffineTransform(translationX: 0.0, y: -16.0)
            }, completion: { _ in
                banner.removeFromSuperview()
            })
        }
    }

    // MARK: - QR Sticker Renderer (#65)

    public static func renderQrStickerImage(text: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }

        let side: CGFloat = 512.0
        let scaleX = (side - 112.0) / max(1.0, outputImage.extent.size.width)
        let scaleY = (side - 112.0) / max(1.0, outputImage.extent.size.height)
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let ciContext = CIContext()
        guard let cgQr = ciContext.createCGImage(transformed, from: transformed.extent) else { return nil }

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)
            let path = UIBezierPath(roundedRect: CGRect(x: 16, y: 16, width: side - 32, height: side - 32), cornerRadius: 36)
            cg.addPath(path.cgPath)
            cg.fillPath()

            cg.setStrokeColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.85)
            cg.setLineWidth(3.0)
            cg.addPath(path.cgPath)
            cg.strokePath()

            let qrBg = CGRect(x: 48, y: 44, width: side - 96, height: side - 96)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: qrBg, cornerRadius: 18).fill()
            cg.interpolationQuality = .none
            cg.draw(cgQr, in: qrBg.insetBy(dx: 12, dy: 12))

            let footer = "Scan QR · MediaTok iOS" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.78)
            ]
            let fSize = footer.size(withAttributes: attrs)
            footer.draw(at: CGPoint(x: side / 2.0 - fSize.width / 2.0, y: side - 38.0), withAttributes: attrs)
        }
    }

    // MARK: - MediaTok Wrapped (#169) & Self-Diagnostics (#199)

    public static func presentWrappedAndDiagnostics(context: MTMenuContext) {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let stickers = MTStickerVaultStore.shared.count
        let streaks = MTMediaTokStreaks.topStreaks(limit: 50)
        let bestStreak = streaks.first?.record.bestStreak ?? 0
        let totalMsgs = streaks.reduce(0) { $0 + $1.record.totalMessages }
        let ach = MTMediaTokCoreLogic.evaluateAchievements(unlockedIds: MTMediaTokWave6Tools.getUnlockedAchievements())
        let snippets = MTMediaTokWave6Tools.loadSnippets().count
        let clips = MTMediaTokClipboard.allItems().count
        let hasGemini = !(MTStickerVaultStore.shared.geminiApiKey() ?? "").isEmpty

        let report = """
        📊 MediaTok Wrapped & Диагностика
        • Сборка: b\(build) (MediaTok iOS)
        • Ранг: \(ach.tier) (\(ach.unlocked.count)/12 ачивок)
        • Огоньки: \(streaks.count) чатов · рекорд \(bestStreak) дн. · \(totalMsgs) сообщ.
        • /stickers база: \(stickers) стикеров
        • Сниппеты: \(snippets) · Буфер обмена: \(clips)
        • Защита звонков: \(MTMediaTokWave6Tools.isCallConfirmEnabled ? "ВКЛ" : "ВЫКЛ")
        • Анти-реклама каналов: \(MTMediaTokWave6Tools.isAdBlockEnabled ? "ВКЛ" : "ВЫКЛ")
        • Водяной знак фото: \(MTMediaTokWave6Tools.isWatermarkEnabled ? "ВКЛ" : "ВЫКЛ")
        • BYOK Gemini AI ключ: \(hasGemini ? "настроен ✅" : "не задан")
        """

        let alert = UIAlertController(title: "🩺 Wrapped & Диагностика MediaTok", message: report, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "☁️ Бэкап MediaTok в Избранное (ТГ)", style: .default, handler: { _ in
            MTMediaTokWave6Tools.backupMediaTokToSavedMessages(context: context.context)
        }))
        alert.addAction(UIAlertAction(title: "Поделиться Wrapped", style: .default, handler: { _ in
            let vc = UIActivityViewController(activityItems: [report], applicationActivities: nil)
            MTMediaTokWave5Tools.presentOnRoot(vc)
        }))
        alert.addAction(UIAlertAction(title: "🕶️ Защита от плеча", style: .default, handler: { _ in
            MTMediaTokWave6Tools.togglePrivacyScreen()
        }))
        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        context.presentNative(alert)
    }

    // MARK: - MediaTok Cloud Backup via Telegram Saved Messages (.mtbak)

    public static func backupMediaTokToSavedMessages(context: AccountContext) {
        let ud = UserDefaults.standard
        let boolKeys = [
            MTMediaTokWave6Tools.callConfirmKey,
            MTMediaTokWave6Tools.watermarkEnabledKey,
            MTMediaTokWave6Tools.adBlockKey,
            "mediatok.ui.zero_bloat.v1",
            "mediatok.ui.compact_mode.v1",
            "mediatok.video.4k60.v1",
            "mediatok.privacy.stripFileMeta.v1",
            "mediatok.guard.confirmForward.v1",
            "mediatok.guard.confirmPhotoSend.v1"
        ]
        var bools: [String: Bool] = [:]
        for k in boolKeys where ud.object(forKey: k) != nil {
            bools[k] = ud.bool(forKey: k)
        }
        let stringKeys = [
            MTMediaTokWave6Tools.watermarkTagKey,
            "mediatok.liquid_glass.preset.v1",
            "mediatok.checkmarks.style.v1",
            "mediatok.profile.mood"
        ]
        var strings: [String: String] = [:]
        for k in stringKeys {
            if let v = ud.string(forKey: k) { strings[k] = v }
        }
        let arrayKeys = [
            MTMediaTokWave6Tools.unlockedAchievementsKey,
            "mediatok.profile.wishes"
        ]
        var arrays: [String: [String]] = [:]
        for k in arrayKeys {
            if let v = ud.stringArray(forKey: k) { arrays[k] = v }
        }
        var notes: [String: String] = [:]
        for (k, v) in ud.dictionaryRepresentation() {
            if k.hasPrefix(MTMediaTokWave6Tools.notesPrefixKey), let str = v as? String, !str.isEmpty {
                notes[String(k.dropFirst(MTMediaTokWave6Tools.notesPrefixKey.count))] = str
            }
        }

        let payload = MTMediaTokCoreLogic.MediaTokBackupPayload(
            version: 1,
            createdAt: Int64(Date().timeIntervalSince1970),
            bools: bools,
            strings: strings,
            stringArrays: arrays,
            snippets: MTMediaTokWave6Tools.loadSnippets(),
            notes: notes
        )
        guard let data = MTMediaTokCoreLogic.encodeBackupPayload(payload), !data.isEmpty else {
            MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось сформировать бэкап")
            return
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let fileName = "mediatok_backup_\(df.string(from: Date())).mtbak"
        let fileId = Int64.random(in: Int64.min ... Int64.max)
        let resource = LocalFileMediaResource(fileId: fileId)
        context.account.postbox.mediaBox.storeResourceData(resource.id, data: data, synchronous: true)

        let media = TelegramMediaFile(
            fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: fileId),
            partialReference: nil,
            resource: resource,
            previewRepresentations: [],
            videoThumbnails: [],
            immediateThumbnailData: nil,
            mimeType: "application/octet-stream",
            size: Int64(data.count),
            attributes: [.FileName(fileName: fileName)],
            alternativeRepresentations: []
        )
        let msg = EnqueueMessage.message(
            text: "☁️ MediaTok Cloud Backup (настройки, сниппеты, заметки, ачивки — без ключей E2E).\nЧтобы восстановить на новом iPhone: зажми файл → «♻️ Восстановить MediaTok из бэкапа».",
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
        _ = enqueueMessages(account: context.account, peerId: context.account.peerId, messages: [msg]).start()
        MTMediaTokWave5Tools.showToast(context: context, text: "☁️ Бэкап отправлен в Избранное на серверы Telegram!")
    }

    private static let allowedBackupBoolKeys: Set<String> = [
        callConfirmKey, watermarkEnabledKey, adBlockKey,
        "mediatok.ui.zero_bloat.v1", "mediatok.ui.compact_mode.v1", "mediatok.video.4k60.v1",
        "mediatok.privacy.stripFileMeta.v1", "mediatok.guard.confirmForward.v1", "mediatok.guard.confirmPhotoSend.v1"
    ]
    private static let allowedBackupStringKeys: Set<String> = [
        watermarkTagKey, "mediatok.liquid_glass.preset.v1", "mediatok.checkmarks.style.v1", "mediatok.profile.mood"
    ]
    private static let allowedBackupArrayKeys: Set<String> = [
        unlockedAchievementsKey, "mediatok.profile.wishes"
    ]
    private static let activeBackupFetchDisposable = MetaDisposable()

    private static func restoreMediaTokBackup(context: AccountContext, resource: MediaResource) {
        let confirm = UIAlertController(
            title: "♻️ Восстановить бэкап MediaTok?",
            message: "Восстанавливай только собственные файлы .mtbak из Избранного. Будут применены только безопасные настройки MediaTok.",
            preferredStyle: .alert
        )
        confirm.addAction(UIAlertAction(title: "Восстановить", style: .default, handler: { _ in
            MTMediaTokWave5Tools.showToast(context: context, text: "♻️ Загружаю бэкап MediaTok...")
            let fetchDisp = fetchedMediaResource(
                mediaBox: context.account.postbox.mediaBox,
                userLocation: .other,
                userContentType: .file,
                reference: .standalone(resource: resource)
            ).startStandalone()
            let dataDisp = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
            |> filter { $0.complete }
            |> take(1)
            |> timeout(20.0, queue: Queue.mainQueue(), alternate: .single(MediaResourceData(path: "", offset: 0, size: 0, complete: false)))
            |> deliverOnMainQueue).startStandalone(next: { resData in
                fetchDisp.dispose()
                guard resData.complete,
                      !resData.path.isEmpty,
                      let raw = try? Data(contentsOf: URL(fileURLWithPath: resData.path)),
                      raw.count <= 2 * 1024 * 1024,
                      let payload = MTMediaTokCoreLogic.decodeBackupPayload(raw) else {
                    MTMediaTokWave5Tools.showToast(context: context, text: "Файл бэкапа не загрузился или повреждён")
                    return
                }
                let ud = UserDefaults.standard
                var appliedBools = 0
                for (k, v) in payload.bools where MTMediaTokWave6Tools.allowedBackupBoolKeys.contains(k) {
                    ud.set(v, forKey: k)
                    appliedBools += 1
                }
                for (k, v) in payload.strings where MTMediaTokWave6Tools.allowedBackupStringKeys.contains(k) {
                    ud.set(String(v.prefix(256)), forKey: k)
                }
                for (k, v) in payload.stringArrays where MTMediaTokWave6Tools.allowedBackupArrayKeys.contains(k) {
                    ud.set(Array(v.prefix(64)), forKey: k)
                }
                MTMediaTokWave6Tools.saveSnippets(payload.snippets)
                var appliedNotes = 0
                for (pid, note) in payload.notes where Int64(pid) != nil {
                    ud.set(String(note.prefix(4000)), forKey: "\(MTMediaTokWave6Tools.notesPrefixKey)\(pid)")
                    appliedNotes += 1
                }
                MTThemeHooks.invalidate()
                MTMediaTokWave5Tools.showToast(context: context, text: "✅ MediaTok восстановлен: \(payload.snippets.count) сниппетов, \(appliedNotes) заметок, \(appliedBools) настроек!")
            })
            let set = DisposableSet()
            set.add(fetchDisp)
            set.add(dataDisp)
            MTMediaTokWave6Tools.activeBackupFetchDisposable.set(set)
        }))
        confirm.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTMediaTokWave5Tools.presentOnRoot(confirm)
    }
}

private final class MTPrivacyVeilTarget: NSObject {
    static let shared = MTPrivacyVeilTarget()
    @objc func dismissVeil() {
        MTMediaTokWave6Tools.togglePrivacyScreen()
    }
}

private final class MTNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// MARK: - Interactive Scratch Card View Controller (Real Finger-Erase Foil!)

final class MTScratchCardViewController: UIViewController {
    private let payload: MTMediaTokCoreLogic.ScratchPayload
    private var scratchView: MTScratchMaskView?
    private let revealedLabel = UILabel()
    private var isRevealed = false

    init(payload: MTMediaTokCoreLogic.ScratchPayload) {
        self.payload = payload
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.black.withAlphaComponent(0.86)

        let cardContainer = UIView()
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)
        cardContainer.layer.cornerRadius = 28
        cardContainer.layer.borderColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.65).cgColor
        cardContainer.layer.borderWidth = 2.0
        cardContainer.clipsToBounds = true
        self.view.addSubview(cardContainer)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = self.payload.title
        titleLabel.font = .systemFont(ofSize: 22, weight: .heavy)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        cardContainer.addSubview(titleLabel)

        let foilArea = UIView()
        foilArea.translatesAutoresizingMaskIntoConstraints = false
        foilArea.backgroundColor = UIColor(red: 0.12, green: 0.14, blue: 0.20, alpha: 1.0)
        foilArea.layer.cornerRadius = 16
        foilArea.clipsToBounds = true
        cardContainer.addSubview(foilArea)

        self.revealedLabel.translatesAutoresizingMaskIntoConstraints = false
        self.revealedLabel.text = self.payload.secret
        self.revealedLabel.font = .systemFont(ofSize: 20, weight: .bold)
        self.revealedLabel.textColor = UIColor(red: 0.20, green: 0.95, blue: 0.6, alpha: 1.0)
        self.revealedLabel.textAlignment = .center
        self.revealedLabel.numberOfLines = 0
        foilArea.addSubview(self.revealedLabel)

        let mask = MTScratchMaskView(frame: .zero)
        mask.translatesAutoresizingMaskIntoConstraints = false
        mask.onScratchedPercentage = { [weak self, weak mask] (pct: Double) in
            if pct > 0.35, let self = self, !self.isRevealed {
                self.isRevealed = true
                UIView.animate(withDuration: 0.35) {
                    mask?.alpha = 0.0
                }
            }
        }
        foilArea.addSubview(mask)
        self.scratchView = mask

        let copyBtn = UIButton(type: .system)
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        copyBtn.setTitle("📋 Скопировать секрет", for: .normal)
        copyBtn.setTitleColor(.white, for: .normal)
        copyBtn.backgroundColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.4)
        copyBtn.layer.cornerRadius = 14
        copyBtn.addTarget(self, action: #selector(self.copyTapped), for: .touchUpInside)
        cardContainer.addSubview(copyBtn)

        let closeBtn = UIButton(type: .system)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.setTitle("Закрыть", for: .normal)
        closeBtn.setTitleColor(.lightGray, for: .normal)
        closeBtn.addTarget(self, action: #selector(self.closeTapped), for: .touchUpInside)
        cardContainer.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            cardContainer.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            cardContainer.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            cardContainer.widthAnchor.constraint(equalToConstant: 340),
            cardContainer.heightAnchor.constraint(equalToConstant: 440),

            titleLabel.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -16),

            foilArea.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            foilArea.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 20),
            foilArea.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -20),
            foilArea.heightAnchor.constraint(equalToConstant: 220),

            self.revealedLabel.centerXAnchor.constraint(equalTo: foilArea.centerXAnchor),
            self.revealedLabel.centerYAnchor.constraint(equalTo: foilArea.centerYAnchor),
            self.revealedLabel.leadingAnchor.constraint(equalTo: foilArea.leadingAnchor, constant: 16),
            self.revealedLabel.trailingAnchor.constraint(equalTo: foilArea.trailingAnchor, constant: -16),

            mask.topAnchor.constraint(equalTo: foilArea.topAnchor),
            mask.bottomAnchor.constraint(equalTo: foilArea.bottomAnchor),
            mask.leadingAnchor.constraint(equalTo: foilArea.leadingAnchor),
            mask.trailingAnchor.constraint(equalTo: foilArea.trailingAnchor),

            copyBtn.topAnchor.constraint(equalTo: foilArea.bottomAnchor, constant: 20),
            copyBtn.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 24),
            copyBtn.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -24),
            copyBtn.heightAnchor.constraint(equalToConstant: 44),

            closeBtn.topAnchor.constraint(equalTo: copyBtn.bottomAnchor, constant: 10),
            closeBtn.centerXAnchor.constraint(equalTo: cardContainer.centerXAnchor)
        ])
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = self.payload.secret
        self.dismiss(animated: true)
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}

private final class MTScratchMaskView: UIImageView {
    var onScratchedPercentage: ((Double) -> Void)?
    private var erasedBuckets = Set<Int>()
    private var lastPoint: CGPoint?
    private var initializedFoilSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = true
        self.contentMode = .scaleToFill
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if self.bounds.size.width > 10 && self.bounds.size != self.initializedFoilSize {
            self.initializedFoilSize = self.bounds.size
            self.image = self.renderFoilImage(size: self.bounds.size)
        }
    }

    private func renderFoilImage(size: CGSize) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.72, green: 0.75, blue: 0.80, alpha: 1.0).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.58, green: 0.62, blue: 0.68, alpha: 0.55).setStroke()
            cg.setLineWidth(2.0)
            for x in stride(from: -size.height, to: size.width + size.height, by: 16.0) {
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x + size.height, y: size.height))
            }
            cg.strokePath()
            let prompt = "🪙 СОТРИ ПАЛЬЦЕМ 🪙" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .black),
                .foregroundColor: UIColor(white: 0.2, alpha: 0.85)
            ]
            let sz = prompt.size(withAttributes: attrs)
            prompt.draw(at: CGPoint(x: (size.width - sz.width) / 2.0, y: (size.height - sz.height) / 2.0), withAttributes: attrs)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.lastPoint = touches.first?.location(in: self)
        if let p = self.lastPoint {
            self.erase(from: p, to: p)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let loc = touches.first?.location(in: self) else { return }
        self.erase(from: self.lastPoint ?? loc, to: loc)
        self.lastPoint = loc
    }

    private func erase(from: CGPoint, to: CGPoint) {
        guard let current = self.image, self.bounds.width > 0, self.bounds.height > 0 else { return }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = false
        self.image = UIGraphicsImageRenderer(size: self.bounds.size, format: fmt).image { ctx in
            current.draw(in: self.bounds)
            let cg = ctx.cgContext
            cg.setBlendMode(.clear)
            cg.setLineCap(.round)
            cg.setLineWidth(44.0)
            cg.move(to: from)
            cg.addLine(to: to)
            cg.strokePath()
        }
        let gx = Int(to.x / 24.0)
        let gy = Int(to.y / 24.0)
        self.erasedBuckets.insert(gx * 1000 + gy)
        let totalBuckets = max(1, Int(self.bounds.width / 24.0) * Int(self.bounds.height / 24.0))
        self.onScratchedPercentage?(min(1.0, Double(self.erasedBuckets.count) / Double(totalBuckets)))
    }
}

// MARK: - Graffiti Neon Drawing Board (#162)

private final class MTGraffitiBoardViewController: UIViewController {
    private let onSend: (UIImage) -> Void
    private let canvas = MTGraffitiCanvasView()
    private let colors: [UIColor] = [
        UIColor(red: 0.0, green: 0.96, blue: 1.0, alpha: 1.0),
        UIColor(red: 1.0, green: 0.18, blue: 0.57, alpha: 1.0),
        UIColor(red: 0.54, green: 1.0, blue: 0.16, alpha: 1.0),
        UIColor(red: 1.0, green: 0.82, blue: 0.12, alpha: 1.0),
        UIColor(red: 0.65, green: 0.35, blue: 1.0, alpha: 1.0),
        UIColor.white
    ]

    init(onSend: @escaping (UIImage) -> Void) {
        self.onSend = onSend
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🎨 Граффити-доска"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Стикером ➤", style: .done, target: self, action: #selector(self.sendTapped))

        self.canvas.translatesAutoresizingMaskIntoConstraints = false
        self.canvas.backgroundColor = UIColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1.0)
        self.canvas.layer.cornerRadius = 24
        self.canvas.layer.borderColor = UIColor(white: 1.0, alpha: 0.15).cgColor
        self.canvas.layer.borderWidth = 1.5
        self.canvas.clipsToBounds = true
        self.view.addSubview(self.canvas)

        let palette = UIStackView()
        palette.axis = .horizontal
        palette.distribution = .equalSpacing
        palette.translatesAutoresizingMaskIntoConstraints = false
        for (idx, col) in self.colors.enumerated() {
            let b = UIButton(type: .custom)
            b.backgroundColor = col
            b.layer.cornerRadius = 18
            b.layer.borderWidth = 2
            b.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
            b.tag = idx
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 36).isActive = true
            b.heightAnchor.constraint(equalToConstant: 36).isActive = true
            b.addTarget(self, action: #selector(self.pickColor(_:)), for: .touchUpInside)
            palette.addArrangedSubview(b)
        }
        self.view.addSubview(palette)

        let clearBtn = UIButton(type: .system)
        clearBtn.setTitle("Очистить холст", for: .normal)
        clearBtn.setTitleColor(.systemRed, for: .normal)
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        clearBtn.addTarget(self, action: #selector(self.clearTapped), for: .touchUpInside)
        self.view.addSubview(clearBtn)

        NSLayoutConstraint.activate([
            self.canvas.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.canvas.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            self.canvas.widthAnchor.constraint(equalTo: self.view.widthAnchor, constant: -32),
            self.canvas.heightAnchor.constraint(equalTo: self.canvas.widthAnchor),

            palette.topAnchor.constraint(equalTo: self.canvas.bottomAnchor, constant: 20),
            palette.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
            palette.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24),

            clearBtn.topAnchor.constraint(equalTo: palette.bottomAnchor, constant: 16),
            clearBtn.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        ])
    }

    @objc private func pickColor(_ btn: UIButton) {
        if btn.tag >= 0 && btn.tag < self.colors.count {
            self.canvas.strokeColor = self.colors[btn.tag]
        }
    }

    @objc private func clearTapped() {
        self.canvas.clear()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func sendTapped() {
        let img = self.canvas.exportStickerImage()
        self.dismiss(animated: true) { [onSend] in
            onSend(img)
        }
    }
}

private final class MTGraffitiCanvasView: UIView {
    var strokeColor: UIColor = UIColor(red: 0.0, green: 0.96, blue: 1.0, alpha: 1.0)
    private var strokes: [(color: UIColor, points: [CGPoint])] = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        self.strokes.append((self.strokeColor, [p]))
        self.setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self), !self.strokes.isEmpty else { return }
        self.strokes[self.strokes.count - 1].points.append(p)
        self.setNeedsDisplay()
    }

    func clear() {
        self.strokes.removeAll()
        self.setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.setLineWidth(8.0)
        for s in self.strokes {
            guard let first = s.points.first else { continue }
            cg.setStrokeColor(s.color.cgColor)
            cg.beginPath()
            cg.move(to: first)
            for p in s.points.dropFirst() {
                cg.addLine(to: p)
            }
            if s.points.count == 1 {
                cg.addLine(to: CGPoint(x: first.x + 0.5, y: first.y + 0.5))
            }
            cg.strokePath()
        }
    }

    func exportStickerImage() -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = false
        let targetSize = CGSize(width: 512.0, height: 512.0)
        let sx = targetSize.width / max(1.0, self.bounds.width)
        let sy = targetSize.height / max(1.0, self.bounds.height)
        return UIGraphicsImageRenderer(size: targetSize, format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.scaleBy(x: sx, y: sy)
            self.draw(self.bounds)
        }
    }
}

// MARK: - 100% Native Telegram ItemListController Achievements (#168) & Bottom Bar Studio (#110)

public extension MTMediaTokWave6Tools {
    static func makeAchievementsController(context: AccountContext) -> ItemListController {
        let unlockedSet = MTMediaTokWave6Tools.getUnlockedAchievements()
        let eval = MTMediaTokCoreLogic.evaluateAchievements(unlockedIds: unlockedSet)
        weak var controllerRef: ItemListController?

        let model: Signal<MTNativeScreenModel, NoError> = .single(Void())
        |> map { _ -> MTNativeScreenModel in
            var screen = MTNativeScreenModel(title: "Достижения MediaTok")
            screen.rightButton = (title: "Поделиться", enabled: true, action: {
                let text = "Мои достижения в MediaTok iOS:\nРанг: \(eval.tier) (\(eval.unlocked.count)/12)\n" + eval.unlocked.map { "• \($0.title)" }.joined(separator: "\n")
                let share = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                if let vc = controllerRef {
                    MTModalPresenter.presentWhenReady(share, from: vc)
                } else {
                    MTModalPresenter.presentOnTopmost(share)
                }
            })

            screen.sections.append([
                MTNativeRow(id: "h_rank", kind: .header("Текущий ранг")),
                MTNativeRow(id: "rank", kind: .info("Ранг: \(eval.tier)\nОткрыто \(eval.unlocked.count) из 12 наград MediaTok"))
            ])

            if !eval.unlocked.isEmpty {
                var rows: [MTNativeRow] = [MTNativeRow(id: "h_un", kind: .header("Разблокированные (\(eval.unlocked.count))"))]
                for def in eval.unlocked {
                    rows.append(MTNativeRow(id: "u_\(def.id)", kind: .check(title: def.title, subtitle: "\(def.subtitle) · \(def.rarity)", checked: true)))
                }
                screen.sections.append(rows)
            }

            if !eval.locked.isEmpty {
                var rows: [MTNativeRow] = [MTNativeRow(id: "h_lk", kind: .header("Заблокированные (\(eval.locked.count))"))]
                for def in eval.locked {
                    rows.append(MTNativeRow(id: "l_\(def.id)", kind: .check(title: def.title, subtitle: "\(def.subtitle) · \(def.rarity)", checked: false)))
                }
                screen.sections.append(rows)
            }
            return screen
        }

        let controller = mtMakeNativeListController(context: context, model: model)
        controllerRef = controller
        return controller
    }

    static func makeBottomBarStudioController(context: AccountContext) -> ItemListController {
        let revision = ValuePromise<Int>(0, ignoreRepeated: false)
        weak var controllerRef: ItemListController?
        let bump: () -> Void = { revision.set(Int.random(in: 1 ... Int.max)) }

        let model = revision.get()
        |> map { _ -> MTNativeScreenModel in
            var screen = MTNativeScreenModel(title: "Редактор нижнего бара")

            var presetRows: [MTNativeRow] = [MTNativeRow(id: "h_presets", kind: .header("Готовые пресеты (1 тап)"))]
            for (idx, preset) in MTMediaTokCoreLogic.BottomTabPreset.allCases.enumerated() {
                let rowId = "preset_\(idx)"
                let label = preset.hiddenTabs.isEmpty ? "Все" : "Скрыто: \(preset.hiddenTabs.count)"
                presetRows.append(MTNativeRow(id: rowId, kind: .disclosure(title: preset.title, label: label, icon: nil, enabled: true)))
                screen.tap[rowId] = {
                    MTMediaTokLiquidUI.applyMediaTokGlobalSettings([
                        "interface.tabBar.hidden": preset.hiddenTabs,
                        "interface.tabBar.wide": preset.isWide
                    ])
                    MTThemeHooks.invalidate()
                    mtPresentNativeToast(context: context, from: controllerRef, text: "Применён пресет: \(preset.title)")
                    bump()
                }
            }
            screen.sections.append(presetRows)

            let lifted = UserDefaults.standard.bool(forKey: "mediatok.tabbar.lifted")
            let wide = MTMediaTokLiquidUI.readMediaTokGlobalBool("interface.tabBar.wide", fallback: UserDefaults.standard.bool(forKey: "mediatok.tabbar.wide"))
            let hideTitles = MTMediaTokLiquidUI.readMediaTokGlobalBool("interface.tabBar.hideTitles", fallback: UserDefaults.standard.bool(forKey: "mediatok.tabbar.hideTitles"))

            screen.sections.append([
                MTNativeRow(id: "h_custom", kind: .header("Кастомизация")),
                MTNativeRow(id: "lifted", kind: .toggle(title: "Парящий бар (+8pt над краем)", value: lifted, enabled: true)),
                MTNativeRow(id: "wide", kind: .toggle(title: "Широкий бар без разделителей", value: wide, enabled: true)),
                MTNativeRow(id: "hideTitles", kind: .toggle(title: "Скрыть подписи под иконками", value: hideTitles, enabled: true))
            ])
            screen.toggle["lifted"] = { on in
                UserDefaults.standard.set(on, forKey: "mediatok.tabbar.lifted")
                MTMediaTokLiquidUI.applyMediaTokGlobalSettings(["interface.tabBar.bottomOffset": on ? 8.0 : 0.0])
                MTThemeHooks.invalidate()
                bump()
            }
            screen.toggle["wide"] = { on in
                UserDefaults.standard.set(on, forKey: "mediatok.tabbar.wide")
                MTMediaTokLiquidUI.applyMediaTokGlobalSettings(["interface.tabBar.wide": on])
                MTThemeHooks.invalidate()
                bump()
            }
            screen.toggle["hideTitles"] = { on in
                UserDefaults.standard.set(on, forKey: "mediatok.tabbar.hideTitles")
                MTMediaTokLiquidUI.applyMediaTokGlobalSettings(["interface.tabBar.hideTitles": on])
                MTThemeHooks.invalidate()
                bump()
            }
            return screen
        }

        let controller = mtMakeNativeListController(context: context, model: model)
        controllerRef = controller
        return controller
    }
}

// MARK: - Neon Minesweeper (Сапёр 8x8) View Controller (#164)

public final class MTMinesweeperViewController: UIViewController {
    private var game = MTMediaTokCoreLogic.MinesweeperGame()
    private var cellButtons: [UIButton] = []
    private let statusLabel = UILabel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Neon Minesweeper"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1.0)

        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.statusLabel.text = "Мины: 10 · Первый клик безопасен · Зажми для флага 🚩"
        self.statusLabel.textColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
        self.statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        self.statusLabel.textAlignment = .center
        self.view.addSubview(self.statusLabel)

        let gridContainer = UIView()
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1.0)
        gridContainer.layer.cornerRadius = 16
        gridContainer.clipsToBounds = true
        self.view.addSubview(gridContainer)

        let cellSize: CGFloat = 36
        for r in 0..<8 {
            for c in 0..<8 {
                let idx = r * 8 + c
                let btn = UIButton(type: .system)
                btn.frame = CGRect(x: CGFloat(c) * (cellSize + 2) + 6, y: CGFloat(r) * (cellSize + 2) + 6, width: cellSize, height: cellSize)
                btn.backgroundColor = UIColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 1.0)
                btn.layer.cornerRadius = 6
                btn.tag = idx
                btn.addTarget(self, action: #selector(self.cellTapped(_:)), for: .touchUpInside)

                let lp = UILongPressGestureRecognizer(target: self, action: #selector(self.cellLongPressed(_:)))
                lp.minimumPressDuration = 0.3
                btn.addGestureRecognizer(lp)

                gridContainer.addSubview(btn)
                self.cellButtons.append(btn)
            }
        }

        let resetBtn = UIButton(type: .system)
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        resetBtn.setTitle("Новая игра", for: .normal)
        resetBtn.setTitleColor(.white, for: .normal)
        resetBtn.backgroundColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.3)
        resetBtn.layer.cornerRadius = 12
        resetBtn.addTarget(self, action: #selector(self.resetGame), for: .touchUpInside)
        self.view.addSubview(resetBtn)

        NSLayoutConstraint.activate([
            self.statusLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            self.statusLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),

            gridContainer.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            gridContainer.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 20),
            gridContainer.widthAnchor.constraint(equalToConstant: 8 * (cellSize + 2) + 12),
            gridContainer.heightAnchor.constraint(equalToConstant: 8 * (cellSize + 2) + 12),

            resetBtn.topAnchor.constraint(equalTo: gridContainer.bottomAnchor, constant: 24),
            resetBtn.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            resetBtn.widthAnchor.constraint(equalToConstant: 180),
            resetBtn.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func cellTapped(_ btn: UIButton) {
        self.game.reveal(at: btn.tag)
        self.updateGridUI()
        if self.game.isWon {
            self.statusLabel.text = "🏆 ПОБЕДА! Все мины обезврежены!"
            self.statusLabel.textColor = .systemGreen
            MTMediaTokWave6Tools.unlockAchievement(.gamer)
        } else if self.game.isGameOver {
            self.statusLabel.text = "💥 БУМ! Вы наступили на мину!"
            self.statusLabel.textColor = .systemRed
        }
    }

    @objc private func cellLongPressed(_ lp: UILongPressGestureRecognizer) {
        guard lp.state == .began, let btn = lp.view as? UIButton else { return }
        self.game.toggleFlag(at: btn.tag)
        self.updateGridUI()
    }

    @objc private func resetGame() {
        self.game = MTMediaTokCoreLogic.MinesweeperGame()
        self.statusLabel.text = "Мины: 10 · Первый клик безопасен · Зажми для флага 🚩"
        self.statusLabel.textColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
        self.updateGridUI()
    }

    private func updateGridUI() {
        for i in 0..<64 {
            let cell = self.game.grid[i]
            let btn = self.cellButtons[i]
            if cell.isRevealed {
                if cell.isMine {
                    btn.setTitle("💣", for: .normal)
                    btn.backgroundColor = UIColor.systemRed.withAlphaComponent(0.6)
                } else {
                    btn.backgroundColor = UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)
                    if cell.adjacentMines > 0 {
                        btn.setTitle("\(cell.adjacentMines)", for: .normal)
                        btn.setTitleColor(self.colorForAdjacent(cell.adjacentMines), for: .normal)
                    } else {
                        btn.setTitle("", for: .normal)
                    }
                }
            } else if cell.isFlagged {
                btn.setTitle("🚩", for: .normal)
                btn.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.4)
            } else {
                btn.setTitle("", for: .normal)
                btn.backgroundColor = UIColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 1.0)
            }
        }
    }

    private func colorForAdjacent(_ n: Int) -> UIColor {
        switch n {
        case 1: return UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
        case 2: return UIColor.systemGreen
        case 3: return UIColor.systemOrange
        case 4: return UIColor.systemPurple
        default: return UIColor.systemRed
        }
    }
}
