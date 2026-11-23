import Foundation
import MTCore

// Settings of the «Сообщения» zone. Declared here, in the light shared module, because
// upstream modules below the feature layer (TranslateUI, ChatPresentationInterfaceState, the chat
// nodes, TelegramUI) and the notification service read some of them. Each is declared once.
// Toggles default to off; `messageMenu.*` children only matter while their master is on.

public enum MTTranslationServiceKind: String {
    case telegram
    case google
    case system
}

public enum MTNotificationDeliveryMode: String {
    case standard = "default"
    case silent
    case disabled
}

public enum MTMessagesSettings {
    // MARK: Restrictions («Обходы ограничений»)
    public static let copyProtectionBypass = MTSetting<Bool>("restrictions.copyProtectionBypass", default: false)
    public static let forwardAttribution = MTSetting<Bool>("restrictions.forwardAttribution", default: false)
    public static let keepSelfDestructingMedia = MTSetting<Bool>("restrictions.keepSelfDestructingMedia", default: false)
    public static let screenshotBypass = MTSetting<Bool>("restrictions.screenshotBypass", default: false)
    public static let blockAds = MTSetting<Bool>("restrictions.blockAds", default: false)
    public static let contentRestrictionsBypass = MTSetting<Bool>("restrictions.contentRestrictionsBypass", default: false)
    public static let revealSpoilers = MTSetting<Bool>("restrictions.revealSpoilers", default: false)

    // MARK: Sending («Отправка»)
    public static let wordReplacement = MTSetting<Bool>("sending.wordReplacement", default: false)
    public static let antiCaps = MTSetting<Bool>("sending.antiCaps", default: false)
    public static let hyperlinkSpoof = MTSetting<Bool>("sending.hyperlinkSpoof", default: false)
    /// The profile every outgoing text links to; per account (a peer of that account).
    public static let hyperlinkTarget = MTAccountSetting<MTPeerKey?>("sending.hyperlinkTarget", default: nil)
    public static let autoQuoteReply = MTSetting<Bool>("sending.autoQuoteReply", default: false)
    /// Sub-option of the quote: comments under channel posts are answered without a quote.
    public static let autoQuoteSkipComments = MTSetting<Bool>("sending.autoQuoteSkipComments", default: true)
    public static let anonymousStickers = MTSetting<Bool>("sending.anonymousStickers", default: false)
    public static let sendWithoutViaBot = MTSetting<Bool>("sending.sendWithoutViaBot", default: false)
    /// Sub-option: keep the bot's caption when the result is re-sent as a normal message.
    public static let keepInlineBotCaption = MTSetting<Bool>("sending.keepInlineBotCaption", default: true)
    public static let sendOnReturn = MTSetting<Bool>("sending.sendOnReturn", default: false)
    public static let hideSendAsButton = MTSetting<Bool>("sending.hideSendAsButton", default: false)

    // MARK: Translation («Перевод»)
    public static let translationService = MTSetting<String>("translation.service", default: MTTranslationServiceKind.google.rawValue)
    /// The user saw and accepted the notice that texts go to a third-party service.
    public static let translationThirdPartyAccepted = MTSetting<Bool>("translation.thirdPartyAccepted", default: true, flags: [.noExport])
    public static let quickTranslateButton = MTSetting<Bool>("translation.quickButton", default: false)
    public static let translateBeforeSending = MTSetting<Bool>("translation.beforeSending", default: false)
    public static let translateBeforeSendingLanguage = MTSetting<String>("translation.beforeSendingLanguage", default: "en")
    /// Outgoing language per chat (peer key → language code); per account.
    public static let outgoingLanguages = MTAccountSetting<[String: String]>("translation.outgoingLanguages", default: [:])
    public static let photoTranslation = MTSetting<Bool>("translation.photo", default: false)

    // MARK: Message menu and gestures («Меню и жесты»)
    // Defaults follow Swiftgram (MediaTok,: its menu always has «В Избранное»,
    // «Без автора» and «Ограничить» (`contextShow…` = true), so the custom menu and these items are on;
    // Telegram's own items stay shown. Turned-off items are hidden — no «MediaTok» submenu, and no
    // «Выбрать от автора» (both removed by the.
    public static let customMessageMenu = MTSetting<Bool>("messageMenu.custom", default: true)
    public static let menuShowReply = MTSetting<Bool>("messageMenu.reply", default: true)
    public static let menuShowPin = MTSetting<Bool>("messageMenu.pin", default: true)
    public static let menuShowReport = MTSetting<Bool>("messageMenu.report", default: true)
    public static let menuShowRestrict = MTSetting<Bool>("messageMenu.restrict", default: true)
    public static let menuShowSaveMedia = MTSetting<Bool>("messageMenu.saveMedia", default: true)
    public static let menuShowReplies = MTSetting<Bool>("messageMenu.replies", default: true)
    public static let menuSaveToCloud = MTSetting<Bool>("messageMenu.saveToCloud", default: true)
    public static let menuForwardWithoutAuthor = MTSetting<Bool>("messageMenu.forwardWithoutAuthor", default: true)
    public static let doubleTapToEdit = MTSetting<Bool>("gestures.doubleTapToEdit", default: false)
    public static let disableVideoPipSwipe = MTSetting<Bool>("gestures.disableVideoPipSwipe", default: false)

