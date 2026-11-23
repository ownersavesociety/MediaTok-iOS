// Compiled into IntentsExtensionLib (filegroup //MediaTok/MTHooks:SiriIntentsHookSources).
// Messages Siri may read aloud (announce, «read my messages»): protected chats are left out
// (MTContentPrivacyHooks.hidesContent, handler in MTFeaturesShared — MediaTok chat lock).

import Foundation
import Intents
import SwiftSignalKit
import Postbox
import TelegramCore

/// MediaTok hook target: `INSearchForMessagesIntent` handling, the messages before they are handed to
/// Siri. `INMessage.conversationIdentifier` is the chat's `PeerId.toInt64()` (IntentMessages.swift).
func mtSiriHidingProtectedMessages(_ messages: Signal<[INMessage], NoError>, accountId: AccountRecordId) -> Signal<[INMessage], NoError> {
    if MTContentPrivacyHooks.hidesContent.isEmpty {
        return messages
    }
    return messages
    |> map { messages -> [INMessage] in
        return messages.filter { message in
            guard let conversationIdentifier = message.conversationIdentifier, let rawValue = Int64(conversationIdentifier) else {
                return true
            }
            return !MTContentPrivacyHooks.hidesContent(accountId: accountId, peerId: PeerId(rawValue))
        }
    }
}
