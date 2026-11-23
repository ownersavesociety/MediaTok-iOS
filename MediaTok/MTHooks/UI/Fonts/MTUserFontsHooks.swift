// The fonts the user added in «Оформление» › «Шрифт», for the features that
// draw text in a font of the user's choice — the island badge studio. MTAppearance answers.

import Foundation
import MTCore

/// A font file the user added: the family it declares and where the file is.
public struct MTUserFont: Equatable {
    public let familyName: String
    public let fileURL: URL

    public init(familyName: String, fileURL: URL) {
        self.familyName = familyName
        self.fileURL = fileURL
    }
}

public enum MTUserFontsHooks {
    /// Provider: the fonts the user added, in the order added. The files are not registered with
    /// CoreText (only the chosen app font is, at launch): a feature registers what it draws with.
    /// Main thread; answer from memory.
    public static let fonts = MTHookPoint<() -> [MTUserFont]>("fonts.userFonts")

    public static func userFonts() -> [MTUserFont] {
        var result: [MTUserFont] = []
        for handler in MTUserFontsHooks.fonts.handlers {
            result.append(contentsOf: handler())
        }
        return result
    }
}
