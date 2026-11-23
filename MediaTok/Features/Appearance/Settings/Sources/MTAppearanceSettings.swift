import Foundation
import MTCore

/// Every appearance setting of MediaTok, declared once. Kept in its own small
/// module (MTCore only) so the upstream modules that draw them — down to the bubble background, which
/// sits below TelegramCore — read the same registry the menu writes.
///
/// Cells and layout never read these one by one on their hot paths: they read the immutable
/// `MTAppearanceSnapshot.current`, rebuilt once per change.
public enum MTAppearanceSettings {
    // MARK: Font (applied at launch: upstream keeps fonts in file-scope constants)

    /// `MTFontFamily.rawValue`; "system" = Telegram's font. Or "custom:<file>" — a font the user
    /// added. Any other value reads as "system".
    public static let fontFamily = MTSetting<String>("appearance.font.family", default: "system", flags: [.requiresRestart])
    /// Fonts the user added from Files, in the order added: "<file name>\t<family name>". The files
    /// live in the app's container (Application Support/mediatok/appearance/userFonts).
    /// Not exported: the files stay on this device.
    public static let customFonts = MTSetting<[String]>("appearance.font.custom", default: [], flags: [.noExport])
    /// Outgoing stylish chat text font ID (Unicode / Cyrillic styles visible to everyone in Telegram); "" = off.
    public static let chatTextFont = MTSetting<String>("appearance.font.chatTextStyle", default: "")

    // MARK: Bubbles

    public static let bubbleEditor = MTSetting<Bool>("appearance.bubbles.editor", default: false)
    public static let bubbleIncomingRadius = MTSetting<Double>("appearance.bubbles.incomingRadius", default: 16.0)
    public static let bubbleOutgoingRadius = MTSetting<Double>("appearance.bubbles.outgoingRadius", default: 16.0)
    /// Horizontal text inset inside a bubble, pt.
    public static let bubblePadding = MTSetting<Double>("appearance.bubbles.padding", default: 11.0)
    /// Share of the upstream maximum bubble width, %.
    public static let bubbleWidth = MTSetting<Double>("appearance.bubbles.width", default: 100.0)
    public static let bubbleBackgroundOpacity = MTSetting<Double>("appearance.bubbles.backgroundOpacity", default: 100.0)
    public static let bubbleOutlineOpacity = MTSetting<Double>("appearance.bubbles.outlineOpacity", default: 0.0)
    public static let bubbleHideTails = MTSetting<Bool>("appearance.bubbles.hideTails", default: false)

    // MARK: Checkmarks ("" = the theme's color)

    public static let readCheckColor = MTSetting<String>("appearance.checkmarks.readColor", default: "")
    public static let unreadCheckColor = MTSetting<String>("appearance.checkmarks.unreadColor", default: "")
    public static let unreadCheckSameAsRead = MTSetting<Bool>("appearance.checkmarks.unreadSameAsRead", default: false)
    public static let checkColorsInChatList = MTSetting<Bool>("appearance.checkmarks.inChatList", default: false)

    // MARK: Stickers

    /// %, 50…200 (bigger than 100 since 2026-10-27; a big sticker still fits the chat's width).
    public static let stickerSize = MTSetting<Double>("appearance.stickers.size", default: 100.0)
    public static let stickerHideTime = MTSetting<Bool>("appearance.stickers.hideTime", default: false)

    // MARK: Messages

    public static let wideChannelPosts = MTSetting<Bool>("appearance.messages.wideChannelPosts", default: false)
    public static let secondsInTime = MTSetting<Bool>("appearance.messages.secondsInTime", default: false)
    /// `MTHiddenReactions.rawValue` (one choice since 2026-10-27; replaced «…in chats» / «…in channels»).
    public static let hideReactions = MTSetting<String>("appearance.messages.hideReactions", default: MTHiddenReactions.off.rawValue)
    public static let hideEdited = MTSetting<Bool>("appearance.messages.hideEdited", default: false)
    public static let hideTime = MTSetting<Bool>("appearance.messages.hideTime", default: false)
    /// `MTHiddenFormatting.rawValue` (one choice since 2026-10-27; replaced «…incoming» / «…own»).
    public static let hideFormatting = MTSetting<String>("appearance.messages.hideFormatting", default: MTHiddenFormatting.off.rawValue)
    public static let hideChannelComments = MTSetting<Bool>("appearance.messages.hideChannelComments", default: false)
    public static let hideViewCounts = MTSetting<Bool>("appearance.messages.hideViewCounts", default: false)
    public static let colorSwatches = MTSetting<Bool>("appearance.messages.colorSwatches", default: false)
    public static let authorOnlineIndicator = MTSetting<Bool>("appearance.messages.authorOnline", default: false)
    public static let exactLastSeen = MTSetting<Bool>("appearance.messages.exactLastSeen", default: false)
    /// `MTTripleTapDelete.rawValue`.
    public static let tripleTapDelete = MTSetting<String>("appearance.messages.tripleTapDelete", default: "off")
    public static let noSelectionBlur = MTSetting<Bool>("appearance.messages.noSelectionBlur", default: false)

