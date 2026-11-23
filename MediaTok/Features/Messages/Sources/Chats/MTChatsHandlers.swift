import Foundation
import TelegramCore
import MTCore
import MTFeaturesShared

/// The «Чаты» section. Most of it is read directly by upstream forks through `MTMessagesPolicy`
/// (greeting sticker, channel button, pull to the next channel / topic, «Send as»); here are the
/// parts that go through hook points. «Безлимитные закрепы» — `MTPinnedChats`.
enum MTChatsHandlers {
    /// «История поиска без лимита» keeps up to this many recent chats (upstream: 20). Every entry is
    /// observed when the search opens, so the list is long but never unbounded.
    static let recentSearchCeiling = 200

    static func register() {
        MTLimitHooks.recentSearchLimit.register({ limit in
            if MTMessagesSettings.unlimitedSearchHistory.value {
                return max(limit, MTChatsHandlers.recentSearchCeiling)
            }
            return nil
        })
    }
}
