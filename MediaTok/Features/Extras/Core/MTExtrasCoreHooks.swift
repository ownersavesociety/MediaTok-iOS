// Compiled into TelegramCore (filegroup //MediaTok/Features/Extras:TelegramCoreSources).
// Points of the Swiftgram-parity features that TelegramCore itself calls. Handlers are
// registered by `MTExtrasShared.register()` (MTFeaturesShared), which reads the settings.
// An empty point = upstream.

import Foundation
import Postbox
import SwiftSignalKit
import MTCore

public enum MTExtrasCoreHooks {
    /// Policy (any `true`): an in-chat text search the server answered with nothing looks for the
    /// query inside the words of the messages already on this device.
    public static let searchesPartialWords = MTHookPoint<() -> Bool>("extras.searchesPartialWords")

    /// Transformer of the text a restricted chat or message shows: `(text, reason, platform)`.
    public static let restrictionText = MTHookPoint<(String, String, String) -> String>("extras.restrictionText")
}

/// MediaTok hook target: `PeerUtils.restrictionText` and `RestrictedContentMessageAttribute.platformText`.
public func mtExtrasRestrictionText(_ text: String, reason: String, platform: String) -> String {
    if MTExtrasCoreHooks.restrictionText.isEmpty {
        return text
    }
    var result = text
    for handler in MTExtrasCoreHooks.restrictionText.handlers {
        result = handler(result, reason, platform)
    }
    return result
}

/// How many of the latest messages of a chat the on-device fallback looks through.
private let mtExtrasSearchScanLimit = 1500
/// How many results it returns at most.
private let mtExtrasSearchResultLimit = 100

private func mtExtrasSearchesPartialWords() -> Bool {
    if MTExtrasCoreHooks.searchesPartialWords.isEmpty {
        return false
    }
    for handler in MTExtrasCoreHooks.searchesPartialWords.handlers where handler() {
        return true
    }
    return false
}

/// MediaTok hook target: `TelegramEngine.Messages.searchMessages`. The upstream signal unchanged while
/// nobody asks for the fallback, and for every page after the first.
func mtExtrasWrapSearch(_ signal: Signal<(SearchMessagesResult, SearchMessagesState), NoError>, account: Account, location: SearchMessagesLocation, query: String, state: SearchMessagesState?) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> {
    if MTExtrasCoreHooks.searchesPartialWords.isEmpty || state != nil {
        return signal
    }
    return signal
    |> mapToSignal { result -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> in
        return mtExtrasSearchFallback(account: account, location: location, query: query, state: state, result: result)
    }
}

/// When the first page of an in-chat
/// text search is empty, the latest messages on this device are searched for the query as a part of
/// a word (case and diacritics ignored). The server's state is kept: the result is complete.
func mtExtrasSearchFallback(account: Account, location: SearchMessagesLocation, query: String, state: SearchMessagesState?, result: (SearchMessagesResult, SearchMessagesState)) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> {
    if state != nil || !result.0.messages.isEmpty || !mtExtrasSearchesPartialWords() {
        return .single(result)
    }
    guard case let .peer(peerId, fromId, tags, reactions, threadId, minDate, maxDate) = location else {
        return .single(result)
    }
    if fromId != nil || tags != nil || reactions != nil {
        return .single(result)
    }
    if (minDate ?? 0) != 0 || (maxDate ?? 0) != 0 {
        return .single(result)
    }
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedQuery.isEmpty {
        return .single(result)
    }
    return account.postbox.transaction { transaction -> (SearchMessagesResult, SearchMessagesState) in
        let view = transaction.getMessagesHistoryViewState(input: .single(peerId: peerId, threadId: threadId), ignoreMessagesInTimestampRange: nil, ignoreMessageIds: Set(), count: mtExtrasSearchScanLimit, clipHoles: false, anchor: .upperBound, namespaces: .just(Set([Namespaces.Message.Cloud])))
        var messages: [Message] = []
        for entry in view.entries.reversed() {
            let message = entry.message
            if message.text.isEmpty {
                continue
            }
            if message.text.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                continue
            }
            messages.append(message)
            if messages.count >= mtExtrasSearchResultLimit {
                break
            }
        }
        if messages.isEmpty {
            return result
        }
        var readStates: [PeerId: CombinedPeerReadState] = [:]
        if let readState = transaction.getCombinedPeerReadState(peerId) {
            readStates[peerId] = readState
        }
        return (SearchMessagesResult(messages: messages, readStates: readStates, threadInfo: [:], totalCount: Int32(messages.count), completed: true), result.1)
    }
}
