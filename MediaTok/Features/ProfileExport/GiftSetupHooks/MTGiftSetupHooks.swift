// Compiled INTO GiftSetupScreen (filegroup //MediaTok/Features/ProfileExport:GiftSetupScreenHookSources).
// Allows MediaTok FakeGifts to offer 100% native visual in-chat + profile gift delivery directly
// from Telegram's native GiftSetupScreen (with real caption, custom emojis, hideName, and upgrade).

import Foundation
import Display
import TelegramCore
import AccountContext
import MTCore

public struct MTNativeStarGiftSetupSendContext {
    public let context: AccountContext
    public let peerId: EnginePeer.Id
    public let gift: StarGift.Gift
    public let text: String
    public let entities: [MessageTextEntity]
    public let hideName: Bool
    public let includeUpgrade: Bool
    public weak var controller: ViewController?
    public let dismissCompletion: (() -> Void)?
    public let proceedRealPurchase: () -> Void

    public init(
        context: AccountContext,
        peerId: EnginePeer.Id,
        gift: StarGift.Gift,
        text: String,
        entities: [MessageTextEntity],
        hideName: Bool,
        includeUpgrade: Bool,
        controller: ViewController?,
        dismissCompletion: (() -> Void)?,
        proceedRealPurchase: @escaping () -> Void
    ) {
        self.context = context
        self.peerId = peerId
        self.gift = gift
        self.text = text
        self.entities = entities
        self.hideName = hideName
        self.includeUpgrade = includeUpgrade
        self.controller = controller
        self.dismissCompletion = dismissCompletion
        self.proceedRealPurchase = proceedRealPurchase
    }
}

public enum MTGiftSetupHooks {
    /// Policy (any `true`): MediaTok intercepted the native GiftSetupScreen Send action.
    public static let interceptSend = MTHookPoint<(MTNativeStarGiftSetupSendContext) -> Bool>("giftSetup.interceptSend")
}

func mtInterceptNativeStarGiftSetupSend(
    context: AccountContext,
    peerId: EnginePeer.Id,
    gift: StarGift.Gift,
    text: String,
    entities: [MessageTextEntity],
    hideName: Bool,
    includeUpgrade: Bool,
    controller: ViewController?,
    dismissCompletion: (() -> Void)?,
    proceedRealPurchase: @escaping () -> Void
) -> Bool {
    if MTGiftSetupHooks.interceptSend.isEmpty {
        return false
    }
    let sendContext = MTNativeStarGiftSetupSendContext(
        context: context,
        peerId: peerId,
        gift: gift,
        text: text,
        entities: entities,
        hideName: hideName,
        includeUpgrade: includeUpgrade,
        controller: controller,
        dismissCompletion: dismissCompletion,
        proceedRealPurchase: proceedRealPurchase
    )
    for handler in MTGiftSetupHooks.interceptSend.handlers {
        if handler(sendContext) {
            return true
        }
    }
    return false
}
