import Foundation
import UIKit
import Display
import AppBundle
import TelegramPresentationData

// brightness 83 % on the mock-up scale. Every menu glyph is tinted by this one function.
public func mtMenuIconColor(theme: PresentationTheme) -> UIColor {
    if theme.overallDarkAppearance {
        return UIColor(rgb: 0xE3E3E8)
    } else {
        return UIColor(rgb: 0xB6B6BD)
    }
}

/// Name of the ghost glyph in this module's asset catalog (`Assets/MTSettingsUI.xcassets`).
let mtGhostGlyphName = "MTSettingsUI/BrandMark"

/// The root header's ghost: the app icon's ghost cut out whole (body, eyes, dust) as a 64 pt
/// template, so it stays sharp at that size (the row glyph is a 24 pt raster).
private let mtHeaderGhostName = "MTSettingsUI/HeaderMark"

/// Side of the root header's ghost.
let mtSettingsHeaderMarkSide: CGFloat = 64.0

private let mtMenuIconSize = CGSize(width: 24.0, height: 24.0)

/// Thread-safe icon cache: menu screens are rebuilt on every settings change, and a fresh UIImage per
/// rebuild would make ItemList re-apply every icon (it compares images by identity).
private final class MTMenuIconCache: @unchecked Sendable {
    static let shared = MTMenuIconCache()

    private let lock = NSLock()
    private var images: [String: UIImage] = [:]
    // The tile is asked for by Telegram's Settings, which may build its rows off the main thread:
    // static lets are initialized once and thread-safely.
    private static let tile: UIImage? = mtRenderSettingsTile()

    func image(for icon: MTMenuIcon, color: UIColor) -> UIImage? {
        let key = "\(icon)|\(color.mtHexKey)"
        self.lock.lock()
        if let image = self.images[key] {
            self.lock.unlock()
            return image
        }
        self.lock.unlock()
        guard let image = mtRenderMenuIcon(icon, color: color) else {
            return nil
        }
        self.lock.lock()
        self.images[key] = image
        self.lock.unlock()
        return image
    }

    func settingsTile() -> UIImage? {
        return MTMenuIconCache.tile
    }

    func mark(isDark: Bool) -> UIImage? {
        let key = "headerMarkSquircle|\(isDark ? "dark" : "light")"
        self.lock.lock()
        if let image = self.images[key] {
            self.lock.unlock()
            return image
        }
        self.lock.unlock()
        guard let image = mtRenderHeaderMark(isDark: isDark) else {
            return nil
        }
        self.lock.lock()
        self.images[key] = image
        self.lock.unlock()
        return image
    }
}

private extension UIColor {
    var mtHexKey: String {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02x%02x%02x%02x", Int(red * 255.0), Int(green * 255.0), Int(blue * 255.0), Int(alpha * 255.0))
    }
}

/// Glyph for a menu row, 24 pt, tinted with `mtMenuIconColor(theme:)`.
public func mtMenuIcon(_ icon: MTMenuIcon, theme: PresentationTheme) -> UIImage? {
    return MTMenuIconCache.shared.image(for: icon, color: mtMenuIconColor(theme: theme))
}

/// Same glyph tinted with an arbitrary color (accent marks in previews).
func mtMenuIcon(_ icon: MTMenuIcon, color: UIColor) -> UIImage? {
    return MTMenuIconCache.shared.image(for: icon, color: color)
}

/// The «MediaTok» row in Telegram's Settings: the standard 30 pt tile, like its neighbours.
public func mtSettingsTileIcon() -> UIImage? {
    return MTMenuIconCache.shared.settingsTile()
}

/// The mark in the root header: the crisp MediaTok stag on a pure #000000 iOS app-icon squircle
/// with a subtle hairline border (matches the Settings tile and AppIcon).
func mtSettingsHeaderMark(theme: PresentationTheme) -> UIImage? {
    return MTMenuIconCache.shared.mark(isDark: theme.overallDarkAppearance)
}

private let mtBrandColors: [UIColor] = [UIColor(rgb: 0x5B5B66), UIColor(rgb: 0x1F1F24)]

