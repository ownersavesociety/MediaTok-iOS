import Foundation
import MTCore

// The fixed part of the menu: six categories, every tab with its
// «кнопка с подписью», and the sections features register their rows into. Each tab gets two
// sections: `<tab>.preview` (order 100) and `<tab>.main` (order 200); features add more as needed.

extension MTMenuCategory {
    public var title: String {
        switch self {
        case .privacy:
            return MTStrings.Menu.Category.privacy
        case .messages:
            return MTStrings.Menu.Category.messages
        case .media:
            return MTStrings.Menu.Category.media
        case .appearance:
            return MTStrings.Menu.Category.appearance
        case .security:
            return MTStrings.Menu.Category.security
        case .more:
            return MTStrings.Menu.Category.more
        }
    }

    public var subtitle: String {
        switch self {
        case .privacy:
            return MTStrings.Menu.Category.privacyInfo
        case .messages:
            return MTStrings.Menu.Category.messagesInfo
        case .media:
            return MTStrings.Menu.Category.mediaInfo
        case .appearance:
            return MTStrings.Menu.Category.appearanceInfo
        case .security:
            return MTStrings.Menu.Category.securityInfo
        case .more:
            return MTStrings.Menu.Category.moreInfo
        }
    }

    public var icon: MTMenuIcon {
        switch self {
        case .privacy:
            return .ghost
        case .messages:
            return .bundle("Chat/Context Menu/Message")
        case .media:
            return .bundle("Chat/Context Menu/Image")
        case .appearance:
            return .bundle("Chat/Context Menu/Customize")
        case .security:
            return .bundle("Chat/Context Menu/Lock")
        case .more:
            return .bundle("Chat/Context Menu/More")
        }
    }
}

extension MTMenuTabID {
    // Privacy
    public static let privacyGhostExceptions = MTMenuTabID("privacy.ghostExceptions")
    public static let privacySendDelay = MTMenuTabID("privacy.sendDelay")
    public static let privacySpoofing = MTMenuTabID("privacy.spoofing")
    public static let privacyAnonymousMode = MTMenuTabID("privacy.anonymousMode")
    // Messages
    public static let messagesAntiDelete = MTMenuTabID("messages.antiDelete")
    public static let messagesRestrictions = MTMenuTabID("messages.restrictions")
    public static let messagesSending = MTMenuTabID("messages.sending")
    public static let messagesTranslation = MTMenuTabID("messages.translation")
    public static let messagesMenuGestures = MTMenuTabID("messages.menuGestures")
    public static let messagesExport = MTMenuTabID("messages.export")
    // Media and calls
    public static let mediaVoice = MTMenuTabID("media.voice")
    public static let mediaCameraVideoMessages = MTMenuTabID("media.cameraVideoMessages")
    public static let mediaCalls = MTMenuTabID("media.calls")
    public static let mediaDownloads = MTMenuTabID("media.downloads")
    // Appearance
    public static let appearanceMessages = MTMenuTabID("appearance.messages")
    public static let appearanceChatList = MTMenuTabID("appearance.chatList")
    public static let appearancePanels = MTMenuTabID("appearance.panels")
    public static let appearanceThemeBackground = MTMenuTabID("appearance.themeBackground")
    public static let appearanceIcons = MTMenuTabID("appearance.icons")
    public static let appearanceProfileSettings = MTMenuTabID("appearance.profileSettings")
    // Security
    public static let securityChatProtection = MTMenuTabID("security.chatProtection")
    public static let securityPasscode = MTMenuTabID("security.passcode")
    public static let securityAccounts = MTMenuTabID("security.accounts")
    // More
    public static let moreVpn = MTMenuTabID("more.vpn")
    public static let moreNickBadge = MTMenuTabID("more.nickBadge")
    public static let moreFakeGifts = MTMenuTabID("more.fakeGifts")
    public static let moreMediaTokSettings = MTMenuTabID("more.mediatokSettings")
    public static let moreAbout = MTMenuTabID("more.about")
}

