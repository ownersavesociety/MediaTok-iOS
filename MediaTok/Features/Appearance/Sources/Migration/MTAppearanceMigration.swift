import Foundation
import MTCore
import MTAppearanceSettings

/// One-time move of the legacy MediaTok appearance settings (three stores: `FontCustomization.*` /
/// `GG.fontCustomization.*`, `GG.checkmark.*`, and the MediaTok keys parked in SGSimpleSettings)
/// into the registry. Only values the user actually stored are moved: an absent key
/// leaves the new default (toggles off). Old «show …» toggles that were ON by default became
/// «hide …» toggles that are OFF by default.
///
/// Dead keys are not moved: `readStatusColor*` (no consumer), the `chatListGradient*` switches
/// (the gradient never painted; its color, size and strength only fill the one edge group when the
/// blur's are absent). The glass settings (`GG.liquidGlass*`) are not moved at all: the feature was
/// removed, its keys only go (`appearance.glass.removed.v1`).
enum MTAppearanceMigration {
    static func register() {
        MTMigrations.registerGlobal(id: "appearance.v1") { legacy in
            MTAppearanceMigration.moveBubbles(legacy)
            MTAppearanceMigration.moveCheckmarks(legacy)
            MTAppearanceMigration.moveMessages(legacy)
            MTAppearanceMigration.moveTheme(legacy)
            MTAppearanceMigration.moveEdges(legacy)
            MTAppearanceMigration.moveBackgrounds(legacy)
            MTAppearanceMigration.moveProfile(legacy)
        }
        MTMigrations.registerGlobal(id: "appearance.font.v2") { legacy in
            MTAppearanceMigration.dropRemovedFonts(legacy)
        }
        MTMigrations.registerGlobal(id: "appearance.merge.v1") { _ in
            MTAppearanceMigration.mergeRetiredSettings()
        }
        // «Стекло» (Liquid Glass) was removed by the owner on 2026-10-27, its upstream edits went back
        // to upstream. Whatever it stored goes once: legacy format keys and this app's
        // `appearance.glass.*` (build 185 and earlier).
        MTMigrations.registerGlobal(id: "appearance.glass.removed.v1") { legacy in
            for key in MTAppearanceMigration.removedGlassLegacyKeys {
                legacy.removeLegacyKey(key)
            }
            MTRetiredSettings.remove(prefixes: ["appearance.glass."])
        }
    }

    /// legacy format glass keys: its raw `UserDefaults` switches and the Swiftgram key of the system
    /// glass (`SGSimpleSettings.systemLiquidGlassEnabled` used the same name).
    static let removedGlassLegacyKeys: [String] = [
        "GG.liquidGlass", "GG.liquidGlassIntensity", "GG.liquidGlass.tintColor", "GG.liquidGlass.cornerRadius",
        "GG.liquidGlass.disableBlur", "GG.liquidGlass.disableShadow", "GG.liquidGlass.disableHighlight",
        "GG.liquidGlass.tabBar", "GG.liquidGlass.navBar", "GG.liquidGlass.search", "GG.liquidGlass.chatInput",
        "GG.liquidGlass.chatButtons", "GG.systemLiquidGlass.enabled"
    ]

    /// Builds ≤ 185 had two switches for hidden reactions, two for hidden formatting and nine rows
    /// of screen edges; since 2026-10-27 each is one setting (`MTAppearanceChoices.swift`). Their
    /// stored values are carried over once, then dropped from the settings file.
    static let retiredKeys: [String] = [
        "appearance.messages.hideReactionsInChats", "appearance.messages.hideReactionsInChannels",
        "appearance.messages.hideIncomingFormatting", "appearance.messages.hideOutgoingFormatting",
        "appearance.edges.blur", "appearance.edges.blurColor", "appearance.edges.blurSize", "appearance.edges.blurIntensity",
        "appearance.edges.gradient", "appearance.edges.gradientColor", "appearance.edges.gradientSize",
        "appearance.edges.gradientIntensity", "appearance.edges.gradientHideInChatList"
    ]

