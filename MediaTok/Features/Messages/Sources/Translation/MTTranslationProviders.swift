import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import MTCore
import MTHooks
import MTFeaturesShared

/// Answers Telegram's translation requests with the chosen service. Telegram (the default) answers
/// nil: upstream does the request. Google is used only after the user accepted the notice
/// (`MTMessagesPolicy.translationService`); system translation only on iOS 18+.
enum MTTranslationProviders {
    static func register() {
        MTTranslationHooks.translateTexts.register({ request in
            let service = MTMessagesPolicy.translationService
            if service == .telegram {
                return nil
            }
            return MTTranslationEngine.translate(request.texts, toLang: request.toLang, service: service)
        })
        MTTranslationHooks.translateMessages.register({ request in
            let service = MTMessagesPolicy.translationService
            if service == .telegram {
                return nil
            }
            return MTTranslationProviders.translateMessages(request, service: service)
        })
    }

    /// Like upstream: translates the stored messages and keeps the result in
    /// `TranslationMessageAttribute` (text, poll options and solution, voice transcription), through
    /// `MTStoredMessagesTranslation` (MTFeaturesShared), which the chat translation without Premium
    /// shares. Rich messages (an InstantPage body) are left to Telegram: `mtTranslateMessages`
    /// (MTHooks) sends them to Telegram's translation next to this one.
    static func translateMessages(_ request: MTMessagesTranslationRequest, service: MTTranslationServiceKind) -> Signal<Void, TranslationError> {
        let toLang = request.toLang
        return MTStoredMessagesTranslation.translate(postbox: request.account.postbox, messageIds: request.messageIds, toLang: toLang, translateTexts: { texts in
            return MTTranslationEngine.translate(texts, toLang: toLang, service: service)
        })
    }
}
