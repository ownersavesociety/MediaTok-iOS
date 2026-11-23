import Foundation
import MTCore

// Every setting of the Interface zone (chat list, folders, tab bar, input panel, icons, the
// Settings tab), declared once. Defaults live here and nowhere else; user toggles are off.
// Keys: `interface.<feature>.<key>` (strings use the same `interface` namespace).

/// Geometry of the chat input panel (input bar editor). Zero = upstream layout.
struct MTInputBarGeometry: Codable, Equatable, MTSettingValue {
    /// Extra height of the text field, pt (0…100).
    var heightPadding: Double
    /// Insets of the text field from the left / right edge, pt (0…160).
    var leftMargin: Double
    var rightMargin: Double
    /// Lift of the whole panel above the bottom edge, pt (0…220).
    var bottomOffset: Double
    /// Free offsets of the attachment, emoji (accessory) and send / record buttons, pt.
    var attachX: Double
    var attachY: Double
    var accessoryX: Double
    var accessoryY: Double
    var sendX: Double
    var sendY: Double

    static let zero = MTInputBarGeometry(heightPadding: 0.0, leftMargin: 0.0, rightMargin: 0.0, bottomOffset: 0.0, attachX: 0.0, attachY: 0.0, accessoryX: 0.0, accessoryY: 0.0, sendX: 0.0, sendY: 0.0)

    var isZero: Bool {
        return self == MTInputBarGeometry.zero
    }

    static let heightPaddingRange: ClosedRange<Double> = 0.0 ... 100.0
    static let marginRange: ClosedRange<Double> = 0.0 ... 160.0
    static let bottomOffsetRange: ClosedRange<Double> = 0.0 ... 220.0
    static let buttonXRange: ClosedRange<Double> = -120.0 ... 120.0
    static let buttonYRange: ClosedRange<Double> = -80.0 ... 80.0

    /// Clamped to the editor's ranges (an imported file may hold anything).
    var clamped: MTInputBarGeometry {
        func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
            return min(range.upperBound, max(range.lowerBound, value))
        }
        return MTInputBarGeometry(
            heightPadding: clamp(self.heightPadding, MTInputBarGeometry.heightPaddingRange),
            leftMargin: clamp(self.leftMargin, MTInputBarGeometry.marginRange),
            rightMargin: clamp(self.rightMargin, MTInputBarGeometry.marginRange),
            bottomOffset: clamp(self.bottomOffset, MTInputBarGeometry.bottomOffsetRange),
            attachX: clamp(self.attachX, MTInputBarGeometry.buttonXRange),
            attachY: clamp(self.attachY, MTInputBarGeometry.buttonYRange),
            accessoryX: clamp(self.accessoryX, MTInputBarGeometry.buttonXRange),
            accessoryY: clamp(self.accessoryY, MTInputBarGeometry.buttonYRange),
            sendX: clamp(self.sendX, MTInputBarGeometry.buttonXRange),
            sendY: clamp(self.sendY, MTInputBarGeometry.buttonYRange)
        )
    }
}

/// A row pinned to Telegram's Settings tab («Ярлыки»).
struct MTSettingsShortcut: Codable, Equatable, MTSettingValue {
    enum Kind: String, Codable {
        case chat
        case miniApp
        case site
    }

    /// `chat:<peer>`, `miniApp:<peer>` or `site:<normalized url>`. Unique within the list.
    var id: String
    var kind: Kind
    var peer: MTPeerKey?
    /// Normalized absolute http(s) URL for sites.
    var url: String?
    /// User title for sites; chats and mini apps always show the peer's current name.
    var title: String?
}

enum InterfaceSettings {
    // MARK: Chat list (chatlist_tweaks, SG-B1…B5)

