import Foundation
import UIKit
import CoreGraphics
import Display
import Postbox
import TelegramCore
import WebPBinding
import GGCore
import GGHooks

/// `.color <color|gradient> <text>` (and `.col ...`) transparent WebP text-sticker generator for MediaTok iOS.
/// Renders crisp 512px transparent text with neon glow, dark stroke, and multi-stop linear gradient
/// using the active MediaTok UI font (custom .ttf, 80 bundled fonts, or rounded system font),
/// encodes via WebPBinding to genuine Telegram `image/webp` sticker, and replaces the outgoing message
/// while preserving replies, topics/threads, silent & scheduled attributes.
/// Visible to 100% of official Telegram users on iOS, Android, Desktop, Web WITHOUT Premium!
enum GGMediaTokColorSticker {
    struct Palette {
        let id: String
        let aliases: [String]
        let colors: [UIColor]
        let glow: UIColor
    }

    static let palettes: [Palette] = [
        Palette(id: "red", aliases: ["red", "красный", "r"], colors: [UIColor(rgb: 0xFF3B5C), UIColor(rgb: 0xFF0A3A)], glow: UIColor(rgb: 0xFF2A55)),
        Palette(id: "orange", aliases: ["orange", "оранжевый", "o"], colors: [UIColor(rgb: 0xFFA500), UIColor(rgb: 0xFF5500)], glow: UIColor(rgb: 0xFF7700)),
        Palette(id: "yellow", aliases: ["yellow", "желтый", "жёлтый", "y"], colors: [UIColor(rgb: 0xFFF04D), UIColor(rgb: 0xFFB800)], glow: UIColor(rgb: 0xFFD000)),
        Palette(id: "green", aliases: ["green", "зеленый", "зелёный", "g"], colors: [UIColor(rgb: 0x3BFF7A), UIColor(rgb: 0x00C853)], glow: UIColor(rgb: 0x00E676)),
        Palette(id: "cyan", aliases: ["cyan", "голубой", "бирюзовый", "c"], colors: [UIColor(rgb: 0x00F5FF), UIColor(rgb: 0x0099FF)], glow: UIColor(rgb: 0x00E5FF)),
        Palette(id: "blue", aliases: ["blue", "синий", "b"], colors: [UIColor(rgb: 0x4D9FFF), UIColor(rgb: 0x2244FF)], glow: UIColor(rgb: 0x2979FF)),
        Palette(id: "purple", aliases: ["purple", "фиолетовый", "violet", "p"], colors: [UIColor(rgb: 0xC471FF), UIColor(rgb: 0x7A1FFF)], glow: UIColor(rgb: 0xAA00FF)),
        Palette(id: "pink", aliases: ["pink", "розовый"], colors: [UIColor(rgb: 0xFF77CC), UIColor(rgb: 0xFF1F8F)], glow: UIColor(rgb: 0xFF40A8)),
        Palette(id: "white", aliases: ["white", "белый", "w"], colors: [UIColor(rgb: 0xFFFFFF), UIColor(rgb: 0xDCE6FF)], glow: UIColor(rgb: 0x99CCFF)),
        Palette(id: "fire", aliases: ["fire", "огонь", "пламя"], colors: [UIColor(rgb: 0xFFF04D), UIColor(rgb: 0xFF6B00), UIColor(rgb: 0xFF1744)], glow: UIColor(rgb: 0xFF5500)),
        Palette(id: "neon", aliases: ["neon", "неон"], colors: [UIColor(rgb: 0x00F5FF), UIColor(rgb: 0xFF00D4)], glow: UIColor(rgb: 0xCC00FF)),
        Palette(id: "cyber", aliases: ["cyber", "кибер", "cyberpunk"], colors: [UIColor(rgb: 0xFFE600), UIColor(rgb: 0x00F5FF), UIColor(rgb: 0xFF007F)], glow: UIColor(rgb: 0x00F0FF)),
        Palette(id: "sunset", aliases: ["sunset", "закат"], colors: [UIColor(rgb: 0xFF5E62), UIColor(rgb: 0xFF9966), UIColor(rgb: 0xFFE259)], glow: UIColor(rgb: 0xFF6E63)),
        Palette(id: "gold", aliases: ["gold", "золото"], colors: [UIColor(rgb: 0xFFF3A1), UIColor(rgb: 0xF5B301), UIColor(rgb: 0xC47F00)], glow: UIColor(rgb: 0xFFCA28)),
        Palette(id: "ocean", aliases: ["ocean", "океан", "ice", "лед", "лёд"], colors: [UIColor(rgb: 0x72F2EB), UIColor(rgb: 0x00B4D8), UIColor(rgb: 0x0066FF)], glow: UIColor(rgb: 0x00C8FF)),
        Palette(id: "toxic", aliases: ["toxic", "токсик", "matrix", "матрица"], colors: [UIColor(rgb: 0xCCFF00), UIColor(rgb: 0x00FF66)], glow: UIColor(rgb: 0x00FF66)),
        Palette(id: "sakura", aliases: ["sakura", "сакура"], colors: [UIColor(rgb: 0xFFD1DC), UIColor(rgb: 0xFF7EB3), UIColor(rgb: 0xC471ED)], glow: UIColor(rgb: 0xFF80BF)),
        Palette(id: "rainbow", aliases: ["rainbow", "радуга", "rgb"], colors: [UIColor(rgb: 0xFF3B5C), UIColor(rgb: 0xFFB800), UIColor(rgb: 0x00E676), UIColor(rgb: 0x00C8FF), UIColor(rgb: 0xC471FF)], glow: UIColor(rgb: 0x80D8FF))
    ]

