import Foundation
import UIKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import MTCore
import MTHooks
import MTFeaturesShared

/// `MTMessageDecorationHooks.decorations`: computed once per message version (the point caches it)
/// for every cell type. Everything comes from the message's own attributes and the settings
/// snapshot; a message without MediaTok attributes costs one pass over its attribute list.
enum MTAntiDeleteDecorations {
    static func decorate(_ decoration: inout MTMessageDecoration, _ context: MTMessageDecorationContext) {
        let message = context.message
        var hasLocalAttributes = false
        for attribute in message.attributes where attribute is MTAntiDeleteLocalAttribute {
            hasLocalAttributes = true
            break
        }
        if !hasLocalAttributes {
            return
        }
        let state = MTAntiDeleteMessageState(attributes: message.attributes)
        var prefix = ""

        if state.deleted != nil {
            decoration.alpha = min(decoration.alpha, MTAntiDeleteSettings.alpha(forTransparency: MTAntiDeleteSettings.transparency.value))
            prefix += MTAntiDeleteDecorations.deletedMark
            MTAntiDeleteReplyQuote.remember(message, context: context.context)
        }
        if let history = state.history {
            prefix += MTAntiDeleteDecorations.historyMark(versionCount: history.versions.count)
            let isBotMessage = (message.author as? TelegramUser)?.botInfo != nil || (message.peers[message.id.peerId] as? TelegramUser)?.botInfo != nil
            if MTAntiDeleteSettings.editHistoryInline.value && !isBotMessage {
                mtApplyEditHistoryFootnote(&decoration, history: history, context: context.context)
            }
        }
        if state.bookmark != nil && MTBookmarkSettings.enabled.value {
            prefix += "🔖 "
        }
        if !prefix.isEmpty {
            // Appended to what other features put there (the point's contract), never replaced.
            decoration.statusPrefix = (decoration.statusPrefix ?? "") + prefix
        }
        if let localEdit = state.localEdit {
            decoration.textOverride = MTMessageTextOverride(text: localEdit.text, entities: localEdit.entities)
        }
    }

    /// Status-line marks; the menu preview shows the same ones. Deleted = a flat trash icon before
    /// the time (`MTStatusIcon`), not an emoji.
    static let deletedMark = String(MTStatusIcon.deleted.rawValue)

    static func historyMark(versionCount: Int) -> String {
        return "✎\(versionCount) "
    }

    /// The previous versions as text: «12:30 — text», oldest first.
    static func versionsText(_ history: MTEditHistoryMessageAttribute, presentationData: PresentationData) -> (text: String, entities: [MessageTextEntity]) {
        var text = ""
        var entities: [MessageTextEntity] = []
        for version in history.versions {
            if !text.isEmpty {
                text += "\n"
            }
            let time = stringForMediumDate(timestamp: version.date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
            let start = (text as NSString).length
            text += time
            entities.append(MessageTextEntity(range: start ..< (text as NSString).length, type: .Italic))
            text += " — "
            var body = version.text
            if body.isEmpty, let media = version.mediaDescription {
                body = mtAntiDeleteMediaTitle(media)
            }
            let bodyStart = (text as NSString).length
            text += body
            for entity in version.entities {
                if case .BlockQuote = entity.type {
                    continue
                }
                let lower = entity.range.lowerBound + bodyStart
                let upper = entity.range.upperBound + bodyStart
                if upper <= (text as NSString).length {
                    entities.append(MessageTextEntity(range: lower ..< upper, type: entity.type))
                }
            }
        }
        return (text, entities)
    }
}
