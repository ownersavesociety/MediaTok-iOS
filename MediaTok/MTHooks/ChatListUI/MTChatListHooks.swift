// Compiled into ChatListUI (filegroup //MediaTok/MTHooks:ChatListUIHookSources). Chat list
// points live here because their types are ChatListUI's own (ChatListItemNode, the header's
// NavigationBarComponent buttons); features import ChatListUI to register.

import Foundation
import UIKit
import SwiftSignalKit
import AsyncDisplayKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatListHeaderComponent
import NavigationBarComponent
import ChatListFilterTabContainerNode
import ItemListUI
import MTCore
import MTHooks

public struct MTChatListRowContext {
    public let context: AccountContext
    public let peer: EnginePeer?
    public let messages: [EngineMessage]
    public let theme: PresentationTheme
    /// The «Archived Chats» row: `peer` and `messages` are the archived chat and message it shows.
    /// Asked by the preview points only (`previewText`, `hidesLastMessageAuthor`, `hidesMediaPreview`).
    public var isArchive: Bool = false
}

public struct MTChatListRowLayout {
    public let context: AccountContext
    public let peer: EnginePeer?
    /// The row node (ChatListItemNode). Add feature subviews to it; they are laid out here.
    public let node: ASDisplayNode
    public let titleFrame: CGRect
    public let avatarFrame: CGRect
}

public struct MTChatListHeaderContext {
    public let context: AccountContext
    public let location: ChatListControllerLocation
}

public enum MTChatListHooks {
    /// Policy: the preview text of a row (chat lock hides it, download status replaces it).
    /// First non-nil wins. Layout path, possibly off the main thread: snapshot reads only.
    public static let previewText = MTHookPoint<(MTChatListRowContext) -> NSAttributedString?>("chatList.previewText")

    /// Observer after a row's layout is applied (main thread): badge after the title, avatar shape.
    public static let rowDidLayout = MTHookPoint<(MTChatListRowLayout) -> Void>("chatList.rowDidLayout")

    /// Provider (summed over handlers): room a feature's mark takes after the title and its icons
    /// (width + spacing, pt; 0 = none). The title is laid out that much narrower, so a long name is
    /// cut before the mark instead of the mark being dropped. Layout path, possibly off the main
    /// thread: answer from memory.
    public static let titleAccessoryWidth = MTHookPoint<(MTChatListRowContext) -> CGFloat>("chatList.titleAccessoryWidth")

    /// Transformer of the header's right buttons (account switcher, «read all», Android-style actions).
    public static let headerRightButtons = MTHookPoint<([NavigationBarComponent.Button], MTChatListHeaderContext) -> [NavigationBarComponent.Button]>("chatList.headerRightButtons")

    /// Transformer of a row's swipe actions (hide «Delete», all of them…). Asked for the right
    /// actions and for the left ones (pin, read) separately.
    public static let revealOptions = MTHookPoint<([ItemListRevealOption], MTChatListRowContext) -> [ItemListRevealOption]>("chatList.revealOptions")

    /// Policy (any `true`): the author line of a group row is hidden together with its preview
    /// (messages of blocked users). Layout path: answer from snapshots.
    public static let hidesLastMessageAuthor = MTHookPoint<(MTChatListRowContext) -> Bool>("chatList.hidesLastMessageAuthor")

    /// Policy (any `true`): the promoted chat of the proxy sponsor (or a PSA chat) is left out of
    /// the list. `isProxy` = the promotion comes from the MTProxy sponsor.
    public static let hidesPromoChat = MTHookPoint<(AccountContext, Bool) -> Bool>("chatList.hidesPromoChat")

    /// Transformer of the folder tabs shown above the list (hide «All chats», reorder). The list's
    /// own filters are not changed: a hidden tab only disappears from the tab strip.
    public static let filterTabs = MTHookPoint<([ChatListFilterTabEntry], AccountContext) -> [ChatListFilterTabEntry]>("chatList.filterTabs")

