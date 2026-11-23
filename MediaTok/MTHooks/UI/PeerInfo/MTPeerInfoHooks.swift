// Profiles (PeerInfoScreen): the «…» menu, extra info rows (ID, data center, dates), how a phone
// number is shown (fake number, hidden number), the header after layout (badge, GIF background,
// avatar shape), redirecting a profile to another peer. Mapping to PeerInfoScreen's internal
// item types: MTHooks/PeerInfoScreen/.

import Foundation
import UIKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import MTCore

public struct MTPeerInfoContext {
    public let context: AccountContext
    /// The peer the profile describes (a secret chat's profile describes the user).
    public let peer: EnginePeer
    /// The chat the profile belongs to (the secret chat itself, a channel…).
    public let chatPeer: EnginePeer?
    public let isSettings: Bool
    public weak var controller: ViewController?
    /// The group or channel the profile was opened from (a member's profile opened from a group's
    /// message), if any: for facts about the membership (when they joined).
    public let sourceChatPeerId: EnginePeer.Id?
    /// The message the profile was opened from (a tap on its author), if any.
    public let sourceMessageId: EngineMessage.Id?
    /// The profile's cached data as the profile shows it (`CachedUserData` of a user: peer settings,
    /// registration month…), nil until loaded.
    public let cachedData: CachedPeerData?

    public init(context: AccountContext, peer: EnginePeer, chatPeer: EnginePeer?, isSettings: Bool, controller: ViewController?, sourceChatPeerId: EnginePeer.Id? = nil, sourceMessageId: EngineMessage.Id? = nil, cachedData: CachedPeerData? = nil) {
        self.context = context
        self.peer = peer
        self.chatPeer = chatPeer
        self.isSettings = isSettings
        self.controller = controller
        self.sourceChatPeerId = sourceChatPeerId
        self.sourceMessageId = sourceMessageId
        self.cachedData = cachedData
    }
}

/// A label / value row in a profile's info section.
public struct MTPeerInfoRow {
    public let id: String
    public let label: String
    public let text: String
    /// Secondary text on the right of the label (e.g. the account's age next to its creation date).
    public let rightLabel: String?
    public let action: (() -> Void)?
    public let longTapAction: (() -> Void)?

    public init(id: String, label: String, text: String, rightLabel: String? = nil, action: (() -> Void)? = nil, longTapAction: (() -> Void)? = nil) {
        self.id = id
        self.label = label
        self.text = text
        self.rightLabel = rightLabel
        self.action = action
        self.longTapAction = longTapAction
    }
}

public enum MTPhoneDisplay {
    case hidden
    case replaced(String)
}

public struct MTPhoneDisplayRequest {
    public let context: AccountContext
    public let peerId: EnginePeer.Id
    /// The account's own number (Settings, own profile).
    public let isAccountPeer: Bool
    public let phone: String
}

public struct MTPeerInfoHeader {
    public let context: AccountContext
    public let peer: EnginePeer?
    public let isSettings: Bool
    /// The header node (PeerInfoHeaderNode); cast it in the feature module for its public parts.
    public let node: ASDisplayNode
    public let width: CGFloat
    public let height: CGFloat
    public let transition: ContainedViewLayoutTransition
    /// The header's background banner (the colored / gift cover area behind the avatar).
    public let backgroundContainerView: UIView?
    /// The name, drawn twice: the regular (centered) and the expanded-avatar state, in this order.
    /// The name's icons (emoji status, premium, verification) are their subviews, placed after the
    /// text; a mark that goes after them in these views scales and fades with the name.
    public let titleStateViews: [UIView]

    public init(context: AccountContext, peer: EnginePeer?, isSettings: Bool, node: ASDisplayNode, width: CGFloat, height: CGFloat, transition: ContainedViewLayoutTransition, backgroundContainerView: UIView? = nil, titleStateViews: [UIView] = []) {
        self.context = context
        self.peer = peer
        self.isSettings = isSettings
        self.node = node
        self.width = width
        self.height = height
        self.transition = transition
        self.backgroundContainerView = backgroundContainerView
        self.titleStateViews = titleStateViews
    }
}

