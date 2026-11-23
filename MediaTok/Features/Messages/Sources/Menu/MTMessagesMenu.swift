import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PresentationDataUtils
import ItemListUI
import TranslateUI
import MTCore
import MTSettingsUI
import MTFeaturesShared

/// Menu rows of the zone: «Сообщения» › «Обходы ограничений», «Отправка», «Перевод»,
/// «Меню и жесты» and the «Чаты» / «Уведомления» sections of the category screen.
/// Order is sparse (step 100); titles are evaluated at display time.
enum MTMessagesMenu {
    static let rulesTab = MTMenuTabID("sending.rules")
    static let keywordsTab = MTMenuTabID("chats.keywords")
    static let localCreatorTab = MTMenuTabID("chats.localCreator")
    static let exceptionsTab = MTMenuTabID("notifications.exceptions")

    static let sendingTextSection = MTMenuSectionID("sending.text")
    static let sendingRepliesSection = MTMenuSectionID("sending.replies")
    static let sendingInputSection = MTMenuSectionID("sending.input")
    static let translationServiceSection = MTMenuSectionID("translation.service")
    static let gesturesSection = MTMenuSectionID("gestures.main")
    static let notificationsSection = MTMenuSectionID("notifications.main")

    static func register() {
        MTMessagesMenu.registerRestrictions()
        MTMessagesMenu.registerSending()
        MTMessagesMenu.registerTranslation()
        MTMessagesMenu.registerMenuAndGestures()
        MTMessagesMenu.registerChats()
        MTMessagesMenu.registerNotifications()
    }

