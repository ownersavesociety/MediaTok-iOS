import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import MTCore
import MTHooks
import MTFeaturesShared

extension MTTextReplacementRule: MTSettingValue {}

/// The one outgoing text pipeline: `MTOutgoingHooks.textStages` runs the three stages of
/// `MTTextPipeline` in their fixed order over text + entities (formatting and custom emoji move
/// with the text). It covers every `.message` that goes through `enqueueMessages`: the composer,
/// bot buttons, captions, inline results, plugins of the future. Copies (forward fallback) carry
/// `MTOutgoingVerbatimAttribute` and are skipped; rich messages (an InstantPage body) are skipped
/// because their text is derived from the page. Edits of sent messages are not transformed.
enum MTOutgoingPipeline {
    /// Global: the user's own dictionary.
    static let replacementRules = MTSetting<[MTTextReplacementRule]>("sending.wordReplacementRules", default: [])

    static func register() {
        MTOutgoingHooks.textStages.register({ text, context in
            MTOutgoingPipeline.transform(&text, context: context)
        }, order: 100)
        MTChatScreenHooks.lifecycle.register({ event, screen in
            if case .willAppear = event {
                MTBotPeerCache.shared.noteChat(screen.chatLocation, context: screen.context)
            }
        })
        // A reply with a bot keyboard button's text: the bot expects it exactly (in a group the
        // bot can not be told from the chat, so the button itself marks the message).
        MTChatScreenHooks.botButtonReplyAttributes.register({
            return [MTOutgoingVerbatimAttribute()]
        })
    }

    static func configuration(accountId: MTAccountID) -> MTTextPipelineConfiguration {
        var configuration = MTTextPipelineConfiguration()
        if MTMessagesSettings.wordReplacement.value {
            configuration.replacementRules = MTOutgoingPipeline.replacementRules.value
        }
        configuration.antiCaps = MTMessagesSettings.antiCaps.value
        if MTMessagesSettings.hyperlinkSpoof.value {
            configuration.hyperlink = MTMessagesSettings.hyperlinkTarget.value(for: accountId) != nil
        }
        return configuration
    }

    static func transform(_ text: inout MTOutgoingText, context: MTOutgoingTextContext) {
        let accountId = context.account.id.mt
        let configuration = MTOutgoingPipeline.configuration(accountId: accountId)
        if configuration.isEmpty {
            return
        }
        let attributes = context.message.attributes
        if MTOutgoingVerbatimAttribute.isPresent(in: attributes) {
            return
        }
        if attributes.contains(where: { $0 is RichTextMessageAttribute }) {
            return
        }
        let pipelineContext = MTTextPipelineContext(
            isBot: MTBotPeerCache.shared.isBot(context.peerId, accountPeerId: context.account.peerId),
            isSavedMessages: context.peerId == context.account.peerId,
            isVerbatim: false
        )
        let target = MTMessagesSettings.hyperlinkTarget.value(for: accountId)
        let result = MTOutgoingPipeline.run(text, configuration: configuration, context: pipelineContext, hyperlinkTarget: target.map { PeerId(mtKey: $0) })
        if result != text {
            text = result
        }
    }

    /// Also used by the preview of the «Отправка» tab.
    static func run(_ text: MTOutgoingText, configuration: MTTextPipelineConfiguration, context: MTTextPipelineContext, hyperlinkTarget: PeerId?) -> MTOutgoingText {
        var configuration = configuration
        if hyperlinkTarget == nil {
            configuration.hyperlink = false
        }
        let input = MTPipelineText(text: text.text, entities: text.entities.enumerated().map { index, entity in
            return MTPipelineEntity(range: entity.range, isProtected: MTOutgoingPipeline.isProtected(entity.type), excludesOverlay: MTOutgoingPipeline.excludesOverlay(entity.type), tag: index)
        })
        let output = MTTextPipeline.run(input, configuration: configuration, context: context)
        if output == input {
            return text
        }
        var entities: [MessageTextEntity] = []
        for entity in output.entities {
            if entity.tag == MTPipelineEntity.addedOverlay {
                if let hyperlinkTarget {
                    entities.append(MessageTextEntity(range: entity.range, type: .TextMention(peerId: hyperlinkTarget)))
                }
            } else if entity.tag >= 0 && entity.tag < text.entities.count {
                entities.append(MessageTextEntity(range: entity.range, type: text.entities[entity.tag].type))
            }
        }
        entities.sort(by: { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            return lhs.range.upperBound > rhs.range.upperBound
        })
        return MTOutgoingText(text: output.text, entities: entities)
    }

    /// The stages never change the text under these.
    static func isProtected(_ type: MessageTextEntityType) -> Bool {
        switch type {
        case .Mention, .Hashtag, .BotCommand, .Url, .Email, .Code, .Pre, .TextUrl, .TextMention, .PhoneNumber, .BankCard, .TonAddress, .CustomEmoji, .FormattedDate:
            return true
        case .Unknown, .Bold, .Italic, .Strikethrough, .BlockQuote, .Underline, .Spoiler, .Custom:
            return false
        }
    }

    /// Link-like and code entities: the mention overlay is never put over them.
    static func excludesOverlay(_ type: MessageTextEntityType) -> Bool {
        switch type {
        case .Mention, .Hashtag, .BotCommand, .Url, .Email, .Code, .Pre, .TextUrl, .TextMention, .PhoneNumber, .BankCard, .TonAddress, .FormattedDate:
            return true
        case .Unknown, .Bold, .Italic, .Strikethrough, .BlockQuote, .Underline, .Spoiler, .Custom, .CustomEmoji:
            return false
        }
    }
}

/// «Is this chat a bot?» for the text stages, which run before the Postbox transaction and can not
/// read the peer. Filled when a chat screen appears (sends nearly always come from an open chat);
/// an unknown peer counts as not a bot.
final class MTBotPeerCache {
    static let shared = MTBotPeerCache()

    private struct Key: Hashable {
        let accountPeerId: PeerId
        let peerId: PeerId
    }

    private let lock = NSLock()
    private var bots = Set<Key>()
    private var checked = Set<Key>()

    func isBot(_ peerId: PeerId, accountPeerId: PeerId) -> Bool {
        if peerId.namespace != Namespaces.Peer.CloudUser {
            return false
        }
        self.lock.lock()
        let result = self.bots.contains(Key(accountPeerId: accountPeerId, peerId: peerId))
        self.lock.unlock()
        return result
    }

    func noteChat(_ chatLocation: ChatLocation, context: AccountContext) {
        guard let peerId = chatLocation.peerId, peerId.namespace == Namespaces.Peer.CloudUser else {
            return
        }
        let key = Key(accountPeerId: context.account.peerId, peerId: peerId)
        self.lock.lock()
        let isNew = self.checked.insert(key).inserted
        self.lock.unlock()
        if !isNew {
            return
        }
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self, case let .user(user)? = peer, user.botInfo != nil else {
                return
            }
            self.lock.lock()
            self.bots.insert(key)
            self.lock.unlock()
        })
    }
}
