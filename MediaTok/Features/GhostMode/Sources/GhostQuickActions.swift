import Foundation
import MTCore
import MTFeaturesShared

/// The zone's buttons of «Кнопки быстрого доступа» in a chat: ghost mode
/// and delayed sending of the account, as switches. The buttons themselves are drawn by MTInterface.
enum MTGhostQuickActions {
    static func register() {
        MTQuickActions.actions.register(MTQuickAction(
            id: MTQuickActionIds.ghostMode,
            order: 100,
            title: { MTStrings.GhostMode.Menu.group },
            iconName: "Chat/Context Menu/EyeLocked",
            isOn: { context in
                return MTGhostSettings.isEnabled.value(for: context.accountID)
            },
            perform: { context in
                let account = context.accountID
                MTGhostSettings.isEnabled.set(!MTGhostSettings.isEnabled.value(for: account), for: account)
            }
        ))
        MTQuickActions.actions.register(MTQuickAction(
            id: MTQuickActionIds.sendDelay,
            order: 400,
            title: { MTStrings.Menu.Tab.Privacy.sendDelay },
            iconName: "Chat/Context Menu/Schedule",
            isOn: { context in
                return MTGhostSettings.sendDelayEnabled.value(for: context.accountID)
            },
            perform: { context in
                let account = context.accountID
                MTGhostSettings.sendDelayEnabled.set(!MTGhostSettings.sendDelayEnabled.value(for: account), for: account)
            }
        ))
    }
}