    /// Providers of a signal that emits whenever a `filterTabs` handler would answer differently (its
    /// setting changed): the tabs are rebuilt then, not only when the folders or their counters do.
    /// The signal should emit its current state first.
    public static let filterTabsChanges = MTHookPoint<(AccountContext) -> Signal<Void, NoError>>("chatList.filterTabsChanges")

    /// Transformer of the account's folders as every list the user sees shows them
    /// (`chatListFilterItems`: the tabs above the list, their pages — so no swipe leads into a
    /// removed folder —, the folder tabs of the forward picker; «Add to folder», the «Chats» tab's
    /// folder menu, Settings › Chat Folders, the folder tags of chat rows; MediaTok's folder lists
    /// call `mtChatListFolders` too). Combine with your own state signal: the lists are rebuilt
    /// whenever it emits (a secret folder unlocked or locked again).
    public static let folders = MTHookPoint<(Signal<[ChatListFilter], NoError>, AccountContext) -> Signal<[ChatListFilter], NoError>>("chatList.folders")

    /// Policy (any `true`): a row shows no media thumbnails and no message-type icon (a locked chat;
    /// its text is replaced through `previewText`). Layout path, possibly off the main thread:
    /// answer from snapshots.
    public static let hidesMediaPreview = MTHookPoint<(MTChatListRowContext) -> Bool>("chatList.hidesMediaPreview")

    /// Policy (any `true`): a found message is left out of the chat list search (every tab of it —
    /// chats, media, links, files, music, voice). Called for every found message: answer from memory.
    public static let hidesSearchMessages = MTHookPoint<(AccountContext, EngineMessage) -> Bool>("chatList.hidesSearchMessages")

    /// Transformer of the stories strip's source (hide stories: map to empty subscriptions;
    /// combine with your setting's signal to apply live).
    public static let storySubscriptions = MTHookPoint<(Signal<EngineStorySubscriptions, NoError>, AccountContext) -> Signal<EngineStorySubscriptions, NoError>>("chatList.storySubscriptions")

    /// Provider (all handlers merged): chats whose rows a feature decorates in place of the preview
    /// (download status). Their rows re-lay out when the set changes; the set must change rarely
    /// (a download starts or ends), never on a progress tick — progress is drawn by the feature's own
    /// view (`rowDidLayout`). Subscribed once per root chat list (`.chatList` location).
    public static let accessoryPeers = MTHookPoint<(AccountContext) -> Signal<Set<EnginePeer.Id>, NoError>>("chatList.accessoryPeers")
}

// MARK: - Call-site helpers (ChatListUI internal)

/// The context the preview points see: a chat row, or the «Archived Chats» row with the archived chat
/// and message it previews (a locked chat must not show through there either).
private func mtChatListPreviewRowContext(item: ChatListItem) -> MTChatListRowContext? {
    switch item.content {
    case let .peer(peerData):
        return MTChatListRowContext(context: item.context, peer: peerData.peer.peer, messages: peerData.messages, theme: item.presentationData.theme)
    case let .groupReference(groupData):
        guard let message = groupData.message, let first = groupData.peers.first else {
            return nil
        }
        return MTChatListRowContext(context: item.context, peer: first.peer.peer, messages: [message], theme: item.presentationData.theme, isArchive: true)
    case .loading:
        return nil
    }
}

func mtChatListPreviewText(item: ChatListItem) -> NSAttributedString? {
    if MTChatListHooks.previewText.isEmpty {
        return nil
    }
    guard let rowContext = mtChatListPreviewRowContext(item: item) else {
        return nil
    }
    for handler in MTChatListHooks.previewText.handlers {
        if let value = handler(rowContext) {
            return value
        }
    }
    return nil
}