extension MTMenuSectionID {
    // Category screens
    public static let privacyPreview = MTMenuSectionID("privacy.preview")
    public static let privacyGhostMode = MTMenuSectionID("privacy.ghostMode")
    public static let privacyTabs = MTMenuSectionID("privacy.tabs")
    public static let privacyTraces = MTMenuSectionID("privacy.traces")
    public static let messagesPreview = MTMenuSectionID("messages.preview")
    public static let messagesTabs = MTMenuSectionID("messages.tabs")
    public static let messagesChats = MTMenuSectionID("messages.chats")
    public static let mediaTabs = MTMenuSectionID("media.tabs")
    public static let appearanceTabs = MTMenuSectionID("appearance.tabs")
    public static let securityTabs = MTMenuSectionID("security.tabs")
    public static let moreTabs = MTMenuSectionID("more.tabs")
    // «Настройки MediaTok» and «О приложении»
    public static let mediatokSettingsLanguage = MTMenuSectionID("more.mediatokSettings.language")
    public static let mediatokSettingsData = MTMenuSectionID("more.mediatokSettings.data")
    public static let aboutInfo = MTMenuSectionID("more.about.info")
    public static let aboutLinks = MTMenuSectionID("more.about.links")
    public static let aboutLicense = MTMenuSectionID("more.about.license")

    /// `<tab>.preview`, order 100 on the tab screen.
    public static func preview(of tab: MTMenuTabID) -> MTMenuSectionID {
        return MTMenuSectionID(tab.rawValue + ".preview")
    }

    /// `<tab>.main`, order 200 on the tab screen.
    public static func main(of tab: MTMenuTabID) -> MTMenuSectionID {
        return MTMenuSectionID(tab.rawValue + ".main")
    }
}

private struct MTSkeletonTab {
    let id: MTMenuTabID
    let section: MTMenuSectionID
    let order: Int
    let title: () -> String
    let info: () -> String
    let icon: MTMenuIcon
    let emoji: String
}

