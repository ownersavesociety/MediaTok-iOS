// Compiled INTO GiftViewScreen (filegroup //MediaTok/Features/ProfileExport:GiftViewScreenHookSources).
// Items a feature adds to the "…" menu of a gift's screen (fake gifts: "Add to my profile",
// "Edit", "Delete"). Upstream shows "…" only for collectible gifts; with a feature that has
// items it is shown for plain gifts too. Without handlers GiftViewScreen is unchanged.

import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import ContextUI
import MTCore

/// The gift a screen shows, as a menu provider sees it.
public struct MTGiftViewMenuContext {
    public let context: AccountContext
    public let gift: StarGift
    /// Where the gift is saved (a profile or a message), when it is someone's gift.
    public let reference: StarGiftReference?
    /// The profile the gift belongs to, when known.
    public let ownerPeerId: EnginePeer.Id?
    public let fromPeerId: EnginePeer.Id?
    public let date: Int32
    public let text: String?
    public let entities: [MessageTextEntity]?
    public let nameHidden: Bool
    public let savedToProfile: Bool
    public let pinnedToTop: Bool
    public let number: Int32?
    /// The gift screen; nil while the button's visibility is being decided.
    public weak var controller: ViewController?

    public init(context: AccountContext, gift: StarGift, reference: StarGiftReference?, ownerPeerId: EnginePeer.Id?, fromPeerId: EnginePeer.Id?, date: Int32, text: String?, entities: [MessageTextEntity]?, nameHidden: Bool, savedToProfile: Bool, pinnedToTop: Bool, number: Int32?, controller: ViewController?) {
        self.context = context
        self.gift = gift
        self.reference = reference
        self.ownerPeerId = ownerPeerId
        self.fromPeerId = fromPeerId
        self.date = date
        self.text = text
        self.entities = entities
        self.nameHidden = nameHidden
        self.savedToProfile = savedToProfile
        self.pinnedToTop = pinnedToTop
        self.number = number
        self.controller = controller
    }
}

public struct MTNativeUniqueGiftBuyContext {
    public let context: AccountContext
    public let recipientPeerId: EnginePeer.Id
    public let uniqueGift: StarGift.UniqueGift
    public let hideName: Bool
    public let text: String?
    public let entities: [MessageTextEntity]?
    public weak var controller: ViewController?
    public weak var messageController: ViewController?
    public let proceedRealBuy: () -> Void

    public init(
        context: AccountContext,
        recipientPeerId: EnginePeer.Id,
        uniqueGift: StarGift.UniqueGift,
        hideName: Bool,
        text: String?,
        entities: [MessageTextEntity]?,
        controller: ViewController?,
        messageController: ViewController?,
        proceedRealBuy: @escaping () -> Void
    ) {
        self.context = context
        self.recipientPeerId = recipientPeerId
        self.uniqueGift = uniqueGift
        self.hideName = hideName
        self.text = text
        self.entities = entities
        self.controller = controller
        self.messageController = messageController
        self.proceedRealBuy = proceedRealBuy
    }
}

public enum MTGiftViewHooks {
    /// Providers of items appended to the gift's «…» menu (main thread). Asked also while the
    /// screen decides whether to show «…» for a plain gift (`controller == nil`): answer cheaply.
    public static let menuItems = MTHookPoint<(MTGiftViewMenuContext) -> [ContextMenuItem]>("giftView.menuItems")

    /// Policy (any `true`): the gift exists only on this device (a fake gift). The screen then does
    /// not offer what needs the server (transfer, wear, sell) even though the gift shows you as owner.
    public static let isLocalGift = MTHookPoint<(MTGiftViewMenuContext) -> Bool>("giftView.isLocalGift")

    /// Policy (any `true`): MediaTok intercepted a collectible resale NFT purchase/send flow.
    public static let interceptResaleBuy = MTHookPoint<(MTNativeUniqueGiftBuyContext) -> Bool>("giftView.interceptResaleBuy")
}

func mtInterceptNativeUniqueGiftBuy(
    context: AccountContext,
    recipientPeerId: EnginePeer.Id,
    uniqueGift: StarGift.UniqueGift,
    hideName: Bool,
    text: String?,
    entities: [MessageTextEntity]?,
    controller: ViewController?,
    messageController: ViewController?,
    proceedRealBuy: @escaping () -> Void
) -> Bool {
    if MTGiftViewHooks.interceptResaleBuy.isEmpty {
        return false
    }
    let buyContext = MTNativeUniqueGiftBuyContext(
        context: context,
        recipientPeerId: recipientPeerId,
        uniqueGift: uniqueGift,
        hideName: hideName,
        text: text,
        entities: entities,
        controller: controller,
        messageController: messageController,
        proceedRealBuy: proceedRealBuy
    )
    for handler in MTGiftViewHooks.interceptResaleBuy.handlers {
        if handler(buyContext) {
            return true
        }
    }
    return false
}

private func mtGiftViewMenuContext(context: AccountContext, subject: GiftViewScreen.Subject, controller: ViewController?) -> MTGiftViewMenuContext? {
    if let arguments = subject.arguments {
        return MTGiftViewMenuContext(
            context: context,
            gift: arguments.gift,
            reference: arguments.reference,
            ownerPeerId: arguments.peerId,
            fromPeerId: arguments.fromPeerId,
            date: arguments.date,
            text: arguments.text,
            entities: arguments.entities,
            nameHidden: arguments.nameHidden,
            savedToProfile: arguments.savedToProfile,
            pinnedToTop: arguments.pinnedToTop ?? false,
            number: arguments.giftNumber,
            controller: controller
        )
    }
    switch subject {
    case let .soldOutGift(generic), let .upgradePreview(generic, _, _):
        return MTGiftViewMenuContext(
            context: context,
            gift: .generic(generic),
            reference: nil,
            ownerPeerId: nil,
            fromPeerId: nil,
            date: Int32(Date().timeIntervalSince1970),
            text: nil,
            entities: nil,
            nameHidden: false,
            savedToProfile: true,
            pinnedToTop: false,
            number: nil,
            controller: controller
        )
    default:
        return nil
    }
}

/// Items of the features for this gift (empty without handlers).
func mtGiftViewMenuItems(context: AccountContext, subject: GiftViewScreen.Subject, controller: ViewController?) -> [ContextMenuItem] {
    if MTGiftViewHooks.menuItems.isEmpty {
        return []
    }
    guard let menuContext = mtGiftViewMenuContext(context: context, subject: subject, controller: controller) else {
        return []
    }
    var result: [ContextMenuItem] = []
    for handler in MTGiftViewHooks.menuItems.handlers {
        result.append(contentsOf: handler(menuContext))
    }
    return result
}

/// Whether a plain (not collectible) gift gets the «…» button.
func mtGiftViewHasMenu(context: AccountContext, subject: GiftViewScreen.Subject) -> Bool {
    if MTGiftViewHooks.menuItems.isEmpty {
        return false
    }
    return !mtGiftViewMenuItems(context: context, subject: subject, controller: nil).isEmpty
}

/// Whether the shown gift is a local-only one (false without handlers).
func mtGiftViewIsLocalGift(context: AccountContext, subject: GiftViewScreen.Subject) -> Bool {
    if MTGiftViewHooks.isLocalGift.isEmpty {
        return false
    }
    guard let menuContext = mtGiftViewMenuContext(context: context, subject: subject, controller: nil) else {
        return false
    }
    for handler in MTGiftViewHooks.isLocalGift.handlers {
        if handler(menuContext) {
            return true
        }
    }
    return false
}
