import Foundation
import MTCore
import MTFeaturesShared

/// The zone's button of «Кнопки быстрого доступа» in a chat:
/// «Переводить перед отправкой» as a switch.
enum MTTranslationQuickAction {
    static func register() {
        MTQuickActions.actions.register(MTQuickAction(
            id: MTQuickActionIds.translateBeforeSend,
            order: 600,
            title: { MTStrings.Translation.Menu.beforeSending },
            iconName: "Chat/Context Menu/Translate",
            isOn: { _ in
                return MTMessagesSettings.translateBeforeSending.value
            },
            perform: { _ in
                MTMessagesSettings.translateBeforeSending.set(!MTMessagesSettings.translateBeforeSending.value)
            }
        ))
    }
}
