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

/// A structured Discord-style integration card rendered in the profile's «Интеграции» section.
public struct MTPeerInfoIntegrationCard {
    public let id: String
    public let platform: String
    public let username: String
    public let isVerified: Bool
    public let memberSinceText: String?
    public let primaryStatBold: String?
    public let primaryStatLabel: String?
    public let secondaryStatBold: String?
    public let secondaryStatLabel: String?
    public let action: (() -> Void)?
    public let longTapAction: (() -> Void)?

    public init(
        id: String,
        platform: String,
        username: String,
        isVerified: Bool = true,
        memberSinceText: String? = nil,
        primaryStatBold: String? = nil,
        primaryStatLabel: String? = nil,
        secondaryStatBold: String? = nil,
        secondaryStatLabel: String? = nil,
        action: (() -> Void)? = nil,
        longTapAction: (() -> Void)? = nil
    ) {
        self.id = id
        self.platform = platform
        self.username = username
        self.isVerified = isVerified
        self.memberSinceText = memberSinceText
        self.primaryStatBold = primaryStatBold
        self.primaryStatLabel = primaryStatLabel
        self.secondaryStatBold = secondaryStatBold
        self.secondaryStatLabel = secondaryStatLabel
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

    /// Providers of Discord-style integration cards shown in the profile's «Интеграции» section.
    public static let integrationCards = MTHookPoint<(MTPeerInfoContext) -> [MTPeerInfoIntegrationCard]>("peerInfo.integrationCards")

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

    public static func integrations(context: @autoclosure () -> MTPeerInfoContext) -> [MTPeerInfoIntegrationCard] {
        if MTPeerInfoHooks.integrationCards.isEmpty {
            return []
        }
        let value = context()
        var result: [MTPeerInfoIntegrationCard] = []
        for handler in MTPeerInfoHooks.integrationCards.handlers {
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

// MARK: - Official Service Brand Vector Icons (24x24 SVG Non-Zero Winding Paths)

public enum MTPeerInfoBrandIcons {
    private static let svgPaths: [String: String] = [
        "steam": "M 11.98 0 C 5.68 0 0.51 4.86 0.02 11.04 L 6.45 13.7 C 7 13.32 7.66 13.11 8.37 13.11 C 8.43 13.11 8.49 13.11 8.55 13.11 L 11.42 8.97 L 11.42 8.91 C 11.42 6.42 13.44 4.39 15.94 4.39 C 18.43 4.39 20.46 6.42 20.46 8.91 C 20.46 11.41 18.43 13.44 15.94 13.44 L 15.83 13.44 L 11.76 16.35 C 11.76 16.4 11.76 16.45 11.76 16.51 C 11.76 18.38 10.25 19.9 8.37 19.9 C 6.74 19.9 5.36 18.73 5.04 17.18 L 0.44 15.27 C 1.86 20.31 6.49 24 11.98 24 C 18.61 24 23.98 18.63 23.98 12 C 23.98 5.37 18.61 0 11.98 0 Z M 7.54 18.21 L 6.07 17.6 C 6.33 18.14 6.78 18.6 7.38 18.85 C 8.68 19.39 10.17 18.77 10.71 17.48 C 10.98 16.85 10.98 16.16 10.72 15.53 C 10.46 14.9 9.97 14.41 9.34 14.14 C 8.72 13.88 8.05 13.89 7.46 14.11 L 8.99 14.74 C 9.94 15.14 10.4 16.24 10 17.2 C 9.6 18.16 8.5 18.61 7.54 18.21 L 7.54 18.21 Z M 18.95 8.91 C 18.95 7.25 17.6 5.89 15.94 5.89 C 14.27 5.89 12.92 7.24 12.92 8.91 C 12.92 10.57 14.27 11.92 15.94 11.92 C 17.6 11.92 18.95 10.57 18.95 8.91 Z M 13.68 8.9 C 13.68 7.65 14.69 6.64 15.95 6.64 C 17.2 6.64 18.21 7.65 18.21 8.9 C 18.21 10.15 17.2 11.17 15.95 11.17 C 14.69 11.17 13.68 10.15 13.68 8.9 Z",
        "spotify": "M 12 0 C 5.4 0 0 5.4 0 12 C 0 18.6 5.4 24 12 24 C 18.6 24 24 18.6 24 12 C 24 5.4 18.66 0 12 0 Z M 17.52 17.34 C 17.28 17.7 16.86 17.82 16.5 17.58 C 13.68 15.84 10.14 15.48 5.94 16.44 C 5.52 16.56 5.16 16.26 5.04 15.9 C 4.92 15.48 5.22 15.12 5.58 15 C 10.14 13.98 14.1 14.4 17.22 16.32 C 17.64 16.5 17.7 16.98 17.52 17.34 Z M 18.96 14.04 C 18.66 14.46 18.12 14.64 17.7 14.34 C 14.46 12.36 9.54 11.76 5.76 12.96 C 5.28 13.08 4.74 12.84 4.62 12.36 C 4.5 11.88 4.74 11.34 5.22 11.22 C 9.6 9.9 15 10.56 18.72 12.84 C 19.08 13.02 19.26 13.62 18.96 14.04 Z M 19.08 10.68 C 15.24 8.4 8.82 8.16 5.16 9.3 C 4.56 9.48 3.96 9.12 3.78 8.58 C 3.6 7.98 3.96 7.38 4.5 7.2 C 8.76 5.94 15.78 6.18 20.22 8.82 C 20.76 9.12 20.94 9.84 20.64 10.38 C 20.34 10.8 19.62 10.98 19.08 10.68 Z",
        "discord": "M 20.32 4.37 C 18.76 3.66 17.12 3.15 15.43 2.85 C 15.4 2.85 15.37 2.86 15.35 2.89 C 15.14 3.27 14.91 3.76 14.75 4.14 C 12.9 3.86 11.07 3.86 9.26 4.14 C 9.09 3.75 8.85 3.27 8.64 2.89 C 8.62 2.86 8.59 2.85 8.56 2.85 C 6.87 3.15 5.23 3.65 3.68 4.37 C 3.66 4.38 3.65 4.39 3.64 4.4 C 0.53 9.05 -0.32 13.58 0.1 18.06 C 0.1 18.08 0.11 18.1 0.13 18.11 C 2.18 19.62 4.17 20.54 6.12 21.14 C 6.15 21.15 6.19 21.14 6.21 21.12 C 6.67 20.49 7.08 19.82 7.43 19.12 C 7.44 19.1 7.44 19.08 7.44 19.06 C 7.43 19.04 7.41 19.02 7.39 19.02 C 6.74 18.77 6.12 18.47 5.52 18.12 C 5.5 18.11 5.48 18.09 5.48 18.06 C 5.48 18.04 5.49 18.01 5.51 18 C 5.64 17.9 5.76 17.8 5.88 17.7 C 5.91 17.69 5.94 17.68 5.96 17.69 C 9.89 19.49 14.14 19.49 18.02 17.69 C 18.05 17.68 18.08 17.69 18.1 17.7 C 18.22 17.8 18.35 17.9 18.47 18 C 18.49 18.01 18.51 18.04 18.5 18.06 C 18.5 18.09 18.49 18.11 18.47 18.12 C 17.87 18.47 17.24 18.77 16.59 19.01 C 16.57 19.02 16.56 19.04 16.55 19.06 C 16.54 19.08 16.54 19.1 16.55 19.12 C 16.91 19.82 17.33 20.48 17.78 21.11 C 17.8 21.14 17.83 21.15 17.86 21.14 C 19.82 20.54 21.81 19.62 23.87 18.11 C 23.88 18.1 23.89 18.08 23.9 18.06 C 24.4 12.88 23.06 8.38 20.35 4.4 C 20.34 4.39 20.33 4.38 20.32 4.37 Z M 8.02 15.33 C 6.84 15.33 5.86 14.25 5.86 12.91 C 5.86 11.58 6.82 10.49 8.02 10.49 C 9.23 10.49 10.2 11.59 10.18 12.91 C 10.18 14.25 9.22 15.33 8.02 15.33 Z M 15.99 15.33 C 14.81 15.33 13.84 14.25 13.84 12.91 C 13.84 11.58 14.79 10.49 15.99 10.49 C 17.21 10.49 18.17 11.59 18.15 12.91 C 18.15 14.25 17.21 15.33 15.99 15.33 Z",
        "youtube": "M 23.5 6.19 C 23.22 5.15 22.41 4.33 21.38 4.05 C 19.5 3.54 12 3.54 12 3.54 C 12 3.54 4.5 3.54 2.62 4.05 C 1.59 4.33 0.78 5.15 0.5 6.19 C 0 8.07 0 12 0 12 C 0 12 0 15.93 0.5 17.81 C 0.78 18.85 1.59 19.67 2.62 19.95 C 4.49 20.45 12 20.45 12 20.45 C 12 20.45 19.5 20.45 21.38 19.95 C 22.41 19.67 23.22 18.85 23.5 17.81 C 24 15.93 24 12 24 12 C 24 12 24 8.07 23.5 6.19 Z M 9.54 15.57 L 9.54 8.43 L 15.82 12 L 9.54 15.57 Z",
        "roblox": "M 18.93 24 L 0 18.89 L 5.08 0 L 24 5.11 Z M 15.35 10.09 L 10.07 8.64 L 8.65 13.91 L 13.93 15.36 Z",
        "twitch": "M 11.57 4.71 L 13.29 4.71 L 13.29 9.86 L 11.57 9.86 Z M 16.29 4.71 L 18 4.71 L 18 9.86 L 16.29 9.86 Z M 6 0 L 1.71 4.29 L 1.71 19.71 L 6.86 19.71 L 6.86 24 L 11.14 19.71 L 14.57 19.71 L 22.29 12 L 22.29 0 Z M 20.57 11.14 L 17.14 14.57 L 13.71 14.57 L 10.71 17.57 L 10.71 14.57 L 6.86 14.57 L 6.86 1.71 L 20.57 1.71 Z",
        "github": "M 12 0.3 C 5.37 0.3 0 5.67 0 12.3 C 0 17.6 3.44 22.1 8.21 23.68 C 8.8 23.8 9.03 23.42 9.03 23.11 C 9.03 22.82 9.02 22.07 9.01 21.07 C 5.67 21.79 4.97 19.46 4.97 19.46 C 4.42 18.07 3.63 17.7 3.63 17.7 C 2.55 16.96 3.72 16.97 3.72 16.97 C 4.92 17.05 5.55 18.21 5.55 18.21 C 6.62 20.04 8.36 19.51 9.05 19.21 C 9.16 18.43 9.47 17.9 9.81 17.6 C 7.15 17.3 4.34 16.27 4.34 11.67 C 4.34 10.36 4.81 9.29 5.58 8.45 C 5.44 8.15 5.04 6.93 5.68 5.27 C 5.68 5.27 6.69 4.95 8.98 6.5 C 9.94 6.24 10.96 6.11 11.98 6.1 C 13 6.11 14.02 6.24 14.98 6.5 C 17.26 4.95 18.27 5.27 18.27 5.27 C 18.91 6.93 18.51 8.15 18.39 8.45 C 19.15 9.29 19.62 10.36 19.62 11.67 C 19.62 16.28 16.81 17.3 14.14 17.59 C 14.56 17.95 14.95 18.69 14.95 19.81 C 14.95 21.42 14.94 22.71 14.94 23.1 C 14.94 23.41 15.15 23.79 15.76 23.67 C 20.57 22.09 24 17.59 24 12.3 C 24 5.67 18.63 0.3 12 0.3",
        "tiktok": "M 12.53 0.02 C 13.84 0 15.13 0.01 16.44 0 C 16.52 1.53 17.07 3.09 18.19 4.17 C 19.31 5.28 20.89 5.79 22.43 5.96 L 22.43 9.99 C 20.99 9.94 19.54 9.64 18.23 9.02 C 17.66 8.76 17.13 8.43 16.61 8.09 C 16.6 11.01 16.62 13.93 16.59 16.84 C 16.51 18.24 16.05 19.63 15.24 20.78 C 13.93 22.7 11.66 23.95 9.33 23.99 C 7.9 24.07 6.47 23.68 5.25 22.96 C 3.23 21.77 1.81 19.59 1.6 17.25 C 1.58 16.75 1.57 16.25 1.59 15.76 C 1.77 13.86 2.71 12.04 4.17 10.8 C 5.83 9.36 8.15 8.67 10.32 9.08 C 10.34 10.56 10.28 12.04 10.28 13.52 C 9.29 13.2 8.13 13.29 7.26 13.89 C 6.63 14.3 6.15 14.93 5.9 15.64 C 5.69 16.15 5.75 16.71 5.76 17.25 C 6 18.89 7.58 20.27 9.26 20.12 C 10.38 20.11 11.45 19.46 12.03 18.51 C 12.22 18.18 12.43 17.84 12.44 17.45 C 12.54 15.66 12.5 13.88 12.51 12.09 C 12.52 8.06 12.5 4.04 12.53 0.02 Z",
        "kick": "M 1.33 0 L 9.33 0 L 9.33 5.33 L 12 5.33 L 12 2.67 L 14.67 2.67 L 14.67 0 L 22.67 0 L 22.67 8 L 20 8 L 20 10.67 L 17.33 10.67 L 17.33 13.33 L 20 13.33 L 20 16 L 22.67 16 L 22.67 24 L 14.67 24 L 14.67 21.33 L 12 21.33 L 12 18.67 L 9.33 18.67 L 9.33 24 L 1.33 24 Z"
    ]

    private static func buildPath(_ encoded: String) -> CGPath {
        let path = CGMutablePath()
        let tokens = encoded.split(separator: " ")
        var i = 0
        func nextVal() -> CGFloat {
            let v = Double(tokens[i]) ?? 0.0
            i += 1
            return CGFloat(v)
        }
        while i < tokens.count {
            let cmd = tokens[i]
            i += 1
            switch cmd {
            case "M":
                let x = nextVal(); let y = nextVal()
                path.move(to: CGPoint(x: x, y: y))
            case "L":
                let x = nextVal(); let y = nextVal()
                path.addLine(to: CGPoint(x: x, y: y))
            case "C":
                let x1 = nextVal(); let y1 = nextVal()
                let x2 = nextVal(); let y2 = nextVal()
                let x = nextVal(); let y = nextVal()
                path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case "Z":
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }

    public static func image(for platform: String, size: CGFloat = 32.0, isDark: Bool = true) -> UIImage {
        let key: String
        switch platform.lowercased() {
        case "lastfm", "listenbrainz": key = "spotify"
        default: key = platform.lowercased()
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            guard let encoded = svgPaths[key] else {
                cg.setFillColor(UIColor(white: 0.35, alpha: 1.0).cgColor)
                cg.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
                return
            }
            let cgPath = buildPath(encoded)

            func fillGlyph(color: UIColor, inset: CGFloat = 0.0, offset: CGPoint = .zero) {
                cg.saveGState()
                let avail = size - inset * 2.0
                let sc = avail / 24.0
                cg.translateBy(x: inset + offset.x, y: inset + offset.y)
                cg.scaleBy(x: sc, y: sc)
                cg.addPath(cgPath)
                cg.setFillColor(color.cgColor)
                cg.fillPath(using: .winding)
                cg.restoreGState()
            }

            switch key {
            case "steam":
                // Exact Discord Steam circular badge (white glyph on dark, dark slate on light)
                fillGlyph(color: isDark ? .white : UIColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1.0), inset: 1.0)
            case "spotify":
                // Exact Discord Spotify green circle
                fillGlyph(color: UIColor(red: 0.118, green: 0.843, blue: 0.376, alpha: 1.0), inset: 1.0)
            case "github":
                // Exact Discord GitHub Octocat circle
                fillGlyph(color: isDark ? .white : UIColor(white: 0.10, alpha: 1.0), inset: 1.0)
            case "roblox":
                // Exact Discord Roblox tilted hollow square
                fillGlyph(color: isDark ? .white : UIColor(white: 0.12, alpha: 1.0), inset: 2.0)
            case "youtube":
                // Exact YouTube red badge with white play triangle behind cutout
                let triBg = CGRect(x: size * 0.34, y: size * 0.32, width: size * 0.34, height: size * 0.36)
                cg.setFillColor(UIColor.white.cgColor)
                cg.fill(triBg)
                fillGlyph(color: UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0), inset: 1.0)
            case "discord":
                // Official Discord blurple rounded badge + white Clyde glyph
                let badge = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: size - 2, height: size - 2), cornerRadius: size * 0.28)
                UIColor(red: 0.345, green: 0.396, blue: 0.949, alpha: 1.0).setFill()
                badge.fill()
                fillGlyph(color: .white, inset: size * 0.18)
            case "twitch":
                // Official Twitch purple badge + white inner face + purple eyes/outline
                let innerRect = CGRect(x: size * 0.28, y: size * 0.14, width: size * 0.56, height: size * 0.50)
                cg.setFillColor(UIColor.white.cgColor)
                cg.fill(innerRect)
                fillGlyph(color: UIColor(red: 0.569, green: 0.275, blue: 1.0, alpha: 1.0), inset: 1.5)
            case "tiktok":
                // Official TikTok dark badge + cyan/pink/white official vector note
                let badge = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: size - 2, height: size - 2), cornerRadius: size * 0.28)
                UIColor(white: 0.07, alpha: 1.0).setFill()
                badge.fill()
                let shift = size * 0.032
                fillGlyph(color: UIColor(red: 0.145, green: 0.957, blue: 0.933, alpha: 1.0), inset: size * 0.19, offset: CGPoint(x: -shift, y: -shift * 0.8))
                fillGlyph(color: UIColor(red: 0.996, green: 0.173, blue: 0.333, alpha: 1.0), inset: size * 0.19, offset: CGPoint(x: shift, y: shift * 0.8))
                fillGlyph(color: .white, inset: size * 0.19)
            case "kick":
                // Official Kick dark badge + neon-green blocky K
                let badge = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: size - 2, height: size - 2), cornerRadius: size * 0.28)
                UIColor(white: 0.07, alpha: 1.0).setFill()
                badge.fill()
                fillGlyph(color: UIColor(red: 0.325, green: 0.988, blue: 0.094, alpha: 1.0), inset: size * 0.22)
            default:
                fillGlyph(color: isDark ? .white : .black, inset: 2.0)
            }
        }
    }
}