    // MARK: Chat top bar

    public static let hideBackButton = MTSetting<Bool>("appearance.chatTopBar.hideBackButton", default: false)
    public static let hideTitlePanel = MTSetting<Bool>("appearance.chatTopBar.hideTitle", default: false)
    public static let hideAvatar = MTSetting<Bool>("appearance.chatTopBar.hideAvatar", default: false)
    public static let hidePinnedMessages = MTSetting<Bool>("appearance.chatTopBar.hidePinned", default: false)

    // MARK: Theme

    public static let amoled = MTSetting<Bool>("appearance.theme.amoled", default: false)
    public static let amoledKeyboard = MTSetting<Bool>("appearance.theme.amoledKeyboard", default: false)
    public static let hideSeparators = MTSetting<Bool>("appearance.theme.hideSeparators", default: false)
    /// %, 0…100; 100 = the server's colors.
    public static let nameColorSaturation = MTSetting<Double>("appearance.theme.nameSaturation", default: 100.0)

    // MARK: Screen edges («Затемнение краёв»: one group since 2026-10-27 instead of blur + gradient)

    /// `MTEdgeStyle.rawValue`.
    public static let edgeStyle = MTSetting<String>("appearance.edges.style", default: MTEdgeStyle.off.rawValue)
    /// "" = automatic (the theme's background).
    public static let edgeColor = MTSetting<String>("appearance.edges.color", default: "")
    /// pt, `MTEdgeStyle.sizeRange`.
    public static let edgeSize = MTSetting<Double>("appearance.edges.size", default: MTEdgeStyle.defaultSize)
    /// %, 0…100.
    public static let edgeIntensity = MTSetting<Double>("appearance.edges.intensity", default: MTEdgeStyle.defaultIntensity)
    /// The gradient only (the blur is never drawn in the chat list).
    public static let edgeHideInChatList = MTSetting<Bool>("appearance.edges.hideInChatList", default: false)

    // MARK: Animated backgrounds (files live in the app container; settings keep only a version)

    public static let chatBackground = MTSetting<Bool>("appearance.chatBackground.enabled", default: false)
    public static let chatBackgroundOpacity = MTSetting<Double>("appearance.chatBackground.opacity", default: 30.0)
    /// Version of the converted file; 0 = none. Bumps on every new pick so players reload.
    public static let chatBackgroundVersion = MTSetting<Int>("appearance.chatBackground.version", default: 0, flags: [.noExport])
    public static let profileBackground = MTSetting<Bool>("appearance.profileBackground.enabled", default: false)
    public static let profileBackgroundOpacity = MTSetting<Double>("appearance.profileBackground.opacity", default: 50.0)
    public static let profileBackgroundVersion = MTSetting<Int>("appearance.profileBackground.version", default: 0, flags: [.noExport])

    // MARK: Snowfall (also the former «New Year» wallpaper effect)

    public static let snow = MTSetting<Bool>("appearance.snow.enabled", default: false)
    /// `MTSnowStyle.rawValue`.
    public static let snowStyle = MTSetting<String>("appearance.snow.style", default: "snow")
    /// %, 10…100.
    public static let snowIntensity = MTSetting<Double>("appearance.snow.intensity", default: 100.0)
    public static let snowHideInChats = MTSetting<Bool>("appearance.snow.hideInChats", default: false)

    // MARK: Profile

    /// On by default, as Swiftgram's `showProfileId` (MediaTok,.
    public static let profileShowId = MTSetting<Bool>("appearance.profile.showId", default: true)
    public static let profileShowDataCenter = MTSetting<Bool>("appearance.profile.showDataCenter", default: false)
    /// On by default: Swiftgram's `showCreationDate` is on, and its «mutual contact» and «joined» rows
    /// have no switch at all.
    public static let profileShowDates = MTSetting<Bool>("appearance.profile.showDates", default: true)
    public static let profileHideDescription = MTSetting<Bool>("appearance.profile.hideDescription", default: false)
    public static let profileHideShareButton = MTSetting<Bool>("appearance.profile.hideShareButton", default: false)
    public static let profileHideStarRating = MTSetting<Bool>("appearance.profile.hideStarRating", default: false)

