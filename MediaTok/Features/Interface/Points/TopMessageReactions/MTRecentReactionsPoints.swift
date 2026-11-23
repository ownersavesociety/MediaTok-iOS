// Compiled into TopMessageReactions (filegroup //MediaTok/Features/Interface:TopMessageReactionsPointSources).
// Owner: MediaTok («Свои недавние реакции»).

import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import MTCore

public enum MTRecentReactionsHooks {
    /// Transformer of the "top" reactions a message's reaction panel starts with (Telegram's
    /// cloud list). Called once per panel: return signals, keep resolved files cached.
    public static let topReactions = MTHookPoint<(Signal<[RecentReactionItem], NoError>, AccountContext, EngineRawMessage) -> Signal<[RecentReactionItem], NoError>>("reactions.top")
}

func mtTopReactions(_ signal: Signal<[RecentReactionItem], NoError>, context: AccountContext, message: EngineRawMessage) -> Signal<[RecentReactionItem], NoError> {
    if MTRecentReactionsHooks.topReactions.isEmpty {
        return signal
    }
    var result = signal
    for handler in MTRecentReactionsHooks.topReactions.handlers {
        result = handler(result, context, message)
    }
    return result
}