    static func register() {
        GGOutgoingHooks.messages.register({ messages, context in
            GGMediaTokColorSticker.transform(&messages, context: context)
        }, order: 40)
    }

    private static func transform(_ messages: inout [EnqueueMessage], context: GGOutgoingContext) {
        for i in 0 ..< messages.count {
            guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = messages[i],
                  mediaReference == nil else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            guard lower.hasPrefix(".color ") || lower.hasPrefix(".col ") else {
                continue
            }
            let prefixLen = lower.hasPrefix(".color ") ? 7 : 5
            let rest = String(trimmed.dropFirst(prefixLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rest.isEmpty else {
                continue
            }
            let (colors, glow, body) = GGMediaTokColorSticker.parseColorAndText(rest)
            guard !body.isEmpty,
                  let rendered = GGMediaTokColorSticker.renderStickerImage(text: body, colors: colors, glowColor: glow),
                  let webpData = try? WebP.convert(toWebP: rendered.image, quality: 92.0),
                  !webpData.isEmpty else {
                continue
            }

            let fileId = Int64.random(in: Int64.min ... Int64.max)
            let resource = LocalFileMediaResource(fileId: fileId)
            context.account.postbox.mediaBox.storeResourceData(resource.id, data: webpData, synchronous: true)

            let fileAttributes: [TelegramMediaFileAttribute] = [
                .FileName(fileName: "mediatok_color.webp"),
                .Sticker(displayText: "🎨", packReference: nil, maskData: nil),
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

    private static func parseHexColor(_ token: String) -> UIColor? {
        var hex = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let val = UInt32(hex, radix: 16) else {
            return nil
        }
        return UIColor(rgb: val)
    }

    private static func parseColorAndText(_ input: String) -> ([UIColor], UIColor, String) {
        let parts = input.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard parts.count == 2 else {
            let fallback = GGMediaTokColorSticker.palettes[10] // neon
            return (fallback.colors, fallback.glow, input)
        }
        let token = String(parts[0]).lowercased()
        let body = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Custom gradient #HEX1-#HEX2
        if token.contains("-") {
            let hexes = token.split(separator: "-").compactMap { GGMediaTokColorSticker.parseHexColor(String($0)) }
            if hexes.count >= 2 {
                return (hexes, hexes[0], body)
            }
        }
        // Single #HEX
        if let single = GGMediaTokColorSticker.parseHexColor(token) {
            return ([single, single], single, body)
        }
        // Named preset
        for p in GGMediaTokColorSticker.palettes {
            if p.aliases.contains(token) {
                return (p.colors, p.glow, body)
            }
        }
        // Unrecognized first token -> treat full input as neon text
        let fallback = GGMediaTokColorSticker.palettes[10]
        return (fallback.colors, fallback.glow, input)
    }

    private static func activeFont(size: CGFloat) -> UIFont {
        if let custom = GGFonts.selectedCustomFont, let f = GGCustomFonts.menuFont(custom, size: size) {
            return f
        }
        if let bundled = GGFonts.selectedBundledFont, let f = GGMediaTokFonts.menuFont(bundled, size: size) {
            return f
        }
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        if let desc = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: desc, size: size)
        }
        return base
    }

    private static func renderStickerImage(text: String, colors: [UIColor], glowColor: UIColor) -> (image: UIImage, width: Int, height: Int)? {
        let maxW: CGFloat = 512.0
        let padX: CGFloat = 24.0
        let padY: CGFloat = 24.0
        let contentW = maxW - padX * 2.0

        let fontSize: CGFloat
        if text.count <= 10 {
            fontSize = 84.0
        } else if text.count <= 24 {
            fontSize = 64.0
        } else if text.count <= 60 {
            fontSize = 48.0
        } else {
            fontSize = 36.0
        }
        let font = GGMediaTokColorSticker.activeFont(size: fontSize)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 4.0

        let measureAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let nsText = text as NSString
        let bounding = nsText.boundingRect(
            with: CGSize(width: contentW, height: 460.0),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: measureAttrs,
            context: nil
        )
        let textW = min(contentW, ceil(bounding.width) + 12.0)
        let textH = min(464.0, max(fontSize * 1.15, ceil(bounding.height) + 12.0))
        let canvasW = Int(maxW)
        let canvasH = Int(min(512.0, max(128.0, textH + padY * 2.0)))
        let size = CGSize(width: CGFloat(canvasW), height: CGFloat(canvasH))

        let drawRect = CGRect(
            x: (size.width - textW) / 2.0,
            y: (size.height - textH) / 2.0,
            width: textW,
            height: textH
        )

        // 1. Render crisp white text mask to fill with linear gradient
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let gradientTextImage = UIGraphicsImageRenderer(size: size, format: format).image { rendererCtx in
            let cg = rendererCtx.cgContext
            let maskImg = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                let fillAttrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .paragraphStyle: paragraph,
                    .foregroundColor: UIColor.white
                ]
                nsText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: fillAttrs, context: nil)
            }
            guard let maskCG = maskImg.cgImage else { return }
            cg.saveGState()
            cg.translateBy(x: 0.0, y: size.height)
            cg.scaleBy(x: 1.0, y: -1.0)
            cg.clip(to: CGRect(origin: .zero, size: size), mask: maskCG)
            let cgColors = colors.map { $0.cgColor } as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: drawRect.minX, y: size.height - drawRect.minY),
                    end: CGPoint(x: drawRect.maxX, y: size.height - drawRect.maxY),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
            cg.restoreGState()
        }

        // 2. Compose outer neon glow + crisp dark outline + gradient fill on transparent background
        let finalImage = UIGraphicsImageRenderer(size: size, format: format).image { rendererCtx in
            let cg = rendererCtx.cgContext
            // Outer neon glow
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 14.0, color: glowColor.withAlphaComponent(0.85).cgColor)
            let glowAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraph,
                .foregroundColor: glowColor.withAlphaComponent(0.35)
            ]
            nsText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: glowAttrs, context: nil)
            cg.restoreGState()

            // Crisp dark outline stroke for readability on both light & dark chat wallpapers
            cg.saveGState()
            let strokeAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraph,
                .strokeColor: UIColor(white: 0.05, alpha: 0.92),
                .strokeWidth: 7.0
            ]
            nsText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: strokeAttrs, context: nil)
            cg.restoreGState()

            // Vibrant gradient text on top
            gradientTextImage.draw(in: CGRect(origin: .zero, size: size))
        }

        return (finalImage, canvasW, canvasH)
    }
}
