// Compiled into ChatListTitleView (filegroup //MediaTok/Features/Interface:ChatListTitleViewPointSources).
// Owner: MediaTok. The lowest module of the chat list chrome MediaTok owns, so the points here serve the
// title (connection text), the header component and the chat list search
// (ChatListUI, ChatListHeaderComponent and StoryPeerListComponent all depend on this module).

import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import MTCore

/// How the chat list title looks. `.upstream` = Telegram's.
public struct MTChatListTitleStyle: Equatable {
    /// While connecting / updating only the spinner is shown, no «Соединение…» text.
    public var hidesConnectionText: Bool

    public init(hidesConnectionText: Bool) {
        self.hidesConnectionText = hidesConnectionText
    }

    public static let upstream = MTChatListTitleStyle(hidesConnectionText: false)
}

public enum MTChatListTitleHooks {
    /// Provider of the title style (first registered wins). Main thread, on title updates and layout.
    public static let style = MTHookPoint<() -> MTChatListTitleStyle>("chatListTitle.style")
}

public func mtChatListTitleStyle() -> MTChatListTitleStyle {
    if MTChatListTitleHooks.style.isEmpty {
        return .upstream
    }
    return MTChatListTitleHooks.style.handlers[0]()
}

/// The text the title shows for a network status.
public func mtChatListTitleText(_ title: NetworkStatusTitle) -> String {
    if MTChatListTitleHooks.style.isEmpty {
        return title.text
    }
    if title.activity && mtChatListTitleStyle().hidesConnectionText {
        return ""
    }
    return title.text
}

public enum MTChatListSearchHooks {
    /// Transformer of the local peers the chat list search shows for a query (search by numeric
    /// id). Called once per query, off the main thread is fine: return signals, do not block.
    public static let localPeers = MTHookPoint<(Signal<[EngineRenderedPeer], NoError>, String, AccountContext) -> Signal<[EngineRenderedPeer], NoError>>("chatListSearch.localPeers")
}

/// Call site helper for ChatListSearchListPaneNode.
public func mtChatListSearchLocalPeers(_ signal: Signal<[EngineRenderedPeer], NoError>, query: String, context: AccountContext) -> Signal<[EngineRenderedPeer], NoError> {
    if MTChatListSearchHooks.localPeers.isEmpty {
        return signal
    }
    var result = signal
    for handler in MTChatListSearchHooks.localPeers.handlers {
        result = handler(result, query, context)
    }
    return result
}