    /// SG-B1: smaller rows and avatars.
    static let compactList = MTSetting<Bool>("interface.chatList.compact", default: false)
    /// SG-B2: lines of message preview, "1" / "2" / "3". "2" is Telegram's layout.
    static let previewLines = MTSetting<String>("interface.chatList.previewLines", default: "2")
    /// Row height in percent of Telegram's ("80" … "130").
    static let rowScale = MTSetting<String>("interface.chatList.rowScale", default: "100")
    /// Avatar size in percent of Telegram's ("70" … "120").
    static let avatarScale = MTSetting<String>("interface.chatList.avatarScale", default: "100")
    static let hideEmojiStatus = MTSetting<Bool>("interface.chatList.hideEmojiStatus", default: false)
    static let hideSearchField = MTSetting<Bool>("interface.chatList.hideSearchField", default: false)
    /// A small avatar of the sender before the preview text (groups).
    static let senderAvatars = MTSetting<Bool>("interface.chatList.senderAvatars", default: false)
    static let hidePreview = MTSetting<Bool>("interface.chatList.hidePreview", default: false)
    /// "all" or "selected" (the chats in `hidePreviewPeers`).
    static let hidePreviewScope = MTSetting<String>("interface.chatList.hidePreviewScope", default: "all")
    static let hidePreviewPeers = MTAccountSetting<Set<MTPeerKey>>("interface.chatList.hidePreviewPeers", default: [])
    /// SG-B3: "all" (Telegram), "noDelete", "none".
    static let swipeActions = MTSetting<String>("interface.chatList.swipeActions", default: "all")
    /// SG-B4.
    static let disableStoryCameraSwipe = MTSetting<Bool>("interface.chatList.disableStoryCameraSwipe", default: false)
    /// SG-B5: no stories strip above the list.
    static let hideStories = MTSetting<Bool>("interface.chatList.hideStories", default: false)
    /// No story rings around the avatars of the rows.
    static let hideStoryRings = MTSetting<Bool>("interface.chatList.hideStoryRings", default: false)
    static let hideProxySponsor = MTSetting<Bool>("interface.chatList.hideProxySponsor", default: false)
    /// Only the spinner while connecting, no «Соединение…» text.
    static let hideConnectionText = MTSetting<Bool>("interface.chatList.hideConnectionText", default: false)
    /// A numeric query in the chat list search also looks the id up. On by default: Swiftgram does it
    /// always (MediaTok,.
    static let searchById = MTSetting<Bool>("interface.chatList.searchById", default: true)

    // MARK: Avatars (square_avatars)

    /// «Скругление углов»: "0" = Telegram's circle, "25"…"100" = how far from a circle the shape
    /// goes (`MTAvatarCorners`). Replaced «Квадратные аватары» + its level on 2026-10-27.
    static let avatarCorners = MTSetting<String>("interface.avatars.corners", default: MTAvatarCorners.round)
    static let roundAvatarsInForums = MTSetting<Bool>("interface.avatars.roundInForums", default: false)
    /// "" = the theme's colors, otherwise "RRGGBB".
    static let storyRingColor = MTSetting<String>("interface.avatars.storyRingColor", default: "")

    // MARK: Folders (folders_tweaks, SG-A5…A9)

    /// SG-A5: the folder strip above the tab bar (`MTChatListFolderStrip.atBottom`).
    static let foldersAtBottom = MTSetting<Bool>("interface.folders.atBottom", default: false)
    /// Service: legacy format `ExperimentalUISettings.foldersTabAtBottom` was read once.
    static let foldersAtBottomImported = MTSetting<Bool>("interface.folders.atBottomImported", default: false, flags: [.noExport])
    static let hideAllChats = MTSetting<Bool>("interface.folders.hideAllChats", default: false)
    static let compactFolderTabs = MTSetting<Bool>("interface.folders.compactTabs", default: false)
    /// "default" (Telegram's «Все») or "long" («Все чаты»).
    static let allChatsTitle = MTSetting<String>("interface.folders.allChatsTitle", default: "default")
    static let rememberLastFolder = MTSetting<Bool>("interface.folders.rememberLast", default: false)
    /// The folder the list showed last, per account: 0 = «Все чаты», otherwise the filter id.
    static let lastFolder = MTAccountSetting<Int32>("interface.folders.lastFolder", default: 0, flags: [.noExport])
    /// Extra height of the folder tab strip, pt (0…24).
    static let folderBarHeightOffset = MTSetting<Double>("interface.folders.barHeightOffset", default: 0.0)

    // MARK: Tab bar (tabbar_tweaks, SG-A1…A4)

    /// Order of the tab ids: "contacts", "calls", "chats", "settings".
    static let tabOrder = MTSetting<[String]>("interface.tabBar.order", default: MTTabBarLayout.defaultOrder)
    /// Own labels by tab id.
    static let tabTitles = MTSetting<[String: String]>("interface.tabBar.titles", default: [:])
    /// Tabs taken out of the bar ("contacts", "calls"); the chat list and Settings always stay.
    static let hiddenTabs = MTSetting<[String]>("interface.tabBar.hidden", default: [])
    static let hideTabTitles = MTSetting<Bool>("interface.tabBar.hideTitles", default: false)
    static let wideTabBar = MTSetting<Bool>("interface.tabBar.wide", default: false)
    static let hideTabBar = MTSetting<Bool>("interface.tabBar.hide", default: false)
    /// Extra height of the bar and its lift above the bottom edge, pt.
    static let tabBarHeightOffset = MTSetting<Double>("interface.tabBar.heightOffset", default: 0.0)
    static let tabBarBottomOffset = MTSetting<Double>("interface.tabBar.bottomOffset", default: 0.0)

