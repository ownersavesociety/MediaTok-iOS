// Compiled into TelegramCore (filegroup //MediaTok/MTHooks:TelegramCoreHookSources).
// Points on the update / deletion paths. All handlers run INSIDE a Postbox transaction:
// they may read MTCore snapshots and mark messages through the given `Transaction`
// (their own attributes), nothing else — no UserDefaults, JSON, files or network.
// Heavy work goes to the feature's own queue after the transaction.

import Foundation
import Postbox
import SwiftSignalKit
import MTCore

/// Where a deletion comes from. User-initiated deletions other than "for everyone" of the
/// user's own messages are not routed through the points: the user asked for them.
public enum MTDeletionSource: Equatable {
    /// `updateDeleteMessages` / `updateDeleteChannelMessages` (incl. getDifference).
    case remoteUpdate
    /// History validation found the message gone on the server (holes, resets).
    case historyValidation
    /// The other side of a secret chat deleted it.
    case secretChat
    /// A self-destruct timer (secret chat TTL, auto-delete, view-once) fired on this device.
    case autoremoveTimer
    /// The user deleted messages "for everyone" (`InteractiveMessagesDeletionType.forEveryone`).
    case localForEveryone
}

public struct MTDeletionRequest {
    public let ids: [MessageId]
    public let source: MTDeletionSource
    public let transaction: Transaction
    private let explicitAccountPeerId: PeerId?

    init(ids: [MessageId], source: MTDeletionSource, transaction: Transaction, accountPeerId: PeerId?) {
        self.ids = ids
        self.source = source
        self.transaction = transaction
        self.explicitAccountPeerId = accountPeerId
    }

    public var accountPeerId: PeerId? {
        return self.explicitAccountPeerId ?? mtAccountPeerId(transaction: self.transaction)
    }

    public var accountId: AccountRecordId? {
        return self.accountPeerId.flatMap(MTAccountHooks.accountId(forAccountPeerId:))
    }

    /// True in the notification service / share extension: an extension must not mark
    /// anything it cannot finish, it hands work to the app (`MTSharedInbox`).
    public var isExtension: Bool {
        if let process = MTCore.environment?.process {
            return !process.isApp
        }
        return false
    }
}

/// A server-side "history cleared up to N" (`UpdateMinAvailableMessage`, cached
/// `minAvailableMessageId`) or a secret chat cleared by the other side.
public struct MTHistoryClearRequest {
    public let peerId: PeerId
    /// nil = every namespace of the chat is cleared (secret chat).
    public let namespace: MessageId.Namespace?
    /// Inclusive upper bound; nil = the whole history.
    public let maxId: MessageId.Id?
    public let source: MTDeletionSource
    public let transaction: Transaction

    public var accountPeerId: PeerId? {
        return mtAccountPeerId(transaction: self.transaction)
    }
}

public struct MTMessageEditRequest {
    /// The stored message before the edit.
    public let previous: Message
    /// Text of the incoming version.
    public let updatedText: String
    /// Media of the incoming version, as it will be stored (a paid media that was already
    /// unlocked keeps its unlocked form).
    public let updatedMedia: [Media]
    public let accountPeerId: PeerId
    public let transaction: Transaction
}

public enum MTUpdateHooks {
    /// Policy (union). Returns the ids the feature keeps (and has marked). The rest is deleted
    /// as in upstream. Called for every source in `MTDeletionSource`.
    public static let messagesWillBeDeleted = MTHookPoint<(MTDeletionRequest) -> Set<MessageId>>("updates.messagesWillBeDeleted")

    /// Policy (union). A cleared history range: ids inside the range that stay. For a whole
    /// history (`maxId == nil`) any non-empty answer keeps the entire history; the feature then
    /// marks the messages itself (after the transaction if that is heavy).
    public static let historyWillBeCleared = MTHookPoint<(MTHistoryClearRequest) -> Set<MessageId>>("updates.historyWillBeCleared")

    /// Transformer. Extra attributes for the incoming version of an edited message
    /// (the previous text, a version counter…). Returns the full attribute list.
    public static let messageWillBeEdited = MTHookPoint<(MTMessageEditRequest, [MessageAttribute]) -> [MessageAttribute]>("updates.messageWillBeEdited")
}

// MARK: - Call-site helpers (TelegramCore internal)

