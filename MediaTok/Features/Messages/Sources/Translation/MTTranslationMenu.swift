import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PresentationDataUtils
import TranslateUI
import MTCore
import MTHooks
import MTSettingsUI
import MTFeaturesShared

/// The service choice of the «Перевод» tab. Google is a third-party service: before it is used the
/// user sees what is sent where and confirms; declining keeps Telegram. A Google choice migrated
/// from legacy format asks once at launch (nothing goes to Google until then).
enum MTTranslationMenu {
    static func register() {
        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTTranslationMenu.askMigratedConsentIfNeeded(context: context)
        })
    }

    static func serviceTitle(_ kind: MTTranslationServiceKind) -> String {
        switch kind {
        case .telegram:
            return MTStrings.Translation.Menu.serviceTelegram
        case .google:
            return MTStrings.Translation.Menu.serviceGoogle
        case .system:
            return MTStrings.Translation.Menu.serviceSystem
        }
    }

    static func chooseService(menuContext: MTMenuContext) {
        let context = menuContext.context
        mtPresentActionSheet(context: context, title: MTStrings.Translation.Menu.service, actions: [
            (MTTranslationMenu.serviceTitle(.telegram), false, {
                MTMessagesSettings.translationService.set(MTTranslationServiceKind.telegram.rawValue)
            }),
            (MTTranslationMenu.serviceTitle(.google), false, {
                MTTranslationMenu.confirmGoogle(context: context, present: { menuContext.present($0) })
            }),
            (MTTranslationMenu.serviceTitle(.system), false, {
                if #available(iOS 18.0, *) {
                    MTMessagesSettings.translationService.set(MTTranslationServiceKind.system.rawValue)
                } else {
                    menuContext.presentToast(MTStrings.Translation.systemUnavailable)
                }
            })
        ], present: { menuContext.present($0) })
    }

    static func confirmGoogle(context: AccountContext, present: @escaping (ViewController) -> Void) {
        if MTMessagesSettings.translationThirdPartyAccepted.value {
            MTMessagesSettings.translationService.set(MTTranslationServiceKind.google.rawValue)
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        present(textAlertController(context: context, title: MTStrings.Translation.Consent.title, text: MTStrings.Translation.Consent.text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: MTStrings.Translation.Consent.accept, action: {
                MTMessagesSettings.translationThirdPartyAccepted.set(true)
                MTMessagesSettings.translationService.set(MTTranslationServiceKind.google.rawValue)
            })
        ]))
    }

    private static var askedMigratedConsent = false

    private static func askMigratedConsentIfNeeded(context: AccountContext) {
        if MTTranslationMenu.askedMigratedConsent {
            return
        }
        MTTranslationMenu.askedMigratedConsent = true
        guard MTMessagesSettings.translationService.value == MTTranslationServiceKind.google.rawValue, !MTMessagesSettings.translationThirdPartyAccepted.value else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let alert = textAlertController(context: context, title: MTStrings.Translation.Consent.title, text: MTStrings.Translation.Consent.text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
                MTMessagesSettings.translationService.set(MTTranslationServiceKind.telegram.rawValue)
            }),
            TextAlertAction(type: .defaultAction, title: MTStrings.Translation.Consent.accept, action: {
                MTMessagesSettings.translationThirdPartyAccepted.set(true)
            })
        ])
        context.sharedContext.mainWindow?.present(alert, on: .root)
    }

    /// Languages for «Язык отправки»: popular first, then every supported one, named in the
    /// language of the interface.
    static func languageOptions() -> [MTMenuChoiceOption] {
        var codes: [String] = []
        var seen = Set<String>()
        for code in popularTranslationLanguages + supportedTranslationLanguages where seen.insert(code).inserted {
            codes.append(code)
        }
        return codes.map { code in
            return MTMenuChoiceOption(value: code, title: {
                return MTTranslationMenu.languageName(code)
            })
        }
    }

    static func languageName(_ code: String) -> String {
        let locale = Locale(identifier: MTLocalization.shared.languageCode)
        let name = locale.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
