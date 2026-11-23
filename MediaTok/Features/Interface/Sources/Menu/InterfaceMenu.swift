import Foundation
import UIKit
import Display
import TelegramPresentationData
import AccountContext
import SettingsUI
import MTCore
import MTSettingsUI
import MTFeaturesShared

/// The zone's part of the menu: «Оформление › Список чатов / Панели / Иконки» and the Settings
/// half of «Профиль и Настройки». Every setting has one row; every row applies at once except the
/// app icon (iOS asks itself) — nothing here restarts the app.
enum InterfaceMenu {
    private static let chatListStories = MTMenuSectionID("appearance.chatList.stories")
    private static let chatListPreviews = MTMenuSectionID("appearance.chatList.previews")
    private static let chatListAvatars = MTMenuSectionID("appearance.chatList.avatars")
    private static let chatListFolders = MTMenuSectionID("appearance.chatList.folders")
    private static let panelsTabBarPreview = MTMenuSectionID("appearance.panels.tabBarPreview")
    private static let panelsTabBar = MTMenuSectionID("appearance.panels.tabBar")
    private static let panelsInput = MTMenuSectionID("appearance.panels.input")
    private static let panelsInputPreview = MTMenuSectionID("appearance.panels.inputPreview")
    private static let panelsTyping = MTMenuSectionID("appearance.panels.typing")
    private static let panelsButtons = MTMenuSectionID("appearance.panels.buttons")
    private static let panelsReactions = MTMenuSectionID("appearance.panels.reactions")
    private static let iconsBadge = MTMenuSectionID("appearance.icons.badge")
    private static let settingsTab = MTMenuSectionID("appearance.profileSettings.settingsTab")

    static func register() {
        InterfaceMenu.registerChatList()
        InterfaceMenu.registerPanels()
        InterfaceMenu.registerIcons()
        InterfaceMenu.registerSettingsTab()
    }

    private static func percent(_ value: Double) -> String {
        return MTStrings.Interface.Menu.percent(value: "\(Int(value.rounded()))")
    }

    private static func points(_ value: Double) -> String {
        return MTStrings.Interface.Menu.points(value: "\(Int(value.rounded()))")
    }

    private static func options(_ values: [String], title: @escaping (String) -> String) -> [MTMenuChoiceOption] {
        return values.map { value in
            return MTMenuChoiceOption(value: value, title: { title(value) })
        }
    }

    // MARK: Список чатов

