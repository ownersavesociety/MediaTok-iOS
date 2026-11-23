import Foundation
import SwiftSignalKit
import MTCore
import MTHooks
import MTSettingsUI
import MTFeaturesShared

/// Where the Swiftgram-parity features live in the MediaTok menu: next to the similar rows
/// of each tab, in a few sections of their own. No new tab: every feature found its place.
enum MTExtrasMenu {
    // Own sections.
    static let linksSection = MTMenuSectionID("extras.links")
    static let messageToolsSection = MTMenuSectionID("extras.messageTools")
    static let groupsSection = MTMenuSectionID("extras.groups")
    static let chatListMenuSection = MTMenuSectionID("extras.chatListMenu")
    static let languageSection = MTMenuSectionID("extras.language")
    static let cacheSection = MTMenuSectionID("extras.cache")
    static let sessionsSection = MTMenuSectionID("extras.sessions")
    /// Right under «Уведомления» (no header of its own: the zone's footer speaks of chat exceptions).
    static let notificationsSection = MTMenuSectionID("extras.notifications")
    static let videoSection = MTMenuSectionID("extras.video")

    // Sections of other zones the rows join (at the end, after their own rows).
    static let sendingInputSection = MTMenuSectionID("sending.input")
    static let passcodeOptionsSection = MTMenuSectionID("security.passcode.options")
    /// MediaTok's «Таббар» section of «Панели».
    static let panelsTabBarSection = MTMenuSectionID("appearance.panels.tabBar")

    static func register() {
        MTExtrasMenu.registerSections()
        MTExtrasMenu.registerMessages()
        MTExtrasMenu.registerGroups()
        MTExtrasMenu.registerAppearance()
        MTExtrasMenu.registerMedia()
        MTExtrasMenu.registerSecurity()
    }

