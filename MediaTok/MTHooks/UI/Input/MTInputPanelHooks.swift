// The chat input panel (ChatTextInputPanelNode; the same points serve the other composers —
// attachment caption, story reply, gift message — as they are wired). Geometry and decoration
// features (input bar editor, typing animation, character counter, formatting toolbar) adjust
// the panel AFTER upstream laid it out, from one snapshot per layout; they get the panel node
// (cast it to `ChatTextInputPanelNode` in the feature module for its public members).

import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AccountContext
import MTCore

public struct MTReturnKeyRequest {
    public let context: AccountContext?
    public let modifierFlags: UIKeyModifierFlags
    /// What upstream decided.
    public let upstreamValue: Bool
}

/// Where the chat panel gave the room asked through `MTInputPanelHooks.sendButtonSlotWidth` in this
/// layout. The rectangles are in the panel's coordinates.
public enum MTInputPanelSlot: Equatable {
    /// No room asked, or the panel shows no text row (empty field, recording, search, slow mode).
    case none
    /// One line of text: the gap between the field's last accessory button (emoji…) and the send
    /// button, from glyph to glyph; the accessory buttons moved left to make it.
    case beforeSendButton(CGRect)
    /// More lines and Telegram's article-editor button in the field's top-right corner: the room left
    /// of its icon; the text keeps clear of it.
    case beforeCornerButton(CGRect)
    /// More lines: the text area; its top-right corner, above the field's buttons, is free.
    case textCorner(CGRect)
}

public struct MTInputPanelLayout {
    public let panel: ASDisplayNode
    public let context: AccountContext?
    public let width: CGFloat
    public let height: CGFloat
    public let transition: ContainedViewLayoutTransition
    /// The chat panel only (`.none` elsewhere).
    public let slot: MTInputPanelSlot
}

public enum MTInputPanelHooks {
    /// Policy: whether Return sends the message.
    public static let sendOnReturn = MTHookPoint<(MTReturnKeyRequest) -> Bool?>("inputPanel.sendOnReturn")

    /// Policy (any `true`): hide the voice / video message button.
    public static let hidesRecordButton = MTHookPoint<(AccountContext?) -> Bool>("inputPanel.hidesRecordButton")

    /// Observer after every layout of the panel (main thread, layout path: snapshot reads only).
    public static let didLayout = MTHookPoint<(MTInputPanelLayout) -> Void>("inputPanel.didLayout")

    /// Provider (the largest wins): room a feature's mark takes in the chat panel's text row, pt
    /// (the character counter). While the text fits one line the panel makes it right before the
    /// send button; with more lines it is given only next to the article-editor button, and
    /// `MTInputPanelLayout.slot` says which. Asked on every layout and text measurement (main
    /// thread, per keystroke): answer from memory.
    public static let sendButtonSlotWidth = MTHookPoint<(ASDisplayNode, AccountContext?) -> CGFloat>("inputPanel.sendButtonSlotWidth")

    /// Policy: a feature's view the panel holds over its top edge (the caption's formatting toolbar) that
    /// takes a touch at `point` (in the panel's view), nil = none. Asked first by the panel's hitTest.
    public static let overlayHitTest = MTHookPoint<(UIView, CGPoint, UIEvent?) -> UIView?>("inputPanel.overlayHitTest")

    /// Observer after the text changed (typing animation, counters). Main thread, per keystroke.
    public static let textDidChange = MTHookPoint<(ASDisplayNode, AccountContext?) -> Void>("inputPanel.textDidChange")

    public static func sendOnReturn(_ upstreamValue: Bool, modifierFlags: UIKeyModifierFlags, context: AccountContext?) -> Bool {
        if MTInputPanelHooks.sendOnReturn.isEmpty {
            return upstreamValue
        }
        let request = MTReturnKeyRequest(context: context, modifierFlags: modifierFlags, upstreamValue: upstreamValue)
        for handler in MTInputPanelHooks.sendOnReturn.handlers {
            if let value = handler(request) {
                return value
            }
        }
        return upstreamValue
    }

    /// True when a feature wants Return of the ON-SCREEN keyboard to send (upstream inserts a line
    /// break there; only the hardware keyboard sends).
    public static func sendsOnScreenReturn(context: AccountContext?) -> Bool {
        if MTInputPanelHooks.sendOnReturn.isEmpty {
            return false
        }
        return MTInputPanelHooks.sendOnReturn(false, modifierFlags: [], context: context)
    }

    /// The Return key of the on-screen keyboard reads «Send» while a feature sends on Return.
    /// Called after every layout of the panel: a property compare when nothing changed.
    public static func applyReturnKeyType(_ inputView: UIView?, context: AccountContext?) {
        if MTInputPanelHooks.sendOnReturn.isEmpty {
            return
        }
        guard let textView = inputView as? UITextView else {
            return
        }
        let returnKeyType: UIReturnKeyType = MTInputPanelHooks.sendsOnScreenReturn(context: context) ? .send : .default
        if textView.returnKeyType != returnKeyType {
            textView.returnKeyType = returnKeyType
            if textView.isFirstResponder {
                textView.reloadInputViews()
            }
        }
    }

    public static func hidesRecordButton(context: AccountContext?) -> Bool {
        for handler in MTInputPanelHooks.hidesRecordButton.handlers {
            if handler(context) {
                return true
            }
        }
        return false
    }

    /// MediaTok hook target: ChatTextInputPanelNode — the room before the send button (0 without handlers).
    public static func sendButtonSlotWidth(panel: ASDisplayNode, context: AccountContext?) -> CGFloat {
        var result: CGFloat = 0.0
        for handler in MTInputPanelHooks.sendButtonSlotWidth.handlers {
            result = max(result, handler(panel, context))
        }
        return result
    }

    public static func notifyDidLayout(panel: ASDisplayNode, context: AccountContext?, width: CGFloat, height: CGFloat, transition: ContainedViewLayoutTransition, slot: MTInputPanelSlot = .none) {
        if MTInputPanelHooks.didLayout.isEmpty {
            return
        }
        let layout = MTInputPanelLayout(panel: panel, context: context, width: width, height: height, transition: transition, slot: slot)
        for handler in MTInputPanelHooks.didLayout.handlers {
            handler(layout)
        }
    }

    public static func overlayHitTest(_ view: UIView, point: CGPoint, event: UIEvent?) -> UIView? {
        for handler in MTInputPanelHooks.overlayHitTest.handlers {
            if let result = handler(view, point, event) {
                return result
            }
        }
        return nil
    }

    public static func notifyTextDidChange(panel: ASDisplayNode, context: AccountContext?) {
        for handler in MTInputPanelHooks.textDidChange.handlers {
            handler(panel, context)
        }
    }
}