/// What `MTPeerInfoHooks.titleTrailingInset` is asked.
public struct MTPeerInfoTitleRequest {
    public let context: AccountContext
    public let peer: EnginePeer
    public let isSettings: Bool
    /// Height of the name in its regular (centered) state, pt.
    public let titleHeight: CGFloat

    public init(context: AccountContext, peer: EnginePeer, isSettings: Bool, titleHeight: CGFloat) {
        self.context = context
        self.peer = peer
        self.isSettings = isSettings
        self.titleHeight = titleHeight
    }
}

/// Telegram's own items of a profile a feature may hide.
public enum MTPeerInfoItemKind {
    /// «О себе» of a user, the description of a group or channel.
    case description
    /// «Поделиться контактом» in the «…» menu.
    case shareButton
    /// The star rating («level») badge before the subtitle of a user's profile and of Settings.
    case starRating
}

/// The shared-media area of a profile (the tabs «Медиа», «Файлы», «Ссылки»… and their panes), after
/// its layout. A feature may put its own view over `paneContainer` (e.g. a lock cover); the pane
/// container keeps adding panes later, so such a view must stay on top on every call.
public struct MTPeerInfoPaneLayout {
    public let context: AccountContext
    /// The chat the media belongs to (a secret chat's profile — the secret chat).
    public let peerId: EnginePeer.Id
    public let isSettings: Bool
    /// The profile shows panes now (not editing, the peer has any).
    public let hasPanes: Bool
    /// PeerInfoPaneContainerNode.
    public let paneContainer: ASDisplayNode
    /// The profile screen (its lifetime is the lifetime of anything granted to it).
    public weak var controller: ViewController?

    public init(context: AccountContext, peerId: EnginePeer.Id, isSettings: Bool, hasPanes: Bool, paneContainer: ASDisplayNode, controller: ViewController?) {
        self.context = context
        self.peerId = peerId
        self.isSettings = isSettings
        self.hasPanes = hasPanes
        self.paneContainer = paneContainer
        self.controller = controller
    }
}

public enum MTPeerInfoHooks {
    /// Observer after the shared-media area of a profile is laid out (main thread, every layout of the
    /// profile): MediaTok covers the media of a protected chat until the check passes.
    public static let paneContainerDidLayout = MTHookPoint<(MTPeerInfoPaneLayout) -> Void>("peerInfo.paneContainerDidLayout")

    /// Providers of items appended to the profile's «…» menu.
    public static let menuItems = MTHookPoint<(MTPeerInfoContext) -> [ContextMenuItem]>("peerInfo.menuItems")

    /// Providers of rows appended to the profile's info section.
    public static let infoRows = MTHookPoint<(MTPeerInfoContext) -> [MTPeerInfoRow]>("peerInfo.infoRows")

    /// Policy: how a phone number is shown (profile, Settings header and row).
    public static let displayedPhoneNumber = MTHookPoint<(MTPhoneDisplayRequest) -> MTPhoneDisplay?>("peerInfo.displayedPhoneNumber")

    /// Observer after every header layout (main thread, scroll path: snapshot reads only).
    public static let headerDidLayout = MTHookPoint<(MTPeerInfoHeader) -> Void>("peerInfo.headerDidLayout")

    /// Provider (summed over handlers): room a feature's mark takes after the name and its icons
    /// (width + spacing, pt; 0 = none). The header shifts the centered name by half of it, as it
    /// does for its own icons, so the name with the mark stays centered. Asked on every header
    /// layout (scroll frames, main thread): answer from memory.
    public static let titleTrailingInset = MTHookPoint<(MTPeerInfoTitleRequest) -> CGFloat>("peerInfo.titleTrailingInset")

    /// Policy: open another peer's profile instead of this one («Подмена профиля»).
    public static let redirectPeer = MTHookPoint<(AccountContext, EnginePeer.Id) -> EnginePeer.Id?>("peerInfo.redirectPeer")

    /// Policy (any `true`): hide one of Telegram's own items of a profile.
    public static let hidesItem = MTHookPoint<(MTPeerInfoItemKind, MTPeerInfoContext) -> Bool>("peerInfo.hidesItem")

