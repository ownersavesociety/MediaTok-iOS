import Foundation
import Postbox
import TelegramCore
import MTCore

/// SG-H1: pushes about pinned messages and about mentions / replies — «как обычно / без звука /
/// не присылать», with per-chat exceptions (legacy format read the exceptions in the extension but
/// nothing ever wrote them; the menu now does, see MTNotificationExceptionsScreen in MTMessages).
///
/// Runs in the notification service extension: settings are App Group / account scoped with
/// `.extensions`. `MTMessagesShared.register()` applies it on `MTNotificationServiceHooks.content`
/// (`MTNotificationContext.isPinnedMessage` / `.isMentionOrReply`, `MTNotificationContent.isSilent`).
public enum MTNotificationFilter {
    public enum Kind {
        case pinnedMessage
        case mentionOrReply
    }

    /// The mode for this push: the chat's exception first, then the global choice.
    public static func mode(kind: Kind, accountId: AccountRecordId?, peerId: PeerId?) -> MTNotificationDeliveryMode {
        let globalValue: String
        let exceptions: [String: String]
        switch kind {
        case .pinnedMessage:
            globalValue = MTMessagesSettings.pinnedNotifications.value
            exceptions = accountId.flatMap { MTMessagesSettings.pinnedNotificationExceptions.value(for: $0.mt) } ?? [:]
        case .mentionOrReply:
            globalValue = MTMessagesSettings.mentionNotifications.value
            exceptions = accountId.flatMap { MTMessagesSettings.mentionNotificationExceptions.value(for: $0.mt) } ?? [:]
        }
        if let peerId, let value = exceptions[peerId.mtKey.stringValue], let mode = MTNotificationDeliveryMode(rawValue: value) {
            return mode
        }
        return MTNotificationDeliveryMode(rawValue: globalValue) ?? .standard
    }

    /// What to do with a push of the given kinds: `nil` = deliver unchanged.
    public static func decision(isPinnedMessage: Bool, isMentionOrReply: Bool, accountId: AccountRecordId?, peerId: PeerId?) -> MTNotificationDeliveryMode? {
        var result: MTNotificationDeliveryMode?
        if isPinnedMessage {
            result = MTNotificationFilter.mode(kind: .pinnedMessage, accountId: accountId, peerId: peerId)
        }
        if isMentionOrReply {
            let mode = MTNotificationFilter.mode(kind: .mentionOrReply, accountId: accountId, peerId: peerId)
            result = MTNotificationFilter.stricter(result, mode)
        }
        if result == .standard {
            return nil
        }
        return result
    }

    /// The same decision for the banner the app shows itself while it is open (no push involved):
    /// a «pinned» service message, a mention or a reply to the account (the message carries a
    /// personal-mention mark, the in-app counterpart of the push's `mention`).
    public static func inAppDecision(message: Message, accountId: AccountRecordId) -> MTNotificationDeliveryMode? {
        var isPinnedMessage = false
        for media in message.media {
            if let action = media as? TelegramMediaAction, case .pinnedMessageUpdated = action.action {
                isPinnedMessage = true
            }
        }
        let isMentionOrReply = message.attributes.contains(where: { $0 is ConsumablePersonalMentionMessageAttribute })
        if !isPinnedMessage && !isMentionOrReply {
            return nil
        }
        return MTNotificationFilter.decision(isPinnedMessage: isPinnedMessage, isMentionOrReply: isMentionOrReply, accountId: accountId, peerId: message.id.peerId)
    }

    private static func stricter(_ lhs: MTNotificationDeliveryMode?, _ rhs: MTNotificationDeliveryMode) -> MTNotificationDeliveryMode {
        guard let lhs else {
            return rhs
        }
        func rank(_ mode: MTNotificationDeliveryMode) -> Int {
            switch mode {
            case .standard:
                return 0
            case .silent:
                return 1
            case .disabled:
                return 2
            }
        }
        return rank(lhs) >= rank(rhs) ? lhs : rhs
    }
}
