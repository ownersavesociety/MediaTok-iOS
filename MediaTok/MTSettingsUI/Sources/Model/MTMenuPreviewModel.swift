import Foundation
import UIKit
import TelegramPresentationData
import MTCore

// Live previews. One host per kind, constant height; the bubble and chat-list renderers are the
// real upstream ones (makeChatMessagePreviewItem / ChatListItem) — nothing is drawn by hand here.

public enum MTMenuPreview {
    /// Real bubbles on the real wallpaper.
    case miniChat(MTMiniChatConfiguration)
    /// Real ChatListItem rows.
    case miniChatList(MTMiniChatListConfiguration)
    /// Any view inside the shared «block with glass corners». If the view adopts
    /// `MTMenuPreviewView`, it is updated on every rebuild of the screen.
    case custom(height: CGFloat, make: (MTMenuContext) -> UIView)
}

/// Adopt to get `update(context:)` on every rebuild (settings change, slider tick, theme change).
public protocol MTMenuPreviewView: UIView {
    func update(context: MTMenuContext)
}

// MARK: - Mini chat

public struct MTPreviewReply: Equatable {
    public var author: String
    public var text: String

    public init(author: String, text: String) {
        self.author = author
        self.text = text
    }
}

/// A mark before the bubble's time (deleted / edited history marks).
///
/// `statusText` is put into the bubble's own status line, exactly as the chat does it (the status
/// prefix of `MTMessageDecorationHooks`), so the bubble makes room for it. `icon` is a glyph drawn
/// next to the time without making room — only for marks the chat itself draws as an icon.
public struct MTPreviewMark: Equatable {
    public var icon: MTMenuIcon?
    public var color: UIColor?
    public var statusText: String?

    public init(icon: MTMenuIcon, color: UIColor? = nil) {
        self.icon = icon
        self.color = color
        self.statusText = nil
    }

    public init(statusText: String) {
        self.icon = nil
        self.color = nil
        self.statusText = statusText
    }
}

public struct MTPreviewMessage: Equatable {
    public var id: Int32
    public var isOutgoing: Bool
    public var text: String
    public var reply: MTPreviewReply?
    /// A block quote on top of the text (a reply sent as a quote, e.g. to a deleted message).
    public var quote: String?
    /// Shows the native «edited» label.
    public var isEdited: Bool
    /// Clock instead of checkmarks (outgoing only).
    public var isPending: Bool
    /// One check instead of two (outgoing only): delivered, not read yet.
    public var isUnread: Bool
    /// Whole bubble alpha (deleted-message transparency).
    public var alpha: CGFloat
    public var mark: MTPreviewMark?
    /// Seconds before now.
    public var ageSeconds: Int32

    public init(id: Int32, isOutgoing: Bool, text: String, reply: MTPreviewReply? = nil, quote: String? = nil, isEdited: Bool = false, isPending: Bool = false, isUnread: Bool = false, alpha: CGFloat = 1.0, mark: MTPreviewMark? = nil, ageSeconds: Int32 = 60) {
        self.id = id
        self.isOutgoing = isOutgoing
        self.text = text
        self.reply = reply
        self.quote = quote
        self.isEdited = isEdited
        self.isPending = isPending
        self.isUnread = isUnread
        self.alpha = alpha
        self.mark = mark
        self.ageSeconds = ageSeconds
    }
}

public struct MTMiniChatHeader: Equatable {
    public enum Peer: Equatable {
        /// The account the menu is open for (its own avatar and name).
        case account
        /// A demo peer with a letters avatar.
        case demo(name: String)
    }

    public var peer: Peer
    public var status: String
    public var statusIsAccent: Bool
    /// The chat's top bar without the avatar (the name moves to the left edge).
    public var hidesAvatar: Bool
    /// The chat's top bar without the name and the status.
    public var hidesTitle: Bool

    public init(peer: Peer, status: String, statusIsAccent: Bool = false, hidesAvatar: Bool = false, hidesTitle: Bool = false) {
        self.peer = peer
        self.status = status
        self.statusIsAccent = statusIsAccent
        self.hidesAvatar = hidesAvatar
        self.hidesTitle = hidesTitle
    }
}

public struct MTMiniChatContent: Equatable {
    public var header: MTMiniChatHeader?
    public var messages: [MTPreviewMessage]

    public init(header: MTMiniChatHeader?, messages: [MTPreviewMessage]) {
        self.header = header
        self.messages = messages
    }
}

