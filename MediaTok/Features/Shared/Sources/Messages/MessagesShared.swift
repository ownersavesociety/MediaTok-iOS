import Foundation
import TelegramCore
import MTCore

/// The part of MTMessages that the extensions (notification service, share) also link: settings with
/// `.extensions`, NSE handlers, attribute declarations. Owner: MediaTok.
public enum MTMessagesShared {
    /// Called from `MTFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `MTCore.environment?.process` for what only one of them needs.
    public static func register() {
        MTMessagesSettings.declare()
        // The verbatim marker can reach Postbox on paths that skip the outgoing transformer: every
        // process that opens an account must be able to decode it.
        MTMessageAttributeHooks.declareEncodables.register({
            mtDeclareMessagesEncodables()
        })
        // SG-H1 (pinned / mention pushes): the decision is `MTNotificationFilter.decision`.
        MTNotificationServiceHooks.content.register({ content, context in
            guard let mode = MTNotificationFilter.decision(isPinnedMessage: context.isPinnedMessage, isMentionOrReply: context.isMentionOrReply, accountId: context.accountId, peerId: context.peerId) else {
                return
            }
            switch mode {
            case .disabled:
                content.isHidden = true
            case .silent:
                content.isSilent = true
            case .standard:
                break
            }
        })
    }
}
