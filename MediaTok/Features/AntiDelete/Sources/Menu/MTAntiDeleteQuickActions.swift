import Foundation
import Display
import AccountContext
import MTCore
import MTFeaturesShared

/// The zone's buttons of «Кнопки быстрого доступа» in a chat: the deleted
/// and the edited messages of this chat, the same screens as the profile's «…» menu opens.
enum MTAntiDeleteQuickActions {
    static func register() {
        MTQuickActions.actions.register(MTQuickAction(
            id: MTQuickActionIds.deletedMessages,
            order: 200,
            title: { MTStrings.AntiDelete.QuickActions.deleted },
            iconName: "Chat/Context Menu/Delete",
            perform: { context in
                MTAntiDeleteQuickActions.open(.deleted, context: context)
            }
        ))
        MTQuickActions.actions.register(MTQuickAction(
            id: MTQuickActionIds.editedMessages,
            order: 300,
            title: { MTStrings.AntiDelete.QuickActions.edited },
            iconName: "Chat/Context Menu/Edit",
            perform: { context in
                MTAntiDeleteQuickActions.open(.edited, context: context)
            }
        ))
    }

    private static func open(_ kind: MTAntiDeleteLogKind, context: MTQuickActionContext) {
        guard let accountContext = context.accountContext as? AccountContext else {
            return
        }
        let screen = mtMakeAntiDeleteChatHistoryController(context: accountContext, kind: kind, peerId: context.peerId)
        if let navigationController = (context.chatController as? ViewController)?.navigationController as? NavigationController {
            navigationController.pushViewController(screen)
        } else {
            MTAntiDeleteMessageMenu.rootNavigationController(accountContext)?.pushViewController(screen)
        }
    }
}
