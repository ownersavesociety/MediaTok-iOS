import Foundation
import UIKit
import SafariServices
import Display
import TelegramCore
import AccountContext
import MTCore
import MTFeaturesShared
import MTExtrasHooks

/// Links: «Переслать» / «Поделиться» in the menu of a long-pressed link, and «Safari в приложении»
/// as a browser (Telegram's «Браузер» settings list it while «Больше браузеров» is on).
enum MTExtrasLinks {
    static func register() {
        MTExtrasUIHooks.linkActions.register({ link in
            if !MTExtrasSettings.linkMenuShare.value {
                return []
            }
            // Web and Telegram links only: an e-mail address or a phone number is not «shared» as a link.
            let lowercasedUrl = link.url.lowercased()
            if lowercasedUrl.hasPrefix("mailto:") || lowercasedUrl.hasPrefix("tel:") {
                return []
            }
            let context = link.context
            let url = link.url
            let present = link.present
            return [
                MTExtrasLinkAction(title: MTStrings.Extras.Link.forward, iconName: "Chat/Context Menu/Forward", action: {
                    present(context.sharedContext.makeShareController(context: context, params: ShareControllerParams(subject: .url(url))))
                }),
                MTExtrasLinkAction(title: MTStrings.Extras.Link.share, iconName: "Chat/Context Menu/Share", action: {
                    present(context.sharedContext.makeShareController(context: context, params: ShareControllerParams(subject: .url(url), externalShare: true, immediateExternalShare: true)))
                })
            ]
        })

        MTExtrasUIHooks.openInAppBrowser.register({ url, context, _ in
            if !MTExtrasPolicy.allowsMoreBrowsers {
                return false
            }
            // SFSafariViewController takes http(s) only (anything else is an exception).
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return false
            }
            // No bar tint: deprecated since iOS 26, where the system draws the bars itself.
            // `presentNativeController` presents over whatever is on top (a sheet included).
            context.sharedContext.applicationBindings.presentNativeController(SFSafariViewController(url: url))
            return true
        })
    }
}