/// MediaTok hook target: `ChatListItem.asyncLayout` — the width the title may take (`titleRectWidth`),
/// less the room features reserve after it. Without handlers: `width` unchanged.
func mtChatListTitleRectWidth(_ width: CGFloat, item: ChatListItem) -> CGFloat {
    if MTChatListHooks.titleAccessoryWidth.isEmpty {
        return width
    }
    guard case let .peer(peerData) = item.content else {
        return width
    }
    let rowContext = MTChatListRowContext(context: item.context, peer: peerData.peer.peer, messages: peerData.messages, theme: item.presentationData.theme)
    var reserved: CGFloat = 0.0
    for handler in MTChatListHooks.titleAccessoryWidth.handlers {
        reserved += max(0.0, handler(rowContext))
    }
    if reserved <= 0.0 {
        return width
    }
    return max(10.0, width - reserved)
}

func mtChatListRowDidLayout(_ node: ChatListItemNode, item: ChatListItem, avatarFrame: CGRect) {
    if MTChatListHooks.rowDidLayout.isEmpty {
        return
    }
    var peer: EnginePeer?
    if case let .peer(peerData) = item.content {
        peer = peerData.peer.peer
    }
    let layout = MTChatListRowLayout(context: item.context, peer: peer, node: node, titleFrame: node.titleNode.frame, avatarFrame: avatarFrame)
    for handler in MTChatListHooks.rowDidLayout.handlers {
        handler(layout)
    }
}

func mtChatListHeaderRightButtons(_ buttons: [NavigationBarComponent.Button], context: AccountContext, location: ChatListControllerLocation) -> [NavigationBarComponent.Button] {
    if MTChatListHooks.headerRightButtons.isEmpty {
        return buttons
    }
    var result = buttons
    let headerContext = MTChatListHeaderContext(context: context, location: location)
    for handler in MTChatListHooks.headerRightButtons.handlers {
        result = handler(result, headerContext)
    }
    return result
}


func mtChatListStorySubscriptions(_ signal: Signal<EngineStorySubscriptions, NoError>, context: AccountContext) -> Signal<EngineStorySubscriptions, NoError> {
    if MTChatListHooks.storySubscriptions.isEmpty {
        return signal
    }
    var result = signal
    for handler in MTChatListHooks.storySubscriptions.handlers {
        result = handler(result, context)
    }
    return result
}

func mtChatListHidesLastMessageAuthor(item: ChatListItem) -> Bool {
    if MTChatListHooks.hidesLastMessageAuthor.isEmpty {
        return false
    }
    guard let rowContext = mtChatListPreviewRowContext(item: item) else {
        return false
    }
    for handler in MTChatListHooks.hidesLastMessageAuthor.handlers {
        if handler(rowContext) {
            return true
        }
    }
    return false
}

/// Spoilers of a row's preview (text and media thumbnail) shown uncovered: the message decoration
/// of the shown message (`MTMessageDecoration.revealsSpoilers`, anti-spoiler).
func mtChatListRevealsSpoilers(_ message: EngineMessage, context: AccountContext) -> Bool {
    if !MTMessageDecorationHooks.isActive {
        return false
    }
    return MTMessageDecorationHooks.decoration(for: message._asMessage(), context: context).revealsSpoilers
}

/// For ChatListNode (owner MediaTok): the merged set of decorated chats, nil when nobody decorates rows
/// (the node then subscribes to nothing and its state stays upstream's).
func mtChatListAccessoryPeers(context: AccountContext) -> Signal<Set<EnginePeer.Id>, NoError>? {
    if MTChatListHooks.accessoryPeers.isEmpty {
        return nil
    }
    let signals = MTChatListHooks.accessoryPeers.handlers.map { $0(context) }
    return combineLatest(signals)
    |> map { sets -> Set<EnginePeer.Id> in
        var result = Set<EnginePeer.Id>()
        for set in sets {
            result.formUnion(set)
        }
        return result
    }
    |> distinctUntilChanged
}

/// For ChatListNodeEntries (owner MediaTok): the promoted chat is left out of the list.
func mtChatListHidesPromoChat(context: AccountContext, isProxy: Bool) -> Bool {
    for handler in MTChatListHooks.hidesPromoChat.handlers {
        if handler(context, isProxy) {
            return true
        }
    }
    return false
}

