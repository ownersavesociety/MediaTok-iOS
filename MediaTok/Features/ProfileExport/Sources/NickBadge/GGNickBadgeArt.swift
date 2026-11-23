import Foundation
import UIKit

// The badge pictures, drawn in code (no assets, sharp at any size): the MediaTok lightning bolt
// for a supporter, the bolt cut out of a wavy seal for the team, or a custom badge image.
//
// Every call is safe from any thread (layout passes run off the main thread). Results are cached
// by a small hashable key — no string formatting per call.

private struct GGNickBadgeArtKey: Hashable {
    let kind: UInt8
    /// Height in half points.
    let halfPoints: Int
    let rgb: UInt32
    let imageId: String?
}

enum GGNickBadgeArt {
    private static let lock = GGProfileExportLock()
    private static var cache: [GGNickBadgeArtKey: UIImage] = [:]
    private static let cacheLimit = 256

    /// The badge `height` points tall. A custom picture that is not in memory yet is drawn as the
    /// supporter ghost in the owner's colour, and its loading is started.
    static func image(for badge: GGNickBadge, height: CGFloat) -> UIImage {
        let halfPoints = max(12, Int((height * 2.0).rounded()))
        let rgb = badge.colorRGB
        switch badge.kind {
        case .team:
            return GGNickBadgeArt.cached(GGNickBadgeArtKey(kind: 1, halfPoints: halfPoints, rgb: rgb, imageId: nil)) {
                GGNickBadgeArt.drawTeam(height: CGFloat(halfPoints) / 2.0, rgb: rgb)
            }
        case .custom:
            if let imageId = badge.imageId, let source = GGNickBadgeImages.shared.source(for: imageId) {
                let keyColor: UInt32 = badge.tinted ? rgb : 0xFFFFFFFF
                return GGNickBadgeArt.cached(GGNickBadgeArtKey(kind: 2, halfPoints: halfPoints, rgb: keyColor, imageId: imageId)) {
                    GGNickBadgeArt.drawCustom(source: source, tinted: badge.tinted, height: CGFloat(halfPoints) / 2.0, rgb: rgb)
                }
            }
            fallthrough
        case .supporter:
            return GGNickBadgeArt.cached(GGNickBadgeArtKey(kind: 0, halfPoints: halfPoints, rgb: rgb, imageId: nil)) {
                GGNickBadgeArt.drawSupporter(height: CGFloat(halfPoints) / 2.0, rgb: rgb)
            }
        }
    }

    /// The supporter ghost in the default colour (the badge screen, before a badge exists).
    static func sampleImage(height: CGFloat) -> UIImage {
        let badge = GGNickBadge(kind: .supporter, imageId: nil, tinted: false, colorRGB: GGNickBadge.defaultColorRGB, text: nil)
        return GGNickBadgeArt.image(for: badge, height: height)
    }

    /// Drops every cached picture (a picture arrived; colours do not change otherwise).
    static func purgeCustom() {
        GGNickBadgeArt.lock.withLock {
            GGNickBadgeArt.cache = GGNickBadgeArt.cache.filter { $0.key.imageId == nil }
        }
    }

    private static func cached(_ key: GGNickBadgeArtKey, _ make: () -> UIImage) -> UIImage {
        if let image = GGNickBadgeArt.lock.withLock({ GGNickBadgeArt.cache[key] }) {
            return image
        }
        let image = make()
        GGNickBadgeArt.lock.withLock {
            if GGNickBadgeArt.cache.count >= GGNickBadgeArt.cacheLimit {
                GGNickBadgeArt.cache.removeAll(keepingCapacity: true)
            }
            GGNickBadgeArt.cache[key] = image
        }
        return image
    }

