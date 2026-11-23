import Foundation
import UIKit
import TelegramCore
import AccountContext
import MTHooks
import MTFeaturesShared

/// «Показывать прежние версии под текстом»: the versions go into their own node under the text
/// of the bubble (`MTMessageDecoration.footnote`), so they are neither selected nor copied with
/// the message text and keep their own transparency.
/// Drawn by ChatMessageTextBubbleContentNode (`MTMessageFootnote`, `MTMessageDecoration.footnote`).
func mtApplyEditHistoryFootnote(_ decoration: inout MTMessageDecoration, history: MTEditHistoryMessageAttribute, context: AccountContext) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let value = MTAntiDeleteDecorations.versionsText(history, presentationData: presentationData)
    if value.text.isEmpty {
        return
    }
    let alpha = MTAntiDeleteSettings.alpha(forTransparency: MTAntiDeleteSettings.versionsTransparency.value)
    decoration.footnote = MTMessageFootnote(text: value.text, entities: value.entities, alpha: alpha)
}
