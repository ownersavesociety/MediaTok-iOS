import Foundation
import GGCore
import GGFeaturesShared

/// The zone's button of «Кнопки быстрого доступа» in a chat:
/// «Переводить перед отправкой» as a switch.
enum GGTranslationQuickAction {
    static func register() {
        GGQuickActions.actions.register(GGQuickAction(
            id: GGQuickActionIds.translateBeforeSend,
            order: 600,
            title: { GGStrings.Translation.Menu.beforeSending },
            iconName: "Chat/Context Menu/Translate",
            isOn: { _ in
                return GGMessagesSettings.translateBeforeSending.value
            },
            perform: { _ in
                GGMessagesSettings.translateBeforeSending.set(!GGMessagesSettings.translateBeforeSending.value)
            }
        ))
    }
}