    // MARK: Input panel (input_bar_editor, typing_animation, SG-F11, SG-G9)

    static let inputBarGeometry = MTSetting<MTInputBarGeometry>("interface.inputBar.geometry", default: .zero)
    static let characterCounter = MTSetting<Bool>("interface.inputBar.characterCounter", default: false)
    /// SG-F11: the formatting toolbar above the keyboard, in every composer.
    static let formattingToolbar = MTSetting<Bool>("interface.inputBar.formattingToolbar", default: false)
    static let autoFormatting = MTSetting<Bool>("interface.inputBar.autoFormatting", default: false)
    /// "bold", "italic", "monospace", "strikethrough", "underline", "spoiler", "quote", "code".
    static let autoFormattingStyle = MTSetting<String>("interface.inputBar.autoFormattingStyle", default: "bold")
    /// SG-G9.
    static let emojiTabFirst = MTSetting<Bool>("interface.inputBar.emojiTabFirst", default: false)
    static let standardEmojiFirst = MTSetting<Bool>("interface.inputBar.standardEmojiFirst", default: false)

    static let typingAnimation = MTSetting<Bool>("interface.typingAnimation.enabled", default: false)
    /// "pulse", "wave", "panelWave", "neon", "shake", "custom".
    static let typingAnimationPreset = MTSetting<String>("interface.typingAnimation.preset", default: "wave")
    static let typingAnimationIntensity = MTSetting<Double>("interface.typingAnimation.intensity", default: 55.0)
    static let typingAnimationSpeed = MTSetting<Double>("interface.typingAnimation.speed", default: 55.0)
    static let typingAnimationScale = MTSetting<Double>("interface.typingAnimation.scale", default: 45.0)
    static let typingAnimationOffset = MTSetting<Double>("interface.typingAnimation.offset", default: 45.0)
    static let typingAnimationGlow = MTSetting<Double>("interface.typingAnimation.glow", default: 55.0)

    // MARK: Quick buttons in a chat (bind_buttons)

    static let bindButtons = MTSetting<Bool>("interface.bindButtons.enabled", default: false)
    /// Action ids switched off by the user (all registered actions show by default once the
    /// master switch is on — the master is the feature toggle and is off by default).
    static let bindButtonsHidden = MTSetting<[String]>("interface.bindButtons.hidden", default: [])
    /// Where each button stands: action id → [x, y], its centre in the chat's free area, 0…1
    /// (`MTQuickButtonsLayout`). A button without an entry stands in the column on the right.
    /// Written by «Расположение и размер» (`MTQuickButtonsEditorController`).
    static let bindButtonsPositions = MTSetting<[String: [Double]]>("interface.bindButtons.positions", default: [:])
    /// Size of every button, pt (`MTQuickButtonsLayout.sideRange`).
    static let bindButtonsWidth = MTSetting<Double>("interface.bindButtons.width", default: MTQuickButtonsLayout.defaultSide)
    static let bindButtonsHeight = MTSetting<Double>("interface.bindButtons.height", default: MTQuickButtonsLayout.defaultSide)

    // MARK: Custom recent reactions (custom_recent_reactions)

    static let customReactions = MTSetting<Bool>("interface.customReactions.enabled", default: false)
    /// "e:<emoji>" for builtin reactions, "doc:<file id>" for custom emoji (the old wire format).
    static let customReactionsList = MTSetting<[String]>("interface.customReactions.list", default: MTCustomReactions.defaultList)
    /// Telegram's own top reactions after the custom set.
    static let customReactionsAppendStandard = MTSetting<Bool>("interface.customReactions.appendStandard", default: false)

    // MARK: Icon packs (icon_packs)

    /// Enabled packs, highest priority first. Empty = Telegram's icons.
    static let iconPacks = MTSetting<[String]>("interface.iconPacks.enabled", default: [])

    // MARK: Badge under the cutout (app_icons_badges, MediaTok)

    /// On by default, as in legacy format: the MediaTok badge takes the place of Telegram's,
    /// which is never shown (`MTIslandBadge`).
    static let islandBadge = MTSetting<Bool>("interface.islandBadge.enabled", default: true)
    /// "mediatok" (bundled) or the id of a studio badge.
    static let islandBadgeSelection = MTSetting<String>("interface.islandBadge.selection", default: "mediatok")

