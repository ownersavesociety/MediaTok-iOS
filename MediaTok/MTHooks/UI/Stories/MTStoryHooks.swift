// The story viewer (StoryItemSetContainerComponent): extra items in the «…» menu of other
// people's stories («Прочитать» in ghost mode) and whether a story may be forwarded / saved
// (copy-protection bypass). Story *views* themselves go through MTPresenceHooks.sendReadReceipt.
// The gate when the viewer opens (warning before stories) is called from StoryContainerScreen.

import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import ContextUI
import MTCore

public struct MTStoryMenuContext {
    public let context: AccountContext
    public let peer: EnginePeer
    public let storyItem: EngineStoryItem
}

public enum MTStoryHooks {
    /// Providers of items appended to the «…» menu of another peer's story.
    public static let menuItems = MTHookPoint<(MTStoryMenuContext) -> [ContextMenuItem]>("stories.menuItems")

    /// Policy: `false` lifts "forwarding disabled" of a story (share, save to gallery).
    public static let forwardingDisabled = MTHookPoint<(EngineStoryItem) -> Bool?>("stories.forwardingDisabled")

    public static func appendMenuItems(_ items: [ContextMenuItem], context: AccountContext, peer: EnginePeer, storyItem: EngineStoryItem) -> [ContextMenuItem] {
        if MTStoryHooks.menuItems.isEmpty {
            return items
        }
        let menuContext = MTStoryMenuContext(context: context, peer: peer, storyItem: storyItem)
        var extra: [ContextMenuItem] = []
        for handler in MTStoryHooks.menuItems.handlers {
            extra.append(contentsOf: handler(menuContext))
        }
        if extra.isEmpty {
            return items
        }
        return items + [.separator] + extra
    }

    public static func isForwardingDisabled(_ storyItem: EngineStoryItem) -> Bool {
        if MTStoryHooks.forwardingDisabled.isEmpty {
            return storyItem.isForwardingDisabled
        }
        for handler in MTStoryHooks.forwardingDisabled.handlers {
            if let value = handler(storyItem) {
                return value
            }
        }
        return storyItem.isForwardingDisabled
    }
}

public struct MTStoryOpenRequest {
    public let context: AccountContext
    /// The first peer shown, when the viewer already knows it.
    public let peerId: EnginePeer.Id?
    public weak var controller: ViewController?

    public init(context: AccountContext, peerId: EnginePeer.Id?, controller: ViewController?) {
        self.context = context
        self.peerId = peerId
        self.controller = controller
    }
}

extension MTStoryHooks {
    /// Gate when the story viewer opens (once per opening). Return `true` to take over: the viewer
    /// pauses and holds "seen" marks until `completion(true)` (watch) or `completion(false)`
    /// (close). Main thread.
    public static let openGate = MTHookPoint<(MTStoryOpenRequest, @escaping (Bool) -> Void) -> Bool>("stories.openGate")

    /// `true` = a gate took over; the viewer waits for `completion`.
    public static func interceptOpen(_ request: MTStoryOpenRequest, completion: @escaping (Bool) -> Void) -> Bool {
        if MTStoryHooks.openGate.isEmpty {
            return false
        }
        for handler in MTStoryHooks.openGate.handlers {
            if handler(request, completion) {
                return true
            }
        }
        return false
    }
}