    // MARK: Chats («Чаты»)
    // «Безлимитные закрепы» have no setting: always on; their per-account
    // state lives in the account's Postbox (MTMessages, `MTPinnedTailStore`).
    public static let unlimitedSearchHistory = MTSetting<Bool>("chats.unlimitedSearchHistory", default: false)
    public static let hideGreetingSticker = MTSetting<Bool>("chats.hideGreetingSticker", default: false)
    public static let keywordFilter = MTSetting<Bool>("chats.keywordFilter", default: false)
    public static let keywords = MTSetting<[String]>("chats.keywords", default: [])
    public static let hideChannelBottomButton = MTSetting<Bool>("chats.hideChannelBottomButton", default: false)
    /// «Без перехода к следующему каналу и теме»: one switch since 2026-10-27 (was one per channel / topic).
    public static let disableScrollToNext = MTSetting<Bool>("chats.disableScrollToNext", default: false)
    public static let disableDeleteEffect = MTSetting<Bool>("chats.disableDeleteEffect", default: false)
    public static let hideRecordButton = MTSetting<Bool>("chats.hideRecordButton", default: false)
    /// Channels shown as if the user created them («локальный режим»); per account.
    public static let localCreatorChannels = MTAccountSetting<Set<MTPeerKey>>("chats.localCreatorChannels", default: [])

    // MARK: Notifications («Уведомления», read by the notification service)
    public static let pinnedNotifications = MTSetting<String>("notifications.pinned", default: MTNotificationDeliveryMode.standard.rawValue, scope: .appGroup, flags: [.extensions])
    public static let mentionNotifications = MTSetting<String>("notifications.mentions", default: MTNotificationDeliveryMode.standard.rawValue, scope: .appGroup, flags: [.extensions])
    /// Per chat (peer key → mode), per account.
    public static let pinnedNotificationExceptions = MTAccountSetting<[String: String]>("notifications.pinnedExceptions", default: [:], flags: [.extensions])
    public static let mentionNotificationExceptions = MTAccountSetting<[String: String]>("notifications.mentionExceptions", default: [:], flags: [.extensions])

    /// Touches every declaration so the registry knows them before export, search and migrations.
    static func declare() {
        let _ = MTMessagesSettings.copyProtectionBypass
        let _ = MTMessagesSettings.forwardAttribution
        let _ = MTMessagesSettings.keepSelfDestructingMedia
        let _ = MTMessagesSettings.screenshotBypass
        let _ = MTMessagesSettings.blockAds
        let _ = MTMessagesSettings.contentRestrictionsBypass
        let _ = MTMessagesSettings.revealSpoilers
        let _ = MTMessagesSettings.wordReplacement
        let _ = MTMessagesSettings.antiCaps
        let _ = MTMessagesSettings.hyperlinkSpoof
        let _ = MTMessagesSettings.hyperlinkTarget
        let _ = MTMessagesSettings.autoQuoteReply
        let _ = MTMessagesSettings.autoQuoteSkipComments
        let _ = MTMessagesSettings.anonymousStickers
        let _ = MTMessagesSettings.sendWithoutViaBot
        let _ = MTMessagesSettings.keepInlineBotCaption
        let _ = MTMessagesSettings.sendOnReturn
        let _ = MTMessagesSettings.hideSendAsButton
        let _ = MTMessagesSettings.translationService
        let _ = MTMessagesSettings.translationThirdPartyAccepted
        let _ = MTMessagesSettings.quickTranslateButton
        let _ = MTMessagesSettings.translateBeforeSending
        let _ = MTMessagesSettings.translateBeforeSendingLanguage
        let _ = MTMessagesSettings.outgoingLanguages
        let _ = MTMessagesSettings.photoTranslation
        let _ = MTMessagesSettings.customMessageMenu
        let _ = MTMessagesSettings.menuShowReply
        let _ = MTMessagesSettings.menuShowPin
        let _ = MTMessagesSettings.menuShowReport
        let _ = MTMessagesSettings.menuShowRestrict
        let _ = MTMessagesSettings.menuShowSaveMedia
        let _ = MTMessagesSettings.menuShowReplies
        let _ = MTMessagesSettings.menuSaveToCloud
        let _ = MTMessagesSettings.menuForwardWithoutAuthor
        let _ = MTMessagesSettings.doubleTapToEdit
        let _ = MTMessagesSettings.disableVideoPipSwipe
        let _ = MTMessagesSettings.unlimitedSearchHistory
        let _ = MTMessagesSettings.hideGreetingSticker
        let _ = MTMessagesSettings.keywordFilter
        let _ = MTMessagesSettings.keywords
        let _ = MTMessagesSettings.hideChannelBottomButton
        let _ = MTMessagesSettings.disableScrollToNext
        let _ = MTMessagesSettings.disableDeleteEffect
        let _ = MTMessagesSettings.hideRecordButton
        let _ = MTMessagesSettings.localCreatorChannels
        let _ = MTMessagesSettings.pinnedNotifications
        let _ = MTMessagesSettings.mentionNotifications
        let _ = MTMessagesSettings.pinnedNotificationExceptions
        let _ = MTMessagesSettings.mentionNotificationExceptions
    }
}