    /// Touches every declaration so the registry knows them before export, search and migrations.
    public static func declare() {
        let _ = MTAppearanceSettings.fontFamily
        let _ = MTAppearanceSettings.customFonts
        let _ = MTAppearanceSettings.chatTextFont
        let _ = MTAppearanceSettings.bubbleEditor
        let _ = MTAppearanceSettings.bubbleIncomingRadius
        let _ = MTAppearanceSettings.bubbleOutgoingRadius
        let _ = MTAppearanceSettings.bubblePadding
        let _ = MTAppearanceSettings.bubbleWidth
        let _ = MTAppearanceSettings.bubbleBackgroundOpacity
        let _ = MTAppearanceSettings.bubbleOutlineOpacity
        let _ = MTAppearanceSettings.bubbleHideTails
        let _ = MTAppearanceSettings.readCheckColor
        let _ = MTAppearanceSettings.unreadCheckColor
        let _ = MTAppearanceSettings.unreadCheckSameAsRead
        let _ = MTAppearanceSettings.checkColorsInChatList
        let _ = MTAppearanceSettings.stickerSize
        let _ = MTAppearanceSettings.stickerHideTime
        let _ = MTAppearanceSettings.wideChannelPosts
        let _ = MTAppearanceSettings.secondsInTime
        let _ = MTAppearanceSettings.hideReactions
        let _ = MTAppearanceSettings.hideEdited
        let _ = MTAppearanceSettings.hideTime
        let _ = MTAppearanceSettings.hideFormatting
        let _ = MTAppearanceSettings.hideChannelComments
        let _ = MTAppearanceSettings.hideViewCounts
        let _ = MTAppearanceSettings.colorSwatches
        let _ = MTAppearanceSettings.authorOnlineIndicator
        let _ = MTAppearanceSettings.exactLastSeen
        let _ = MTAppearanceSettings.tripleTapDelete
        let _ = MTAppearanceSettings.noSelectionBlur
        let _ = MTAppearanceSettings.hideBackButton
        let _ = MTAppearanceSettings.hideTitlePanel
        let _ = MTAppearanceSettings.hideAvatar
        let _ = MTAppearanceSettings.hidePinnedMessages
        let _ = MTAppearanceSettings.amoled
        let _ = MTAppearanceSettings.amoledKeyboard
        let _ = MTAppearanceSettings.hideSeparators
        let _ = MTAppearanceSettings.nameColorSaturation
        let _ = MTAppearanceSettings.edgeStyle
        let _ = MTAppearanceSettings.edgeColor
        let _ = MTAppearanceSettings.edgeSize
        let _ = MTAppearanceSettings.edgeIntensity
        let _ = MTAppearanceSettings.edgeHideInChatList
        let _ = MTAppearanceSettings.chatBackground
        let _ = MTAppearanceSettings.chatBackgroundOpacity
        let _ = MTAppearanceSettings.chatBackgroundVersion
        let _ = MTAppearanceSettings.profileBackground
        let _ = MTAppearanceSettings.profileBackgroundOpacity
        let _ = MTAppearanceSettings.profileBackgroundVersion
        let _ = MTAppearanceSettings.snow
        let _ = MTAppearanceSettings.snowStyle
        let _ = MTAppearanceSettings.snowIntensity
        let _ = MTAppearanceSettings.snowHideInChats
        let _ = MTAppearanceSettings.profileShowId
        let _ = MTAppearanceSettings.profileShowDataCenter
        let _ = MTAppearanceSettings.profileShowDates
        let _ = MTAppearanceSettings.profileHideDescription
        let _ = MTAppearanceSettings.profileHideShareButton
        let _ = MTAppearanceSettings.profileHideStarRating
    }
}

/// The fonts offered in the menu: the system font, its designs and families preinstalled in iOS 15+
///. Fonts the user adds are not cases here: they are
/// "custom:<file>" values of `appearance.font.family`. The raw values are stored in
/// `appearance.font.family`; the legacy MediaTok values (bundled free fonts, «imported») are not
/// among them and read as `.system`.
public enum MTFontFamily: String, CaseIterable {
    /// Telegram's font (SF Pro): no substitution at all.
    case system
    // Designs of the system font.
    case rounded
    case serif
    case monospaced
    // Families preinstalled in iOS; the menu lists them in this order (with Cyrillic first).
    case helveticaNeue
    case arial
    case avenirNext
    case gillSans
    case trebuchet
    case verdana
    case georgia
    case timesNewRoman
    case palatino
    case baskerville
    case charter
    case cochin
    case hoeflerText
    case iowanOldStyle
    case rockwell
    case americanTypewriter
    case markerFelt
    case noteworthy
    case chalkboard
    case menlo
    case courierNew
    case futura
    case optima
    case didot
    case bodoni

    /// The stored value as a family; anything unknown (a removed font) is the system font.
    public static func resolved(_ rawValue: String) -> MTFontFamily {
        return MTFontFamily(rawValue: rawValue) ?? .system
    }
}

public enum MTTripleTapDelete: String {
    case off
    case local
    case everyone
}

public enum MTSnowStyle: String {
    case snow
    case lightning
}

/// "RRGGBB" / "#RRGGBB" → 0xRRGGBB; nil for "" and anything malformed.
public func mtAppearanceParseColor(_ value: String) -> UInt32? {
    var text = value.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") {
        text.removeFirst()
    }
    if text.count != 6 {
        return nil
    }
    return UInt32(text, radix: 16)
}

/// 0xRRGGBB → "RRGGBB".
public func mtAppearanceColorString(_ rgb: UInt32) -> String {
    return String(format: "%06X", Int(rgb & 0xffffff))
}
