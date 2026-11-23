import Foundation
import UIKit
import ObjectiveC
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ComponentFlow
import ChatListUI
import UndoUI
import LocalizedPeerData
import MTCore
import MTHooks
import MTNickBadgeSlot

// Where the badge is drawn. Every place reads the same in-memory table through one provider:
//   - chat header, contacts, peer lists — `MTNickBadgeSlot` lines in those files;
//   - chat list rows — `MTChatListHooks.rowDidLayout`;
//   - profile header — `MTPeerInfoHooks.headerDidLayout`;
//   - the author line of a bubble — `MTMessageDecorationHooks.authorBadge`.
// A tap shows the bulletin "<name> supports MediaTok development" with "More".

enum MTNickBadgeSlots {
    /// Line heights of the places (points): a badge is a little smaller than the name's capitals.
    static let chatListHeight: CGFloat = 16.0
    static let bubbleHeight: CGFloat = 15.0
    static let bulletinHeight: CGFloat = 32.0

    static func register() {
        MTNickBadgeSlot.provider.register({ request in
            guard MTNickBadgeSettings.isEnabled.value, let badge = MTNickBadgeService.shared.badge(for: request.peerId) else {
                return nil
            }
            let context = request.context
            let peerId = request.peerId
            return MTNickBadgeContent(image: MTNickBadgeArt.image(for: badge, height: request.height), tap: { _ in
                mtPresentNickBadgeBulletin(context: context, peerId: peerId)
            })
        })

        MTChatListHooks.rowDidLayout.register({ layout in
            MTNickBadgeSlots.layoutChatListRow(layout)
        })
        // The row's title leaves room for the badge, so a long name is cut before it.
        MTChatListHooks.titleAccessoryWidth.register({ row in
            guard let peerId = MTNickBadgeSlots.chatListBadgePeerId(row.peer, context: row.context) else {
                return 0.0
            }
            return MTNickBadgeSlot.reservedWidth(peerId: peerId, context: row.context, height: MTNickBadgeSlots.chatListHeight)
        })

        MTPeerInfoHooks.headerDidLayout.register({ header in
            MTNickBadgeSlots.layoutProfileHeader(header)
        })
        // The centered name leaves room for the badge, so the name with the badge stays centered.
        MTPeerInfoHooks.titleTrailingInset.register({ request in
            guard case .user = request.peer else {
                return 0.0
            }
            return MTNickBadgeSlot.reservedWidth(peerId: request.peer.id, context: request.context, height: MTNickBadgeSlots.profileHeight(titleHeight: request.titleHeight))
        })

        MTMessageDecorationHooks.authorBadge.register({ message, context in
            guard MTNickBadgeSettings.isEnabled.value, let author = message.author, author.id.namespace == Namespaces.Peer.CloudUser else {
                return nil
            }
            guard let badge = MTNickBadgeService.shared.badge(for: author.id) else {
                return nil
            }
            let image = MTNickBadgeArt.image(for: badge, height: MTNickBadgeSlots.bubbleHeight)
            let peerId = author.id
            return MTMessageAuthorBadge(image: image, size: image.size, tap: {
                mtPresentNickBadgeBulletin(context: context, peerId: peerId)
            })
        })

        MTLifecycleHooks.applicationDidBecomeActive.register({
            MTNickBadgeService.shared.applicationDidBecomeActive()
        })
        MTLifecycleHooks.applicationWillResignActive.register({
            MTNickBadgeService.shared.applicationWillResignActive()
        })
    }

    // MARK: - Chat list

    private static var chatListBadgeKey: UInt8 = 0

    /// Whose badge a chat list row shows: the user of a private or secret chat. Not on Saved
    /// Messages: that row is titled after the chat, not after a person.
    static func chatListBadgePeerId(_ peer: EnginePeer?, context: AccountContext) -> EnginePeer.Id? {
        switch peer {
        case let .user(user)?:
            return user.id == context.account.peerId ? nil : user.id
        case let .secretChat(secretChat)?:
            return secretChat.regularPeerId
        default:
            return nil
        }
    }

