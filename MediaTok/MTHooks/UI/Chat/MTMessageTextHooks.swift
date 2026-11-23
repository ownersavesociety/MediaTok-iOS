// The attributed text of a text bubble after entities are applied and before layout (color
// swatches after hex colors…). Call site: ChatMessageTextBubbleContentNode, for every layout of a
// text bubble: handlers cache their own work per message version.

import Foundation
import UIKit
import Postbox
import TelegramCore
import AccountContext
import MTCore

public struct MTMessageTextContext {
    public let message: Message
    public let context: AccountContext
}

public enum MTMessageTextHooks {
    /// Transformer of the attributed text of a text bubble. Return the same object when nothing applies.
    public static let attributedText = MTHookPoint<(NSAttributedString, MTMessageTextContext) -> NSAttributedString>("messageText.attributedText")

    public static func attributedText(_ text: NSAttributedString, message: Message, context: AccountContext) -> NSAttributedString {
        if MTMessageTextHooks.attributedText.isEmpty {
            return text
        }
        let textContext = MTMessageTextContext(message: message, context: context)
        var result = text
        for handler in MTMessageTextHooks.attributedText.handlers {
            result = handler(result, textContext)
        }
        return result
    }
}
