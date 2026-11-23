// Compiled into TelegramCore (filegroup //MediaTok/MTHooks:TelegramCoreHookSources).
// Lets a feature answer Telegram's translation requests with another service (Google JSON
// endpoint, system translation). First provider that returns a signal wins; nil = Telegram.

import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import MTCore

public struct MTTextTranslationRequest {
    public let texts: [(String, [MessageTextEntity])]
    public let toLang: String
    public let tone: TranslationTone
}

public struct MTMessagesTranslationRequest {
    public let account: Account
    public let peerId: PeerId
    public let messageIds: [MessageId]
    public let fromLang: String?
    public let toLang: String
}

public enum MTTranslationHooks {
    /// Provider for `translateText`-style requests (single text and batches): results in the
    /// order of `texts`.
    public static let translateTexts = MTHookPoint<(MTTextTranslationRequest) -> Signal<[(String, [MessageTextEntity])], TranslationError>?>("translation.translateTexts")

    /// Provider for translating stored messages of a chat (the chat translation bar). The
    /// provider stores `TranslationMessageAttribute` itself, as upstream does.
    public static let translateMessages = MTHookPoint<(MTMessagesTranslationRequest) -> Signal<Void, TranslationError>?>("translation.translateMessages")
}

func mtTranslateTexts(_ texts: [(String, [MessageTextEntity])], toLang: String, tone: TranslationTone) -> Signal<[(String, [MessageTextEntity])], TranslationError>? {
    if MTTranslationHooks.translateTexts.isEmpty {
        return nil
    }
    let request = MTTextTranslationRequest(texts: texts, toLang: toLang, tone: tone)
    for handler in MTTranslationHooks.translateTexts.handlers {
        if let signal = handler(request) {
            return signal
        }
    }
    return nil
}

func mtTranslateText(_ text: String, entities: [MessageTextEntity], toLang: String, tone: TranslationTone) -> Signal<(String, [MessageTextEntity])?, TranslationError>? {
    guard let signal = mtTranslateTexts([(text, entities)], toLang: toLang, tone: tone) else {
        return nil
    }
    return signal
    |> map { results -> (String, [MessageTextEntity])? in
        return results.first
    }
}

func mtTranslateMessages(account: Account, peerId: PeerId, messageIds: [MessageId], fromLang: String?, toLang: String) -> Signal<Void, TranslationError>? {
    if MTTranslationHooks.translateMessages.isEmpty {
        return nil
    }
    let request = MTMessagesTranslationRequest(account: account, peerId: peerId, messageIds: messageIds, fromLang: fromLang, toLang: toLang)
    for handler in MTTranslationHooks.translateMessages.handlers {
        if let signal = handler(request) {
            // Providers translate plain messages only. Rich ones (an InstantPage body) go to Telegram,
            // the way upstream sends them; a failure there does not fail the plain ones.
            return combineLatest(signal, mtTranslateRichMessagesByTelegram(account: account, peerId: peerId, messageIds: messageIds, toLang: toLang))
            |> map { _ -> Void in
                return Void()
            }
        }
    }
    return nil
}

private struct MTRichTranslationKey: Hashable {
    let account: AccountRecordId
    let messageId: MessageId
    let toLang: String
}

/// Rich messages Telegram refused to translate (no Premium, limits): the chat asks for every message
/// without a translation on each history update, so they are not asked again until the next launch.
private let mtRefusedRichTranslations = Atomic<Set<MTRichTranslationKey>>(value: Set())

private func mtTranslateRichMessagesByTelegram(account: Account, peerId: PeerId, messageIds: [MessageId], toLang: String) -> Signal<Void, TranslationError> {
    let accountId = account.id
    return account.postbox.transaction { transaction -> (Api.InputPeer?, [MessageId]) in
        var ids: [MessageId] = []
        for id in messageIds {
            if let message = transaction.getMessage(id), message.attributes.contains(where: { $0 is RichTextMessageAttribute }) {
                ids.append(id)
            }
        }
        if ids.isEmpty {
            return (nil, [])
        }
        return (transaction.getPeer(peerId).flatMap(apiInputPeer), ids)
    }
    |> castError(TranslationError.self)
    |> mapToSignal { (inputPeer, ids) -> Signal<Void, TranslationError> in
        let refused = mtRefusedRichTranslations.with { $0 }
        let pending = ids.filter { id in
            return !refused.contains(MTRichTranslationKey(account: accountId, messageId: id, toLang: toLang))
        }
        guard let inputPeer, !pending.isEmpty else {
            return .single(Void())
        }
        return _internal_translateRichMessages(account: account, inputPeer: inputPeer, messageIds: pending, toLang: toLang)
        |> map { _ -> Void in
            return Void()
        }
        |> `catch` { _ -> Signal<Void, TranslationError> in
            let _ = mtRefusedRichTranslations.modify { current in
                var current = current
                for id in pending {
                    current.insert(MTRichTranslationKey(account: accountId, messageId: id, toLang: toLang))
                }
                return current
            }
            return .single(Void())
        }
    }
}

/// MediaTok hook target: `_internal_composeAIMessage`. A plain translation (no style, no emojification,
/// text with entities) — the translate screen of a message — goes to the chosen service instead of
/// Telegram's AI; anything only Telegram can do stays upstream's. nil = upstream.
func mtComposeAITranslation(text: ComposedRichMessage, mode: TelegramComposeAIMessageMode) -> Signal<TelegramAIComposeMessageResult, TelegramAIComposeMessageError>? {
    guard case let .translate(toLanguage, emojify, style) = mode, !emojify, case .neutral = style else {
        return nil
    }
    guard case let .plain(plainText, entities) = text else {
        return nil
    }
    guard let signal = mtTranslateText(plainText, entities: entities, toLang: toLanguage, tone: .neutral) else {
        return nil
    }
    return signal
    |> mapError { _ -> TelegramAIComposeMessageError in
        return .generic
    }
    |> map { result -> TelegramAIComposeMessageResult in
        let value = result ?? (plainText, entities)
        return TelegramAIComposeMessageResult(text: .plain(text: value.0, entities: value.1), diffRanges: [])
    }
}