    private static func mergeRetiredSettings() {
        if let value = MTHiddenReactions.merged(inChats: MTRetiredSettings.value("appearance.messages.hideReactionsInChats", as: Bool.self), inChannels: MTRetiredSettings.value("appearance.messages.hideReactionsInChannels", as: Bool.self)) {
            MTAppearanceSettings.hideReactions.set(value.rawValue)
        }
        if let value = MTHiddenFormatting.merged(inIncoming: MTRetiredSettings.value("appearance.messages.hideIncomingFormatting", as: Bool.self), inOutgoing: MTRetiredSettings.value("appearance.messages.hideOutgoingFormatting", as: Bool.self)) {
            MTAppearanceSettings.hideFormatting.set(value.rawValue)
        }
        var old = MTEdgeMerge.Old()
        old.blur = MTRetiredSettings.value("appearance.edges.blur", as: Bool.self)
        old.blurColor = MTRetiredSettings.value("appearance.edges.blurColor", as: String.self)
        old.blurSize = MTRetiredSettings.value("appearance.edges.blurSize", as: Double.self)
        old.blurIntensity = MTRetiredSettings.value("appearance.edges.blurIntensity", as: Double.self)
        old.gradient = MTRetiredSettings.value("appearance.edges.gradient", as: Bool.self)
        old.gradientColor = MTRetiredSettings.value("appearance.edges.gradientColor", as: String.self)
        old.gradientSize = MTRetiredSettings.value("appearance.edges.gradientSize", as: Double.self)
        old.gradientIntensity = MTRetiredSettings.value("appearance.edges.gradientIntensity", as: Double.self)
        old.gradientHideInChatList = MTRetiredSettings.value("appearance.edges.gradientHideInChatList", as: Bool.self)
        if let merge = MTEdgeMerge.merged(old) {
            MTAppearanceMigration.apply(merge)
        }
        MTRetiredSettings.remove(keys: MTAppearanceMigration.retiredKeys)
    }

    private static func apply(_ merge: MTEdgeMerge) {
        if merge.style != .off {
            MTAppearanceSettings.edgeStyle.set(merge.style.rawValue)
        }
        if let color = merge.color, let rgb = mtAppearanceParseColor(color) {
            MTAppearanceSettings.edgeColor.set(mtAppearanceColorString(rgb))
        }
        if let size = merge.size {
            MTAppearanceSettings.edgeSize.set(size)
        }
        if let intensity = merge.intensity {
            MTAppearanceSettings.edgeIntensity.set(intensity)
        }
        if let hideInChatList = merge.hideInChatList {
            MTAppearanceSettings.edgeHideInChatList.set(hideInChatList)
        }
    }

    // MARK: Helpers

    private static func bool(_ legacy: MTLegacyDefaults, _ key: String, to setting: MTSetting<Bool>, inverted: Bool = false) {
        if let value = legacy.bool(key) {
            setting.set(inverted ? !value : value)
            legacy.removeLegacyKey(key)
        }
    }

    private static func double(_ legacy: MTLegacyDefaults, _ key: String, to setting: MTSetting<Double>, range: ClosedRange<Double>) {
        if let value = legacy.double(key) {
            setting.set(min(range.upperBound, max(range.lowerBound, value)))
            legacy.removeLegacyKey(key)
        }
    }

    /// The old checkmark colors were stored as `[r, g, b, a]` doubles.
    private static func rgbaColor(_ legacy: MTLegacyDefaults, _ key: String) -> String? {
        guard let components = legacy.object(key) as? [NSNumber], components.count >= 3 else {
            return nil
        }
        let r = UInt32(max(0.0, min(1.0, components[0].doubleValue)) * 255.0)
        let g = UInt32(max(0.0, min(1.0, components[1].doubleValue)) * 255.0)
        let b = UInt32(max(0.0, min(1.0, components[2].doubleValue)) * 255.0)
        return mtAppearanceColorString((r << 16) | (g << 8) | b)
    }

