import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import MTCore
import MTHooks
import MTAppearanceSettings

// Handlers of the extension points in frozen files (the sticker nodes, the bubble, the text bubble,
// the profile items): MTMessageLayoutHooks, MTMessageGestureHooks, MTMessageTextHooks,
// MTPeerInfoHooks.hidesItem.

enum MTAppearancePendingPoints {
    static func register() {
        // P1. Sticker size and time: ChatMessageStickerItemNode / ChatMessageAnimatedStickerItemNode.
        MTMessageLayoutHooks.sticker.register({ layout, _, _ in
            let snapshot = MTAppearanceSnapshot.current
            layout.scale *= CGFloat(snapshot.stickerScale)
            if snapshot.stickerHideTime {
                layout.showsTime = false
            }
        }, order: 100)

        // P1. Bubble editor padding: chatMessageItemLayoutConstants (ChatMessageItemView).
        MTMessageLayoutHooks.bubbleTextInset.register({ _ in
            guard let bubbles = MTAppearanceSnapshot.current.bubbles else {
                return nil
            }
            return CGFloat(bubbles.padding)
        }, order: 100)

        // P1. Wide channel posts: full width and no side share button, as the old feature did.
        MTMessageLayoutHooks.fullWidthBubble.register({ message, _ in
            guard MTAppearanceSnapshot.current.wideChannelPosts else {
                return false
            }
            if let channel = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = channel.info {
                return true
            }
            return false
        }, order: 100)

        // P2. Triple tap deletes a message (message_ui_toggles): one recognizer in the bubble for every
        // feature that reacts to multiple taps (double tap is MediaTok's). While it is on, the bubble's
        // double tap waits for the third tap, so the second one sends no quick reaction to the server.
        MTMessageGestureHooks.wantsTripleTap.register({ _ in
            return MTAppearanceSnapshot.current.tripleTapDelete != .off
        }, order: 100)
        MTMessageGestureHooks.tap.register({ request in
            guard request.tapCount == 3 else {
                return false
            }
            let mode = MTAppearanceSnapshot.current.tripleTapDelete
            switch mode {
            case .off:
                return false
            case .local:
                let _ = request.context.engine.messages.deleteMessagesInteractively(messageIds: [request.message.id], type: .forLocalPeer).startStandalone()
                return true
            case .everyone:
                let _ = request.context.engine.messages.deleteMessagesInteractively(messageIds: [request.message.id], type: .forEveryone).startStandalone()
                return true
            }
        }, order: 100)

        // P3. Color swatches after hex colors in message text (message_ui_toggles).
        MTMessageTextHooks.attributedText.register({ text, _ in
            guard MTAppearanceSnapshot.current.colorSwatches else {
                return text
            }
            return MTColorSwatches.apply(text)
        }, order: 100)

        // P4. Hidden profile items: the description, the share button and the rating badge (profile_ui_toggles).
        MTPeerInfoHooks.hidesItem.register({ kind, _ in
            switch kind {
            case .description:
                return MTAppearanceSettings.profileHideDescription.value
            case .shareButton:
                return MTAppearanceSettings.profileHideShareButton.value
            case .starRating:
                return MTAppearanceSettings.profileHideStarRating.value
            }
        }, order: 100)
    }
}

/// Hex colors written in a message («#FF5733», «#abc», «#RRGGBBAA») get a colored dot after them.
/// The matches are cached by the text shown — not by the message: what is shown changes without a
/// new message version (the chat's translation on and off, «Edit locally», hidden formatting), and
/// offsets cached for another text put the dot in the middle of a word. The old code ran the
/// regular expression on every layout of every text cell, with no switch to turn it off.
enum MTColorSwatches {
    private static let expression = try? NSRegularExpression(pattern: "(?<![0-9A-Za-z_#])#([0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})(?![0-9A-Za-z_])", options: [])

    private struct Match {
        let range: NSRange
        let color: UIColor
    }

    private static let lock = NSLock()
    private static var cache: [String: [Match]] = [:]

    static func apply(_ text: NSAttributedString) -> NSAttributedString {
        let matches = MTColorSwatches.matches(text.string)
        if matches.isEmpty {
            return text
        }
        let result = NSMutableAttributedString(attributedString: text)
        // From the end, so earlier ranges stay valid.
        for match in matches.reversed() {
            let end = match.range.location + match.range.length
            if end > result.length {
                continue
            }
            var attributes = result.attributes(at: max(0, end - 1), effectiveRange: nil)
            attributes[.foregroundColor] = match.color
            attributes.removeValue(forKey: .link)
            result.insert(NSAttributedString(string: "\u{00A0}\u{25CF}", attributes: attributes), at: end)
        }
        return result
    }

    private static func matches(_ string: String) -> [Match] {
        if !string.contains("#") {
            return []
        }
        MTColorSwatches.lock.lock()
        if let cached = MTColorSwatches.cache[string] {
            MTColorSwatches.lock.unlock()
            return cached
        }
        MTColorSwatches.lock.unlock()

        var result: [Match] = []
        if let expression = MTColorSwatches.expression {
            let nsString = string as NSString
            for match in expression.matches(in: string, options: [], range: NSRange(location: 0, length: nsString.length)) where match.numberOfRanges > 1 {
                if let color = MTColorSwatches.color(nsString.substring(with: match.range(at: 1))) {
                    result.append(Match(range: match.range, color: color))
                }
            }
        }

        MTColorSwatches.lock.lock()
        if MTColorSwatches.cache.count > 512 {
            MTColorSwatches.cache.removeAll()
        }
        MTColorSwatches.cache[string] = result
        MTColorSwatches.lock.unlock()
        return result
    }

    private static func color(_ digits: String) -> UIColor? {
        var normalized = digits
        if normalized.count == 3 {
            normalized = normalized.map { "\($0)\($0)" }.joined()
        }
        guard let value = UInt32(normalized, radix: 16) else {
            return nil
        }
        if normalized.count == 8 {
            return UIColor(rgb: value >> 8, alpha: CGFloat(value & 0xff) / 255.0)
        }
        if normalized.count == 6 {
            return UIColor(rgb: value)
        }
        return nil
    }
}