extension MTMiniChatContent {
    /// The standard conversation (an incoming message and an outgoing reply), localized. Features
    /// usually start from it and change it in their own content closure or in a modifier.
    public static func sample(header: MTMiniChatHeader? = nil) -> MTMiniChatContent {
        let peerName = MTStrings.Menu.Preview.peerName
        let incoming = MTStrings.Menu.Preview.incomingText
        return MTMiniChatContent(header: header, messages: [
            MTPreviewMessage(id: 1, isOutgoing: false, text: incoming, ageSeconds: 180),
            MTPreviewMessage(id: 2, isOutgoing: true, text: MTStrings.Menu.Preview.outgoingText, reply: MTPreviewReply(author: peerName, text: incoming), ageSeconds: 120)
        ])
    }

    /// A conversation long enough to fill a whole chat screen (`MTFullChatPreviewNode`), localized.
    /// Its ids (101…) differ from the mini chat's: the status marks are stored by message id.
    public static func fullSample(header: MTMiniChatHeader? = nil) -> MTMiniChatContent {
        let peerName = MTStrings.Menu.Preview.peerName
        let incoming = MTStrings.Menu.Preview.incomingText
        return MTMiniChatContent(header: header, messages: [
            MTPreviewMessage(id: 101, isOutgoing: false, text: MTStrings.Menu.Preview.fullChat1, ageSeconds: 7200),
            MTPreviewMessage(id: 102, isOutgoing: true, text: MTStrings.Menu.Preview.fullChat2, ageSeconds: 7140),
            MTPreviewMessage(id: 103, isOutgoing: false, text: MTStrings.Menu.Preview.fullChat3, ageSeconds: 7080),
            MTPreviewMessage(id: 104, isOutgoing: true, text: MTStrings.Menu.Preview.fullChat4, ageSeconds: 7020),
            MTPreviewMessage(id: 105, isOutgoing: false, text: incoming, ageSeconds: 900),
            MTPreviewMessage(id: 106, isOutgoing: true, text: MTStrings.Menu.Preview.outgoingText, reply: MTPreviewReply(author: peerName, text: incoming), ageSeconds: 840),
            MTPreviewMessage(id: 107, isOutgoing: false, text: MTStrings.Menu.Preview.chatListText1, ageSeconds: 300),
            MTPreviewMessage(id: 108, isOutgoing: true, text: MTStrings.Menu.Preview.pendingText, isUnread: true, ageSeconds: 60)
        ])
    }

    /// Header with the demo peer «online».
    public static func sampleHeader() -> MTMiniChatHeader {
        return MTMiniChatHeader(peer: .demo(name: MTStrings.Menu.Preview.peerName), status: MTStrings.Menu.Preview.statusOnline, statusIsAccent: true)
    }
}

public struct MTMiniChatConfiguration {
    /// Modifiers see it as `context.previewScope` and decide whether they apply.
    public let scope: String
    /// Constant height of the block; bubbles rest on its bottom edge.
    public let height: CGFloat
    /// Base content, localized at display time. Modifiers run on top of it.
    public let content: (MTMenuContext) -> MTMiniChatContent
    /// The theme the bubbles are drawn with, instead of the app's: e.g. one built from the values
    /// a slider of this screen is being dragged to (`context.draftValue(forKey:)`), so the bubbles
    /// follow the finger while the setting itself is written only on release. Called inside
    /// `draftScope`, on the main thread, on every rebuild of the screen.
    public let presentationData: ((MTMenuContext) -> PresentationData)?
    /// Wraps everything the preview computes for the bubbles (the theme above, the message items
    /// and their layout — main thread, synchronously): a feature sets its own draft state for the
    /// duration of `body` (layout hooks reading the feature's settings then see the dragged value)
    /// and must restore it before returning. Never write settings here.
    public let draftScope: ((MTMenuContext, () -> Void) -> Void)?
    /// Layers of the chat screen drawn by features (animated background, snow, edge bands): made
    /// once per preview node, updated on every rebuild of the screen and every layout.
    public let overlays: ((MTMenuContext) -> [MTMiniChatOverlay])?

    public init(scope: String, height: CGFloat = 196.0, content: @escaping (MTMenuContext) -> MTMiniChatContent, presentationData: ((MTMenuContext) -> PresentationData)? = nil, draftScope: ((MTMenuContext, () -> Void) -> Void)? = nil, overlays: ((MTMenuContext) -> [MTMiniChatOverlay])? = nil) {
        self.scope = scope
        self.height = height
        self.content = content
        self.presentationData = presentationData
        self.draftScope = draftScope
        self.overlays = overlays
    }

    /// A preview that follows drafts and overlays is rebuilt on every rebuild of its screen.
    var isLive: Bool {
        return self.presentationData != nil || self.draftScope != nil || self.overlays != nil
    }
}

