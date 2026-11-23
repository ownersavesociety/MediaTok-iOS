import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import AccountContext
import UIKitRuntimeUtils
import MTCore
import MTHooks
import MTFeaturesShared

/// «Скрывать чат на скриншотах»: one setting (`security.screenshotPrivacy`), one point that applies
/// it (`MTChatScreenHooks.hidesChromeFromCapture` → header, input panel, the panels over it,
/// navigation buttons, quick buttons come out empty on screenshots and screen recordings; the
/// messages stay; no send animation). The menu row and the chat's quick button write the same
/// setting — the button no longer flips any master switch. «И список чатов» does the same for the
/// whole chat list screen (rows, header, folder tabs).
enum MTScreenshotPrivacy {
    private static var chatListKey: UInt8 = 0

    static func register() {
        MTChatScreenHooks.hidesChromeFromCapture.register({ _, _ in
            return MTSecuritySettings.screenshotPrivacy.value
        })
        MTQuickActions.actions.register(MTQuickAction(
            id: MTQuickActionIds.screenshotPrivacy,
            order: 700,
            title: { MTStrings.Security.Screenshot.quickAction },
            iconName: "Chat/Context Menu/Lock",
            isOn: { _ in
                return MTSecuritySettings.screenshotPrivacy.value
            },
            perform: { context in
                MTSecuritySettings.screenshotPrivacy.set(!MTSecuritySettings.screenshotPrivacy.value)
                // The chat applies it on its next layout: ask for one now.
                (context.chatController as? ViewController)?.requestLayout(transition: .immediate)
            }
        ))
        MTChatListChromeHooks.containerDidLayout.register({ layout in
            let hides = MTSecuritySettings.screenshotPrivacy.value && MTSecuritySettings.screenshotPrivacyChatList.value
            let node = layout.node
            let applied = (objc_getAssociatedObject(node, &MTScreenshotPrivacy.chatListKey) as? NSNumber)?.boolValue ?? false
            if hides == applied {
                return
            }
            objc_setAssociatedObject(node, &MTScreenshotPrivacy.chatListKey, NSNumber(value: hides), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            setLayerDisableScreenshots(node.layer, hides)
        })
    }
}