    static func color(_ rgb: UInt32) -> UIColor {
        return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255.0, green: CGFloat((rgb >> 8) & 0xFF) / 255.0, blue: CGFloat(rgb & 0xFF) / 255.0, alpha: 1.0)
    }

    /// Near-white and near-black badges get a soft rim of the opposite tone, so a white badge does
    /// not vanish in a light theme and a black one in a dark theme.
    private static func rim(for rgb: UInt32, height: CGFloat) -> (color: UIColor, radius: CGFloat)? {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let radius = max(1.0, height * 0.08)
        if luma >= 0.8 {
            return (UIColor(white: 0.0, alpha: 0.45), radius)
        }
        if luma <= 0.16 {
            return (UIColor(white: 1.0, alpha: 0.6), radius)
        }
        return nil
    }

    private static func render(size: CGSize, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(context.cgContext)
        }
    }

    // MARK: - Shapes

    /// MediaTok lightning bolt glyph inside `box`.
    private static func boltPath(in box: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let x = box.minX
        let y = box.minY
        let w = box.width
        let h = box.height
        path.move(to: CGPoint(x: x + w * 0.60, y: y + h * 0.04))
        path.addLine(to: CGPoint(x: x + w * 0.14, y: y + h * 0.56))
        path.addLine(to: CGPoint(x: x + w * 0.46, y: y + h * 0.56))
        path.addLine(to: CGPoint(x: x + w * 0.38, y: y + h * 0.96))
        path.addLine(to: CGPoint(x: x + w * 0.86, y: y + h * 0.44))
        path.addLine(to: CGPoint(x: x + w * 0.54, y: y + h * 0.44))
        path.close()
        return path
    }

    private static func sealPath(in square: CGRect) -> UIBezierPath {
        let center = CGPoint(x: square.midX, y: square.midY)
        let outer = square.width / 2.0
        let inner = outer * 0.87
        let bumps = 12
        let steps = bumps * 8
        let path = UIBezierPath()
        for step in 0 ... steps {
            let angle = CGFloat(step) / CGFloat(steps) * 2.0 * .pi - .pi / 2.0
            let wave = (cos(angle * CGFloat(bumps)) + 1.0) / 2.0
            let radius = inner + (outer - inner) * wave
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        return path
    }

    // MARK: - Badges

    private static func drawSupporter(height: CGFloat, rgb: UInt32) -> UIImage {
        let rim = GGNickBadgeArt.rim(for: rgb, height: height)
        let inset = rim?.radius ?? 0.0
        let markHeight = (height - inset * 2.0) * 0.92
        let markWidth = markHeight * 0.84
        let box = CGRect(x: (height - markWidth) / 2.0, y: (height - markHeight) / 2.0, width: markWidth, height: markHeight)
        return GGNickBadgeArt.render(size: CGSize(width: height, height: height)) { context in
            context.saveGState()
            if let rim = rim {
                context.setShadow(offset: CGSize(), blur: rim.radius, color: rim.color.cgColor)
            }
            context.setFillColor(GGNickBadgeArt.color(rgb).cgColor)
            context.addPath(GGNickBadgeArt.boltPath(in: box).cgPath)
            context.fillPath()
            context.restoreGState()
        }
    }

    private static func drawTeam(height: CGFloat, rgb: UInt32) -> UIImage {
        let rim = GGNickBadgeArt.rim(for: rgb, height: height)
        let inset = rim?.radius ?? 0.0
        let side = (height - inset * 2.0) * 0.98
        let square = CGRect(x: (height - side) / 2.0, y: (height - side) / 2.0, width: side, height: side)
        let markHeight = side * 0.56
        let markWidth = markHeight * 0.82
        let markBox = CGRect(x: square.midX - markWidth / 2.0, y: square.midY - markHeight / 2.0, width: markWidth, height: markHeight)
        return GGNickBadgeArt.render(size: CGSize(width: height, height: height)) { context in
            context.saveGState()
            if let rim = rim {
                context.setShadow(offset: CGSize(), blur: rim.radius, color: rim.color.cgColor)
            }
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            let fill = GGNickBadgeArt.color(rgb).cgColor
            context.setFillColor(fill)
            context.addPath(GGNickBadgeArt.sealPath(in: square).cgPath)
            context.fillPath()
            // The lightning bolt is cut out of the seal.
            context.setBlendMode(.clear)
            context.addPath(GGNickBadgeArt.boltPath(in: markBox).cgPath)
            context.fillPath()
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }

    private static func drawCustom(source: UIImage, tinted: Bool, height: CGFloat, rgb: UInt32) -> UIImage {
        let aspect = min(4.0, max(0.25, source.size.width / max(1.0, source.size.height)))
        let rim = tinted ? GGNickBadgeArt.rim(for: rgb, height: height) : nil
        let inset = rim?.radius ?? 0.0
        let pictureHeight = height - inset * 2.0
        let pictureWidth = (pictureHeight * aspect * 2.0).rounded() / 2.0
        let size = CGSize(width: max(height, pictureWidth + inset * 2.0), height: height)
        let rect = CGRect(x: (size.width - pictureWidth) / 2.0, y: inset, width: pictureWidth, height: pictureHeight)
        if !tinted {
            return GGNickBadgeArt.render(size: size) { _ in
                source.draw(in: rect)
            }
        }
        // Only the picture's alpha survives: the owner's colour is filled into it.
        let glyph = GGNickBadgeArt.render(size: size) { context in
            source.draw(in: rect)
            context.setBlendMode(.sourceIn)
            context.setFillColor(GGNickBadgeArt.color(rgb).cgColor)
            context.fill(CGRect(origin: CGPoint(), size: size))
        }
        guard let rim = rim else {
            return glyph
        }
        return GGNickBadgeArt.render(size: size) { context in
            context.setShadow(offset: CGSize(), blur: rim.radius, color: rim.color.cgColor)
            glyph.draw(at: CGPoint())
        }
    }
}
