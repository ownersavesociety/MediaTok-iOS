import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import MTCore
import MTHooks
import MTSettingsUI
import MTFeaturesShared
import ChatListUI

/// Entry point of the MTAntiDelete feature module. Owner: MediaTok.
/// The capture itself (Postbox attributes, the index, the notification service) is registered by
/// `MTAntiDeleteShared` (MTFeaturesShared); this module adds the menu, the chat UI and the
/// background maintenance of the app.
public enum MTAntiDeleteModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        MTAntiDeleteMenu.register()
        MTAntiDeleteMigrations.register()
        MTAntiDeleteQuickActions.register()

        // Bubbles of every type: transparency, status marks, the local edit, previous versions.
        MTMessageDecorationHooks.decorations.register({ decoration, context in
            MTAntiDeleteDecorations.decorate(&decoration, context)
        }, order: 100)

        // Message menu.
        MTMessageMenuHooks.items.register({ context in
            return MTAntiDeleteMessageMenu.items(context)
        })
        MTMessageMenuHooks.filter.register({ items, context in
            return MTAntiDeleteMessageMenu.filter(items, context)
        }, order: 100)

        // Profile «…».
        MTPeerInfoHooks.menuItems.register({ context in
            return MTAntiDeletePeerMenu.items(context)
        })

        // Chat list preview with the local edit; late, so a locked chat's hidden preview wins.
        MTChatListHooks.previewText.register({ row in
            return MTAntiDeleteChatList.previewText(row)
        }, order: 1000)

        // Reply to a deleted message → a quote, before the other outgoing transformers.
        MTOutgoingHooks.messages.register({ messages, context in
            MTAntiDeleteReplyQuote.transform(&messages, context: context)
        }, order: -100)
        MTChatScreenHooks.replySubject.register({ subject, request in
            MTAntiDeleteReplyQuote.warmUp(request)
            return subject
        })

        // A chat opens: archived media of its kept messages go back into the cache if it lost them.
        MTChatScreenHooks.lifecycle.register({ event, screen in
            guard case .willAppear = event, !screen.isPreview, let peerId = screen.chatLocation.peerId else {
                return
            }
            let context = screen.context
            if MTAntiDeleteAccounts.shared.count(account: context.account.id, kind: .deleted, peerId: peerId) == 0 {
                return
            }
            guard let basePath = MTAntiDeleteAccounts.shared.basePath(for: context.account.id) else {
                return
            }
            MTAntiDeleteMediaArchive.restore(postbox: context.account.postbox, basePath: basePath, peerId: peerId, completion: { restored in
                if !restored.isEmpty {
                    Queue.mainQueue().async {
                        MTMessageDecorationHooks.redraw(messageIds: restored)
                    }
                }
            })
        })

        // Excluded folders follow folder changes of every running account.
        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTAntiDeleteFolderSync.start(sharedContext: context.sharedContext)
            MTAntiDeleteModule.sharedContext = context.sharedContext
        })

        // Background work only on return to the app, throttled (MTCore scheduler).
        MTForegroundTaskScheduler.shared.register(id: "antiDelete.inbox", minimumInterval: 60.0, delay: 1.0, task: { done in
            MTAntiDeleteIndexQueue.shared.drainInbox(completion: {
                Queue.mainQueue().async {
                    done()
                }
            })
            return EmptyDisposable
        })
        MTForegroundTaskScheduler.shared.register(id: "antiDelete.autoClear", minimumInterval: 6.0 * 60.0 * 60.0, delay: 8.0, task: { done in
            return (MTAntiDeleteOperations.pruneAllAccounts()
            |> deliverOnMainQueue).start(completed: {
                done()
            })
        })
        MTForegroundTaskScheduler.shared.register(id: "antiDelete.folders", minimumInterval: 15.0 * 60.0, delay: 5.0, task: { done in
            guard let sharedContext = MTAntiDeleteModule.sharedContext else {
                done()
                return EmptyDisposable
            }
            return (MTAntiDeleteFolderSync.refreshAll(sharedContext: sharedContext)
            |> deliverOnMainQueue).start(completed: {
                done()
            })
        })
    }

    /// Set when the first account's UI is up (main thread); used by the foreground refresh.
    fileprivate static weak var sharedContext: SharedAccountContext?
}
