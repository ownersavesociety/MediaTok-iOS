// The message context menu: features add items («Прочитать», «История», «Изменить локально»,
// «Закладка», «Скопировать без защиты»…) and filter Telegram's own. One call site:
// the end of `contextMenuForChatPresentationInterfaceState` (ChatInterfaceStateContextMenus.swift).

import Foundation
import UIKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import MTCore

public struct MTMessageMenuContext {
    public let context: AccountContext
    public let chatLocation: ChatLocation
    /// The long-pressed message group (one message unless it is an album).
    public let messages: [Message]
    public let presentationData: PresentationData
    /// The chat forbids copying and forwarding (the chat's own protection, with features applied —
    /// `ChatPresentationInterfaceState.copyProtectionEnabled`); a message's own flag is
    /// `Message.isCopyProtected()`.
    public let isCopyProtectionEnabled: Bool

    public init(context: AccountContext, chatLocation: ChatLocation, messages: [Message], presentationData: PresentationData, isCopyProtectionEnabled: Bool = false) {
        self.context = context
        self.chatLocation = chatLocation
        self.messages = messages
        self.presentationData = presentationData
        self.isCopyProtectionEnabled = isCopyProtectionEnabled
    }
}

public struct MTMessageMenuEntry {
    public enum Position {
        /// Before Telegram's first item.
        case top
        /// After Telegram's items, before nothing.
        case bottom
    }

    public let position: Position
    public let item: ContextMenuItem

    public init(position: Position, item: ContextMenuItem) {
        self.position = position
        self.item = item
    }
}

public enum MTMessageMenuHooks {
    /// Providers of extra items. Actions dismiss the menu through the action's `f(.default)`.
    public static let items = MTHookPoint<(MTMessageMenuContext) -> [MTMessageMenuEntry]>("messageMenu.items")

    /// Transformer over the final list (hide Telegram's items, reorder).
    public static let filter = MTHookPoint<([ContextMenuItem], MTMessageMenuContext) -> [ContextMenuItem]>("messageMenu.filter")

    public static var isEmpty: Bool {
        return MTMessageMenuHooks.items.isEmpty && MTMessageMenuHooks.filter.isEmpty
    }

    public static func apply(_ actions: [ContextMenuItem], context: MTMessageMenuContext) -> [ContextMenuItem] {
        var top: [ContextMenuItem] = []
        var bottom: [ContextMenuItem] = []
        for handler in MTMessageMenuHooks.items.handlers {
            for entry in handler(context) {
                switch entry.position {
                case .top:
                    top.append(entry.item)
                case .bottom:
                    bottom.append(entry.item)
                }
            }
        }
        var result = actions
        if !top.isEmpty {
            result = top + [.separator] + result
        }
        if !bottom.isEmpty {
            result = result + [.separator] + bottom
        }
        for handler in MTMessageMenuHooks.filter.handlers {
            result = handler(result, context)
        }
        return result
    }
}