/// Where an overlay of the mini chat sits.
public enum MTMiniChatOverlayPlacement {
    /// Above the wallpaper, under the bubbles (animated background, snow).
    case belowMessages
    /// Above the bubbles, under the chat's top bar (edge blur and gradient).
    case aboveMessages
}

/// A layer of the chat screen shown in the mini chat (`MTMiniChatConfiguration.overlays`).
public protocol MTMiniChatOverlay: AnyObject {
    var view: UIView { get }
    var placement: MTMiniChatOverlayPlacement { get }
    /// Main thread. `size` — the visible block; `insets.top` — the height of the top bar of the
    /// preview (0 without a header). Read drafts through `context.draftValue(forKey:)`.
    func update(context: MTMenuContext, size: CGSize, insets: UIEdgeInsets)
}

// MARK: - Mini chat list

public struct MTPreviewChatListRow: Equatable {
    public enum Kind: Equatable {
        case user
        case group
        case channel
    }

    public var id: Int64
    public var kind: Kind
    public var title: String
    public var text: String
    /// Author shown before the text in groups.
    public var authorName: String?
    public var isOutgoing: Bool
    public var ageSeconds: Int32
    public var isPinned: Bool
    public var isOnline: Bool
    public var isTyping: Bool
    public var unreadCount: Int32

    public init(id: Int64, kind: Kind, title: String, text: String, authorName: String? = nil, isOutgoing: Bool = false, ageSeconds: Int32 = 600, isPinned: Bool = false, isOnline: Bool = false, isTyping: Bool = false, unreadCount: Int32 = 0) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.authorName = authorName
        self.isOutgoing = isOutgoing
        self.ageSeconds = ageSeconds
        self.isPinned = isPinned
        self.isOnline = isOnline
        self.isTyping = isTyping
        self.unreadCount = unreadCount
    }
}

extension MTPreviewChatListRow {
    /// Three rows: a pinned person online, a group with unread messages, a channel. Localized.
    public static func samples() -> [MTPreviewChatListRow] {
        return [
            MTPreviewChatListRow(id: 1, kind: .user, title: MTStrings.Menu.Preview.peerName, text: MTStrings.Menu.Preview.chatListText1, ageSeconds: 300, isPinned: true, isOnline: true),
            MTPreviewChatListRow(id: 2, kind: .group, title: MTStrings.Menu.Preview.chatListName2, text: MTStrings.Menu.Preview.chatListText2, authorName: MTStrings.Menu.Preview.chatListAuthor2, ageSeconds: 900, unreadCount: 3),
            MTPreviewChatListRow(id: 3, kind: .channel, title: MTStrings.Menu.Preview.chatListName3, text: MTStrings.Menu.Preview.chatListText3, ageSeconds: 3600)
        ]
    }
}

public struct MTMiniChatListConfiguration {
    public let scope: String
    /// Constant height of the block; rows are laid out from the top and clipped.
    public let height: CGFloat
    public let rows: (MTMenuContext) -> [MTPreviewChatListRow]

    public init(scope: String, height: CGFloat = 228.0, rows: @escaping (MTMenuContext) -> [MTPreviewChatListRow]) {
        self.scope = scope
        self.height = height
        self.rows = rows
    }
}

// MARK: - Modifiers

public enum MTPreviewModifiers {
    /// A feature changes the demo messages of every mini chat (deleted transparency, «edited»,
    /// translation…). Check `context.previewScope` to limit it to some previews.
    public static func registerChatModifier(id: String, order: Int, _ modify: @escaping (inout [MTPreviewMessage], MTMenuContext) -> Void) {
        MTMenuStorage.shared.addChatModifier(MTMenuStorage.ChatModifier(id: id, order: order, modify: modify))
    }

    public static func registerChatListModifier(id: String, order: Int, _ modify: @escaping (inout [MTPreviewChatListRow], MTMenuContext) -> Void) {
        MTMenuStorage.shared.addChatListModifier(MTMenuStorage.ChatListModifier(id: id, order: order, modify: modify))
    }

    static func applyChat(_ messages: [MTPreviewMessage], context: MTMenuContext) -> [MTPreviewMessage] {
        var result = messages
        for modifier in MTMenuStorage.shared.chatModifiers {
            modifier.modify(&result, context)
        }
        return result
    }

    static func applyChatList(_ rows: [MTPreviewChatListRow], context: MTMenuContext) -> [MTPreviewChatListRow] {
        var result = rows
        for modifier in MTMenuStorage.shared.chatListModifiers {
            modifier.modify(&result, context)
        }
        return result
    }
}