    private static func registerChatList() {
        let tab = MTMenuTabID.appearanceChatList
        let main = MTMenuSectionID.main(of: tab)

        MTMenuRegistry.register(MTMenuRow(
            id: "interface.chatList.preview",
            section: .preview(of: tab),
            order: 100,
            title: { "" },
            kind: .preview(.miniChatList(MTMiniChatListConfiguration(scope: "interface.chatList", height: 228.0, rows: { _ in
                return MTPreviewChatListRow.samples()
            })))
        ))
        // Hidden previews show in the mini list the way they do in the real one.
        MTPreviewModifiers.registerChatListModifier(id: "interface.hidePreview", order: 100, { rows, context in
            guard context.previewScope == "interface.chatList", InterfaceSettings.hidePreview.value, InterfaceSettings.hidePreviewScope.value == "all" else {
                return
            }
            for index in rows.indices {
                rows[index].text = ""
                rows[index].authorName = nil
            }
        })

        let toggles: [(String, Int, () -> String, (() -> String)?, MTSetting<Bool>, () -> [String])] = [
            ("interface.chatList.compact", 200, { MTStrings.Interface.Menu.compactList }, { MTStrings.Interface.Menu.compactListInfo }, InterfaceSettings.compactList, { [] }),
            ("interface.chatList.senderAvatars", 600, { MTStrings.Interface.Menu.senderAvatars }, { MTStrings.Interface.Menu.senderAvatarsInfo }, InterfaceSettings.senderAvatars, { [] }),
            ("interface.chatList.hideEmojiStatus", 700, { MTStrings.Interface.Menu.hideEmojiStatus }, nil, InterfaceSettings.hideEmojiStatus, { [] }),
            ("interface.chatList.hideSearchField", 800, { MTStrings.Interface.Menu.hideSearchField }, { MTStrings.Interface.Menu.hideSearchFieldInfo }, InterfaceSettings.hideSearchField, { [] }),
            ("interface.chatList.searchById", 900, { MTStrings.Interface.Menu.searchById }, { MTStrings.Interface.Menu.searchByIdInfo }, InterfaceSettings.searchById, { [] }),
            ("interface.chatList.hideConnectionText", 1000, { MTStrings.Interface.Menu.hideConnectionText }, { MTStrings.Interface.Menu.hideConnectionTextInfo }, InterfaceSettings.hideConnectionText, { [] }),
            ("interface.chatList.hideProxySponsor", 1200, { MTStrings.Interface.Menu.hideProxySponsor }, { MTStrings.Interface.Menu.hideProxySponsorInfo }, InterfaceSettings.hideProxySponsor, { [] })
        ]
        for (id, order, title, subtitle, setting, keywords) in toggles {
            MTMenuRegistry.register(MTMenuRow(id: id, section: main, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting)), searchKeywords: keywords))
        }
        MTMenuRegistry.register(MTMenuRow(id: "interface.chatList.previewLines", section: main, order: 300, title: { MTStrings.Interface.Menu.previewLines }, kind: .discreteChoice(.global(InterfaceSettings.previewLines), options: InterfaceMenu.options(["1", "2", "3"], title: { MTStrings.Interface.Menu.number(value: $0) }))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.chatList.rowScale", section: main, order: 400, title: { MTStrings.Interface.Menu.rowScale }, kind: .choice(.global(InterfaceSettings.rowScale), options: InterfaceMenu.options(MTChatListFeature.rowScaleOptions, title: { InterfaceMenu.percent(Double($0) ?? 100.0) }))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.chatList.avatarScale", section: main, order: 500, title: { MTStrings.Interface.Menu.avatarScale }, kind: .choice(.global(InterfaceSettings.avatarScale), options: InterfaceMenu.options(MTChatListFeature.avatarScaleOptions, title: { InterfaceMenu.percent(Double($0) ?? 100.0) }))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.chatList.swipeActions", section: main, order: 1100, title: { MTStrings.Interface.Menu.swipeActions }, kind: .choice(.global(InterfaceSettings.swipeActions), options: [
            MTMenuChoiceOption(value: "all", title: { MTStrings.Interface.Menu.swipeAll }),
            MTMenuChoiceOption(value: "noDelete", title: { MTStrings.Interface.Menu.swipeNoDelete }),
            MTMenuChoiceOption(value: "none", title: { MTStrings.Interface.Menu.swipeNone })
        ])))

        // Stories
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.chatListStories, screen: .tab(tab), order: 300, header: { MTStrings.Interface.Menu.storiesHeader }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.chatList.hideStories", section: InterfaceMenu.chatListStories, order: 100, title: { MTStrings.Interface.Menu.hideStories }, kind: .toggle(.global(InterfaceSettings.hideStories))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.chatList.hideStoryRings", section: InterfaceMenu.chatListStories, order: 200, title: { MTStrings.Interface.Menu.hideStoryRings }, kind: .toggle(.global(InterfaceSettings.hideStoryRings))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.chatList.disableStoryCameraSwipe", section: InterfaceMenu.chatListStories, order: 300, title: { MTStrings.Interface.Menu.disableStoryCameraSwipe }, subtitle: { MTStrings.Interface.Menu.disableStoryCameraSwipeInfo }, kind: .toggle(.global(InterfaceSettings.disableStoryCameraSwipe))))
        let ringColors: [(String, () -> String)] = [
            ("", { MTStrings.Interface.Menu.colorTheme }),
            ("3390EC", { MTStrings.Interface.Menu.colorBlue }),
            ("34C759", { MTStrings.Interface.Menu.colorGreen }),
            ("FF9500", { MTStrings.Interface.Menu.colorOrange }),
            ("FF2D55", { MTStrings.Interface.Menu.colorPink }),
            ("AF52DE", { MTStrings.Interface.Menu.colorPurple }),
            ("FFFFFF", { MTStrings.Interface.Menu.colorWhite }),
            ("8E8E93", { MTStrings.Interface.Menu.colorGray })
        ]
        MTMenuRegistry.register(MTMenuRow(id: "interface.avatars.storyRingColor", section: InterfaceMenu.chatListStories, order: 400, title: { MTStrings.Interface.Menu.storyRingColor }, kind: .choice(.global(InterfaceSettings.storyRingColor), options: ringColors.map { MTMenuChoiceOption(value: $0.0, title: $0.1) }), isVisible: { _ in !InterfaceSettings.hideStoryRings.value }))

        // Message previews
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.chatListPreviews, screen: .tab(tab), order: 400, header: { MTStrings.Interface.Menu.previewsHeader }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.chatList.hidePreview", section: InterfaceMenu.chatListPreviews, order: 100, title: { MTStrings.Interface.Menu.hidePreview }, subtitle: { MTStrings.Interface.Menu.hidePreviewInfo }, kind: .toggle(.global(InterfaceSettings.hidePreview))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.chatList.hidePreviewScope", section: InterfaceMenu.chatListPreviews, order: 200, title: { MTStrings.Interface.Menu.hidePreviewScope }, kind: .choice(.global(InterfaceSettings.hidePreviewScope), options: [
            MTMenuChoiceOption(value: "all", title: { MTStrings.Interface.Menu.scopeAll }),
            MTMenuChoiceOption(value: "selected", title: { MTStrings.Interface.Menu.scopeSelected })
        ]), isVisible: { _ in InterfaceSettings.hidePreview.value }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.chatList.hidePreviewPeers", section: InterfaceMenu.chatListPreviews, order: 300, title: { MTStrings.Interface.ChatList.hiddenPreviewChats }, kind: .action({ menu in
            menu.push(MTHiddenPreviewScreens.makeScreen(context: menu.context))
        }), isVisible: { _ in InterfaceSettings.hidePreview.value && InterfaceSettings.hidePreviewScope.value == "selected" }, label: { menu in
            let count = InterfaceSettings.hidePreviewPeers.value(for: menu.accountID).count
            return count == 0 ? nil : "\(count)"
        }))

        // Avatars
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.chatListAvatars, screen: .tab(tab), order: 500, header: { MTStrings.Interface.Menu.avatarsHeader }, footer: { _ in MTStrings.Interface.Menu.avatarsFooter }))
        // One row since 2026-10-27: the circle is the first stop, the square the last.
        MTMenuRegistry.register(MTMenuRow(id: "interface.avatars.corners", section: InterfaceMenu.chatListAvatars, order: 100, title: { MTStrings.Interface.Menu.squareness }, kind: .discreteChoice(.global(InterfaceSettings.avatarCorners), options: [
            MTMenuChoiceOption(value: MTAvatarCorners.round, title: { MTStrings.Interface.Menu.squarenessNone }),
            MTMenuChoiceOption(value: "25", title: { MTStrings.Interface.Menu.squarenessSlight }),
            MTMenuChoiceOption(value: "50", title: { MTStrings.Interface.Menu.squarenessMedium }),
            MTMenuChoiceOption(value: "75", title: { MTStrings.Interface.Menu.squarenessStrong }),
            MTMenuChoiceOption(value: "100", title: { MTStrings.Interface.Menu.squarenessFull })
        ]), searchKeywords: { [MTStrings.Interface.Menu.squarenessKeywords] }))
        // Forums are drawn as circles with any corner setting, so the switch is always shown.
        MTMenuRegistry.register(MTMenuRow(id: "interface.avatars.roundInForums", section: InterfaceMenu.chatListAvatars, order: 200, title: { MTStrings.Interface.Menu.roundInForums }, kind: .toggle(.global(InterfaceSettings.roundAvatarsInForums))))

        // Folders
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.chatListFolders, screen: .tab(tab), order: 600, header: { MTStrings.Interface.Menu.foldersHeader }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.folders.hideAllChats", section: InterfaceMenu.chatListFolders, order: 100, title: { MTStrings.Interface.Menu.hideAllChats }, subtitle: { MTStrings.Interface.Menu.hideAllChatsInfo }, kind: .toggle(.global(InterfaceSettings.hideAllChats))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.folders.allChatsTitle", section: InterfaceMenu.chatListFolders, order: 200, title: { MTStrings.Interface.Menu.allChatsTitle }, kind: .choice(.global(InterfaceSettings.allChatsTitle), options: [
            MTMenuChoiceOption(value: "default", title: { MTStrings.Interface.Menu.allChatsTitleDefault }),
            MTMenuChoiceOption(value: "long", title: { MTStrings.Interface.Menu.allChatsTitleLong })
        ]), isVisible: { _ in !InterfaceSettings.hideAllChats.value }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.folders.compactTabs", section: InterfaceMenu.chatListFolders, order: 300, title: { MTStrings.Interface.Menu.compactFolderTabs }, kind: .toggle(.global(InterfaceSettings.compactFolderTabs))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.folders.atBottom", section: InterfaceMenu.chatListFolders, order: 400, title: { MTStrings.Interface.Menu.foldersAtBottom }, subtitle: { MTStrings.Interface.Menu.foldersAtBottomInfo }, kind: .toggle(.global(InterfaceSettings.foldersAtBottom))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.folders.barHeightOffset", section: InterfaceMenu.chatListFolders, order: 500, title: { MTStrings.Interface.Menu.folderBarHeight }, kind: .slider(.global(InterfaceSettings.folderBarHeightOffset), range: 0.0 ... 24.0, step: 1.0, format: InterfaceMenu.points)))
        MTMenuRegistry.register(MTMenuRow(id: "interface.folders.rememberLast", section: InterfaceMenu.chatListFolders, order: 600, title: { MTStrings.Interface.Menu.rememberLastFolder }, subtitle: { MTStrings.Interface.Menu.rememberLastFolderInfo }, kind: .toggle(.global(InterfaceSettings.rememberLastFolder))))
    }

    // MARK: Панели

    private static func registerPanels() {
        let tab = MTMenuTabID.appearancePanels

        // Two previews, each under its section's header and over its rows (owner, builds 188–189): the
        // tab bar, the input field.
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.panelsTabBarPreview, screen: .tab(tab), order: 240, header: { MTStrings.Interface.Menu.tabBarHeader }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.panels.preview", section: InterfaceMenu.panelsTabBarPreview, order: 100, title: { "" }, kind: .preview(.custom(height: MTTabBarPreviewView.height, make: { _ in
            return MTTabBarPreviewView(frame: CGRect())
        }))))

        let main = InterfaceMenu.panelsTabBar
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: main, screen: .tab(tab), order: 250))
        MTMenuRegistry.register(MTMenuRow(id: "interface.tabBar.organizer", section: main, order: 100, title: { MTStrings.Interface.TabBar.organizerTitle }, subtitle: { MTStrings.Interface.Menu.tabOrganizerInfo }, kind: .action({ menu in
            menu.push(MTTabBarScreens.makeOrganizer(context: menu.context))
        }), searchKeywords: { [MTStrings.Interface.Menu.tabKeywords] }, label: { _ in
            let changed = !InterfaceSettings.tabOrder.isDefault || !InterfaceSettings.tabTitles.isDefault || !InterfaceSettings.hiddenTabs.isDefault
            return changed ? MTStrings.Interface.Menu.changedLabel : nil
        }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.tabBar.hideTitles", section: main, order: 200, title: { MTStrings.Interface.Menu.hideTabTitles }, subtitle: { MTStrings.Interface.Menu.hideTabTitlesInfo }, kind: .toggle(.global(InterfaceSettings.hideTabTitles))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.tabBar.wide", section: main, order: 300, title: { MTStrings.Interface.Menu.wideTabBar }, kind: .toggle(.global(InterfaceSettings.wideTabBar))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.tabBar.hide", section: main, order: 400, title: { MTStrings.Interface.Menu.hideTabBar }, subtitle: { MTStrings.Interface.Menu.hideTabBarInfo }, kind: .toggle(.global(InterfaceSettings.hideTabBar))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.tabBar.heightOffset", section: main, order: 500, title: { MTStrings.Interface.Menu.tabBarHeight }, kind: .slider(.global(InterfaceSettings.tabBarHeightOffset), range: MTTabBarLayout.heightOffsetRange, step: 1.0, format: InterfaceMenu.points), isVisible: { _ in !InterfaceSettings.hideTabBar.value }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.tabBar.bottomOffset", section: main, order: 600, title: { MTStrings.Interface.Menu.tabBarLift }, kind: .slider(.global(InterfaceSettings.tabBarBottomOffset), range: MTTabBarLayout.bottomOffsetRange, step: 1.0, format: InterfaceMenu.points), isVisible: { _ in !InterfaceSettings.hideTabBar.value }))

        // Input field
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.panelsInputPreview, screen: .tab(tab), order: 290, header: { MTStrings.Interface.Menu.inputHeader }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.panels.inputPreview", section: InterfaceMenu.panelsInputPreview, order: 100, title: { "" }, kind: .preview(.custom(height: MTInputBarPreviewView.height, make: { _ in
            return MTInputBarPreviewView(frame: CGRect())
        }))))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.panelsInput, screen: .tab(tab), order: 300))
        MTMenuRegistry.register(MTMenuRow(id: "interface.inputBar.editor", section: InterfaceMenu.panelsInput, order: 100, title: { MTStrings.Interface.Menu.inputEditor }, subtitle: { MTStrings.Interface.Menu.inputEditorInfo }, kind: .action({ menu in
            MTInputBarEditor.start(context: menu.context, navigationController: menu.navigationController)
        }), label: { _ in
            return InterfaceSettings.inputBarGeometry.isDefault ? nil : MTStrings.Interface.Menu.changedLabel
        }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.inputBar.characterCounter", section: InterfaceMenu.panelsInput, order: 200, title: { MTStrings.Interface.Menu.characterCounter }, subtitle: { MTStrings.Interface.Menu.characterCounterInfo }, kind: .toggle(.global(InterfaceSettings.characterCounter))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.inputBar.formattingToolbar", section: InterfaceMenu.panelsInput, order: 300, title: { MTStrings.Interface.Menu.formattingToolbar }, subtitle: { MTStrings.Interface.Menu.formattingToolbarInfo }, kind: .toggle(.global(InterfaceSettings.formattingToolbar))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.inputBar.autoFormatting", section: InterfaceMenu.panelsInput, order: 400, title: { MTStrings.Interface.Menu.autoFormatting }, subtitle: { MTStrings.Interface.Menu.autoFormattingInfo }, kind: .toggle(.global(InterfaceSettings.autoFormatting))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.inputBar.autoFormattingStyle", section: InterfaceMenu.panelsInput, order: 500, title: { MTStrings.Interface.Menu.autoFormattingStyle }, kind: .choice(.global(InterfaceSettings.autoFormattingStyle), options: InterfaceMenu.options(MTAutoFormatting.styles, title: MTAutoFormatting.title)), isVisible: { _ in InterfaceSettings.autoFormatting.value }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.inputBar.emojiTabFirst", section: InterfaceMenu.panelsInput, order: 600, title: { MTStrings.Interface.Menu.emojiTabFirst }, kind: .toggle(.global(InterfaceSettings.emojiTabFirst))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.inputBar.standardEmojiFirst", section: InterfaceMenu.panelsInput, order: 700, title: { MTStrings.Interface.Menu.standardEmojiFirst }, kind: .toggle(.global(InterfaceSettings.standardEmojiFirst))))

        // Typing animation
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.panelsTyping, screen: .tab(tab), order: 400, header: { MTStrings.Interface.Menu.typingHeader }, footer: { _ in MTStrings.Interface.Menu.typingFooter }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.typingAnimation.enabled", section: InterfaceMenu.panelsTyping, order: 100, title: { MTStrings.Interface.Menu.typingAnimation }, kind: .toggle(.global(InterfaceSettings.typingAnimation))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.typingAnimation.preset", section: InterfaceMenu.panelsTyping, order: 200, title: { MTStrings.Interface.Menu.typingPreset }, kind: .choice(.global(InterfaceSettings.typingAnimationPreset), options: InterfaceMenu.options(MTTypingAnimationParameters.presets, title: InterfaceMenu.presetTitle)), isVisible: { _ in InterfaceSettings.typingAnimation.value }))
        let isCustom: (MTMenuContext) -> Bool = { _ in InterfaceSettings.typingAnimation.value && InterfaceSettings.typingAnimationPreset.value == "custom" }
        let sliders: [(String, Int, () -> String, MTSetting<Double>)] = [
            ("interface.typingAnimation.intensity", 300, { MTStrings.Interface.Menu.typingIntensity }, InterfaceSettings.typingAnimationIntensity),
            ("interface.typingAnimation.speed", 400, { MTStrings.Interface.Menu.typingSpeed }, InterfaceSettings.typingAnimationSpeed),
            ("interface.typingAnimation.scale", 500, { MTStrings.Interface.Menu.typingScale }, InterfaceSettings.typingAnimationScale),
            ("interface.typingAnimation.offset", 600, { MTStrings.Interface.Menu.typingOffset }, InterfaceSettings.typingAnimationOffset),
            ("interface.typingAnimation.glow", 700, { MTStrings.Interface.Menu.typingGlow }, InterfaceSettings.typingAnimationGlow)
        ]
        for (id, order, title, setting) in sliders {
            MTMenuRegistry.register(MTMenuRow(id: id, section: InterfaceMenu.panelsTyping, order: order, title: title, kind: .slider(.global(setting), range: 0.0 ... 100.0, step: 5.0, format: InterfaceMenu.percent), isVisible: isCustom))
        }

        // Quick buttons
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.panelsButtons, screen: .tab(tab), order: 500, header: { MTStrings.Interface.Menu.buttonsHeader }, footer: { _ in MTStrings.Interface.Menu.buttonsFooter }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.bindButtons.enabled", section: InterfaceMenu.panelsButtons, order: 100, title: { MTStrings.Interface.Menu.bindButtons }, kind: .toggle(.global(InterfaceSettings.bindButtons))))
        // The buttons on a full chat preview: dragged into place, width and height by sliders.
        MTMenuRegistry.register(MTMenuRow(id: "interface.bindButtons.layout", section: InterfaceMenu.panelsButtons, order: 150, title: { MTStrings.Interface.Binds.editorTitle }, kind: .action({ menu in
            menu.push(MTQuickButtonsEditorController(context: menu.context))
        }), isVisible: { _ in InterfaceSettings.bindButtons.value }, label: { _ in
            let size = MTQuickButtonsLayout.size()
            let defaultSide = CGFloat(MTQuickButtonsLayout.defaultSide)
            if size.width != defaultSide || size.height != defaultSide {
                return "\(Int(size.width))×\(Int(size.height))"
            }
            return InterfaceSettings.bindButtonsPositions.value.isEmpty ? nil : MTStrings.Interface.Binds.customLayout
        }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.bindButtons.hidden", section: InterfaceMenu.panelsButtons, order: 200, title: { MTStrings.Interface.Binds.buttonsTitle }, kind: .action({ menu in
            menu.push(MTQuickButtonScreens.makeScreen(context: menu.context))
        }), isVisible: { _ in InterfaceSettings.bindButtons.value }, label: { _ in
            let all = MTQuickActions.all.map { $0.id }
            let hidden = Set(InterfaceSettings.bindButtonsHidden.value)
            return "\(all.filter { !hidden.contains($0) }.count)/\(all.count)"
        }))

        // Reactions
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.panelsReactions, screen: .tab(tab), order: 600, header: { MTStrings.Interface.Menu.reactionsHeader }, footer: { _ in MTStrings.Interface.Menu.reactionsFooter }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.customReactions.enabled", section: InterfaceMenu.panelsReactions, order: 100, title: { MTStrings.Interface.Menu.customReactions }, kind: .toggle(.global(InterfaceSettings.customReactions))))
        MTMenuRegistry.register(MTMenuRow(id: "interface.customReactions.list", section: InterfaceMenu.panelsReactions, order: 200, title: { MTStrings.Interface.Reactions.editorTitle }, kind: .action({ menu in
            menu.push(MTReactionScreens.makeEditor(context: menu.context))
        }), isVisible: { _ in InterfaceSettings.customReactions.value }, label: { _ in
            return "\(InterfaceSettings.customReactionsList.value.count)"
        }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.customReactions.appendStandard", section: InterfaceMenu.panelsReactions, order: 300, title: { MTStrings.Interface.Menu.appendStandardReactions }, kind: .toggle(.global(InterfaceSettings.customReactionsAppendStandard)), isVisible: { _ in InterfaceSettings.customReactions.value }))
    }

    private static func presetTitle(_ preset: String) -> String {
        switch preset {
        case "pulse":
            return MTStrings.Interface.Menu.presetPulse
        case "wave":
            return MTStrings.Interface.Menu.presetWave
        case "panelWave":
            return MTStrings.Interface.Menu.presetPanelWave
        case "neon":
            return MTStrings.Interface.Menu.presetNeon
        case "shake":
            return MTStrings.Interface.Menu.presetShake
        default:
            return MTStrings.Interface.Menu.presetCustom
        }
    }

    // MARK: Иконки

    private static func registerIcons() {
        let tab = MTMenuTabID.appearanceIcons
        let main = MTMenuSectionID.main(of: tab)

        MTMenuRegistry.register(MTMenuRow(id: "interface.icons.preview", section: .preview(of: tab), order: 100, title: { "" }, kind: .preview(.custom(height: 176.0, make: { _ in
            return MTIconsPreviewView(frame: CGRect())
        }))))

        // No «Иконка приложения» row: MediaTok ships one app icon, the ghost (the duck was removed by
        // the, so there is nothing to choose.
        MTMenuRegistry.register(MTMenuRow(id: "interface.iconPacks", section: main, order: 200, title: { MTStrings.Interface.IconPacks.title }, subtitle: { MTStrings.Interface.Menu.iconPacksInfo }, icon: .bundle("Chat/Context Menu/Apps"), kind: .action({ menu in
            menu.push(MTIconPackScreens.makeListScreen(context: menu.context))
        }), searchKeywords: { [MTStrings.Interface.Menu.iconPacksKeywords] }, label: { _ in
            let count = InterfaceSettings.iconPacks.value.count
            return count == 0 ? MTStrings.Interface.Menu.offLabel : "\(count)"
        }))

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.iconsBadge, screen: .tab(tab), order: 300, header: { MTStrings.Interface.Menu.badgeHeader }, footer: { _ in
            return MTIslandBadgeGeometry.isSupported ? MTStrings.Interface.Menu.badgeFooter : MTStrings.Interface.Menu.badgeUnsupported
        }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.islandBadge.enabled", section: InterfaceMenu.iconsBadge, order: 100, title: { MTStrings.Interface.Menu.islandBadge }, kind: .toggle(.global(InterfaceSettings.islandBadge)), searchKeywords: { [MTStrings.Interface.Menu.badgeKeywords] }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.islandBadge.selection", section: InterfaceMenu.iconsBadge, order: 200, title: { MTStrings.Interface.Badge.galleryTitle }, kind: .action({ menu in
            menu.push(MTBadgeGallery.makeScreen(context: menu.context))
        }), label: { _ in
            let selection = InterfaceSettings.islandBadgeSelection.value
            return MTBadgeStore.isValidId(selection) ? MTStrings.Interface.Menu.ownBadgeLabel : MTStrings.Interface.Badge.bundledName
        }))
    }

    // MARK: Вкладка «Настройки»

    private static func registerSettingsTab() {
        let tab = MTMenuTabID.appearanceProfileSettings
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: InterfaceMenu.settingsTab, screen: .tab(tab), order: 500, header: { MTStrings.Interface.Menu.settingsTabHeader }, footer: { _ in MTStrings.Interface.Menu.settingsTabFooter }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.settingsTab.items", section: InterfaceMenu.settingsTab, order: 100, title: { MTStrings.Interface.SettingsTab.itemsTitle }, subtitle: { MTStrings.Interface.Menu.settingsItemsInfo }, kind: .action({ menu in
            menu.push(MTSettingsTabScreens.makeScreen(context: menu.context))
        }), searchKeywords: { [MTStrings.Interface.Menu.settingsItemsKeywords] }, label: { _ in
            let count = InterfaceSettings.hiddenSettingsItems.value.count
            return count == 0 ? nil : MTStrings.Interface.Menu.hiddenCount(count: count)
        }))
        MTMenuRegistry.register(MTMenuRow(id: "interface.settingsTab.shortcuts", section: InterfaceMenu.settingsTab, order: 200, title: { MTStrings.Interface.Shortcuts.title }, subtitle: { MTStrings.Interface.Menu.shortcutsInfo }, kind: .action({ menu in
            menu.push(MTShortcutScreens.makeScreen(context: menu.context))
        }), searchKeywords: { [MTStrings.Interface.Menu.shortcutsKeywords] }, label: { menu in
            let count = InterfaceSettings.settingsShortcuts.value(for: menu.accountID).count
            return count == 0 ? nil : "\(count)"
        }))
    }
}
