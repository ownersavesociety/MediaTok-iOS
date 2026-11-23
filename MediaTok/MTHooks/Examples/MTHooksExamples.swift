// Examples of registering into MTHooks points. NOT part of any BUILD target and never registered in
// a real launch: it only shows the shapes. Real handlers live in the feature modules
// (MediaTok/Features/<Zone>) and are registered from their `register()`.

import Foundation
import UIKit
import Postbox
import TelegramCore
import AccountContext
import ContextUI
import MTCore
import MTHooks

enum MTHooksExamples {
    static func registerExamples() {
        // Policy inside a Postbox transaction: keep messages deleted by the other side.
        MTUpdateHooks.messagesWillBeDeleted.register({ request in
            if request.source != .remoteUpdate || request.isExtension {
                return Set()
            }
            // Mark with an own attribute via request.transaction.updateMessage(...) and keep.
            return Set(request.ids)
        })

        // Read receipts: keep everything on the device for secret chats (snapshot read only).
        MTPresenceHooks.sendReadReceipt.register({ request in
            if request.peerId.namespace == Namespaces.Peer.SecretChat {
                return false
            }
            return nil
        })

        // Outgoing text stage that keeps entities valid.
        MTOutgoingHooks.textStages.register({ text, _ in
            if text.text.hasSuffix("  ") {
                text.text = String(text.text.dropLast())
            }
        }, order: 100)

        // Message decoration: half-transparent messages from a muted author.
        MTMessageDecorationHooks.decorations.register({ decoration, context in
            if context.message.author?.id == context.context.account.peerId {
                return
            }
            decoration.alpha = 0.5
            decoration.statusPrefix = "· "
        })

        // A message menu item at the bottom.
        MTMessageMenuHooks.items.register({ menuContext in
            let item = ContextMenuItem.action(ContextMenuActionItem(text: "Example", icon: { _ in return nil }, action: { _, f in
                f(.default)
            }))
            return [MTMessageMenuEntry(position: .bottom, item: item)]
        })
    }
}