private func mtSkeletonTabs() -> [MTSkeletonTab] {
    return [
        MTSkeletonTab(id: .privacyGhostExceptions, section: .privacyTabs, order: 100, title: { MTStrings.Menu.Tab.Privacy.ghostExceptions }, info: { MTStrings.Menu.Tab.Privacy.ghostExceptionsInfo }, icon: .bundle("Chat/Context Menu/Eye"), emoji: "👥"),
        MTSkeletonTab(id: .privacySendDelay, section: .privacyTabs, order: 200, title: { MTStrings.Menu.Tab.Privacy.sendDelay }, info: { MTStrings.Menu.Tab.Privacy.sendDelayInfo }, icon: .bundle("Chat/Context Menu/Schedule"), emoji: "⏳"),
        MTSkeletonTab(id: .privacySpoofing, section: .privacyTabs, order: 300, title: { MTStrings.Menu.Tab.Privacy.spoofing }, info: { MTStrings.Menu.Tab.Privacy.spoofingInfo }, icon: .bundle("Chat/Context Menu/Replace"), emoji: "🎭"),
        MTSkeletonTab(id: .privacyAnonymousMode, section: .privacyTabs, order: 400, title: { MTStrings.Menu.Tab.Privacy.anonymousMode }, info: { MTStrings.Menu.Tab.Privacy.anonymousModeInfo }, icon: .bundle("Chat/Context Menu/EyeLocked"), emoji: "🕶"),

        MTSkeletonTab(id: .messagesAntiDelete, section: .messagesTabs, order: 100, title: { MTStrings.Menu.Tab.Messages.antiDelete }, info: { MTStrings.Menu.Tab.Messages.antiDeleteInfo }, icon: .bundle("Chat/Context Menu/Delete"), emoji: "🗑"),
        MTSkeletonTab(id: .messagesRestrictions, section: .messagesTabs, order: 200, title: { MTStrings.Menu.Tab.Messages.restrictions }, info: { MTStrings.Menu.Tab.Messages.restrictionsInfo }, icon: .bundle("Chat/Context Menu/Copy"), emoji: "🔓"),
        MTSkeletonTab(id: .messagesSending, section: .messagesTabs, order: 300, title: { MTStrings.Menu.Tab.Messages.sending }, info: { MTStrings.Menu.Tab.Messages.sendingInfo }, icon: .bundle("Chat/Context Menu/FormatText"), emoji: "✉️"),
        MTSkeletonTab(id: .messagesTranslation, section: .messagesTabs, order: 400, title: { MTStrings.Menu.Tab.Messages.translation }, info: { MTStrings.Menu.Tab.Messages.translationInfo }, icon: .bundle("Chat/Context Menu/Translate"), emoji: "🌐"),
        MTSkeletonTab(id: .messagesMenuGestures, section: .messagesTabs, order: 500, title: { MTStrings.Menu.Tab.Messages.menuGestures }, info: { MTStrings.Menu.Tab.Messages.menuGesturesInfo }, icon: .bundle("Chat/Context Menu/List"), emoji: "👆"),
        MTSkeletonTab(id: .messagesExport, section: .messagesTabs, order: 600, title: { MTStrings.Menu.Tab.Messages.export }, info: { MTStrings.Menu.Tab.Messages.exportInfo }, icon: .bundle("Chat/Context Menu/Share"), emoji: "📦"),

        MTSkeletonTab(id: .mediaVoice, section: .mediaTabs, order: 100, title: { MTStrings.Menu.Tab.Media.voice }, info: { MTStrings.Menu.Tab.Media.voiceInfo }, icon: .bundle("Chat/Context Menu/VoiceChat"), emoji: "🎙"),
        MTSkeletonTab(id: .mediaCameraVideoMessages, section: .mediaTabs, order: 200, title: { MTStrings.Menu.Tab.Media.cameraVideoMessages }, info: { MTStrings.Menu.Tab.Media.cameraVideoMessagesInfo }, icon: .bundle("Chat/Context Menu/Camera"), emoji: "📹"),
        MTSkeletonTab(id: .mediaCalls, section: .mediaTabs, order: 300, title: { MTStrings.Menu.Tab.Media.calls }, info: { MTStrings.Menu.Tab.Media.callsInfo }, icon: .bundle("Chat/Context Menu/PhoneCall"), emoji: "📞"),
        MTSkeletonTab(id: .mediaDownloads, section: .mediaTabs, order: 400, title: { MTStrings.Menu.Tab.Media.downloads }, info: { MTStrings.Menu.Tab.Media.downloadsInfo }, icon: .bundle("Chat/Context Menu/Download"), emoji: "⚡️"),

        MTSkeletonTab(id: .appearanceMessages, section: .appearanceTabs, order: 100, title: { MTStrings.Menu.Tab.Appearance.messages }, info: { MTStrings.Menu.Tab.Appearance.messagesInfo }, icon: .bundle("Chat/Context Menu/MessageBubble"), emoji: "💬"),
        MTSkeletonTab(id: .appearanceChatList, section: .appearanceTabs, order: 200, title: { MTStrings.Menu.Tab.Appearance.chatList }, info: { MTStrings.Menu.Tab.Appearance.chatListInfo }, icon: .bundle("Chat/Context Menu/Chats"), emoji: "📋"),
        MTSkeletonTab(id: .appearancePanels, section: .appearanceTabs, order: 300, title: { MTStrings.Menu.Tab.Appearance.panels }, info: { MTStrings.Menu.Tab.Appearance.panelsInfo }, icon: .bundle("Chat/Context Menu/AlignBottom"), emoji: "🧩"),
        MTSkeletonTab(id: .appearanceThemeBackground, section: .appearanceTabs, order: 400, title: { MTStrings.Menu.Tab.Appearance.themeBackground }, info: { MTStrings.Menu.Tab.Appearance.themeBackgroundInfo }, icon: .bundle("Chat/Context Menu/ApplyTheme"), emoji: "🎨"),
        MTSkeletonTab(id: .appearanceIcons, section: .appearanceTabs, order: 500, title: { MTStrings.Menu.Tab.Appearance.icons }, info: { MTStrings.Menu.Tab.Appearance.iconsInfo }, icon: .bundle("Chat/Context Menu/Apps"), emoji: "🖼"),
        MTSkeletonTab(id: .appearanceProfileSettings, section: .appearanceTabs, order: 600, title: { MTStrings.Menu.Tab.Appearance.profileSettings }, info: { MTStrings.Menu.Tab.Appearance.profileSettingsInfo }, icon: .bundle("Chat/Context Menu/User"), emoji: "🪪"),

        MTSkeletonTab(id: .securityChatProtection, section: .securityTabs, order: 100, title: { MTStrings.Menu.Tab.Security.chatProtection }, info: { MTStrings.Menu.Tab.Security.chatProtectionInfo }, icon: .bundle("Chat/Context Menu/Lock"), emoji: "🔐"),
        MTSkeletonTab(id: .securityPasscode, section: .securityTabs, order: 300, title: { MTStrings.Menu.Tab.Security.passcode }, info: { MTStrings.Menu.Tab.Security.passcodeInfo }, icon: .bundle("Chat/Context Menu/FaceId"), emoji: "🔢"),
        MTSkeletonTab(id: .securityAccounts, section: .securityTabs, order: 400, title: { MTStrings.Menu.Tab.Security.accounts }, info: { MTStrings.Menu.Tab.Security.accountsInfo }, icon: .bundle("Chat/Context Menu/AddUser"), emoji: "👤"),

        MTSkeletonTab(id: .moreVpn, section: .moreTabs, order: 100, title: { MTStrings.Menu.Tab.More.vpn }, info: { MTStrings.Menu.Tab.More.vpnInfo }, icon: .bundle("Chat/Context Menu/Globe"), emoji: "🛡"),
        MTSkeletonTab(id: .moreNickBadge, section: .moreTabs, order: 200, title: { MTStrings.Menu.Tab.More.nickBadge }, info: { MTStrings.Menu.Tab.More.nickBadgeInfo }, icon: .bundle("Chat/Context Menu/Tag"), emoji: "🏷"),
        MTSkeletonTab(id: .moreFakeGifts, section: .moreTabs, order: 300, title: { MTStrings.Menu.Tab.More.fakeGifts }, info: { MTStrings.Menu.Tab.More.fakeGiftsInfo }, icon: .bundle("Chat/Context Menu/Gift"), emoji: "🎁"),
        MTSkeletonTab(id: .moreMediaTokSettings, section: .moreTabs, order: 400, title: { MTStrings.Menu.Tab.More.mediatokSettings }, info: { MTStrings.Menu.Tab.More.mediatokSettingsInfo }, icon: .bundle("Chat/Context Menu/Settings"), emoji: "⚙️"),
        MTSkeletonTab(id: .moreAbout, section: .moreTabs, order: 500, title: { MTStrings.Menu.Tab.More.about }, info: { MTStrings.Menu.Tab.More.aboutInfo }, icon: .bundle("Chat/Context Menu/Info"), emoji: "⚡")
    ]
}

