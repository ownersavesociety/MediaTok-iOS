import Foundation
import SwiftSignalKit
import TelegramCore
import MTCore
import MTFeaturesShared

/// Entry point of the MTGhostMode feature module. Owner: MediaTok.
///
/// The decisions about what leaves the device live in `MTFeaturesShared` (`MTGhostModeShared`,
/// registered by the aggregator for the app and the extensions alike). This module is the app's
/// side: the menu, the chat-screen tracking, the explicit reads and the menu items.
public enum MTGhostModeModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        MTGhostMigrations.register()
        MTGhostMenu.register()
        MTGhostMenuItems.register()
        MTGhostChatTracking.register()
        MTGhostBlockedPeers.register()
        MTGhostTraces.register()
        MTGhostQuickActions.register()

        MTAccountHooks.accountWillBeRemoved.register({ id in
            let account = id.mt
            Queue.mainQueue().async {
                MTGhostAccounts.shared.accountWillBeRemoved(account)
                MTGhostBlockedPeers.shared.clear(account: account)
            }
        }, order: 100)

        // Throttled work on return to the app (never on every activation, never in the background):
        // the blocked lists of the accounts that hide them, and «Прочитать локально» re-applied
        // after a server reset of the read state.
        MTForegroundTaskScheduler.shared.register(id: "ghostMode.refresh", minimumInterval: 30.0 * 60.0, delay: 4.0, task: { done in
            let contexts = MTGhostAccounts.shared.contexts
            var signals: [Signal<Never, NoError>] = []
            for context in contexts {
                let account = context.account.id.mt
                if MTGhostSettings.hideBlockedMessages.value(for: account) {
                    // The current list stays in use until the new one is complete.
                    MTGhostBlockedPeers.shared.reload(context: context)
                }
                signals.append(MTGhostAccounts.reapplyLocalReads(context: context))
            }
            if signals.isEmpty {
                done()
                return EmptyDisposable
            }
            return combineLatest(signals).start(completed: {
                done()
            })
        })
    }
}
