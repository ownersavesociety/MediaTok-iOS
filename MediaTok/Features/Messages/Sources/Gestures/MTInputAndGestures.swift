import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import ChatMessageItemCommon
import MTCore
import MTHooks
import MTFeaturesShared

/// Input field and gestures:
/// - SG-F8 «Отправка по Return» — `MTInputPanelHooks.sendOnReturn` (chat and attachment composers);
/// - SG-G6 «Скрыть кнопку записи» — `MTInputPanelHooks.hidesRecordButton`;
/// - SG-G7 «Без эффекта удаления» — `MTChatScreenHooks.deleteEffect`;
/// - SG-G2 double tap on an own message → edit (`MTMessageGestureHooks.tap`), SG-G10 no
///   picture-in-picture swipe (`MTGalleryHooks.swipeToPictureInPicture`);
/// - SG-E2 the quick translate button beside a bubble (`MTMessageDecorationHooks.translateButtonLanguage`).
enum MTInputAndGestures {
    static func register() {
        MTInputPanelHooks.sendOnReturn.register({ request in
            if MTMessagesSettings.sendOnReturn.value {
                // Shift+Return still makes a new line on hardware keyboards.
                return !request.modifierFlags.contains(.shift)
            }
            return nil
        })
        MTInputPanelHooks.hidesRecordButton.register({ _ in
            return MTMessagesSettings.hideRecordButton.value
        })
        MTChatScreenHooks.deleteEffect.register({ _ in
            return MTMessagesSettings.disableDeleteEffect.value ? false : nil
        })
        MTMessageGestureHooks.tap.register({ request in
            guard request.tapCount == 2, let action = MTInputAndGestures.doubleTapAction(message: request.message, context: request.context) else {
                return false
            }
            switch action {
            case .edit:
                return request.startEditing()
            }
        })
        MTGalleryHooks.swipeToPictureInPicture.register({ context in
            return MTInputAndGestures.allowsSwipeToPictureInPicture(context: context)
        })
        MTMessageDecorationHooks.translateButtonLanguage.register({ message, context in
            return MTQuickTranslateButton.sourceLanguage(message: message, context: context)
        })
    }

    enum DoubleTapAction {
        case edit
    }

    /// SG-G2: what a double tap on `message` does instead of the quick reaction; nil = upstream.
    static func doubleTapAction(message: Message, context: AccountContext) -> DoubleTapAction? {
        guard MTMessagesSettings.doubleTapToEdit.value else {
            return nil
        }
        if message.effectivelyIncoming(context.account.peerId) {
            return nil
        }
        if message.id.namespace != Namespaces.Message.Cloud {
            return nil
        }
        if message.text.isEmpty && !message.media.contains(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile }) {
            return nil
        }
        // The rule behind Telegram's own «Edit» (time limit, forwards, stickers, round videos, rights
        // in channels and gigagroups): what cannot be edited keeps the double-tap reaction.
        let limits = EngineConfiguration.Limits(context.currentLimitsConfiguration.with { $0 })
        if !canEditMessage(accountPeerId: context.account.peerId, limitsConfiguration: limits, message: message) {
            return nil
        }
        return .edit
    }

    /// SG-G10: false = a vertical swipe on a gallery video dismisses it instead of starting
    /// picture-in-picture; nil = upstream.
    static func allowsSwipeToPictureInPicture(context: AccountContext) -> Bool? {
        return MTMessagesSettings.disableVideoPipSwipe.value ? false : nil
    }
}