func mtRegisterMenuSkeleton() {
    // Category screens.
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .privacyPreview, screen: .category(.privacy), order: 100))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .privacyGhostMode, screen: .category(.privacy), order: 200, header: { MTStrings.Menu.Section.Privacy.ghostMode }))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .privacyTabs, screen: .category(.privacy), order: 300))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .privacyTraces, screen: .category(.privacy), order: 400, header: { MTStrings.Menu.Section.Privacy.traces }))

    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .messagesPreview, screen: .category(.messages), order: 100))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .messagesTabs, screen: .category(.messages), order: 200))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .messagesChats, screen: .category(.messages), order: 300, header: { MTStrings.Menu.Section.Messages.chats }))

    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .mediaTabs, screen: .category(.media), order: 100))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .appearanceTabs, screen: .category(.appearance), order: 100))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .securityTabs, screen: .category(.security), order: 100))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .moreTabs, screen: .category(.more), order: 100))

    // Tabs, their links and their default sections.
    for tab in mtSkeletonTabs() {
        let emoji = tab.emoji
        let info = tab.info
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: tab.id,
                parent: MTMenuStorage.shared.sectionsById[tab.section]?.screen ?? .root,
                title: tab.title,
                topView: MTMenuTopView(content: .emoji(emoji), text: info),
                searchKeywords: { [info()] }
            ),
            linkIn: tab.section,
            order: tab.order,
            subtitle: info,
            icon: tab.icon
        )
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .preview(of: tab.id), screen: .tab(tab.id), order: 100))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .main(of: tab.id), screen: .tab(tab.id), order: 200))
    }

    // «Настройки MediaTok» and «О приложении» carry MediaTok's own rows (see MTSettingsDataScreens.swift).
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .mediatokSettingsLanguage, screen: .tab(.moreMediaTokSettings), order: 300, header: { MTStrings.Menu.Settings.languageHeader }, footer: { _ in MTStrings.Menu.Settings.languageFooter }))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .mediatokSettingsData, screen: .tab(.moreMediaTokSettings), order: 400, header: { MTStrings.Menu.Settings.dataHeader }, footer: { _ in MTStrings.Menu.Settings.dataFooter }))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .aboutInfo, screen: .tab(.moreAbout), order: 300, isVisible: { _ in false }))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .aboutLinks, screen: .tab(.moreAbout), order: 400, header: { MTStrings.Menu.Root.links }, isVisible: { _ in false }))
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .aboutLicense, screen: .tab(.moreAbout), order: 500, header: { MTStrings.Menu.About.licenseHeader }, footer: { _ in MTStrings.Menu.About.licenseFooter }, isVisible: { _ in false }))
}