    /// After the title and the icons that follow it (emoji status, verification, muted, hidden), in
    /// the title's own container. The row reserves room for it (`titleAccessoryWidth`); a badge that
    /// arrives after the row was laid out and does not fit before the date hides instead of
    /// covering it, until the row is laid out again.
    private static func layoutChatListRow(_ layout: MTChatListRowLayout) {
        guard let node = layout.node as? ChatListItemNode else {
            return
        }
        var badgeView = objc_getAssociatedObject(node, &MTNickBadgeSlots.chatListBadgeKey) as? MTNickBadgeView
        let titleNode = node.titleNode
        let peerId = MTNickBadgeSlots.chatListBadgePeerId(layout.peer, context: layout.context)
        guard let container = titleNode.supernode?.view, peerId != nil || badgeView != nil else {
            return
        }
        let titleFrame = titleNode.frame
        var originX = titleFrame.maxX
        var limitX = container.bounds.width
        for sublayer in container.layer.sublayers ?? [] {
            if sublayer === titleNode.layer || sublayer === badgeView?.layer || sublayer.isHidden || sublayer.opacity <= 0.0 {
                continue
            }
            let frame = sublayer.frame
            if frame.minX < titleFrame.maxX - 1.0 || frame.midY < titleFrame.minY || frame.midY > titleFrame.maxY {
                continue
            }
            if sublayer.asyncdisplaykit_node is TextNode {
                // The date (or a label) on the same line: the badge must end before it.
                limitX = min(limitX, frame.minX)
                continue
            }
            let isTitleIcon = sublayer.delegate is ComponentHostView<Empty> || sublayer.asyncdisplaykit_node is ASImageNode || sublayer.delegate is UIImageView
            if isTitleIcon && frame.minX <= titleFrame.maxX + 96.0 && frame.height <= titleFrame.height + 12.0 {
                originX = max(originX, frame.maxX)
            }
        }
        // The limit stays with the view: a badge drawn later (the table read after this layout,
        // `refreshVisibleSlots`) hides instead of covering the date too.
        MTNickBadgeSlot.update(&badgeView, peerId: peerId, context: layout.context, container: container, originX: originX, centerY: titleFrame.midY, height: MTNickBadgeSlots.chatListHeight, maxX: limitX - 4.0)
        objc_setAssociatedObject(node, &MTNickBadgeSlots.chatListBadgeKey, badgeView, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    // MARK: - Profile header

    private static var headerBadgeKey: UInt8 = 0

    /// Badge height in the profile header for a name line of `titleHeight`.
    static func profileHeight(titleHeight: CGFloat) -> CGFloat {
        return max(14.0, floor(titleHeight * 0.72))
    }

    /// The header draws the name twice (the regular and the expanded state, `titleStateViews`); each
    /// state's view carries the name's icons (emoji status, premium / verification). The badge goes
    /// after them in both, so it scales and fades with the name; the header keeps the regular name
    /// centered with the badge (`titleTrailingInset`).
    private static func layoutProfileHeader(_ header: MTPeerInfoHeader) {
        var peerId: EnginePeer.Id?
        if let peer = header.peer, case .user = peer {
            peerId = peer.id
        }
        for titleView in header.titleStateViews {
            var badgeView = objc_getAssociatedObject(titleView, &MTNickBadgeSlots.headerBadgeKey) as? MTNickBadgeView
            if peerId == nil && badgeView == nil {
                continue
            }
            var originX = titleView.bounds.width
            for subview in titleView.subviews where subview is ComponentHostView<Empty> {
                if subview.isHidden || subview.alpha <= 0.0 || subview.frame.width <= 0.0 || subview.frame.maxX <= 0.0 {
                    continue
                }
                originX = max(originX, subview.frame.maxX)
            }
            let height = MTNickBadgeSlots.profileHeight(titleHeight: titleView.bounds.height)
            MTNickBadgeSlot.update(&badgeView, peerId: peerId, context: header.context, container: titleView, originX: originX, centerY: titleView.bounds.midY, height: height)
            objc_setAssociatedObject(titleView, &MTNickBadgeSlots.headerBadgeKey, badgeView, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// MARK: - Bulletin

/// What a tap on a badge says. The owner's own line wins; `{name}` in it is the wearer's name.
func mtNickBadgeCaption(badge: MTNickBadge, name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedName = trimmed.isEmpty ? MTStrings.NickBadge.Bulletin.someone : trimmed
    if let text = badge.text {
        return text.replacingOccurrences(of: "{name}", with: resolvedName)
    }
    switch badge.kind {
    case .team:
        return MTStrings.NickBadge.Bulletin.team(name: resolvedName)
    case .supporter, .custom:
        return MTStrings.NickBadge.Bulletin.supporter(name: resolvedName)
    }
}

/// The bulletin parses markdown; names and the owner's line are user text and must stay plain. A
/// word joiner between markup characters keeps them from forming `**`, `__` or `](`.
func mtNickBadgePlainMarkdown(_ text: String) -> String {
    let markup: Set<Character> = ["*", "_", "[", "]", "(", ")", "`", "~", "|"]
    var result = ""
    result.reserveCapacity(text.count)
    var previousWasMarkup = false
    for character in text {
        let isMarkup = markup.contains(character)
        if isMarkup && previousWasMarkup {
            result.append("\u{2060}")
        }
        result.append(character)
        previousWasMarkup = isMarkup
    }
    return result
}

func mtPresentNickBadgeBulletin(context: AccountContext, peerId: EnginePeer.Id) {
    guard let badge = MTNickBadgeService.shared.badge(for: peerId) else {
        return
    }
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    |> deliverOnMainQueue).start(next: { peer in
        guard let (navigationController, topController) = mtProfileExportTopController(context: context) else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let name = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? ""
        let text = mtNickBadgePlainMarkdown(mtNickBadgeCaption(badge: badge, name: name))
        let image = MTNickBadgeArt.image(for: badge, height: MTNickBadgeSlots.bulletinHeight)
        topController.present(UndoOverlayController(
            presentationData: presentationData,
            content: .image(image: image, title: nil, text: text, round: false, undoText: MTStrings.NickBadge.Bulletin.more),
            elevatedLayout: false,
            action: { [weak navigationController] action in
                if case .undo = action, let navigationController = navigationController {
                    navigationController.pushViewController(mtMakeNickBadgeScreen(context: context))
                }
                return true
            }
        ), in: .current)
    })
}