private func mtRenderMenuIcon(_ icon: MTMenuIcon, color: UIColor) -> UIImage? {
    let tinted: UIImage?
    switch icon {
    case let .bundle(name):
        tinted = generateTintedImage(image: UIImage(bundleImageName: name), color: color)
    case let .system(name):
        let configuration = UIImage.SymbolConfiguration(pointSize: 18.0, weight: .regular)
        tinted = UIImage(systemName: name, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal)
    case .ghost:
        if let image = UIImage(bundleImageName: mtGhostGlyphName) {
            tinted = generateTintedImage(image: image, color: color)
        } else {
            tinted = mtVectorGhost(size: mtMenuIconSize, color: color)
        }
    }
    guard let tinted else {
        return nil
    }
    if tinted.size == mtMenuIconSize {
        return tinted
    }
    // Aspect-fit into the 24 pt canvas so every row's glyph sits on the same grid.
    let scale = min(mtMenuIconSize.width / max(1.0, tinted.size.width), mtMenuIconSize.height / max(1.0, tinted.size.height), 1.0)
    let fittedSize = CGSize(width: floor(tinted.size.width * scale), height: floor(tinted.size.height * scale))
    let renderer = UIGraphicsImageRenderer(size: mtMenuIconSize)
    return renderer.image { _ in
        tinted.draw(in: CGRect(origin: CGPoint(x: floor((mtMenuIconSize.width - fittedSize.width) / 2.0), y: floor((mtMenuIconSize.height - fittedSize.height) / 2.0)), size: fittedSize))
    }
}

/// Name of the «MediaTok» row's tile in this module's asset catalog: the legacy MediaTok picture
/// (dark square, white ghost), drawn whole — not a glyph on a generated background.
private let mtSettingsTileName = "MTSettingsUI/SettingsTile"

private func mtRenderHeaderMark(isDark: Bool) -> UIImage? {
    let side = mtSettingsHeaderMarkSide
    let size = CGSize(width: side, height: side)
    let cornerRadius = side * 0.225
    let tile = UIImage(bundleImageName: mtSettingsTileName)
    let stagMask = UIImage(bundleImageName: mtHeaderGhostName)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { rendererContext in
        let rect = CGRect(origin: .zero, size: size)
        let squircle = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        rendererContext.cgContext.saveGState()
        squircle.addClip()

        UIColor.black.setFill()
        squircle.fill()

        if let tile {
            tile.draw(in: rect)
        } else if let stagMask, let tinted = generateTintedImage(image: stagMask, color: .white) {
            let inset = side * 0.14
            tinted.draw(in: rect.insetBy(dx: inset, dy: inset))
        }
        rendererContext.cgContext.restoreGState()

        let borderPath = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cornerRadius - 0.5)
        let borderColor = isDark ? UIColor(white: 1.0, alpha: 0.16) : UIColor(white: 0.0, alpha: 0.10)
        borderColor.setStroke()
        borderPath.lineWidth = 1.0
        borderPath.stroke()
    }
}

private func mtRenderSettingsTile() -> UIImage? {
    // As the legacy MediaTok drew it: the full picture through Telegram's own tile
    // renderer for app icons in Settings (30 pt, corner radius 8, the same gloss as its neighbours).
    if let image = UIImage(bundleImageName: mtSettingsTileName) {
        return renderAttachAppIcon(iconImage: image)
    }
    return mtRenderBrandMark(size: 30.0, cornerRadius: 8.0, glyphSize: 19.0)
}

private func mtRenderBrandMark(size: CGFloat, cornerRadius: CGFloat, glyphSize: CGFloat) -> UIImage? {
    let glyph = UIImage(bundleImageName: mtGhostGlyphName).flatMap { generateTintedImage(image: $0, color: .white) } ?? mtVectorGhost(size: CGSize(width: glyphSize, height: glyphSize), color: .white)
    let canvas = CGSize(width: size, height: size)
    let renderer = UIGraphicsImageRenderer(size: canvas)
    return renderer.image { rendererContext in
        let context = rendererContext.cgContext
        let bounds = CGRect(origin: CGPoint(), size: canvas)
        context.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath)
        context.clip()

        let colors = mtBrandColors.map(\.cgColor) as CFArray
        var locations: [CGFloat] = [0.0, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: &locations) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: size, y: size), options: [])
        }
        if let glyph {
            let glyphRect = CGRect(x: floor((size - glyphSize) / 2.0), y: floor((size - glyphSize) / 2.0), width: glyphSize, height: glyphSize)
            glyph.draw(in: glyphRect)
        }
    }
}

/// Fallback MediaTok minimal geometric mark when the asset catalog is absent.
private func mtVectorGhost(size: CGSize, color: UIColor) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { rendererContext in
        let context = rendererContext.cgContext
        let w = size.width
        let h = size.height
        let mark = UIBezierPath()
        mark.move(to: CGPoint(x: w * 0.50, y: h * 0.14))
        mark.addLine(to: CGPoint(x: w * 0.84, y: h * 0.50))
        mark.addLine(to: CGPoint(x: w * 0.50, y: h * 0.86))
        mark.addLine(to: CGPoint(x: w * 0.16, y: h * 0.50))
        mark.close()
        context.setFillColor(color.cgColor)
        context.addPath(mark.cgPath)
        context.fillPath()
    }
}