    /// The old code stored absolute paths, which break when iOS moves the app container: the same
    /// file name is looked up in Documents as well.
    static func legacyFile(_ path: String) -> URL? {
        if path.isEmpty {
            return nil
        }
        if FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty, let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let candidate = documents.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Deletes a leftover directory off the main thread (migrations run on it at launch).
    static func removeInBackground(_ url: URL) {
        DispatchQueue.global(qos: .utility).async {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: Groups

    /// Fonts are only the ones that ship with iOS, so no font value is
    /// carried over; whatever pointed at a removed font goes:
    /// - the legacy MediaTok keys (it offered only its bundled free fonts and an imported file; the
    ///   last one is its «show fonts» list state) and `Documents/Fonts`, where its import copied every
    ///   picked file and never deleted one;
    /// - a family stored by an earlier build of this app (a removed bundled font, «imported») → the
    ///   system font (the default), and that build's directory of imported fonts.
    private static func dropRemovedFonts(_ legacy: MTLegacyDefaults) {
        for key in ["FontCustomization.isEnabled", "FontCustomization.selectedFont", "FontCustomization.isCustomSelected", "FontCustomization.importedFontPath", "FontCustomization.importedFontName", "FontCustomizationController.fontsExpanded"] {
            legacy.removeLegacyKey(key)
        }
        if MTFontFamily(rawValue: MTAppearanceSettings.fontFamily.value) == nil && !MTCustomFonts.isCustomValue(MTAppearanceSettings.fontFamily.value) {
            MTAppearanceSettings.fontFamily.reset()
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            MTAppearanceMigration.removeInBackground(documents.appendingPathComponent("Fonts", isDirectory: true))
        }
        if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            MTAppearanceMigration.removeInBackground(applicationSupport.appendingPathComponent("mediatok/appearance/fonts", isDirectory: true))
        }
    }

    private static func moveBubbles(_ legacy: MTLegacyDefaults) {
        MTAppearanceMigration.bool(legacy, "bubbleEditorEnabled", to: MTAppearanceSettings.bubbleEditor)
        MTAppearanceMigration.double(legacy, "bubbleIncomingRadius", to: MTAppearanceSettings.bubbleIncomingRadius, range: 0.0 ... 16.0)
        MTAppearanceMigration.double(legacy, "bubbleOutgoingRadius", to: MTAppearanceSettings.bubbleOutgoingRadius, range: 0.0 ... 16.0)
        MTAppearanceMigration.double(legacy, "bubblePadding", to: MTAppearanceSettings.bubblePadding, range: 0.0 ... 24.0)
        MTAppearanceMigration.double(legacy, "bubbleWidthPercent", to: MTAppearanceSettings.bubbleWidth, range: 40.0 ... 100.0)
        MTAppearanceMigration.double(legacy, "bubbleBackgroundOpacity", to: MTAppearanceSettings.bubbleBackgroundOpacity, range: 0.0 ... 100.0)
        MTAppearanceMigration.double(legacy, "bubbleOutlineOpacity", to: MTAppearanceSettings.bubbleOutlineOpacity, range: 0.0 ... 100.0)
        MTAppearanceMigration.bool(legacy, "bubbleHasTails", to: MTAppearanceSettings.bubbleHideTails, inverted: true)
    }

    private static func moveCheckmarks(_ legacy: MTLegacyDefaults) {
        if legacy.bool("GG.checkmark.useCustomReadColor") == true, let color = MTAppearanceMigration.rgbaColor(legacy, "GG.checkmark.readColor") {
            MTAppearanceSettings.readCheckColor.set(color)
        }
        if legacy.bool("GG.checkmark.useCustomUnreadColor") == true, let color = MTAppearanceMigration.rgbaColor(legacy, "GG.checkmark.unreadColor") {
            MTAppearanceSettings.unreadCheckColor.set(color)
        }
        MTAppearanceMigration.bool(legacy, "GG.checkmark.useReadColorForUnread", to: MTAppearanceSettings.unreadCheckSameAsRead)
        MTAppearanceMigration.bool(legacy, "GG.checkmark.applyInChatList", to: MTAppearanceSettings.checkColorsInChatList)
        for key in ["GG.checkmark.useCustomReadColor", "GG.checkmark.readColor", "GG.checkmark.useCustomUnreadColor", "GG.checkmark.unreadColor"] {
            legacy.removeLegacyKey(key)
        }
    }

    private static func moveMessages(_ legacy: MTLegacyDefaults) {
        MTAppearanceMigration.bool(legacy, "FontCustomization.showExactLastSeen", to: MTAppearanceSettings.exactLastSeen)
        // Hidden formatting and hidden reactions are one choice each since 2026-10-27.
        if let value = MTHiddenFormatting.merged(inIncoming: legacy.bool("FontCustomization.hideIncomingTextFormatting"), inOutgoing: legacy.bool("FontCustomization.hideOutgoingTextFormatting")) {
            MTAppearanceSettings.hideFormatting.set(value.rawValue)
        }
        legacy.removeLegacyKey("FontCustomization.hideIncomingTextFormatting")
        legacy.removeLegacyKey("FontCustomization.hideOutgoingTextFormatting")
        MTAppearanceMigration.bool(legacy, "FontCustomization.hideChannelComments", to: MTAppearanceSettings.hideChannelComments)
        MTAppearanceMigration.bool(legacy, "FontCustomization.hideChannelViewCounts", to: MTAppearanceSettings.hideViewCounts)
        MTAppearanceMigration.bool(legacy, "FontCustomization.hideMessageTimestamps", to: MTAppearanceSettings.hideTime)
        MTAppearanceMigration.bool(legacy, "FontCustomization.hideEditedStatus", to: MTAppearanceSettings.hideEdited)
        MTAppearanceMigration.bool(legacy, "FontCustomization.chatAvatarOnlineIndicator", to: MTAppearanceSettings.authorOnlineIndicator)
        if let mode = legacy.string("GG.fontCustomization.tripleTapDeleteMode") {
            switch mode {
            case "local":
                MTAppearanceSettings.tripleTapDelete.set(MTTripleTapDelete.local.rawValue)
            case "everyone":
                MTAppearanceSettings.tripleTapDelete.set(MTTripleTapDelete.everyone.rawValue)
            default:
                break
            }
            legacy.removeLegacyKey("GG.fontCustomization.tripleTapDeleteMode")
        }
        MTAppearanceMigration.bool(legacy, "FontCustomization.showChatTopBarBackButton", to: MTAppearanceSettings.hideBackButton, inverted: true)
        MTAppearanceMigration.bool(legacy, "FontCustomization.showChatTopBarTitlePanel", to: MTAppearanceSettings.hideTitlePanel, inverted: true)
        MTAppearanceMigration.bool(legacy, "FontCustomization.showChatTopBarAvatar", to: MTAppearanceSettings.hideAvatar, inverted: true)
        MTAppearanceMigration.bool(legacy, "FontCustomization.showChatTopBarPinnedMessages", to: MTAppearanceSettings.hidePinnedMessages, inverted: true)
        MTAppearanceMigration.bool(legacy, "disableBlurOnMessageSelection", to: MTAppearanceSettings.noSelectionBlur)
        MTAppearanceMigration.bool(legacy, "wideChannelPosts", to: MTAppearanceSettings.wideChannelPosts)
        MTAppearanceMigration.bool(legacy, "secondsInMessages", to: MTAppearanceSettings.secondsInTime)
        // The old Swiftgram key meant both places; it is older, so the specific keys win.
        let hideEverywhere: Bool? = legacy.bool("hideReactions") == true ? true : nil
        if let value = MTHiddenReactions.merged(inChats: legacy.bool("hideReactionsInChats") ?? hideEverywhere, inChannels: legacy.bool("hideReactionsInChannels") ?? hideEverywhere) {
            MTAppearanceSettings.hideReactions.set(value.rawValue)
        }
        for key in ["hideReactions", "hideReactionsInChats", "hideReactionsInChannels"] {
            legacy.removeLegacyKey(key)
        }
        MTAppearanceMigration.double(legacy, "stickerSize", to: MTAppearanceSettings.stickerSize, range: 50.0 ... 100.0)
        MTAppearanceMigration.bool(legacy, "stickerTimestamp", to: MTAppearanceSettings.stickerHideTime, inverted: true)
    }

    private static func moveTheme(_ legacy: MTLegacyDefaults) {
        MTAppearanceMigration.bool(legacy, "GG.fontCustomization.amoledTrueBlack", to: MTAppearanceSettings.amoled)
        MTAppearanceMigration.bool(legacy, "GG.fontCustomization.amoledKeyboard", to: MTAppearanceSettings.amoledKeyboard)
        MTAppearanceMigration.bool(legacy, "GG.fontCustomization.hideCellSeparators", to: MTAppearanceSettings.hideSeparators)
        MTAppearanceMigration.double(legacy, "accountColorsSaturation", to: MTAppearanceSettings.nameColorSaturation, range: 0.0 ... 100.0)
        MTAppearanceMigration.bool(legacy, "GG.fontCustomization.snowflakes", to: MTAppearanceSettings.snow)
        MTAppearanceMigration.double(legacy, "GG.fontCustomization.snowflakesIntensity", to: MTAppearanceSettings.snowIntensity, range: 10.0 ... 100.0)
        MTAppearanceMigration.bool(legacy, "GG.fontCustomization.snowflakesInChat", to: MTAppearanceSettings.snowHideInChats, inverted: true)
        // Swiftgram's New Year effect needed its server to switch on; its style is kept.
        if let style = legacy.string("nyStyle") {
            if style == "lightning" {
                MTAppearanceSettings.snowStyle.set(MTSnowStyle.lightning.rawValue)
            }
            legacy.removeLegacyKey("nyStyle")
        }
    }

    /// The old switches are not carried over (the blur was on by default, the gradient never
    /// painted): only the values, into the one group «Затемнение краёв» — the blur's first.
    private static func moveEdges(_ legacy: MTLegacyDefaults) {
        var old = MTEdgeMerge.Old()
        old.blurColor = MTAppearanceMigration.legacyColor(legacy, "chatBlurColor", autoKey: "chatBlurAutoColor")
        old.blurSize = legacy.double("chatBlurSize")
        old.blurIntensity = legacy.double("chatBlurIntensity")
        old.gradientColor = MTAppearanceMigration.legacyColor(legacy, "chatListGradientColor", autoKey: "chatListGradientAutoColor")
        old.gradientSize = legacy.double("chatListGradientSize")
        old.gradientIntensity = legacy.double("chatListGradientIntensity")
        old.gradientHideInChatList = legacy.bool("chatListGradientInChatList").map { !$0 }
        if let merge = MTEdgeMerge.merged(old) {
            MTAppearanceMigration.apply(merge)
        }
        for key in ["displayBlurInChats", "chatBlurAutoColor", "chatBlurColor", "chatBlurSize", "chatBlurIntensity", "chatListGradientEnabled", "chatListGradientAutoColor", "chatListGradientColor", "chatListGradientSize", "chatListGradientIntensity", "chatListGradientInChatList"] {
            legacy.removeLegacyKey(key)
        }
    }

    /// An old color is used only when its «automatic» switch was off.
    private static func legacyColor(_ legacy: MTLegacyDefaults, _ key: String, autoKey: String) -> String? {
        guard legacy.bool(autoKey) == false, let value = legacy.string(key), let rgb = mtAppearanceParseColor(value) else {
            return nil
        }
        return mtAppearanceColorString(rgb)
    }

    private static func moveBackgrounds(_ legacy: MTLegacyDefaults) {
        MTAppearanceMigration.double(legacy, "gifWallpaperOpacity", to: MTAppearanceSettings.chatBackgroundOpacity, range: 5.0 ... 100.0)
        MTAppearanceMigration.double(legacy, "profileGifOpacity", to: MTAppearanceSettings.profileBackgroundOpacity, range: 5.0 ... 100.0)
        // Old files are converted in the background; the background switches on when ready.
        if legacy.bool("gifWallpaperEnabled") == true, let path = legacy.string("gifWallpaperPath"), let url = MTAppearanceMigration.legacyFile(path) {
            MTAnimatedBackgrounds.importFile(at: url, kind: .chat, completion: { _ in })
        }
        if legacy.bool("profileGifEnabled") == true, let path = legacy.string("profileGifPath"), let url = MTAppearanceMigration.legacyFile(path) {
            MTAnimatedBackgrounds.importFile(at: url, kind: .profile, completion: { _ in })
        }
        for key in ["gifWallpaperEnabled", "gifWallpaperPath", "profileGifEnabled", "profileGifPath"] {
            legacy.removeLegacyKey(key)
        }
    }

    private static func moveProfile(_ legacy: MTLegacyDefaults) {
        MTAppearanceMigration.bool(legacy, "showProfileId", to: MTAppearanceSettings.profileShowId)
        MTAppearanceMigration.bool(legacy, "showDC", to: MTAppearanceSettings.profileShowDataCenter)
        MTAppearanceMigration.bool(legacy, "showCreationDate", to: MTAppearanceSettings.profileShowDates)
        MTAppearanceMigration.bool(legacy, "GG.fontCustomization.hideProfileDescription", to: MTAppearanceSettings.profileHideDescription)
        MTAppearanceMigration.bool(legacy, "GG.fontCustomization.showPeerInfoShareButton", to: MTAppearanceSettings.profileHideShareButton, inverted: true)
        MTAppearanceMigration.bool(legacy, "GG.fontCustomization.hideStarRatingBadge", to: MTAppearanceSettings.profileHideStarRating)
    }
}