func mtMessageIdsToDelete(_ ids: [MessageId], source: MTDeletionSource, transaction: Transaction, accountPeerId: PeerId?) -> [MessageId] {
    if ids.isEmpty || MTUpdateHooks.messagesWillBeDeleted.isEmpty {
        return ids
    }
    let request = MTDeletionRequest(ids: ids, source: source, transaction: transaction, accountPeerId: accountPeerId)
    var kept = Set<MessageId>()
    for handler in MTUpdateHooks.messagesWillBeDeleted.handlers {
        kept.formUnion(handler(request))
    }
    if kept.isEmpty {
        return ids
    }
    return ids.filter { !kept.contains($0) }
}

/// Global ids (private chats and basic groups): the message id equals the global id.
func mtGlobalMessageIdsToDelete(_ ids: [Int32], source: MTDeletionSource, transaction: Transaction, accountPeerId: PeerId?) -> [Int32] {
    if ids.isEmpty || MTUpdateHooks.messagesWillBeDeleted.isEmpty {
        return ids
    }
    let messageIds = transaction.messageIdsForGlobalIds(ids)
    if messageIds.isEmpty {
        return ids
    }
    let remaining = mtMessageIdsToDelete(messageIds, source: source, transaction: transaction, accountPeerId: accountPeerId)
    if remaining.count == messageIds.count {
        return ids
    }
    let remainingSet = Set(remaining)
    var kept = Set<Int32>()
    for id in messageIds where !remainingSet.contains(id) {
        kept.insert(id.id)
    }
    return ids.filter { !kept.contains($0) }
}

/// True when a feature keeps this message instead of letting it be deleted.
func mtKeepsMessage(_ id: MessageId, source: MTDeletionSource, transaction: Transaction, accountPeerId: PeerId?) -> Bool {
    return mtMessageIdsToDelete([id], source: source, transaction: transaction, accountPeerId: accountPeerId).isEmpty
}

/// `transaction.deleteMessagesInRange` that leaves the ids features keep.
func mtDeleteMessagesInRange(transaction: Transaction, peerId: PeerId, namespace: MessageId.Namespace, minId: MessageId.Id, maxId: MessageId.Id, source: MTDeletionSource, forEachMedia: ((Media) -> Void)?) {
    if MTUpdateHooks.historyWillBeCleared.isEmpty {
        transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: minId, maxId: maxId, forEachMedia: forEachMedia)
        return
    }
    let request = MTHistoryClearRequest(peerId: peerId, namespace: namespace, maxId: maxId, source: source, transaction: transaction)
    var kept = Set<MessageId.Id>()
    for handler in MTUpdateHooks.historyWillBeCleared.handlers {
        for id in handler(request) where id.peerId == peerId && id.namespace == namespace && id.id >= minId && id.id <= maxId {
            kept.insert(id.id)
        }
    }
    if kept.isEmpty {
        transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: minId, maxId: maxId, forEachMedia: forEachMedia)
        return
    }
    // Delete the gaps between the kept ids.
    var lower = minId
    for id in kept.sorted() {
        if id > lower {
            transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: lower, maxId: id - 1, forEachMedia: forEachMedia)
        }
        lower = id + 1
    }
    if lower <= maxId {
        transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: lower, maxId: maxId, forEachMedia: forEachMedia)
    }
}

/// True when a feature keeps the whole history the other side of a secret chat cleared.
func mtKeepsClearedHistory(peerId: PeerId, source: MTDeletionSource, transaction: Transaction) -> Bool {
    if MTUpdateHooks.historyWillBeCleared.isEmpty {
        return false
    }
    let request = MTHistoryClearRequest(peerId: peerId, namespace: nil, maxId: nil, source: source, transaction: transaction)
    for handler in MTUpdateHooks.historyWillBeCleared.handlers {
        if !handler(request).isEmpty {
            return true
        }
    }
    return false
}

func mtEditedMessageAttributes(previous: Message, updatedText: String, updatedMedia: [Media], attributes: [MessageAttribute], accountPeerId: PeerId, transaction: Transaction) -> [MessageAttribute] {
    let request = MTMessageEditRequest(previous: previous, updatedText: updatedText, updatedMedia: updatedMedia, accountPeerId: accountPeerId, transaction: transaction)
    var result = attributes
    for handler in MTUpdateHooks.messageWillBeEdited.handlers {
        result = handler(request, result)
    }
    return result
}