    private static func registerSections() {
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTExtrasMenu.linksSection, screen: .tab(.messagesMenuGestures), order: 400, header: { MTStrings.Extras.Menu.linksHeader }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTExtrasMenu.messageToolsSection, screen: .tab(.messagesMenuGestures), order: 500, header: { MTStrings.Extras.Menu.messageToolsHeader }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTExtrasMenu.groupsSection, screen: .category(.messages), order: 350, header: { MTStrings.Extras.Menu.groupsHeader }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTExtrasMenu.chatListMenuSection, screen: .tab(.appearanceChatList), order: 700, header: { MTStrings.Extras.Menu.chatListMenuHeader }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTExtrasMenu.languageSection, screen: .tab(.appearanceProfileSettings), order: 600, header: { MTStrings.Extras.Menu.languageHeader }, footer: { _ in MTStrings.Extras.Menu.languageFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTExtrasMenu.cacheSection, screen: .tab(.mediaDownloads), order: 700, header: { MTStrings.Extras.Menu.cacheHeader }, footer: { _ in MTStrings.Extras.Menu.cacheFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTExtrasMenu.sessionsSection, screen: .tab(.securityAccounts), order: 400, header: { MTStrings.Extras.Menu.sessionsHeader }, footer: { _ in MTStrings.Extras.Menu.sessionsFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTExtrasMenu.notificationsSection, screen: .category(.messages), order: 410))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTExtrasMenu.videoSection, screen: .tab(.mediaDownloads), order: 650, header: { MTStrings.Extras.Menu.videoHeader }))
    }

    // MARK: Сообщения

    private static func registerMessages() {
        // Under «Уведомления» (category screen).
        MTMenuRegistry.register(toggle("extras.extraMuteDurations", section: MTExtrasMenu.notificationsSection, order: 100, setting: MTExtrasSettings.extraMuteDurations, title: { MTStrings.Extras.Menu.extraMuteDurations }, subtitle: { MTStrings.Extras.Menu.extraMuteDurationsInfo }))
        MTMenuRegistry.register(toggle("extras.hideAccountInNotifications", section: MTExtrasMenu.notificationsSection, order: 200, setting: MTExtrasSettings.hideAccountInNotifications, title: { MTStrings.Extras.Menu.hideAccountInNotifications }, subtitle: { MTStrings.Extras.Menu.hideAccountInNotificationsInfo }))

        // «Чаты» (category screen).
        MTMenuRegistry.register(toggle("extras.searchPartialWords", section: .messagesChats, order: 1200, setting: MTExtrasSettings.searchPartialWords, title: { MTStrings.Extras.Menu.searchPartialWords }, subtitle: { MTStrings.Extras.Menu.searchPartialWordsInfo }))

        // «Отправка» › «Ввод».
        MTMenuRegistry.register(toggle("extras.mentionChain", section: MTExtrasMenu.sendingInputSection, order: 9000, setting: MTExtrasSettings.mentionChain, title: { MTStrings.Extras.Menu.mentionChain }, subtitle: { MTStrings.Extras.Menu.mentionChainInfo }))
        MTMenuRegistry.register(toggle("extras.noRecordTooltip", section: MTExtrasMenu.sendingInputSection, order: 9100, setting: MTExtrasSettings.noRecordTooltip, title: { MTStrings.Extras.Menu.noRecordTooltip }, subtitle: { MTStrings.Extras.Menu.noRecordTooltipInfo }))

        // «Меню и жесты» › «Ссылки и «Поделиться»».
        let links = MTExtrasMenu.linksSection
        MTMenuRegistry.register(toggle("extras.linkPreviewOpensMedia", section: links, order: 100, setting: MTExtrasSettings.linkPreviewOpensMedia, title: { MTStrings.Extras.Menu.linkPreviewOpensMedia }, subtitle: { MTStrings.Extras.Menu.linkPreviewOpensMediaInfo }))
        MTMenuRegistry.register(toggle("extras.linkMenuShare", section: links, order: 200, setting: MTExtrasSettings.linkMenuShare, title: { MTStrings.Extras.Menu.linkMenuShare }, subtitle: { MTStrings.Extras.Menu.linkMenuShareInfo }))
        MTMenuRegistry.register(toggle("extras.bioLinks", section: links, order: 300, setting: MTExtrasSettings.bioLinks, title: { MTStrings.Extras.Menu.bioLinks }, subtitle: { MTStrings.Extras.Menu.bioLinksInfo }))
        MTMenuRegistry.register(toggle("extras.moreBrowsers", section: links, order: 400, setting: MTExtrasSettings.moreBrowsers, title: { MTStrings.Extras.Menu.moreBrowsers }, subtitle: { MTStrings.Extras.Menu.moreBrowsersInfo }))
        MTMenuRegistry.register(toggle("extras.systemShareSheet", section: links, order: 500, setting: MTExtrasSettings.systemShareSheet, title: { MTStrings.Extras.Menu.systemShareSheet }, subtitle: { MTStrings.Extras.Menu.systemShareSheetInfo }))
        MTMenuRegistry.register(toggle("extras.hideRepostToStory", section: links, order: 600, setting: MTExtrasSettings.hideRepostToStory, title: { MTStrings.Extras.Menu.hideRepostToStory }, subtitle: { MTStrings.Extras.Menu.hideRepostToStoryInfo }))

        // «Меню и жесты» › «Меню и выделение».
        let tools = MTExtrasMenu.messageToolsSection
        MTMenuRegistry.register(toggle("extras.selectionPanelButtons", section: tools, order: 200, setting: MTExtrasSettings.selectionPanelButtons, title: { MTStrings.Extras.Menu.selectionPanelButtons }, subtitle: { MTStrings.Extras.Menu.selectionPanelButtonsInfo }))
    }

    // MARK: Сообщения › Группы и каналы

    private static func registerGroups() {
        let section = MTExtrasMenu.groupsSection
        MTMenuRegistry.register(toggle("extras.adminListsForAllAdmins", section: section, order: 100, setting: MTExtrasSettings.adminListsForAllAdmins, title: { MTStrings.Extras.Menu.adminListsForAllAdmins }, subtitle: { MTStrings.Extras.Menu.adminListsForAllAdminsInfo }))
        MTMenuRegistry.register(toggle("extras.recentActionsShortcut", section: section, order: 200, setting: MTExtrasSettings.recentActionsShortcut, title: { MTStrings.Extras.Menu.recentActionsShortcut }, subtitle: { MTStrings.Extras.Menu.recentActionsShortcutInfo }))
        MTMenuRegistry.register(toggle("extras.administratorsMenuItem", section: section, order: 300, setting: MTExtrasSettings.administratorsMenuItem, title: { MTStrings.Extras.Menu.administratorsMenuItem }, subtitle: { MTStrings.Extras.Menu.administratorsMenuItemInfo }))
        MTMenuRegistry.register(toggle("extras.hiddenPinnedMenuItem", section: section, order: 400, setting: MTExtrasSettings.hiddenPinnedMenuItem, title: { MTStrings.Extras.Menu.hiddenPinnedMenuItem }, subtitle: { MTStrings.Extras.Menu.hiddenPinnedMenuItemInfo }))
        MTMenuRegistry.register(toggle("extras.restrictUntilTime", section: section, order: 500, setting: MTExtrasSettings.restrictUntilTime, title: { MTStrings.Extras.Menu.restrictUntilTime }, subtitle: { MTStrings.Extras.Menu.restrictUntilTimeInfo }))
        MTMenuRegistry.register(toggle("extras.restrictionReasonCode", section: section, order: 600, setting: MTExtrasSettings.restrictionReasonCode, title: { MTStrings.Extras.Menu.restrictionReasonCode }, subtitle: { MTStrings.Extras.Menu.restrictionReasonCodeInfo }))
        MTMenuRegistry.register(toggle("extras.discussionButton", section: section, order: 700, setting: MTExtrasSettings.discussionButton, title: { MTStrings.Extras.Menu.discussionButton }, subtitle: { MTStrings.Extras.Menu.discussionButtonInfo }))
    }

    // MARK: Оформление

    private static func registerAppearance() {
        let chatList = MTExtrasMenu.chatListMenuSection
        MTMenuRegistry.register(toggle("extras.archiveInChatMenu", section: chatList, order: 100, setting: MTExtrasSettings.archiveInChatMenu, title: { MTStrings.Extras.Menu.archiveInChatMenu }, subtitle: { MTStrings.Extras.Menu.archiveInChatMenuInfo }))
        MTMenuRegistry.register(toggle("extras.hidePremiumOffers", section: chatList, order: 200, setting: MTExtrasSettings.hidePremiumOffers, title: { MTStrings.Extras.Menu.hidePremiumOffers }, subtitle: { MTStrings.Extras.Menu.hidePremiumOffersInfo }))

        // «Панели» › tab bar.

        MTMenuRegistry.register(toggle("extras.extraLanguages", section: MTExtrasMenu.languageSection, order: 100, setting: MTExtrasSettings.extraLanguages, title: { MTStrings.Extras.Menu.extraLanguages }, subtitle: { MTStrings.Extras.Menu.extraLanguagesInfo }))
    }

    // MARK: Медиа › Загрузки и качество

    private static func registerMedia() {
        MTMenuRegistry.register(toggle("extras.youTubePictureInPicture", section: MTExtrasMenu.videoSection, order: 100, setting: MTExtrasSettings.youTubePictureInPicture, title: { MTStrings.Extras.Menu.youTubePictureInPicture }, subtitle: { MTStrings.Extras.Menu.youTubePictureInPictureInfo }))
        MTMenuRegistry.register(toggle("extras.extraCacheOptions", section: MTExtrasMenu.cacheSection, order: 100, setting: MTExtrasSettings.extraCacheOptions, title: { MTStrings.Extras.Menu.extraCacheOptions }, subtitle: { MTStrings.Extras.Menu.extraCacheOptionsInfo }))
    }

    // MARK: Безопасность

    private static func registerSecurity() {
        MTMenuRegistry.register(toggle("extras.autolockFiveSeconds", section: MTExtrasMenu.passcodeOptionsSection, order: 9000, setting: MTExtrasSettings.autolockFiveSeconds, title: { MTStrings.Extras.Menu.autolockFiveSeconds }, subtitle: { MTStrings.Extras.Menu.autolockFiveSecondsInfo }))
        let sessions = MTExtrasMenu.sessionsSection
        MTMenuRegistry.register(toggle("extras.sessionDetails", section: sessions, order: 100, setting: MTExtrasSettings.sessionDetails, title: { MTStrings.Extras.Menu.sessionDetails }, subtitle: { MTStrings.Extras.Menu.sessionDetailsInfo }))
        MTMenuRegistry.register(toggle("extras.qrLoginAlways", section: sessions, order: 200, setting: MTExtrasSettings.qrLoginAlways, title: { MTStrings.Extras.Menu.qrLoginAlways }, subtitle: { MTStrings.Extras.Menu.qrLoginAlwaysInfo }))
        MTMenuRegistry.register(MTMenuRow(id: "extras.logoutReason", section: sessions, order: 300, title: { MTStrings.Extras.Menu.logoutReason }, subtitle: { MTStrings.Extras.Menu.logoutReasonInfo }, kind: .toggle(.global(MTExtrasSettings.logoutReason)), isVisible: { _ in false })) // MediaTok: hidden
        // «Аккаунты», after its own rows.
        MTMenuRegistry.register(toggle("extras.addAccountRow", section: MTMenuSectionID.main(of: MTMenuTabID.securityAccounts), order: 9000, setting: MTExtrasSettings.addAccountRow, title: { MTStrings.Extras.Menu.addAccountRow }, subtitle: { MTStrings.Extras.Menu.addAccountRowInfo }))
        // The row is built with the Settings tab, which Telegram rebuilds only when its own data
        // changes: the switch rebuilds it at once.
        MTExtrasMenu.addAccountRowDisposable = (MTExtrasSettings.addAccountRow.signal
        |> deliverOnMainQueue).start(next: { _ in
            MTSettingsTabHooks.invalidate()
        })
    }

    private static var addAccountRowDisposable: Disposable?

    private static func toggle(_ id: String, section: MTMenuSectionID, order: Int, setting: MTSetting<Bool>, title: @escaping () -> String, subtitle: (() -> String)? = nil) -> MTMenuRow {
        return MTMenuRow(id: id, section: section, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting)))
    }
}
