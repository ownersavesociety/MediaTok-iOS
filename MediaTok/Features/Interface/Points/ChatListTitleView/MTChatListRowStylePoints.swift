// Compiled into ChatListTitleView (see MTChatListTitlePoints.swift). Owner: MediaTok.
// The look of chat list rows as ONE snapshot: `ChatListPresentationData` takes it once when it is
// created (`mtRowStyle`), `ChatListItem` reads the fields from there — no setting is read per cell
// and no cell observes anything. A change of the style publishes a new theme instance
// (`MTThemeHooks`), which recreates `ChatListPresentationData` and re-lays the rows out.
//
// Also here: the folder strip and the header of the chat list (ChatListControllerNode,
// ChatListNavigationBar, ChatListController call these; they all depend on this module).

import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import MTCore

public struct MTChatListRowStyle: Equatable {
    /// Avatar diameter multiplier (1 = Telegram).
    public var avatarScale: CGFloat
    /// Row height multiplier (1 = Telegram).
    public var heightScale: CGFloat
    /// Lines of preview text when the row has no author line (Telegram: 2); with an author line
    /// one line less, never fewer than one.
    public var previewLines: Int
    /// No story rings around the avatars of the rows.
    public var hidesStoryRing: Bool
    /// No emoji status / premium star after the names.
    public var hidesEmojiStatus: Bool
    /// Diameter of the sender's avatar before the author line in groups (0 = none).
    public var senderAvatarSize: CGFloat

    public init(avatarScale: CGFloat, heightScale: CGFloat, previewLines: Int, hidesStoryRing: Bool, hidesEmojiStatus: Bool, senderAvatarSize: CGFloat) {
        self.avatarScale = avatarScale
        self.heightScale = heightScale
        self.previewLines = previewLines
        self.hidesStoryRing = hidesStoryRing
        self.hidesEmojiStatus = hidesEmojiStatus
        self.senderAvatarSize = senderAvatarSize
    }

    public static let upstream = MTChatListRowStyle(avatarScale: 1.0, heightScale: 1.0, previewLines: 2, hidesStoryRing: false, hidesEmojiStatus: false, senderAvatarSize: 0.0)

    /// Max lines of the preview text: `upstream` is what ChatListItem computed (2 or 1).
    public func previewLineLimit(upstream: Int) -> Int {
        if self.previewLines == 2 {
            return upstream
        }
        return upstream >= 2 ? self.previewLines : max(1, self.previewLines - 1)
    }

    /// Extra row height for the chosen number of preview lines, given one text line's height.
    public func previewLinesHeightDelta(lineHeight: CGFloat) -> CGFloat {
        return CGFloat(self.previewLines - 2) * lineHeight
    }
}

public enum MTChatListStyleHooks {
    /// Provider of the row style (first registered wins). Asked once per ChatListPresentationData.
    public static let rowStyle = MTHookPoint<() -> MTChatListRowStyle>("chatList.rowStyle")

    /// Policy: the folder strip of the root chat list (compact tabs, «Все чаты» title, extra
    /// height, strip at the bottom). Asked when the strip is laid out: answer from a snapshot.
    public static let folderStrip = MTHookPoint<(AccountContext) -> MTChatListFolderStrip?>("chatList.folderStrip")

    /// Policy (any `true`): no search field above the chat list.
    public static let hidesSearchField = MTHookPoint<(AccountContext) -> Bool>("chatList.hidesSearchField")
}

public struct MTChatListFolderStrip: Equatable {
    /// «Все» / «Все чаты»; nil = Telegram's («Все»).
    public var allChatsTitle: String?
    /// Halved spacing between the tabs.
    public var compactTabs: Bool
    /// Extra height of the strip, pt.
    public var heightOffset: CGFloat
    /// «Папки внизу»: the strip sits above the tab bar instead of in the header
    /// (ChatListControllerNode → MTChatListBottomFolderStrip, MTHooks/ChatListUI).
    public var atBottom: Bool

    public init(allChatsTitle: String?, compactTabs: Bool, heightOffset: CGFloat, atBottom: Bool) {
        self.allChatsTitle = allChatsTitle
        self.compactTabs = compactTabs
        self.heightOffset = heightOffset
        self.atBottom = atBottom
    }

    public static let upstream = MTChatListFolderStrip(allChatsTitle: nil, compactTabs: false, heightOffset: 0.0, atBottom: false)
}

/// The row style, evaluated once for a new ChatListPresentationData.
public func mtChatListRowStyle() -> MTChatListRowStyle {
    if MTChatListStyleHooks.rowStyle.isEmpty {
        return .upstream
    }
    return MTChatListStyleHooks.rowStyle.handlers[0]()
}

public func mtChatListFolderStrip(context: AccountContext) -> MTChatListFolderStrip {
    for handler in MTChatListStyleHooks.folderStrip.handlers {
        if let value = handler(context) {
            return value
        }
    }
    return .upstream
}

public func mtChatListHidesSearchField(context: AccountContext) -> Bool {
    for handler in MTChatListStyleHooks.hidesSearchField.handlers {
        if handler(context) {
            return true
        }
    }
    return false
}

/// What a row decoration needs after the row was laid out (main thread).
public struct MTChatListRowDecoration {
    public let context: AccountContext
    /// The row's content container (ChatListItemNode.mainContentContainerNode, which the author and
    /// text frames are relative to); decorations are its subnodes, created once per row.
    public let node: ASDisplayNode
    public let style: MTChatListRowStyle
    /// The author of the shown message in groups, nil otherwise.
    public let author: EnginePeer?
    /// Frame of the author line in the row (in a forum: where «Author: text» begins), nil when the
    /// row has none.
    public let authorFrame: CGRect?
    public let theme: PresentationTheme

    public init(context: AccountContext, node: ASDisplayNode, style: MTChatListRowStyle, author: EnginePeer?, authorFrame: CGRect?, theme: PresentationTheme) {
        self.context = context
        self.node = node
        self.style = style
        self.author = author
        self.authorFrame = authorFrame
        self.theme = theme
    }
}

extension MTChatListStyleHooks {
    /// Observer after a row's apply (sender avatars before the author line).
    public static let decorateRow = MTHookPoint<(MTChatListRowDecoration) -> Void>("chatList.decorateRow")
}

public func mtChatListDecorateRow(_ decoration: @autoclosure () -> MTChatListRowDecoration) {
    if MTChatListStyleHooks.decorateRow.isEmpty {
        return
    }
    let value = decoration()
    for handler in MTChatListStyleHooks.decorateRow.handlers {
        handler(value)
    }
}