func mtChatListRevealOptions(_ options: [ItemListRevealOption], item: ChatListItem) -> [ItemListRevealOption] {
    if MTChatListHooks.revealOptions.isEmpty {
        return options
    }
    guard case let .peer(peerData) = item.content else {
        return options
    }
    let rowContext = MTChatListRowContext(context: item.context, peer: peerData.peer.peer, messages: peerData.messages, theme: item.presentationData.theme)
    var result = options
    for handler in MTChatListHooks.revealOptions.handlers {
        result = handler(result, rowContext)
    }
    return result
}

func mtChatListFilterTabs(_ entries: [ChatListFilterTabEntry], context: AccountContext) -> [ChatListFilterTabEntry] {
    if MTChatListHooks.filterTabs.isEmpty {
        return entries
    }
    var result = entries
    for handler in MTChatListHooks.filterTabs.handlers {
        result = handler(result, context)
    }
    return result
}

/// MediaTok hook target: the folder items `reloadFilters` builds the tabs from — re-emitted whenever a
/// `filterTabsChanges` signal does. Without handlers: `signal` unchanged.
func mtChatListFilterItemsWithTabChanges<T>(_ signal: Signal<T, NoError>, context: AccountContext) -> Signal<T, NoError> {
    if MTChatListHooks.filterTabsChanges.isEmpty {
        return signal
    }
    let changes = combineLatest(MTChatListHooks.filterTabsChanges.handlers.map { $0(context) })
    return combineLatest(signal, changes)
    |> map { value, _ -> T in
        return value
    }
}

// The tab the list opens on is chosen from the unfiltered folders (upstream falls back to
// «All chats»), so when a handler hid it the first tab that is still shown is taken instead.
func mtChatListSelectedFilterTab(_ selected: ChatListFilterTabEntryId, tabs: [ChatListFilterTabEntry]) -> ChatListFilterTabEntryId {
    if MTChatListHooks.filterTabs.isEmpty {
        return selected
    }
    if tabs.isEmpty || tabs.contains(where: { $0.id == selected }) {
        return selected
    }
    return tabs[0].id
}

/// MediaTok hook target: every list of folders the user sees — `chatListFilterItems(context:)` (tabs,
/// their pages, the forward picker), «Add to folder», the «Chats» tab's folder menu, Settings › Chat
/// Folders, the folder tags of chat rows, and the folder lists of MediaTok's own screens. Code that
/// needs the real folders (a feature's own membership, exceptions by folder id) reads the engine.
/// Without handlers: `signal` unchanged.
public func mtChatListFolders(_ signal: Signal<[ChatListFilter], NoError>, context: AccountContext) -> Signal<[ChatListFilter], NoError> {
    if MTChatListHooks.folders.isEmpty {
        return signal
    }
    var result = signal
    for handler in MTChatListHooks.folders.handlers {
        result = handler(result, context)
    }
    return result
}

/// MediaTok hook target: `ChatListItem.asyncLayout`, after the media thumbnails of the preview are chosen.
func mtChatListHidesMediaPreview(item: ChatListItem) -> Bool {
    if MTChatListHooks.hidesMediaPreview.isEmpty {
        return false
    }
    guard let rowContext = mtChatListPreviewRowContext(item: item) else {
        return false
    }
    for handler in MTChatListHooks.hidesMediaPreview.handlers {
        if handler(rowContext) {
            return true
        }
    }
    return false
}

/// MediaTok hook target: the found messages of the chat list search, one by one.
func mtChatListHidesSearchMessage(_ message: EngineMessage, context: AccountContext) -> Bool {
    if MTChatListHooks.hidesSearchMessages.isEmpty {
        return false
    }
    for handler in MTChatListHooks.hidesSearchMessages.handlers {
        if handler(context, message) {
            return true
        }
    }
    return false
}