    // MARK: Telegram's Settings tab (settings_structure)

    /// Telegram rows hidden from the Settings tab (`MTSettingsTabItem.rawValue`).
    static let hiddenSettingsItems = MTSetting<[String]>("interface.settingsTab.hidden", default: [])
    /// Order of Telegram's rows inside their sections; empty = Telegram's order.
    static let settingsItemsOrder = MTSetting<[String]>("interface.settingsTab.order", default: [])
    static let settingsShortcuts = MTAccountSetting<[MTSettingsShortcut]>("interface.settingsTab.shortcuts", default: [])

    /// Called from `MTInterfaceModule.register()`: the registry must know every setting before
    /// export, search and migrations run.
    static func declare() {
        let _ = InterfaceSettings.compactList
        let _ = InterfaceSettings.previewLines
        let _ = InterfaceSettings.rowScale
        let _ = InterfaceSettings.avatarScale
        let _ = InterfaceSettings.hideEmojiStatus
        let _ = InterfaceSettings.hideSearchField
        let _ = InterfaceSettings.senderAvatars
        let _ = InterfaceSettings.hidePreview
        let _ = InterfaceSettings.hidePreviewScope
        let _ = InterfaceSettings.hidePreviewPeers
        let _ = InterfaceSettings.swipeActions
        let _ = InterfaceSettings.disableStoryCameraSwipe
        let _ = InterfaceSettings.hideStories
        let _ = InterfaceSettings.hideStoryRings
        let _ = InterfaceSettings.hideProxySponsor
        let _ = InterfaceSettings.hideConnectionText
        let _ = InterfaceSettings.searchById

        let _ = InterfaceSettings.avatarCorners
        let _ = InterfaceSettings.roundAvatarsInForums
        let _ = InterfaceSettings.storyRingColor

        let _ = InterfaceSettings.foldersAtBottom
        let _ = InterfaceSettings.foldersAtBottomImported
        let _ = InterfaceSettings.hideAllChats
        let _ = InterfaceSettings.compactFolderTabs
        let _ = InterfaceSettings.allChatsTitle
        let _ = InterfaceSettings.rememberLastFolder
        let _ = InterfaceSettings.lastFolder
        let _ = InterfaceSettings.folderBarHeightOffset

        let _ = InterfaceSettings.tabOrder
        let _ = InterfaceSettings.tabTitles
        let _ = InterfaceSettings.hiddenTabs
        let _ = InterfaceSettings.hideTabTitles
        let _ = InterfaceSettings.wideTabBar
        let _ = InterfaceSettings.hideTabBar
        let _ = InterfaceSettings.tabBarHeightOffset
        let _ = InterfaceSettings.tabBarBottomOffset

        let _ = InterfaceSettings.inputBarGeometry
        let _ = InterfaceSettings.characterCounter
        let _ = InterfaceSettings.formattingToolbar
        let _ = InterfaceSettings.autoFormatting
        let _ = InterfaceSettings.autoFormattingStyle
        let _ = InterfaceSettings.emojiTabFirst
        let _ = InterfaceSettings.standardEmojiFirst

        let _ = InterfaceSettings.typingAnimation
        let _ = InterfaceSettings.typingAnimationPreset
        let _ = InterfaceSettings.typingAnimationIntensity
        let _ = InterfaceSettings.typingAnimationSpeed
        let _ = InterfaceSettings.typingAnimationScale
        let _ = InterfaceSettings.typingAnimationOffset
        let _ = InterfaceSettings.typingAnimationGlow

        let _ = InterfaceSettings.bindButtons
        let _ = InterfaceSettings.bindButtonsHidden
        let _ = InterfaceSettings.bindButtonsPositions
        let _ = InterfaceSettings.bindButtonsWidth
        let _ = InterfaceSettings.bindButtonsHeight

        let _ = InterfaceSettings.customReactions
        let _ = InterfaceSettings.customReactionsList
        let _ = InterfaceSettings.customReactionsAppendStandard

        let _ = InterfaceSettings.iconPacks

        let _ = InterfaceSettings.islandBadge
        let _ = InterfaceSettings.islandBadgeSelection

        let _ = InterfaceSettings.hiddenSettingsItems
        let _ = InterfaceSettings.settingsItemsOrder
        let _ = InterfaceSettings.settingsShortcuts
    }
}
