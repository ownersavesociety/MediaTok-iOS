import Foundation
import MTCore

/// The masks that ship with the app. They are ordinary manifests rendered by the same engine as
/// catalog and own masks (one code path), and they never touch the disk or the network.
enum MTBuiltInMasks {
    static let ids: [String] = [
        "autoBlur", "pixelate", "heavyFaceBlur", "backgroundBlur",
        "colorNoir", "sepiaVintage", "chrome", "fade", "warmTone", "coldTone",
        "emojiFire", "emojiSkull", "emojiGhost", "emojiAlien", "emojiClown", "emojiRobot", "emojiCool"
    ]

    static func manifest(id: String) -> MTMaskManifest? {
        let effects: [MTMaskEffect]
        switch id {
        case "autoBlur":
            effects = [MTMaskEffect.filter("blur.gaussianFace", params: ["radius": .number(28.0)])]
        case "heavyFaceBlur":
            effects = [MTMaskEffect.filter("blur.gaussianFace", params: ["radius": .number(45.0)])]
        case "pixelate":
            effects = [MTMaskEffect.filter("blur.pixelFace", params: ["scale": .number(24.0)])]
        case "backgroundBlur":
            effects = [MTMaskEffect.filter("blur.background", params: ["radius": .number(18.0)])]
        case "colorNoir":
            effects = [MTMaskEffect(type: .colorFilter, preset: .noir)]
        case "sepiaVintage":
            effects = [MTMaskEffect(type: .colorFilter, preset: .sepia)]
        case "chrome":
            effects = [MTMaskEffect(type: .colorFilter, preset: .chrome)]
        case "fade":
            effects = [MTMaskEffect(type: .colorFilter, preset: .fade)]
        case "warmTone":
            effects = [MTMaskEffect(type: .colorFilter, preset: .warm)]
        case "coldTone":
            effects = [MTMaskEffect(type: .colorFilter, preset: .cold)]
        default:
            guard let emoji = MTBuiltInMasks.emoji(id: id) else {
                return nil
            }
            effects = [MTMaskEffect(type: .emojiHead, emoji: emoji)]
        }
        return MTMaskManifest(id: id, name: [:], effects: effects)
    }

    /// Glyph of the mask's chip.
    static func glyph(id: String) -> String {
        if let emoji = MTBuiltInMasks.emoji(id: id) {
            return emoji
        }
        switch id {
        case "autoBlur", "heavyFaceBlur":
            return "🌫"
        case "pixelate":
            return "🟪"
        case "backgroundBlur":
            return "🧍"
        case "colorNoir":
            return "⚫️"
        case "sepiaVintage":
            return "🟤"
        case "chrome":
            return "💿"
        case "fade":
            return "🌁"
        case "warmTone":
            return "🌅"
        case "coldTone":
            return "🧊"
        default:
            return "🎭"
        }
    }

    private static func emoji(id: String) -> String? {
        switch id {
        case "emojiFire":
            return "🔥"
        case "emojiSkull":
            return "💀"
        case "emojiGhost":
            return "👻"
        case "emojiAlien":
            return "👽"
        case "emojiClown":
            return "🤡"
        case "emojiRobot":
            return "🤖"
        case "emojiCool":
            return "😎"
        default:
            return nil
        }
    }

    static func title(id: String) -> String {
        switch id {
        case "autoBlur":
            return MTStrings.CameraMasks.BuiltIn.autoBlur
        case "heavyFaceBlur":
            return MTStrings.CameraMasks.BuiltIn.heavyFaceBlur
        case "pixelate":
            return MTStrings.CameraMasks.BuiltIn.pixelate
        case "backgroundBlur":
            return MTStrings.CameraMasks.BuiltIn.backgroundBlur
        case "colorNoir":
            return MTStrings.CameraMasks.BuiltIn.colorNoir
        case "sepiaVintage":
            return MTStrings.CameraMasks.BuiltIn.sepiaVintage
        case "chrome":
            return MTStrings.CameraMasks.BuiltIn.chrome
        case "fade":
            return MTStrings.CameraMasks.BuiltIn.fade
        case "warmTone":
            return MTStrings.CameraMasks.BuiltIn.warmTone
        case "coldTone":
            return MTStrings.CameraMasks.BuiltIn.coldTone
        case "emojiFire":
            return MTStrings.CameraMasks.BuiltIn.emojiFire
        case "emojiSkull":
            return MTStrings.CameraMasks.BuiltIn.emojiSkull
        case "emojiGhost":
            return MTStrings.CameraMasks.BuiltIn.emojiGhost
        case "emojiAlien":
            return MTStrings.CameraMasks.BuiltIn.emojiAlien
        case "emojiClown":
            return MTStrings.CameraMasks.BuiltIn.emojiClown
        case "emojiRobot":
            return MTStrings.CameraMasks.BuiltIn.emojiRobot
        case "emojiCool":
            return MTStrings.CameraMasks.BuiltIn.emojiCool
        default:
            return id
        }
    }
}
