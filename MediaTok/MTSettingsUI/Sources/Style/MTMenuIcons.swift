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

/// Main-thread cache: menu screens are rebuilt on every settings change, and a fresh UIImage per
/// rebuild would make ItemList re-apply every icon (it compares images by identity).
private final class MTMenuIconCache {
    static let shared = MTMenuIconCache()

    private var images: [String: UIImage] = [:]
    // The tile is asked for by Telegram's Settings, which may build its rows off the main thread:
    // static lets are initialized once and thread-safely.
    private static let tile: UIImage? = mtRenderSettingsTile()

    func image(for icon: MTMenuIcon, color: UIColor) -> UIImage? {
        assert(Thread.isMainThread)
        let key = "\(icon)|\(color.mtHexKey)"
        if let image = self.images[key] {
            return image
        }
        guard let image = mtRenderMenuIcon(icon, color: color) else {
            return nil
        }
        self.images[key] = image
        return image
    }

    func settingsTile() -> UIImage? {
        return MTMenuIconCache.tile
    }

    func mark(color: UIColor) -> UIImage? {
        assert(Thread.isMainThread)
        let key = "headerMark|\(color.mtHexKey)"
        if let image = self.images[key] {
            return image
        }
        guard let image = mtRenderHeaderMark(color: color) else {
            return nil
        }
        self.images[key] = image
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

/// The mark in the root header: the plain ghost,
/// 64 pt, in the theme's primary text color so it reads on light and dark backgrounds.
func mtSettingsHeaderMark(theme: PresentationTheme) -> UIImage? {
    return MTMenuIconCache.shared.mark(color: theme.list.itemPrimaryTextColor)
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

private func mtRenderHeaderMark(color: UIColor) -> UIImage? {
    let side = mtSettingsHeaderMarkSide
    if let image = UIImage(bundleImageName: mtHeaderGhostName) {
        return generateTintedImage(image: image, color: color)
    }
    if let tile = UIImage(bundleImageName: mtSettingsTileName) {
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: side * 0.225).addClip()
            tile.draw(in: rect)
        }
    }
    return mtVectorGhost(size: CGSize(width: side, height: side), color: color)
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

/// Fallback MediaTok lightning bolt vector mark when the asset catalog is absent.
private func mtVectorGhost(size: CGSize, color: UIColor) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { rendererContext in
        let context = rendererContext.cgContext
        let w = size.width
        let h = size.height
        let bolt = UIBezierPath()
        bolt.move(to: CGPoint(x: w * 0.58, y: h * 0.08))
        bolt.addLine(to: CGPoint(x: w * 0.22, y: h * 0.56))
        bolt.addLine(to: CGPoint(x: w * 0.48, y: h * 0.56))
        bolt.addLine(to: CGPoint(x: w * 0.42, y: h * 0.92))
        bolt.addLine(to: CGPoint(x: w * 0.78, y: h * 0.44))
        bolt.addLine(to: CGPoint(x: w * 0.52, y: h * 0.44))
        bolt.close()
        context.setFillColor(color.cgColor)
        context.addPath(bolt.cgPath)
        context.fillPath()
    }
}
