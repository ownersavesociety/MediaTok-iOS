import Foundation
import UIKit
import Postbox
import TelegramCore
import AccountContext
import MTCore
import MTHooks
import MTFeaturesShared

/// Per-message decisions of this zone, computed once per message version by the shared decoration
/// cache (MTMessageDecorationHooks) and read by every cell type: revealed spoilers, keyword-filter
/// dimming, the mark on kept view-once media, hidden «via @bot» on own messages, the mark on
/// messages written in the local creator mode.
enum MTMessageDecorations {
    static let keptMediaMark = "🔥 "
    static let localOnlyMark = "📍 "
    static let filteredAlpha: CGFloat = 0.3

    static func register() {
        MTMessageDecorationHooks.decorations.register({ decoration, context in
            MTMessageDecorations.decorate(&decoration, context: context)
        }, order: 300)
    }

    static func decorate(_ decoration: inout MTMessageDecoration, context: MTMessageDecorationContext) {
        let message = context.message
        let accountPeerId = context.context.account.peerId
        let isIncoming = message.effectivelyIncoming(accountPeerId)

        if MTMessagesSettings.revealSpoilers.value {
            decoration.revealsSpoilers = true
        }
        if isIncoming && MTMessagesSettings.keywordFilter.value && MTKeywordMatcher.shared.matches(message.text) {
            decoration.alpha = min(decoration.alpha, MTMessageDecorations.filteredAlpha)
        }
        if isIncoming && MTMessagesSettings.keepSelfDestructingMedia.value && message.mtRawContainsSecretMedia { // raw: the media itself is drawn as ordinary
            decoration.statusPrefix = (decoration.statusPrefix ?? "") + MTMessageDecorations.keptMediaMark
        }
        if !isIncoming && MTMessagesSettings.sendWithoutViaBot.value {
            decoration.hidesViaBot = true
        }
        if message.id.namespace == Namespaces.Message.Local && MTMessagesPolicy.isLocalCreatorMode(accountId: context.context.account.id, peerId: message.id.peerId) {
            decoration.statusPrefix = (decoration.statusPrefix ?? "") + MTMessageDecorations.localOnlyMark
        }
    }
}

/// Case-insensitive keyword matching; the lowercased word list is rebuilt only when the setting
/// changes, the text of each message is checked once (the decoration cache keeps the answer).
final class MTKeywordMatcher {
    static let shared = MTKeywordMatcher()

    private let lock = NSLock()
    private var source: [String] = []
    private var prepared: [String] = []

    func matches(_ text: String) -> Bool {
        if text.isEmpty {
            return false
        }
        let keywords = MTMessagesSettings.keywords.value
        if keywords.isEmpty {
            return false
        }
        self.lock.lock()
        if self.source != keywords {
            self.source = keywords
            self.prepared = keywords.compactMap { keyword in
                let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        let words = self.prepared
        self.lock.unlock()
        for word in words {
            if text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
        }
        return false
    }
}