    private static func toggle(_ id: String, section: MTMenuSectionID, order: Int, setting: MTSetting<Bool>, title: @escaping () -> String, subtitle: (() -> String)? = nil, isVisible: ((MTMenuContext) -> Bool)? = nil, keywords: @escaping () -> [String] = { [] }) -> MTMenuRow {
        return MTMenuRow(id: id, section: section, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting)), isVisible: isVisible, searchKeywords: keywords)
    }

    // MARK: Restrictions

    private static func registerRestrictions() {
        let section = MTMenuSectionID.main(of: .messagesRestrictions)
        MTMenuRegistry.register(toggle("restrictions.copyProtection", section: section, order: 100, setting: MTMessagesSettings.copyProtectionBypass, title: { MTStrings.Restrictions.Menu.copyProtection }, subtitle: { MTStrings.Restrictions.Menu.copyProtectionInfo }, keywords: { [MTStrings.Restrictions.Menu.keywordForward] }))
        MTMenuRegistry.register(toggle("restrictions.forwardAttribution", section: section, order: 200, setting: MTMessagesSettings.forwardAttribution, title: { MTStrings.Restrictions.Menu.forwardAttribution }, subtitle: { MTStrings.Restrictions.Menu.forwardAttributionInfo }, isVisible: { _ in MTMessagesSettings.copyProtectionBypass.value }))
        MTMenuRegistry.register(toggle("restrictions.keepSelfDestructing", section: section, order: 300, setting: MTMessagesSettings.keepSelfDestructingMedia, title: { MTStrings.Restrictions.Menu.keepSelfDestructing }, subtitle: { MTStrings.Restrictions.Menu.keepSelfDestructingInfo }, keywords: { [MTStrings.Restrictions.Menu.keywordViewOnce] }))
        MTMenuRegistry.register(toggle("restrictions.screenshots", section: section, order: 400, setting: MTMessagesSettings.screenshotBypass, title: { MTStrings.Restrictions.Menu.screenshots }, subtitle: { MTStrings.Restrictions.Menu.screenshotsInfo }, keywords: { [MTStrings.Restrictions.Menu.keywordScreenshot] }))
        MTMenuRegistry.register(toggle("restrictions.blockAds", section: section, order: 500, setting: MTMessagesSettings.blockAds, title: { MTStrings.Restrictions.Menu.blockAds }, subtitle: { MTStrings.Restrictions.Menu.blockAdsInfo }))
        MTMenuRegistry.register(toggle("restrictions.contentRestrictions", section: section, order: 600, setting: MTMessagesSettings.contentRestrictionsBypass, title: { MTStrings.Restrictions.Menu.contentRestrictions }, subtitle: { MTStrings.Restrictions.Menu.contentRestrictionsInfo }))
        MTMenuRegistry.register(toggle("restrictions.revealSpoilers", section: section, order: 700, setting: MTMessagesSettings.revealSpoilers, title: { MTStrings.Restrictions.Menu.revealSpoilers }, subtitle: { MTStrings.Restrictions.Menu.revealSpoilersInfo }))
    }

    // MARK: Sending

    private static func registerSending() {
        let screen = MTMenuScreenID.tab(.messagesSending)
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTMessagesMenu.sendingTextSection, screen: screen, order: 300, header: { MTStrings.Sending.Menu.textHeader }, footer: { _ in MTStrings.Sending.Menu.textFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTMessagesMenu.sendingRepliesSection, screen: screen, order: 400, header: { MTStrings.Sending.Menu.repliesHeader }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTMessagesMenu.sendingInputSection, screen: screen, order: 500, header: { MTStrings.Sending.Menu.inputHeader }))

        MTMenuRegistry.register(MTMenuRow(id: "sending.preview", section: .preview(of: .messagesSending), order: 100, title: { "" }, kind: .preview(.miniChat(MTMiniChatConfiguration(scope: "sending", height: 150.0, content: { context in
            return MTSendingPreview.content(context)
        })))))

        let text = MTMessagesMenu.sendingTextSection
        MTMenuRegistry.register(toggle("sending.wordReplacement", section: text, order: 100, setting: MTMessagesSettings.wordReplacement, title: { MTStrings.Sending.Menu.wordReplacement }, subtitle: { MTStrings.Sending.Menu.wordReplacementInfo }, keywords: { [MTStrings.Sending.Menu.keywordText] }))
        MTMenuRegistry.register(tab: MTMenuTabDescriptor(id: MTMessagesMenu.rulesTab, parent: screen, title: { MTStrings.Sending.Rules.title }, makeScreen: { context in
            return mtMakeReplacementRulesScreen(menuContext: context)
        }))
        MTMenuRegistry.register(MTMenuRow(id: "sending.rules", section: text, order: 200, title: { MTStrings.Sending.Menu.rules }, kind: .tab(MTMessagesMenu.rulesTab), isVisible: { _ in MTMessagesSettings.wordReplacement.value }, label: { _ in
            return MTStrings.Sending.Menu.rulesCount(count: MTOutgoingPipeline.replacementRules.value.count)
        }))
        MTMenuRegistry.register(toggle("sending.antiCaps", section: text, order: 300, setting: MTMessagesSettings.antiCaps, title: { MTStrings.Sending.Menu.antiCaps }, subtitle: { MTStrings.Sending.Menu.antiCapsInfo }))
        MTMenuRegistry.register(toggle("sending.hyperlink", section: text, order: 600, setting: MTMessagesSettings.hyperlinkSpoof, title: { MTStrings.Sending.Menu.hyperlink }, subtitle: { MTStrings.Sending.Menu.hyperlinkInfo }))
        MTMenuRegistry.register(MTMenuRow(id: "sending.hyperlinkTarget", section: text, order: 700, title: { MTStrings.Sending.Menu.hyperlinkTarget }, kind: .action({ context in
            MTHyperlinkTarget.edit(menuContext: context)
        }), isVisible: { _ in MTMessagesSettings.hyperlinkSpoof.value }, label: { context in
            return MTHyperlinkTarget.label(menuContext: context)
        }))

        let replies = MTMessagesMenu.sendingRepliesSection
        MTMenuRegistry.register(toggle("sending.autoQuote", section: replies, order: 100, setting: MTMessagesSettings.autoQuoteReply, title: { MTStrings.Sending.Menu.autoQuote }, subtitle: { MTStrings.Sending.Menu.autoQuoteInfo }))
        MTMenuRegistry.register(toggle("sending.autoQuoteSkipComments", section: replies, order: 200, setting: MTMessagesSettings.autoQuoteSkipComments, title: { MTStrings.Sending.Menu.autoQuoteSkipComments }, isVisible: { _ in MTMessagesSettings.autoQuoteReply.value }))
        MTMenuRegistry.register(toggle("sending.anonymousStickers", section: replies, order: 300, setting: MTMessagesSettings.anonymousStickers, title: { MTStrings.Sending.Menu.anonymousStickers }, subtitle: { MTStrings.Sending.Menu.anonymousStickersInfo }))
        MTMenuRegistry.register(toggle("sending.withoutVia", section: replies, order: 400, setting: MTMessagesSettings.sendWithoutViaBot, title: { MTStrings.Sending.Menu.withoutVia }, subtitle: { MTStrings.Sending.Menu.withoutViaInfo }))
        MTMenuRegistry.register(toggle("sending.keepCaption", section: replies, order: 500, setting: MTMessagesSettings.keepInlineBotCaption, title: { MTStrings.Sending.Menu.keepCaption }, isVisible: { _ in MTMessagesSettings.sendWithoutViaBot.value }))

        let input = MTMessagesMenu.sendingInputSection
        MTMenuRegistry.register(toggle("sending.sendOnReturn", section: input, order: 100, setting: MTMessagesSettings.sendOnReturn, title: { MTStrings.Sending.Menu.sendOnReturn }, subtitle: { MTStrings.Sending.Menu.sendOnReturnInfo }))
        MTMenuRegistry.register(toggle("sending.hideSendAs", section: input, order: 200, setting: MTMessagesSettings.hideSendAsButton, title: { MTStrings.Sending.Menu.hideSendAs }))
    }

    // MARK: Translation

    private static func registerTranslation() {
        let screen = MTMenuScreenID.tab(.messagesTranslation)
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTMessagesMenu.translationServiceSection, screen: screen, order: 300, footer: { _ in MTStrings.Translation.Menu.serviceFooter }))

        // An incoming message in another language shows the quick translate button (when it is on),
        // the outgoing one the translation before sending.
        MTMenuRegistry.register(MTMenuRow(id: "translation.preview", section: .preview(of: .messagesTranslation), order: 100, title: { "" }, kind: .preview(.miniChat(MTMiniChatConfiguration(scope: "translation", height: 200.0, content: { _ in
            return MTMiniChatContent(header: nil, messages: [
                MTPreviewMessage(id: 1, isOutgoing: false, text: MTStrings.Translation.Preview.incoming, ageSeconds: 120),
                MTPreviewMessage(id: 2, isOutgoing: true, text: MTStrings.Translation.Preview.result, reply: MTPreviewReply(author: MTStrings.Translation.Preview.input, text: MTStrings.Translation.Preview.source), ageSeconds: 60)
            ])
        })))))

        MTMenuRegistry.register(MTMenuRow(id: "translation.service", section: MTMessagesMenu.translationServiceSection, order: 100, title: { MTStrings.Translation.Menu.service }, kind: .action({ context in
            MTTranslationMenu.chooseService(menuContext: context)
        }), searchKeywords: { [MTStrings.Translation.Menu.keyword] }, label: { _ in
            return MTTranslationMenu.serviceTitle(MTTranslationServiceKind(rawValue: MTMessagesSettings.translationService.value) ?? .telegram)
        }))

        let main = MTMenuSectionID.main(of: .messagesTranslation)
        MTMenuRegistry.register(toggle("translation.quickButton", section: main, order: 100, setting: MTMessagesSettings.quickTranslateButton, title: { MTStrings.Translation.Menu.quickButton }, subtitle: { MTStrings.Translation.Menu.quickButtonInfo }))
        MTMenuRegistry.register(toggle("translation.beforeSending", section: main, order: 200, setting: MTMessagesSettings.translateBeforeSending, title: { MTStrings.Translation.Menu.beforeSending }, subtitle: { MTStrings.Translation.Menu.beforeSendingInfo }))
        MTMenuRegistry.register(MTMenuRow(id: "translation.beforeSendingLanguage", section: main, order: 300, title: { MTStrings.Translation.Menu.beforeSendingLanguage }, kind: .choice(.global(MTMessagesSettings.translateBeforeSendingLanguage), options: MTTranslationMenu.languageOptions()), isVisible: { _ in MTMessagesSettings.translateBeforeSending.value }))
        MTMenuRegistry.register(toggle("translation.photo", section: main, order: 400, setting: MTMessagesSettings.photoTranslation, title: { MTStrings.Translation.Menu.photo }, subtitle: { MTStrings.Translation.Menu.photoInfo }))
        MTMenuRegistry.register(MTMenuRow(id: "translation.telegramSettings", section: main, order: 500, title: { MTStrings.Translation.Menu.telegramSettings }, subtitle: { MTStrings.Translation.Menu.telegramSettingsInfo }, kind: .action({ context in
            if let make = MTSettingsUIEnvironment.shared.makeTelegramLanguageController {
                context.push(make(context.context))
            }
        }), isVisible: { _ in MTSettingsUIEnvironment.shared.makeTelegramLanguageController != nil }))
    }

    // MARK: Menu and gestures

    private static func registerMenuAndGestures() {
        let main = MTMenuSectionID.main(of: .messagesMenuGestures)
        let children: [MTMenuRow] = [
            toggle("messageMenu.reply", section: main, order: 100, setting: MTMessagesSettings.menuShowReply, title: { MTStrings.MessageMenu.Menu.reply }),
            toggle("messageMenu.pin", section: main, order: 200, setting: MTMessagesSettings.menuShowPin, title: { MTStrings.MessageMenu.Menu.pin }),
            toggle("messageMenu.report", section: main, order: 300, setting: MTMessagesSettings.menuShowReport, title: { MTStrings.MessageMenu.Menu.report }),
            toggle("messageMenu.saveMedia", section: main, order: 400, setting: MTMessagesSettings.menuShowSaveMedia, title: { MTStrings.MessageMenu.Menu.saveMedia }),
            toggle("messageMenu.replies", section: main, order: 500, setting: MTMessagesSettings.menuShowReplies, title: { MTStrings.MessageMenu.Menu.replies }),
            toggle("messageMenu.restrict", section: main, order: 600, setting: MTMessagesSettings.menuShowRestrict, title: { MTStrings.MessageMenu.Menu.restrict }),
            toggle("messageMenu.saveToCloud", section: main, order: 700, setting: MTMessagesSettings.menuSaveToCloud, title: { MTStrings.MessageMenu.Menu.saveToCloud }),
            toggle("messageMenu.forwardWithoutAuthor", section: main, order: 800, setting: MTMessagesSettings.menuForwardWithoutAuthor, title: { MTStrings.MessageMenu.Menu.forwardWithoutAuthor })
        ]
        MTMenuRegistry.register(MTMenuRow(id: "messageMenu.custom", section: main, order: 100, title: { MTStrings.MessageMenu.Menu.custom }, subtitle: { MTStrings.MessageMenu.Menu.customInfo }, kind: .expandableGroup(master: .global(MTMessagesSettings.customMessageMenu), children: children)))

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTMessagesMenu.gesturesSection, screen: .tab(.messagesMenuGestures), order: 300, header: { MTStrings.Gestures.Menu.header }))
        MTMenuRegistry.register(toggle("gestures.doubleTapToEdit", section: MTMessagesMenu.gesturesSection, order: 100, setting: MTMessagesSettings.doubleTapToEdit, title: { MTStrings.Gestures.Menu.doubleTapToEdit }, subtitle: { MTStrings.Gestures.Menu.doubleTapToEditInfo }))
        MTMenuRegistry.register(toggle("gestures.disableVideoPipSwipe", section: MTMessagesMenu.gesturesSection, order: 200, setting: MTMessagesSettings.disableVideoPipSwipe, title: { MTStrings.Gestures.Menu.disableVideoPipSwipe }, subtitle: { MTStrings.Gestures.Menu.disableVideoPipSwipeInfo }))
    }

    // MARK: Chats

    private static func registerChats() {
        let section = MTMenuSectionID.messagesChats
        MTMenuRegistry.register(toggle("chats.unlimitedSearch", section: section, order: 200, setting: MTMessagesSettings.unlimitedSearchHistory, title: { MTStrings.Chats.Menu.unlimitedSearch }, subtitle: { MTStrings.Chats.Menu.unlimitedSearchInfo }))
        MTMenuRegistry.register(toggle("chats.hideGreeting", section: section, order: 300, setting: MTMessagesSettings.hideGreetingSticker, title: { MTStrings.Chats.Menu.hideGreeting }, subtitle: { MTStrings.Chats.Menu.hideGreetingInfo }))
        MTMenuRegistry.register(toggle("chats.keywordFilter", section: section, order: 400, setting: MTMessagesSettings.keywordFilter, title: { MTStrings.Chats.Menu.keywordFilter }, subtitle: { MTStrings.Chats.Menu.keywordFilterInfo }))
        MTMenuRegistry.register(tab: MTMenuTabDescriptor(id: MTMessagesMenu.keywordsTab, parent: .category(.messages), title: { MTStrings.Chats.Keywords.title }, makeScreen: { context in
            return mtMakeKeywordsScreen(menuContext: context)
        }))
        MTMenuRegistry.register(MTMenuRow(id: "chats.keywords", section: section, order: 500, title: { MTStrings.Chats.Menu.keywords }, kind: .tab(MTMessagesMenu.keywordsTab), isVisible: { _ in MTMessagesSettings.keywordFilter.value }, label: { _ in
            return MTStrings.Chats.Menu.keywordsCount(count: MTMessagesSettings.keywords.value.count)
        }))
        MTMenuRegistry.register(toggle("chats.hideChannelButton", section: section, order: 600, setting: MTMessagesSettings.hideChannelBottomButton, title: { MTStrings.Chats.Menu.hideChannelButton }, subtitle: { MTStrings.Chats.Menu.hideChannelButtonInfo }))
        // One switch for channels and forum topics (2026-10-27).
        MTMenuRegistry.register(toggle("chats.noNext", section: section, order: 700, setting: MTMessagesSettings.disableScrollToNext, title: { MTStrings.Chats.Menu.noNext }, subtitle: { MTStrings.Chats.Menu.noNextInfo }))
        MTMenuRegistry.register(toggle("chats.noDeleteEffect", section: section, order: 900, setting: MTMessagesSettings.disableDeleteEffect, title: { MTStrings.Chats.Menu.noDeleteEffect }, subtitle: { MTStrings.Chats.Menu.noDeleteEffectInfo }))
        MTMenuRegistry.register(toggle("chats.hideRecordButton", section: section, order: 1000, setting: MTMessagesSettings.hideRecordButton, title: { MTStrings.Chats.Menu.hideRecordButton }, subtitle: { MTStrings.Chats.Menu.hideRecordButtonInfo }))
        MTMenuRegistry.register(tab: MTMenuTabDescriptor(id: MTMessagesMenu.localCreatorTab, parent: .category(.messages), title: { MTStrings.Chats.LocalCreator.title }, makeScreen: { context in
            return mtMakeLocalCreatorScreen(menuContext: context)
        }))
        MTMenuRegistry.register(MTMenuRow(id: "chats.localCreator", section: section, order: 1100, title: { MTStrings.Chats.Menu.localCreator }, subtitle: { MTStrings.Chats.Menu.localCreatorInfo }, kind: .tab(MTMessagesMenu.localCreatorTab), label: { context in
            return MTStrings.Chats.Menu.localCreatorCount(count: MTMessagesSettings.localCreatorChannels.value(for: context.accountID).count)
        }))
        // «Безлимитные закрепы» have no switch (always on,. The section
        // ends with what the user has to know about them: where they work and that the pins beyond
        // Telegram's limit stay on this device. Found by search as «закрепы».
        MTMenuRegistry.register(MTMenuRow(id: "chats.unlimitedPins", section: section, order: 10000, title: { MTStrings.Chats.Menu.unlimitedPins }, subtitle: { MTStrings.Chats.Menu.unlimitedPinsInfo }, kind: .custom({ context in
            return ItemListTextItem(presentationData: context.itemListPresentationData, text: .plain(MTStrings.Chats.Menu.unlimitedPinsInfo), sectionId: context.sectionId)
        }), searchKeywords: { [MTStrings.Chats.Menu.keywordPins] }))
    }

    // MARK: Notifications

    private static func registerNotifications() {
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTMessagesMenu.notificationsSection, screen: .category(.messages), order: 400, header: { MTStrings.Notifications.Menu.header }, footer: { _ in MTStrings.Notifications.Menu.footer }))
        let options = [
            MTMenuChoiceOption(value: MTNotificationDeliveryMode.standard.rawValue, title: { MTStrings.Notifications.Menu.modeStandard }),
            MTMenuChoiceOption(value: MTNotificationDeliveryMode.silent.rawValue, title: { MTStrings.Notifications.Menu.modeSilent }),
            MTMenuChoiceOption(value: MTNotificationDeliveryMode.disabled.rawValue, title: { MTStrings.Notifications.Menu.modeDisabled })
        ]
        let section = MTMessagesMenu.notificationsSection
        MTMenuRegistry.register(MTMenuRow(id: "notifications.pinned", section: section, order: 100, title: { MTStrings.Notifications.Menu.pinned }, kind: .choice(.global(MTMessagesSettings.pinnedNotifications), options: options)))
        MTMenuRegistry.register(MTMenuRow(id: "notifications.mentions", section: section, order: 200, title: { MTStrings.Notifications.Menu.mentions }, kind: .choice(.global(MTMessagesSettings.mentionNotifications), options: options)))
        MTMenuRegistry.register(tab: MTMenuTabDescriptor(id: MTMessagesMenu.exceptionsTab, parent: .category(.messages), title: { MTStrings.Notifications.Exceptions.title }, makeScreen: { context in
            return mtMakeNotificationExceptionsScreen(menuContext: context)
        }))
        MTMenuRegistry.register(MTMenuRow(id: "notifications.exceptions", section: section, order: 300, title: { MTStrings.Notifications.Menu.exceptions }, kind: .tab(MTMessagesMenu.exceptionsTab), label: { context in
            return MTStrings.Notifications.Menu.exceptionsCount(count: MTNotificationExceptions.peerKeys(accountId: context.accountID).count)
        }))
    }
}

/// «было → станет» on a real bubble: the sample text run through the enabled stages.
enum MTSendingPreview {
    static func content(_ context: MTMenuContext) -> MTMiniChatContent {
        let sample = MTStrings.Sending.Preview.sample
        let configuration = MTOutgoingPipeline.configuration(accountId: context.accountID)
        let pipelineContext = MTTextPipelineContext(isBot: false, isSavedMessages: false, isVerbatim: false)
        let result = MTOutgoingPipeline.run(MTOutgoingText(text: sample, entities: []), configuration: configuration, context: pipelineContext, hyperlinkTarget: nil)
        return MTMiniChatContent(header: nil, messages: [
            MTPreviewMessage(id: 1, isOutgoing: true, text: result.text, reply: MTPreviewReply(author: MTStrings.Sending.Preview.before, text: sample), ageSeconds: 60)
        ])
    }
}
