import Foundation
import UIKit
import CoreText
import Postbox
import TelegramCore
import GGCore
import GGHooks
import GGAppearanceSettings

struct GGBundledFont: Equatable {
    let slug: String
    let displayName: String
    let category: String
    let resourceName: String
}

enum GGMediaTokFonts {
    static let valuePrefix = "bundled:"

    static let all: [GGBundledFont] = [
        // Современные (26)
        GGBundledFont(slug: "inter", displayName: "Inter", category: "Современные", resourceName: "mt_inter"),
        GGBundledFont(slug: "montserrat", displayName: "Montserrat", category: "Современные", resourceName: "mt_montserrat"),
        GGBundledFont(slug: "manrope", displayName: "Manrope", category: "Современные", resourceName: "mt_manrope"),
        GGBundledFont(slug: "nunito", displayName: "Nunito", category: "Современные", resourceName: "mt_nunito"),
        GGBundledFont(slug: "comfortaa", displayName: "Comfortaa", category: "Современные", resourceName: "mt_comfortaa"),
        GGBundledFont(slug: "rubik", displayName: "Rubik", category: "Современные", resourceName: "mt_rubik"),
        GGBundledFont(slug: "onest", displayName: "Onest", category: "Современные", resourceName: "mt_onest"),
        GGBundledFont(slug: "golos_text", displayName: "Golos Text", category: "Современные", resourceName: "mt_golos_text"),
        GGBundledFont(slug: "raleway", displayName: "Raleway", category: "Современные", resourceName: "mt_raleway"),
        GGBundledFont(slug: "mulish", displayName: "Mulish", category: "Современные", resourceName: "mt_mulish"),
        GGBundledFont(slug: "jost", displayName: "Jost", category: "Современные", resourceName: "mt_jost"),
        GGBundledFont(slug: "ubuntu", displayName: "Ubuntu", category: "Современные", resourceName: "mt_ubuntu"),
        GGBundledFont(slug: "pt_sans", displayName: "PT Sans", category: "Современные", resourceName: "mt_pt_sans"),
        GGBundledFont(slug: "fira_sans", displayName: "Fira Sans", category: "Современные", resourceName: "mt_fira_sans"),
        GGBundledFont(slug: "exo_2", displayName: "Exo 2", category: "Современные", resourceName: "mt_exo_2"),
        GGBundledFont(slug: "oswald", displayName: "Oswald", category: "Современные", resourceName: "mt_oswald"),
        GGBundledFont(slug: "sofia_sans", displayName: "Sofia Sans", category: "Современные", resourceName: "mt_sofia_sans"),
        GGBundledFont(slug: "commissioner", displayName: "Commissioner", category: "Современные", resourceName: "mt_commissioner"),
        GGBundledFont(slug: "cuprum", displayName: "Cuprum", category: "Современные", resourceName: "mt_cuprum"),
        GGBundledFont(slug: "yanone_kaffeesatz", displayName: "Yanone Kaffeesatz", category: "Современные", resourceName: "mt_yanone_kaffeesatz"),
        GGBundledFont(slug: "didact_gothic", displayName: "Didact Gothic", category: "Современные", resourceName: "mt_didact_gothic"),
        GGBundledFont(slug: "tenor_sans", displayName: "Tenor Sans", category: "Современные", resourceName: "mt_tenor_sans"),
        GGBundledFont(slug: "el_messiri", displayName: "El Messiri", category: "Современные", resourceName: "mt_el_messiri"),
        GGBundledFont(slug: "alumni_sans", displayName: "Alumni Sans", category: "Современные", resourceName: "mt_alumni_sans"),
        GGBundledFont(slug: "bellota_text", displayName: "Bellota Text", category: "Современные", resourceName: "mt_bellota_text"),
        GGBundledFont(slug: "wix_madefor_display", displayName: "Wix Madefor Display", category: "Современные", resourceName: "mt_wix_madefor_display"),

        // Кибер / Пиксель / Арт (29)
        GGBundledFont(slug: "unbounded", displayName: "Unbounded", category: "Кибер / Пиксель / Арт", resourceName: "mt_unbounded"),
        GGBundledFont(slug: "russo_one", displayName: "Russo One", category: "Кибер / Пиксель / Арт", resourceName: "mt_russo_one"),
        GGBundledFont(slug: "tektur", displayName: "Tektur", category: "Кибер / Пиксель / Арт", resourceName: "mt_tektur"),
        GGBundledFont(slug: "jura", displayName: "Jura", category: "Кибер / Пиксель / Арт", resourceName: "mt_jura"),
        GGBundledFont(slug: "press_start_2p", displayName: "Press Start 2P", category: "Кибер / Пиксель / Арт", resourceName: "mt_press_start_2p"),
        GGBundledFont(slug: "pixelify_sans", displayName: "Pixelify Sans", category: "Кибер / Пиксель / Арт", resourceName: "mt_pixelify_sans"),
        GGBundledFont(slug: "tiny5", displayName: "Tiny5", category: "Кибер / Пиксель / Арт", resourceName: "mt_tiny5"),
        GGBundledFont(slug: "rubik_glitch", displayName: "Rubik Glitch", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_glitch"),
        GGBundledFont(slug: "rubik_bubbles", displayName: "Rubik Bubbles", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_bubbles"),
        GGBundledFont(slug: "rubik_mono_one", displayName: "Rubik Mono One", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_mono_one"),
        GGBundledFont(slug: "kelly_slab", displayName: "Kelly Slab", category: "Кибер / Пиксель / Арт", resourceName: "mt_kelly_slab"),
        GGBundledFont(slug: "underdog", displayName: "Underdog", category: "Кибер / Пиксель / Арт", resourceName: "mt_underdog"),
        GGBundledFont(slug: "poiret_one", displayName: "Poiret One", category: "Кибер / Пиксель / Арт", resourceName: "mt_poiret_one"),
        GGBundledFont(slug: "ruslan_display", displayName: "Ruslan Display", category: "Кибер / Пиксель / Арт", resourceName: "mt_ruslan_display"),
        GGBundledFont(slug: "seymour_one", displayName: "Seymour One", category: "Кибер / Пиксель / Арт", resourceName: "mt_seymour_one"),
        GGBundledFont(slug: "stalinist_one", displayName: "Stalinist One", category: "Кибер / Пиксель / Арт", resourceName: "mt_stalinist_one"),
        GGBundledFont(slug: "kablammo", displayName: "Kablammo", category: "Кибер / Пиксель / Арт", resourceName: "mt_kablammo"),
        GGBundledFont(slug: "rubik_wet_paint", displayName: "Rubik Wet Paint", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_wet_paint"),
        GGBundledFont(slug: "rubik_spray_paint", displayName: "Rubik Spray Paint", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_spray_paint"),
        GGBundledFont(slug: "rubik_vinyl", displayName: "Rubik Vinyl", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_vinyl"),
        GGBundledFont(slug: "rubik_iso", displayName: "Rubik Iso", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_iso"),
        GGBundledFont(slug: "rubik_broken_fax", displayName: "Rubik Broken Fax", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_broken_fax"),
        GGBundledFont(slug: "rubik_burned", displayName: "Rubik Burned", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_burned"),
        GGBundledFont(slug: "rubik_distressed", displayName: "Rubik Distressed", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_distressed"),
        GGBundledFont(slug: "rubik_marker_hatch", displayName: "Rubik Marker Hatch", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_marker_hatch"),
        GGBundledFont(slug: "rubik_maze", displayName: "Rubik Maze", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_maze"),
        GGBundledFont(slug: "rubik_moonrocks", displayName: "Rubik Moonrocks", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_moonrocks"),
        GGBundledFont(slug: "rubik_puddles", displayName: "Rubik Puddles", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_puddles"),
        GGBundledFont(slug: "rubik_scribble", displayName: "Rubik Scribble", category: "Кибер / Пиксель / Арт", resourceName: "mt_rubik_scribble"),

        // С засечками (10)
        GGBundledFont(slug: "playfair_display", displayName: "Playfair Display", category: "Serif", resourceName: "mt_playfair_display"),
        GGBundledFont(slug: "cormorant_garamond", displayName: "Cormorant Garamond", category: "Serif", resourceName: "mt_cormorant_garamond"),
        GGBundledFont(slug: "lora", displayName: "Lora", category: "Serif", resourceName: "mt_lora"),
        GGBundledFont(slug: "yeseva_one", displayName: "Yeseva One", category: "Serif", resourceName: "mt_yeseva_one"),
        GGBundledFont(slug: "philosopher", displayName: "Philosopher", category: "Serif", resourceName: "mt_philosopher"),
        GGBundledFont(slug: "alice", displayName: "Alice", category: "Serif", resourceName: "mt_alice"),
        GGBundledFont(slug: "merriweather", displayName: "Merriweather", category: "Serif", resourceName: "mt_merriweather"),
        GGBundledFont(slug: "vollkorn", displayName: "Vollkorn", category: "Serif", resourceName: "mt_vollkorn"),
        GGBundledFont(slug: "forum", displayName: "Forum", category: "Serif", resourceName: "mt_forum"),
        GGBundledFont(slug: "prata", displayName: "Prata", category: "Serif", resourceName: "mt_prata"),

        // Рукописные и Фан (11)
        GGBundledFont(slug: "caveat", displayName: "Caveat", category: "Рукописные и Фан", resourceName: "mt_caveat"),
        GGBundledFont(slug: "pacifico", displayName: "Pacifico", category: "Рукописные и Фан", resourceName: "mt_pacifico"),
        GGBundledFont(slug: "marck_script", displayName: "Marck Script", category: "Рукописные и Фан", resourceName: "mt_marck_script"),
        GGBundledFont(slug: "bad_script", displayName: "Bad Script", category: "Рукописные и Фан", resourceName: "mt_bad_script"),
        GGBundledFont(slug: "lobster", displayName: "Lobster", category: "Рукописные и Фан", resourceName: "mt_lobster"),
        GGBundledFont(slug: "amatic_sc", displayName: "Amatic SC", category: "Рукописные и Фан", resourceName: "mt_amatic_sc"),
        GGBundledFont(slug: "neucha", displayName: "Neucha", category: "Рукописные и Фан", resourceName: "mt_neucha"),
        GGBundledFont(slug: "balsamiq_sans", displayName: "Balsamiq Sans", category: "Рукописные и Фан", resourceName: "mt_balsamiq_sans"),
        GGBundledFont(slug: "shantell_sans", displayName: "Shantell Sans", category: "Рукописные и Фан", resourceName: "mt_shantell_sans"),
        GGBundledFont(slug: "pangolin", displayName: "Pangolin", category: "Рукописные и Фан", resourceName: "mt_pangolin"),
        GGBundledFont(slug: "comforter_brush", displayName: "Comforter Brush", category: "Рукописные и Фан", resourceName: "mt_comforter_brush"),

        // Моноширинные (4)
        GGBundledFont(slug: "jetbrains_mono", displayName: "JetBrains Mono", category: "Mono", resourceName: "mt_jetbrains_mono"),
        GGBundledFont(slug: "fira_code", displayName: "Fira Code", category: "Mono", resourceName: "mt_fira_code"),
        GGBundledFont(slug: "ibm_plex_mono", displayName: "IBM Plex Mono", category: "Mono", resourceName: "mt_ibm_plex_mono"),
        GGBundledFont(slug: "anonymous_pro", displayName: "Anonymous Pro", category: "Mono", resourceName: "mt_anonymous_pro")
    ]

    static func settingValue(_ font: GGBundledFont) -> String {
        return GGMediaTokFonts.valuePrefix + font.slug
    }

    static func isBundledValue(_ value: String) -> Bool {
        return value.hasPrefix(GGMediaTokFonts.valuePrefix)
    }

    static func font(forSettingValue value: String) -> GGBundledFont? {
        guard GGMediaTokFonts.isBundledValue(value) else {
            return nil
        }
        let slug = String(value.dropFirst(GGMediaTokFonts.valuePrefix.count))
        return GGMediaTokFonts.all.first(where: { $0.slug == slug })
    }

    static func fileURL(_ font: GGBundledFont) -> URL? {
        if let url = Bundle.main.url(forResource: font.resourceName, withExtension: "ttf", subdirectory: "MediaTokFonts") {
            return url
        }
        return Bundle.main.url(forResource: font.resourceName, withExtension: "ttf")
    }

    static func registerForLaunch(_ font: GGBundledFont) -> String? {
        guard let url = GGMediaTokFonts.fileURL(font) else {
            return nil
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String,
              !familyName.isEmpty else {
            return nil
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            error?.release()
        }
        if UIFont.fontNames(forFamilyName: familyName).isEmpty {
            return nil
        }
        return familyName
    }

    private static let menuFontsLock = NSLock()
    private static var menuFonts: [String: UIFont] = [:]

    static func menuFont(_ font: GGBundledFont, size: CGFloat) -> UIFont? {
        let key = "\(font.slug)_\(size)"
        GGMediaTokFonts.menuFontsLock.lock()
        let cached = GGMediaTokFonts.menuFonts[key]
        GGMediaTokFonts.menuFontsLock.unlock()
        if let cached {
            return cached
        }
        guard let url = GGMediaTokFonts.fileURL(font),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first else {
            return nil
        }
        let result = CTFontCreateWithFontDescriptor(first, size, nil) as UIFont
        GGMediaTokFonts.menuFontsLock.lock()
        GGMediaTokFonts.menuFonts[key] = result
        GGMediaTokFonts.menuFontsLock.unlock()
        return result
    }
}

// MARK: - Stylish Outgoing Chat Text Fonts (32 styles, visible to everyone in Telegram)

struct GGChatTextStyle: Equatable {
    let id: String
    let name: String
    let cyrillicFull: Bool
}

enum GGChatTextFonts {
    static let all: [GGChatTextStyle] = [
        // Кириллица + Латиница (21)
        GGChatTextStyle(id: "smallcaps", name: "Маленькие капсы", cyrillicFull: true),
        GGChatTextStyle(id: "wide", name: "Широкий Vaporwave", cyrillicFull: true),
        GGChatTextStyle(id: "spaced", name: "Разрядка (А Э С Т Е Т И К А)", cyrillicFull: true),
        GGChatTextStyle(id: "ancient", name: "Старославянский", cyrillicFull: true),
        GGChatTextStyle(id: "cyber", name: "Киберпанк", cyrillicFull: true),
        GGChatTextStyle(id: "runes", name: "Рунический / Греч.", cyrillicFull: true),
        GGChatTextStyle(id: "bubble", name: "В кружочках", cyrillicFull: true),
        GGChatTextStyle(id: "square", name: "В квадратах", cyrillicFull: true),
        GGChatTextStyle(id: "underline", name: "Подчёркнутый", cyrillicFull: true),
        GGChatTextStyle(id: "double_line", name: "Двойная линия", cyrillicFull: true),
        GGChatTextStyle(id: "strike", name: "Зачёркнутый", cyrillicFull: true),
        GGChatTextStyle(id: "slash", name: "Перечёркнутый", cyrillicFull: true),
        GGChatTextStyle(id: "overline", name: "Надчёркнутый", cyrillicFull: true),
        GGChatTextStyle(id: "wave", name: "Волнистый", cyrillicFull: true),
        GGChatTextStyle(id: "glitch", name: "Глитч / Zalgo", cyrillicFull: true),
        GGChatTextStyle(id: "stars", name: "Эстетик ✦", cyrillicFull: true),
        GGChatTextStyle(id: "brackets", name: "Японские рамки 『 』", cyrillicFull: true),
        GGChatTextStyle(id: "leet", name: "Хакер 1337", cyrillicFull: true),
        GGChatTextStyle(id: "fence", name: "Заборчик", cyrillicFull: true),
        GGChatTextStyle(id: "upside", name: "Перевёрнутый", cyrillicFull: true),
        GGChatTextStyle(id: "mirror", name: "Зеркальный", cyrillicFull: true),

        // Латиница + Цифры Unicode Math (11)
        GGChatTextStyle(id: "bold", name: "Bold Serif", cyrillicFull: false),
        GGChatTextStyle(id: "italic", name: "Italic Serif", cyrillicFull: false),
        GGChatTextStyle(id: "bold_italic", name: "Bold Italic", cyrillicFull: false),
        GGChatTextStyle(id: "sans_bold", name: "Sans Bold", cyrillicFull: false),
        GGChatTextStyle(id: "sans_italic", name: "Sans Italic", cyrillicFull: false),
        GGChatTextStyle(id: "script", name: "Calligraphy Script", cyrillicFull: false),
        GGChatTextStyle(id: "bold_script", name: "Bold Script", cyrillicFull: false),
        GGChatTextStyle(id: "fraktur", name: "Gothic / Fraktur", cyrillicFull: false),
        GGChatTextStyle(id: "bold_fraktur", name: "Bold Gothic", cyrillicFull: false),
        GGChatTextStyle(id: "double_struck", name: "Double-Struck", cyrillicFull: false),
        GGChatTextStyle(id: "mono", name: "Monospace Unicode", cyrillicFull: false)
    ]

    static var cyrillicStyles: [GGChatTextStyle] {
        return GGChatTextFonts.all.filter { $0.cyrillicFull }
    }

    static var mathStyles: [GGChatTextStyle] {
        return GGChatTextFonts.all.filter { !$0.cyrillicFull }
    }

    static var selectedStyle: GGChatTextStyle? {
        let value = GGAppearanceSettings.chatTextFont.value
        guard !value.isEmpty else {
            return nil
        }
        return GGChatTextFonts.all.first(where: { $0.id == value })
    }

    static var selectedDisplayName: String {
        if let style = GGChatTextFonts.selectedStyle {
            return style.name
        }
        return GGStrings.Appearance.ChatFont.off
    }

    static func preview(for style: GGChatTextStyle) -> String {
        let sample = style.cyrillicFull ? "Привет • Hello 123" : "Hello MediaTok 123"
        return GGChatTextFonts.transform(sample, styleId: style.id)
    }

    static func register() {
        GGOutgoingHooks.textStages.register({ outgoing, _ in
            GGChatTextFonts.processOutgoing(&outgoing)
        }, order: 200)
    }

    private static func processOutgoing(_ outgoing: inout GGOutgoingText) {
        let raw = outgoing.text
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        // Inline one-off command: ".f <style> <text>"
        if trimmed.lowercased().hasPrefix(".f ") {
            let afterPrefix = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if let spaceIdx = afterPrefix.firstIndex(where: { $0.isWhitespace }) {
                let query = String(afterPrefix[..<spaceIdx]).lowercased()
                let body = String(afterPrefix[spaceIdx...]).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty, let style = GGChatTextFonts.findStyle(query) {
                    outgoing.text = GGChatTextFonts.transform(body, styleId: style.id)
                    outgoing.entities = []
                    return
                }
            }
        }

        // Skip commands
        if trimmed.hasPrefix(".") || trimmed.hasPrefix("/") {
            return
        }

        guard let activeStyle = GGChatTextFonts.selectedStyle else {
            return
        }

        if outgoing.entities.isEmpty {
            outgoing.text = GGChatTextFonts.transform(raw, styleId: activeStyle.id)
            return
        }

        GGChatTextFonts.transformWithEntities(&outgoing, styleId: activeStyle.id)
    }

    private static func findStyle(_ query: String) -> GGChatTextStyle? {
        if let exact = GGChatTextFonts.all.first(where: { $0.id == query }) {
            return exact
        }
        if let prefix = GGChatTextFonts.all.first(where: { $0.id.hasPrefix(query) || $0.name.lowercased().hasPrefix(query) }) {
            return prefix
        }
        return GGChatTextFonts.all.first(where: { $0.id.contains(query) || $0.name.lowercased().contains(query) })
    }

    private static func isProtectedEntity(_ type: MessageTextEntityType) -> Bool {
        switch type {
        case .Mention, .Hashtag, .BotCommand, .Url, .Email, .Code, .Pre, .TextUrl, .TextMention, .PhoneNumber, .BankCard, .TonAddress, .CustomEmoji, .FormattedDate:
            return true
        default:
            return false
        }
    }

    private static func transformWithEntities(_ outgoing: inout GGOutgoingText, styleId: String) {
        if styleId == "mirror" || styleId == "upside" {
            return
        }
        let nsText = outgoing.text as NSString
        let utf16Length = nsText.length
        var protectedMask = [Bool](repeating: false, count: utf16Length)
        for entity in outgoing.entities where GGChatTextFonts.isProtectedEntity(entity.type) {
            let lower = max(0, min(entity.range.lowerBound, utf16Length))
            let upper = max(lower, min(entity.range.upperBound, utf16Length))
            if lower < upper {
                for idx in lower ..< upper {
                    protectedMask[idx] = true
                }
            }
        }

        var result = ""
        result.reserveCapacity(outgoing.text.count * 2)
        var indexMap = [Int](repeating: 0, count: utf16Length + 1)
        var outUtf16Len = 0
        var srcUtf16Offset = 0
        var fenceIdx = 0

        for ch in outgoing.text {
            let charUtf16Len = ch.utf16.count
            for k in 0 ..< charUtf16Len where srcUtf16Offset + k < utf16Length {
                indexMap[srcUtf16Offset + k] = outUtf16Len
            }
            let isProtected = srcUtf16Offset < utf16Length && protectedMask[srcUtf16Offset]
            let piece: String
            if isProtected {
                piece = String(ch)
            } else {
                piece = GGChatTextFonts.transformCharacter(ch, styleId: styleId, index: fenceIdx)
                if ch.isLetter {
                    fenceIdx += 1
                }
            }
            result.append(piece)
            outUtf16Len += piece.utf16.count
            srcUtf16Offset += charUtf16Len
        }
        indexMap[utf16Length] = outUtf16Len

        var remapped: [MessageTextEntity] = []
        remapped.reserveCapacity(outgoing.entities.count)
        for entity in outgoing.entities {
            let oldLower = max(0, min(entity.range.lowerBound, utf16Length))
            let oldUpper = max(oldLower, min(entity.range.upperBound, utf16Length))
            let newLower = indexMap[oldLower]
            let newUpper = max(newLower, indexMap[oldUpper])
            remapped.append(MessageTextEntity(range: newLower ..< newUpper, type: entity.type))
        }
        outgoing.text = result
        outgoing.entities = remapped
    }

    static func transform(_ text: String, styleId: String) -> String {
        guard !styleId.isEmpty, !text.isEmpty else {
            return text
        }
        if styleId == "stars" {
            return "✦ \(GGChatTextFonts.transformTokens(text, styleId: "smallcaps")) ✦"
        }
        if styleId == "brackets" {
            return "『\(text)』"
        }
        if styleId == "mirror" {
            return GGChatTextFonts.containsSpecialToken(text)
                ? GGChatTextFonts.transformTokens(text, styleId: styleId)
                : String(text.reversed())
        }
        if styleId == "upside" {
            return GGChatTextFonts.containsSpecialToken(text)
                ? GGChatTextFonts.transformTokens(text, styleId: styleId)
                : GGChatTextFonts.flipUpsideDown(text)
        }
        return GGChatTextFonts.transformTokens(text, styleId: styleId)
    }

    private static func containsSpecialToken(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("http://") || lower.contains("https://") || lower.contains("t.me/") || text.contains("@") || text.contains("#")
    }

    private static func isProtectedToken(_ token: String) -> Bool {
        if token.isEmpty {
            return true
        }
        let lower = token.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("t.me/") || lower.hasPrefix("www.") {
            return true
        }
        if (token.hasPrefix("@") || token.hasPrefix("#") || token.hasPrefix("/")) && token.count > 1 {
            return true
        }
        return false
    }

    private static func transformTokens(_ text: String, styleId: String) -> String {
        var result = ""
        result.reserveCapacity(text.count * 2)
        var currentToken = ""
        var fenceIdx = 0

        func flushToken() {
            guard !currentToken.isEmpty else {
                return
            }
            if GGChatTextFonts.isProtectedToken(currentToken) {
                result.append(currentToken)
            } else if styleId == "mirror" {
                result.append(String(currentToken.reversed()))
            } else if styleId == "upside" {
                result.append(GGChatTextFonts.flipUpsideDown(currentToken))
            } else {
                for ch in currentToken {
                    result.append(GGChatTextFonts.transformCharacter(ch, styleId: styleId, index: fenceIdx))
                    if ch.isLetter {
                        fenceIdx += 1
                    }
                }
            }
            currentToken = ""
        }

        for ch in text {
            if ch.isWhitespace {
                flushToken()
                result.append(ch)
            } else {
                currentToken.append(ch)
            }
        }
        flushToken()
        return result
    }

    private static func flipUpsideDown(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text.reversed() {
            out.append(GGChatTextFonts.upsideMap[ch] ?? String(ch))
        }
        return out
    }

    private static func scalarString(_ value: UInt32) -> String {
        if let scalar = UnicodeScalar(value) {
            return String(scalar)
        }
        return ""
    }

    private static func mapMath(_ ch: Character, upperStart: UInt32, lowerStart: UInt32, digitStart: UInt32) -> String {
        guard ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value else {
            return String(ch)
        }
        if v >= 0x41 && v <= 0x5A {
            return GGChatTextFonts.scalarString(upperStart + (v - 0x41))
        }
        if v >= 0x61 && v <= 0x7A {
            return GGChatTextFonts.scalarString(lowerStart + (v - 0x61))
        }
        if digitStart != 0 && v >= 0x30 && v <= 0x39 {
            return GGChatTextFonts.scalarString(digitStart + (v - 0x30))
        }
        return String(ch)
    }

    private static func isCyrillic(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else {
            return false
        }
        return (v >= 0x0410 && v <= 0x044F) || v == 0x0401 || v == 0x0451
    }

    private static func transformCharacter(_ ch: Character, styleId: String, index: Int) -> String {
        switch styleId {
        case "smallcaps":
            return GGChatTextFonts.smallCapsMap[ch] ?? String(ch)
        case "wide":
            if ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value, v >= 0x21 && v <= 0x7E {
                return GGChatTextFonts.scalarString(v + 0xFEE0)
            }
            if GGChatTextFonts.isCyrillic(ch) {
                return "\(ch)\u{2009}"
            }
            return String(ch)
        case "spaced":
            return (ch.isLetter || ch.isNumber) ? "\(ch) " : String(ch)
        case "ancient":
            if let mapped = GGChatTextFonts.ancientMap[ch] {
                return mapped
            }
            return GGChatTextFonts.transformCharacter(ch, styleId: "fraktur", index: index)
        case "cyber":
            return GGChatTextFonts.cyberMap[ch] ?? String(ch)
        case "runes":
            return GGChatTextFonts.runesMap[ch] ?? String(ch)
        case "bubble":
            if ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value {
                if v >= 0x41 && v <= 0x5A { return GGChatTextFonts.scalarString(0x24B6 + (v - 0x41)) }
                if v >= 0x61 && v <= 0x7A { return GGChatTextFonts.scalarString(0x24D0 + (v - 0x61)) }
                if v == 0x30 { return "\u{24EA}" }
                if v >= 0x31 && v <= 0x39 { return GGChatTextFonts.scalarString(0x2460 + (v - 0x31)) }
            }
            return (ch.isLetter || ch.isNumber) ? "\(ch)\u{20DD}" : String(ch)
        case "square":
            if ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value {
                if v >= 0x41 && v <= 0x5A { return GGChatTextFonts.scalarString(0x1F130 + (v - 0x41)) }
                if v >= 0x61 && v <= 0x7A { return GGChatTextFonts.scalarString(0x1F130 + (v - 0x61)) }
            }
            return (ch.isLetter || ch.isNumber) ? "\(ch)\u{20DE}" : String(ch)
        case "underline":
            return ch.isWhitespace ? String(ch) : "\(ch)\u{0332}"
        case "double_line":
            return ch.isWhitespace ? String(ch) : "\(ch)\u{0333}"
        case "strike":
            return ch.isWhitespace ? String(ch) : "\(ch)\u{0336}"
        case "slash":
            return ch.isWhitespace ? String(ch) : "\(ch)\u{0337}"
        case "overline":
            return ch.isWhitespace ? String(ch) : "\(ch)\u{0305}"
        case "wave":
            return ch.isWhitespace ? String(ch) : "\(ch)\u{0330}"
        case "glitch":
            guard ch.isLetter || ch.isNumber else {
                return String(ch)
            }
            let mid = GGChatTextFonts.glitchMid[index % GGChatTextFonts.glitchMid.count]
            let code = Int(ch.unicodeScalars.first?.value ?? 0)
            let up = GGChatTextFonts.glitchUp[(index * 3 + code) % GGChatTextFonts.glitchUp.count]
            return "\(ch)\(mid)\(up)"
        case "leet":
            return GGChatTextFonts.leetMap[ch] ?? String(ch)
        case "fence":
            guard ch.isLetter else {
                return String(ch)
            }
            return index % 2 == 0 ? String(ch).uppercased() : String(ch).lowercased()
        case "bold":
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D400, lowerStart: 0x1D41A, digitStart: 0x1D7CE)
        case "italic":
            if ch == "h" { return "\u{210E}" }
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D434, lowerStart: 0x1D44E, digitStart: 0)
        case "bold_italic":
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D468, lowerStart: 0x1D482, digitStart: 0x1D7CE)
        case "sans_bold":
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D5D4, lowerStart: 0x1D5EE, digitStart: 0x1D7EC)
        case "sans_italic":
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D608, lowerStart: 0x1D622, digitStart: 0)
        case "script":
            if let ex = GGChatTextFonts.scriptExceptions[ch] { return ex }
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D49C, lowerStart: 0x1D4B6, digitStart: 0)
        case "bold_script":
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D4D0, lowerStart: 0x1D4EA, digitStart: 0x1D7CE)
        case "fraktur":
            if let ex = GGChatTextFonts.frakturExceptions[ch] { return ex }
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D504, lowerStart: 0x1D51E, digitStart: 0)
        case "bold_fraktur":
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D56C, lowerStart: 0x1D586, digitStart: 0x1D7CE)
        case "double_struck":
            if let ex = GGChatTextFonts.doubleStruckExceptions[ch] { return ex }
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D538, lowerStart: 0x1D552, digitStart: 0x1D7D8)
        case "mono":
            return GGChatTextFonts.mapMath(ch, upperStart: 0x1D670, lowerStart: 0x1D68A, digitStart: 0x1D7F6)
        default:
            return String(ch)
        }
    }

    private static let glitchMid: [String] = ["\u{0334}", "\u{0335}", "\u{0336}", "\u{0337}", "\u{0338}"]
    private static let glitchUp: [String] = ["\u{030D}", "\u{030E}", "\u{0304}", "\u{0305}", "\u{0311}", "\u{0315}", "\u{031A}"]

    private static let scriptExceptions: [Character: String] = [
        "B": "\u{212C}", "E": "\u{2130}", "F": "\u{2131}", "H": "\u{210B}",
        "I": "\u{2110}", "L": "\u{2112}", "M": "\u{2133}", "R": "\u{211B}",
        "e": "\u{212F}", "g": "\u{210A}", "o": "\u{2134}"
    ]

    private static let frakturExceptions: [Character: String] = [
        "C": "\u{212D}", "H": "\u{210C}", "I": "\u{2111}", "R": "\u{211C}", "Z": "\u{2128}"
    ]

    private static let doubleStruckExceptions: [Character: String] = [
        "C": "\u{2102}", "H": "\u{210D}", "N": "\u{2115}", "P": "\u{2119}",
        "Q": "\u{211A}", "R": "\u{211D}", "Z": "\u{2124}"
    ]

    private static let smallCapsMap: [Character: String] = [
        "a": "ᴀ", "b": "ʙ", "c": "ᴄ", "d": "ᴅ", "e": "ᴇ", "f": "ғ",
        "g": "ɢ", "h": "ʜ", "i": "ɪ", "j": "ᴊ", "k": "ᴋ", "l": "ʟ",
        "m": "ᴍ", "n": "ɴ", "o": "ᴏ", "p": "ᴘ", "q": "ǫ", "r": "ʀ",
        "s": "s", "t": "ᴛ", "u": "ᴜ", "v": "ᴠ", "w": "ᴡ", "x": "x",
        "y": "ʏ", "z": "ᴢ",
        "а": "ᴀ", "в": "ʙ", "е": "ᴇ", "ё": "ᴇ\u{0308}", "к": "ᴋ", "м": "ᴍ",
        "н": "ʜ", "о": "ᴏ", "р": "ᴘ", "с": "ᴄ", "т": "ᴛ", "у": "ʏ",
        "А": "ᴀ", "В": "ʙ", "Е": "ᴇ", "Ё": "ᴇ\u{0308}", "К": "ᴋ", "М": "ᴍ",
        "Н": "ʜ", "О": "ᴏ", "Р": "ᴘ", "С": "ᴄ", "Т": "ᴛ", "У": "ʏ"
    ]

    private static let ancientMap: [Character: String] = [
        "Е": "Ѣ", "Ё": "Ѥ", "З": "Ꙁ", "И": "І", "Й": "Ї", "О": "Ѻ",
        "С": "Ѕ", "У": "Ѹ", "Ф": "Ѳ", "Э": "Є", "Я": "Ѧ",
        "е": "ѣ", "ё": "ѥ", "з": "ꙁ", "и": "і", "й": "ї", "о": "ѻ",
        "с": "ѕ", "у": "ѹ", "ф": "ѳ", "э": "є", "я": "ѧ"
    ]

    private static let cyberMap: [Character: String] = [
        "А": "卂", "Б": "Ƃ", "В": "乃", "Г": "厂", "Е": "乇", "Ё": "乇",
        "З": "Ӡ", "К": "长", "Л": "爪", "М": "爪", "Н": "卄", "О": "口",
        "Р": "尺", "С": "匚", "Т": "匕", "У": "ㄚ", "Ф": "中", "Х": "乂",
        "Ш": "山", "Щ": "山",
        "а": "卂", "б": "Ƃ", "в": "乃", "г": "厂", "е": "乇", "ё": "乇",
        "к": "长", "м": "爪", "н": "卄", "о": "口", "р": "尺", "с": "匚",
        "т": "匕", "у": "ㄚ", "ф": "中", "х": "乂", "ш": "山", "щ": "山",
        "A": "卂", "B": "乃", "C": "匚", "D": "刀", "E": "乇", "F": "下",
        "G": "ム", "H": "卄", "I": "工", "J": "丁", "K": "长", "L": "乚",
        "M": "爪", "N": "几", "O": "口", "P": "尸", "Q": "Ɋ", "R": "尺",
        "S": "丂", "T": "匕", "U": "凵", "V": "リ", "W": "山", "X": "乂",
        "Y": "ㄚ", "Z": "乙",
        "a": "卂", "b": "乃", "c": "匚", "d": "刀", "e": "乇", "f": "下",
        "g": "ム", "h": "卄", "i": "工", "j": "丁", "k": "长", "l": "乚",
        "m": "爪", "n": "几", "o": "口", "p": "尸", "q": "Ɋ", "r": "尺",
        "s": "丂", "t": "匕", "u": "凵", "v": "リ", "w": "山", "x": "乂",
        "y": "ㄚ", "z": "乙"
    ]

    private static let runesMap: [Character: String] = [
        "А": "Λ", "Б": "Ƃ", "В": "Β", "Г": "Γ", "Д": "Δ", "Е": "Σ", "Ё": "Σ",
        "З": "Ζ", "К": "Κ", "Л": "Λ", "М": "Μ", "Н": "Η", "О": "Θ", "П": "Π",
        "Р": "Ρ", "С": "Ϲ", "Т": "Τ", "У": "Υ", "Ф": "Φ", "Х": "Χ", "Ц": "Џ",
        "Ш": "Ψ", "Щ": "Ψ", "Э": "Ξ",
        "а": "α", "б": "ɓ", "в": "β", "г": "γ", "д": "δ", "е": "ε", "ё": "ε",
        "з": "ζ", "и": "ι", "к": "κ", "л": "λ", "м": "μ", "н": "η", "о": "σ",
        "п": "π", "р": "ρ", "с": "ς", "т": "τ", "у": "υ", "ф": "φ", "х": "χ",
        "ш": "ω", "щ": "ψ",
        "A": "Λ", "B": "Β", "C": "Ϲ", "D": "Δ", "E": "Σ", "F": "Ғ", "G": "Ǥ",
        "H": "Η", "I": "Ι", "K": "Κ", "L": "Λ", "M": "Μ", "N": "Ν", "O": "Θ",
        "P": "Ρ", "R": "Я", "S": "Ѕ", "T": "Τ", "U": "Ц", "W": "Ψ", "X": "Χ",
        "Y": "Υ", "Z": "Ζ",
        "a": "α", "b": "β", "c": "ς", "d": "δ", "e": "ε", "g": "γ", "h": "η",
        "i": "ι", "k": "κ", "l": "λ", "m": "μ", "n": "η", "o": "σ", "p": "ρ",
        "r": "г", "s": "ѕ", "t": "τ", "u": "υ", "v": "ν", "w": "ω", "x": "χ",
        "y": "γ", "z": "ζ"
    ]

    private static let leetMap: [Character: String] = [
        "А": "4", "а": "4", "В": "8", "в": "8", "Е": "3", "е": "3", "Ё": "3", "ё": "3",
        "З": "3", "з": "3", "И": "1", "и": "1", "О": "0", "о": "0", "С": "(", "с": "(",
        "Т": "7", "т": "7", "Ч": "4", "ч": "4",
        "A": "4", "a": "4", "B": "8", "b": "8", "E": "3", "e": "3", "G": "6", "g": "9",
        "I": "1", "i": "1", "L": "1", "l": "1", "O": "0", "o": "0", "S": "5", "s": "5",
        "T": "7", "t": "7", "Z": "2", "z": "2"
    ]

    private static let upsideMap: [Character: String] = [
        "a": "ɐ", "b": "q", "c": "ɔ", "d": "p", "e": "ǝ", "f": "ɟ", "g": "ƃ",
        "h": "ɥ", "i": "ᴉ", "j": "ɾ", "k": "ʞ", "l": "ן", "m": "ɯ", "n": "u",
        "o": "o", "p": "d", "q": "b", "r": "ɹ", "s": "s", "t": "ʇ", "u": "n",
        "v": "ʌ", "w": "ʍ", "x": "x", "y": "ʎ", "z": "z",
        "A": "∀", "C": "Ɔ", "D": "◖", "E": "Ǝ", "F": "Ⅎ", "G": "⅁", "J": "ſ",
        "K": "⋊", "L": "˥", "M": "W", "P": "Ԁ", "Q": "Ό", "R": "ᴚ", "T": "⊥",
        "U": "∩", "V": "Λ", "W": "M", "Y": "⅄",
        "а": "ɐ", "б": "ƍ", "в": "ʚ", "г": "ɹ", "д": "ɓ", "е": "ǝ", "ё": "ǝ",
        "з": "ε", "к": "ʞ", "л": "v", "м": "w", "п": "u", "р": "d", "с": "ɔ",
        "т": "ɯ", "у": "ʎ", "ц": "ǹ", "ч": "Һ", "ш": "m", "щ": "m", "ы": "ıq",
        "э": "є", "ю": "oı", "я": "ʁ",
        "А": "∀", "В": "ꓭ", "Г": "⅃", "Е": "Ǝ", "З": "Ɛ", "К": "⋊", "Л": "V",
        "М": "W", "П": "U", "Р": "Ԁ", "С": "Ɔ", "Т": "⊥", "У": "⅄", "Ш": "M",
        "Я": "ʁ", "!": "¡", "?": "¿", ".": "˙", ",": "'", "(": ")", ")": "("
    ]
}
