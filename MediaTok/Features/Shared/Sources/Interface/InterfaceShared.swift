import Foundation
import TelegramCore
import MTCore

/// The part of MTInterface that the extensions (notification service, share) also link: settings with
/// `.extensions`, NSE handlers, attribute declarations. Owner: MediaTok.
///
/// The Interface zone has nothing the extensions read. What lives here is the one cross-zone API of
/// the zone — quick actions for the chat's quick buttons — because MTFeaturesShared is the module
/// every feature module may depend on (MT<Feature> modules may not depend on each other).
public enum MTInterfaceShared {
    /// Called from `MTFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `MTCore.environment?.process` for what only one of them needs.
    public static func register() {
    }
}

/// Where a quick action is performed.
public struct MTQuickActionContext {
    public let account: Account
    /// The chat the button was tapped in.
    public let peerId: EnginePeer.Id
    /// The chat screen (`ChatController`), for actions that act on it (scroll, input).
    public weak var chatController: AnyObject?
    /// The chat's `AccountContext` (this module can not name the type: cast with `as? AccountContext`),
    /// for actions that open a screen.
    public let accountContext: AnyObject?

    public init(account: Account, peerId: EnginePeer.Id, chatController: AnyObject?, accountContext: AnyObject? = nil) {
        self.account = account
        self.peerId = peerId
        self.chatController = chatController
        self.accountContext = accountContext
    }

    public var accountID: MTAccountID {
        return self.account.id.mt
    }
}

/// One button of «Кнопки быстрого доступа» in a chat. Registered by the feature that owns the
/// action (ghost mode — MediaTok, deleted / edited messages — MediaTok, translation — MediaTok, screenshot
/// protection — MediaTok, scroll to top — MediaTok). The buttons themselves are drawn by MTInterface.
public struct MTQuickAction {
    public let id: String
    /// Sparse, step 100; the order of the buttons.
    public let order: Int
    /// MTStrings accessor, evaluated when shown.
    public let title: () -> String
    /// A template glyph of the app's asset catalog («Chat/Context Menu/…»).
    public let iconName: String
    /// For switch-like actions: whether it is on for the account (the button is highlighted).
    /// Called on every layout of the buttons: answer from a setting read.
    public let isOn: ((MTQuickActionContext) -> Bool)?
    /// Hidden in chats where it makes no sense (nil = always available).
    public let isAvailable: ((MTQuickActionContext) -> Bool)?
    /// Main thread.
    public let perform: (MTQuickActionContext) -> Void

    public init(id: String, order: Int, title: @escaping () -> String, iconName: String, isOn: ((MTQuickActionContext) -> Bool)? = nil, isAvailable: ((MTQuickActionContext) -> Bool)? = nil, perform: @escaping (MTQuickActionContext) -> Void) {
        self.id = id
        self.order = order
        self.title = title
        self.iconName = iconName
        self.isOn = isOn
        self.isAvailable = isAvailable
        self.perform = perform
    }
}

public enum MTQuickActions {
    /// Register from `register()` of the owning module (main thread, before freeze).
    public static let actions = MTHookPoint<MTQuickAction>("quickActions.actions")

    /// The registered actions in their order.
    public static var all: [MTQuickAction] {
        return MTQuickActions.actions.handlers.sorted(by: { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        })
    }
}

/// Ids of the actions legacy format had (the migration of its per-button switches uses them).
public enum MTQuickActionIds {
    public static let ghostMode = "ghostMode"
    public static let deletedMessages = "antiDelete.deleted"
    public static let editedMessages = "antiDelete.edited"
    public static let sendDelay = "sendDelay"
    public static let scrollToTop = "interface.scrollToTop"
    public static let translateBeforeSend = "translation.beforeSend"
    public static let screenshotPrivacy = "security.screenshotPrivacy"
}
