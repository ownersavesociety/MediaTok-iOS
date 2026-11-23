import Foundation
import UIKit
import CoreText
import SwiftSignalKit
import MTCore
import MTHooks
import MTAppearanceSettings

/// A font the user added from Files/// можно было заливать»). The file is copied into the app's container and registered for this
/// process only (CTFontManager, `.process` scope) at launch: nothing is installed system-wide and
/// nothing leaves the device.
struct MTCustomFont: Equatable {
    /// File name inside `MTCustomFonts.directory`.
    let fileName: String
    /// The family the file declares: what the menu shows and what CoreText resolves faces from.
    let familyName: String
}

enum MTCustomFontImportResult {
    case added(MTCustomFont)
    case notAFont
    case tooMany
}

enum MTCustomFonts {
    /// `appearance.font.family` of a custom font: the prefix and the file name.
    static let valuePrefix = "custom:"
    static let maximumCount = 50

    private static let queue = Queue(name: "org.mediatok.appearance.fonts", qos: .utility)
    private static let fileExtensions: Set<String> = ["ttf", "otf", "ttc"]

    static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        // Not ".../fonts": the font.v2 migration deletes that directory of an earlier build.
        return base.appendingPathComponent("mediatok/appearance/userFonts", isDirectory: true)
    }

    /// The fonts in the order they were added (an in-memory setting read: the menu asks per row).
    static var fonts: [MTCustomFont] {
        return MTAppearanceSettings.customFonts.value.compactMap { entry in
            let parts = entry.components(separatedBy: "\t")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                return nil
            }
            return MTCustomFont(fileName: parts[0], familyName: parts[1])
        }
    }

    static func settingValue(_ font: MTCustomFont) -> String {
        return MTCustomFonts.valuePrefix + font.fileName
    }

    static func isCustomValue(_ value: String) -> Bool {
        return value.hasPrefix(MTCustomFonts.valuePrefix)
    }

    /// The font a stored `appearance.font.family` names, if it is a custom one still in the list.
    static func font(forSettingValue value: String) -> MTCustomFont? {
        guard MTCustomFonts.isCustomValue(value) else {
            return nil
        }
        let fileName = String(value.dropFirst(MTCustomFonts.valuePrefix.count))
        return MTCustomFonts.fonts.first(where: { $0.fileName == fileName })
    }

    /// The fonts the user added, for the other features that draw in them (MTUserFontsHooks: the island
    /// badge studio).
    static func registerProvider() {
        MTUserFontsHooks.fonts.register({
            return MTCustomFonts.fonts.compactMap { font -> MTUserFont? in
                guard let url = MTCustomFonts.fileURL(font) else {
                    return nil
                }
                return MTUserFont(familyName: font.familyName, fileURL: url)
            }
        })
    }

    private static func fileURL(_ font: MTCustomFont) -> URL? {
        return MTCustomFonts.directory?.appendingPathComponent(font.fileName)
    }

    // MARK: Import and removal (main thread; the file work runs on the fonts queue)

    /// Checks that CoreText reads the picked file as a font, copies it, adds it to the list and makes
    /// it the app font (applied after a restart, like every font).
    static func importFont(at sourceURL: URL, completion: @escaping (MTCustomFontImportResult) -> Void) {
        if MTCustomFonts.fonts.count >= MTCustomFonts.maximumCount {
            completion(.tooMany)
            return
        }
        MTCustomFonts.queue.async {
            let result = MTCustomFonts.copyFont(at: sourceURL)
            Queue.mainQueue().async {
                guard let font = result else {
                    completion(.notAFont)
                    return
                }
                var entries = MTAppearanceSettings.customFonts.value
                entries.append("\(font.fileName)\t\(font.familyName)")
                MTAppearanceSettings.customFonts.set(entries)
                MTAppearanceSettings.fontFamily.set(MTCustomFonts.settingValue(font))
                completion(.added(font))
            }
        }
    }

    private static func copyFont(at sourceURL: URL) -> MTCustomFont? {
        guard let directory = MTCustomFonts.directory else {
            return nil
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(sourceURL as CFURL) as? [CTFontDescriptor], let first = descriptors.first else {
            return nil
        }
        guard let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String, !familyName.isEmpty else {
            return nil
        }
        var fileExtension = sourceURL.pathExtension.lowercased()
        if !MTCustomFonts.fileExtensions.contains(fileExtension) {
            fileExtension = descriptors.count > 1 ? "ttc" : "ttf"
        }
        let fileName = "font-\(UInt32.random(in: 0 ... UInt32.max)).\(fileExtension)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: directory.appendingPathComponent(fileName))
        } catch {
            MTLog.warning("appearance", "custom font copy failed")
            return nil
        }
        return MTCustomFont(fileName: fileName, familyName: familyName.replacingOccurrences(of: "\t", with: " "))
    }

    /// Drops the font from the list; the app font falls back to the system one if it was chosen. The
    /// file itself is deleted at the next launch (`cleanUp`): the running app may still draw with it.
    static func remove(_ font: MTCustomFont) {
        if MTAppearanceSettings.fontFamily.value == MTCustomFonts.settingValue(font) {
            MTAppearanceSettings.fontFamily.reset()
        }
        let entries = MTAppearanceSettings.customFonts.value.filter { !$0.hasPrefix(font.fileName + "\t") }
        MTAppearanceSettings.customFonts.set(entries)
    }

    // MARK: Launch

    /// Registers the chosen font's file for this process. Nil when the file is gone or unreadable.
    static func registerForLaunch(_ font: MTCustomFont) -> String? {
        guard let url = MTCustomFonts.fileURL(font), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Already registered by this process is fine; anything else shows up as a missing family.
            error?.release()
        }
        if UIFont.fontNames(forFamilyName: font.familyName).isEmpty {
            return nil
        }
        return font.familyName
    }

    /// Deletes files no longer in the list (removed fonts), off the main thread, once per launch.
    static func cleanUp() {
        let kept = Set(MTCustomFonts.fonts.map(\.fileName))
        MTCustomFonts.queue.async {
            guard let directory = MTCustomFonts.directory, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
                return
            }
            for name in names where !kept.contains(name) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    // MARK: Menu (main thread)

    private static let menuFontsLock = NSLock()
    private static var menuFonts: [String: UIFont] = [:]

    /// The font's regular face for the menu sample, read straight from its file (not registered:
    /// a font added in this session is drawn before any restart). Cached per file.
    static func menuFont(_ font: MTCustomFont, size: CGFloat) -> UIFont? {
        let key = "\(font.fileName)_\(size)"
        MTCustomFonts.menuFontsLock.lock()
        let cached = MTCustomFonts.menuFonts[key]
        MTCustomFonts.menuFontsLock.unlock()
        if let cached {
            return cached
        }
        guard let url = MTCustomFonts.fileURL(font), let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let first = descriptors.first else {
            return nil
        }
        let result = CTFontCreateWithFontDescriptor(first, size, nil) as UIFont
        MTCustomFonts.menuFontsLock.lock()
        MTCustomFonts.menuFonts[key] = result
        MTCustomFonts.menuFontsLock.unlock()
        return result
    }
}
