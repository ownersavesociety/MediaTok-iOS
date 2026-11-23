// Compiled into NotificationServiceExtensionLib (filegroup
// //MediaTok/MTHooks:NotificationServiceHookSources). Launch of MediaTok in the notification
// service extension and the content point applied to what is handed to the system.

import Foundation
import UserNotifications
import Postbox
import TelegramCore
import MTCore
import MTFeaturesShared

private var mtNotificationServiceStarted = false
private let mtNotificationServiceLock = NSLock()

/// MediaTok hook target: at the start of every push, before `initializeAccountManagement()` (feature
/// attribute declarations) and before any account is opened. The first call starts MediaTok in the
/// process; iOS keeps the process alive and reuses it for the next pushes, so every later call reads
/// the settings files again (chat protection, notification modes, «Удалённые» changed in the app).
func mtNotificationServiceDidStart(appGroupPath: String) {
    mtNotificationServiceLock.lock()
    defer {
        mtNotificationServiceLock.unlock()
    }
    if mtNotificationServiceStarted {
        MTCore.reloadSettings()
        return
    }
    mtNotificationServiceStarted = true
    MTCore.bootstrap(MTCoreEnvironment(appGroupPath: appGroupPath, process: .notificationService))
    // Handlers register on the main thread (MTHookPoint contract); the extension calls this
    // from its handler queue, before anything reads the points.
    if Thread.isMainThread {
        MTFeaturesShared.registerForExtension()
    } else {
        DispatchQueue.main.sync {
            MTFeaturesShared.registerForExtension()
        }
    }
    MTHookRegistry.freeze()
}

// Marks the extension puts into the content's userInfo while it builds it, read back (and
// removed) when the final content is handed to the system. Only set while the point has handlers.
private let mtPinnedMessageKey = "mt.pinnedMessage"
private let mtMentionOrReplyKey = "mt.mentionOrReply"

/// MediaTok hook target: the payload of a message push (`mention`, `loc-key`), right after the
/// content is created.
func mtMarkNotificationContent(_ userInfo: inout [AnyHashable: Any], payload: [String: Any]) {
    if MTNotificationServiceHooks.content.isEmpty {
        return
    }
    if let mention = payload["mention"] as? String, mention == "1" {
        userInfo[mtMentionOrReplyKey] = true
    }
    if let locKey = payload["loc-key"] as? String, locKey.hasPrefix("PINNED_") {
        userInfo[mtPinnedMessageKey] = true
    }
}

/// MediaTok hook target: the message fetched for the push is a «pinned» service message.
func mtMarkNotificationContent(_ userInfo: inout [AnyHashable: Any], media: Media?) {
    if MTNotificationServiceHooks.content.isEmpty {
        return
    }
    if let action = media as? TelegramMediaAction, case .pinnedMessageUpdated = action.action {
        userInfo[mtPinnedMessageKey] = true
    }
}

/// What the content point decides about a push before upstream builds the final content.
enum MTNotificationPreparation {
    case unchanged
    /// Deliver nothing (no content is generated, no Siri intent is donated).
    case hidden
    /// Show this text instead of the message: no custom emoji (`attributedBody`), no attachments and
    /// no donated Siri intent, which would all carry the real text.
    case hiddenBody(String)
}

/// MediaTok hook target: called with upstream's content fields BEFORE `generate()`, which writes the
/// text into `attributedBody` (custom emoji, iOS 18+) and donates an `INSendMessageIntent` with it.
/// `mtNotificationContent` still runs on the generated content (titles, sound, marks).
func mtNotificationPreparation(title: String?, subtitle: String?, body: String?, userInfo: [AnyHashable: Any]) -> MTNotificationPreparation {
    if MTNotificationServiceHooks.content.isEmpty {
        return .unchanged
    }
    let original = MTNotificationContent(title: title ?? "", subtitle: subtitle ?? "", body: body ?? "", threadIdentifier: "", categoryIdentifier: "", isHidden: false, isSilent: false)
    let updated = MTNotificationServiceHooks.transform(original, context: mtNotificationContext(userInfo))
    if updated.isHidden {
        return .hidden
    }
    if updated.hidesAttachments || updated.body != original.body {
        return .hiddenBody(updated.body)
    }
    return .unchanged
}

private func mtNotificationContext(_ userInfo: [AnyHashable: Any]) -> MTNotificationContext {
    var accountId: AccountRecordId?
    if let value = userInfo["accountId"] as? String, let rawValue = Int64(value) {
        accountId = AccountRecordId(rawValue: rawValue)
    }
    var peerId: PeerId?
    if let value = userInfo["peerId"] as? String, let rawValue = Int64(value) {
        peerId = PeerId(rawValue)
    }
    var messageId: MessageId?
    if let peerId, let value = userInfo["msg_id"] as? String, let rawValue = Int32(value) {
        messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: rawValue)
    }
    let isPinnedMessage = (userInfo[mtPinnedMessageKey] as? Bool) ?? false
    let isMentionOrReply = (userInfo[mtMentionOrReplyKey] as? Bool) ?? false
    return MTNotificationContext(accountId: accountId, peerId: peerId, messageId: messageId, isPinnedMessage: isPinnedMessage, isMentionOrReply: isMentionOrReply)
}

/// MediaTok hook target: the content handed to `contentHandler` (MTNotificationServiceHooks.content).
func mtNotificationContent(_ content: UNNotificationContent) -> UNNotificationContent {
    if MTNotificationServiceHooks.content.isEmpty {
        return content
    }
    let userInfo = content.userInfo
    let hasMarks = userInfo[mtPinnedMessageKey] != nil || userInfo[mtMentionOrReplyKey] != nil
    let original = MTNotificationContent(title: content.title, subtitle: content.subtitle, body: content.body, threadIdentifier: content.threadIdentifier, categoryIdentifier: content.categoryIdentifier, isHidden: false, isSilent: false)
    let updated = MTNotificationServiceHooks.transform(original, context: mtNotificationContext(userInfo))
    if updated == original && !hasMarks {
        return content
    }
    if updated.isHidden {
        return UNNotificationContent()
    }
    guard let mutable = content.mutableCopy() as? UNMutableNotificationContent else {
        return content
    }
    if hasMarks {
        var cleanUserInfo = userInfo
        cleanUserInfo.removeValue(forKey: mtPinnedMessageKey)
        cleanUserInfo.removeValue(forKey: mtMentionOrReplyKey)
        mutable.userInfo = cleanUserInfo
    }
    mutable.title = updated.title
    mutable.subtitle = updated.subtitle
    mutable.body = updated.body
    mutable.threadIdentifier = updated.threadIdentifier
    mutable.categoryIdentifier = updated.categoryIdentifier
    if updated.isSilent {
        mutable.sound = nil
    }
    if updated.hidesAttachments {
        mutable.attachments = []
    }
    return mutable
}

/// MediaTok hook target: every content the extension hands to the system, after the content point.
/// An empty one (upstream's way to drop a push, or hidden by the content point) goes as a passive
/// placeholder that is removed once delivered: without the filtering entitlement iOS would show the
/// server's own push instead (MTEmptyNotifications). Placeholders left by earlier pushes go first.
func mtDeliverNotificationContent(_ content: UNNotificationContent, requestIdentifier: String, to contentHandler: (UNNotificationContent) -> Void) {
    MTEmptyNotifications.removeDelivered()
    if MTEmptyNotifications.isEmpty(content) {
        contentHandler(MTEmptyNotifications.placeholder(badge: content.badge))
        MTEmptyNotifications.removeDelivered(waitingFor: requestIdentifier)
    } else {
        contentHandler(content)
    }
}