    /// Policy (any `true`): a feature draws its own header background inside `backgroundContainerView`
    /// (e.g. a custom profile banner / theme), so the header treats it as having a colored backdrop
    /// and uses crisp white title/subtitle/music/button styling.
    public static let hasHeaderBackground = MTHookPoint<(EnginePeer.Id) -> Bool>("peerInfo.hasHeaderBackground")

    public static func hasCustomHeaderBackground(peerId: EnginePeer.Id) -> Bool {
        if MTPeerInfoHooks.hasHeaderBackground.isEmpty {
            return false
        }
        for handler in MTPeerInfoHooks.hasHeaderBackground.handlers {
            if handler(peerId) {
                return true
            }
        }
        return false
    }

    /// `context` is built only when a feature hides items.
    public static func hidesItem(_ kind: MTPeerInfoItemKind, context: @autoclosure () -> MTPeerInfoContext?) -> Bool {
        if MTPeerInfoHooks.hidesItem.isEmpty {
            return false
        }
        guard let value = context() else {
            return false
        }
        for handler in MTPeerInfoHooks.hidesItem.handlers {
            if handler(kind, value) {
                return true
            }
        }
        return false
    }

    public static func appendMenuItems(_ items: [ContextMenuItem], context: @autoclosure () -> MTPeerInfoContext) -> [ContextMenuItem] {
        if MTPeerInfoHooks.menuItems.isEmpty {
            return items
        }
        let value = context()
        var extra: [ContextMenuItem] = []
        for handler in MTPeerInfoHooks.menuItems.handlers {
            extra.append(contentsOf: handler(value))
        }
        if extra.isEmpty {
            return items
        }
        if items.isEmpty {
            return extra
        }
        return items + [.separator] + extra
    }

    public static func rows(context: @autoclosure () -> MTPeerInfoContext) -> [MTPeerInfoRow] {
        if MTPeerInfoHooks.infoRows.isEmpty {
            return []
        }
        let value = context()
        var result: [MTPeerInfoRow] = []
        for handler in MTPeerInfoHooks.infoRows.handlers {
            result.append(contentsOf: handler(value))
        }
        return result
    }

    /// The phone to show: nil hides it.
    public static func phone(_ phone: String?, peerId: EnginePeer.Id, context: AccountContext) -> String? {
        guard let phone, !MTPeerInfoHooks.displayedPhoneNumber.isEmpty else {
            return phone
        }
        let request = MTPhoneDisplayRequest(context: context, peerId: peerId, isAccountPeer: peerId == context.account.peerId, phone: phone)
        for handler in MTPeerInfoHooks.displayedPhoneNumber.handlers {
            if let value = handler(request) {
                switch value {
                case .hidden:
                    return nil
                case let .replaced(replacement):
                    return replacement
                }
            }
        }
        return phone
    }

    /// MediaTok hook target: PeerInfoHeaderNode — the room after the name (0 without handlers).
    public static func resolvedTitleTrailingInset(context: AccountContext, peer: EnginePeer?, isSettings: Bool, titleHeight: CGFloat) -> CGFloat {
        if MTPeerInfoHooks.titleTrailingInset.isEmpty {
            return 0.0
        }
        guard let peer = peer else {
            return 0.0
        }
        let request = MTPeerInfoTitleRequest(context: context, peer: peer, isSettings: isSettings, titleHeight: titleHeight)
        var result: CGFloat = 0.0
        for handler in MTPeerInfoHooks.titleTrailingInset.handlers {
            result += max(0.0, handler(request))
        }
        return result
    }

    public static func notifyHeaderDidLayout(_ header: @autoclosure () -> MTPeerInfoHeader) {
        if MTPeerInfoHooks.headerDidLayout.isEmpty {
            return
        }
        let value = header()
        for handler in MTPeerInfoHooks.headerDidLayout.handlers {
            handler(value)
        }
    }

    public static func redirect(_ peerId: EnginePeer.Id, context: AccountContext) -> EnginePeer.Id {
        for handler in MTPeerInfoHooks.redirectPeer.handlers {
            if let value = handler(context, peerId) {
                return value
            }
        }
        return peerId
    }
}
