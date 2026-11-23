import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import MTCore

/// Index work collected inside Postbox transactions and done after them.
/// - App: batches are applied to the account's own Postbox in a separate transaction on the
///   anti-delete queue, coalesced for 0.2 s (a deletion burst becomes one write per chat).
/// - Extensions: the records go to the app through `MTSharedInbox("antiDelete.index")`; the
///   message itself is already marked in the shared Postbox.
public final class MTAntiDeleteIndexQueue {
    public static let shared = MTAntiDeleteIndexQueue()

    static let inboxName = "antiDelete.index"

    struct Batch {
        let kind: MTAntiDeleteInboxRecord.Kind
        let peerId: PeerId
        let entries: [MTAntiDeleteLogEntry]
    }

    private let lock = NSLock()
    private var pending: [AccountRecordId: [Batch]] = [:]
    private var isFlushScheduled = false
    private var pendingInboxRecords: [Data] = []
    private var isInboxAppendScheduled = false

    private init() {
    }

    private var isExtension: Bool {
        if let process = MTCore.environment?.process {
            return !process.isApp
        }
        return false
    }

    /// From a transaction handler: only memory work here.
    func enqueue(account: AccountRecordId?, kind: MTAntiDeleteInboxRecord.Kind, peerId: PeerId, entries: [MTAntiDeleteLogEntry]) {
        guard let account else {
            MTLog.warning("antiDelete", "index entries without an account dropped")
            return
        }
        if entries.isEmpty {
            return
        }
        if self.isExtension {
            let record = MTAntiDeleteInboxRecord(account: account.mt, kind: kind, peer: peerId.mtKey, entries: entries)
            self.lock.lock()
            self.pendingInboxRecords.append(record.encode())
            let schedule = !self.isInboxAppendScheduled
            self.isInboxAppendScheduled = true
            self.lock.unlock()
            if schedule {
                // Not from inside the transaction: the file is written on our own queue.
                MTAntiDeleteAccounts.shared.queue.justDispatch { [weak self] in
                    self?.appendInboxRecords()
                }
            }
            return
        }
        if kind == .deleted {
            MTAntiDeleteAccounts.shared.noteKept(account: account, peerId: peerId)
        }
        self.lock.lock()
        self.pending[account, default: []].append(Batch(kind: kind, peerId: peerId, entries: entries))
        let schedule = !self.isFlushScheduled
        self.isFlushScheduled = true
        self.lock.unlock()
        if schedule {
            MTAntiDeleteAccounts.shared.queue.after(0.2, { [weak self] in
                self?.flush()
            })
        }
    }

    private func appendInboxRecords() {
        self.lock.lock()
        let records = self.pendingInboxRecords
        self.pendingInboxRecords = []
        self.isInboxAppendScheduled = false
        self.lock.unlock()
        if records.isEmpty {
            return
        }
        let inbox = MTSharedInbox(name: MTAntiDeleteIndexQueue.inboxName)
        for record in records {
            inbox.append(record)
        }
    }

    private func flush() {
        self.lock.lock()
        let pending = self.pending
        self.pending = [:]
        self.isFlushScheduled = false
        self.lock.unlock()
        for (account, batches) in pending {
            self.apply(account: account, batches: batches)
        }
    }

    /// Applies batches to one account (anti-delete queue).
    func apply(account: AccountRecordId, batches: [Batch]) {
        guard let postbox = MTAntiDeleteAccounts.shared.postbox(for: account) else {
            MTLog.warning("antiDelete", "index batch for an account that is not running dropped")
            return
        }
        let _ = (postbox.transaction { transaction -> ([MTAntiDeleteLogKind: MTAntiDeleteSummary], [PeerId: [MTAntiDeleteLogEntry]]) in
            var summaries: [MTAntiDeleteLogKind: MTAntiDeleteSummary] = [:]
            var deletedByPeer: [PeerId: [MTAntiDeleteLogEntry]] = [:]
            var dropped: [MessageId] = []
            for batch in batches {
                let kind: MTAntiDeleteLogKind = batch.kind == .deleted ? .deleted : .edited
                var summary = summaries[kind] ?? MTAntiDeleteIndexStore.readSummary(transaction, kind: kind)
                let pushedOut = MTAntiDeleteIndexStore.apply(transaction, kind: kind, peerId: batch.peerId, entries: batch.entries, summary: &summary)
                summaries[kind] = summary
                if kind == .deleted {
                    deletedByPeer[batch.peerId, default: []].append(contentsOf: batch.entries)
                    for entry in pushedOut where !entry.isArchiveOnly {
                        dropped.append(MessageId(peerId: batch.peerId, namespace: entry.namespace, id: entry.id))
                    }
                } else {
                    for entry in pushedOut {
                        mtClearEditHistory(transaction, id: MessageId(peerId: batch.peerId, namespace: entry.namespace, id: entry.id))
                    }
                }
            }
            for (kind, summary) in summaries {
                MTAntiDeleteIndexStore.writeSummary(transaction, kind: kind, summary: summary)
            }
            if !dropped.isEmpty {
                // Over the per-chat cap: nothing lists them any more, so they go for real.
                mtDeleteKeptMessages(transaction, postbox: postbox, ids: dropped)
            }
            return (summaries, deletedByPeer)
        }
        |> map { summaries, deletedByPeer -> [PeerId: [MTAntiDeleteLogEntry]] in
            // On the Postbox queue, in transaction order: a later operation never sees an older summary.
            MTAntiDeleteAccounts.shared.updateSummaries(account: account, summaries, flushedPeers: Set(batches.map(\.peerId)))
            return deletedByPeer
        }
        |> deliverOn(MTAntiDeleteAccounts.shared.queue)).start(next: { deletedByPeer in
            if let basePath = MTAntiDeleteAccounts.shared.basePath(for: account) {
                for (peerId, entries) in deletedByPeer {
                    MTAntiDeleteMediaArchive.archive(postbox: postbox, basePath: basePath, peerId: peerId, entries: entries)
                }
            }
        })
    }

    /// App: takes what the notification service left in the inbox (anti-delete queue, never main).
    public func drainInbox(completion: @escaping () -> Void) {
        MTAntiDeleteAccounts.shared.queue.justDispatch { [weak self] in
            guard let self else {
                completion()
                return
            }
            let records = MTSharedInbox(name: MTAntiDeleteIndexQueue.inboxName).drain()
            var batches: [AccountRecordId: [Batch]] = [:]
            for data in records {
                guard let record = MTAntiDeleteInboxRecord(data: data) else {
                    MTLog.warning("antiDelete", "damaged inbox record skipped")
                    continue
                }
                batches[AccountRecordId(mt: record.account), default: []].append(Batch(kind: record.kind, peerId: PeerId(mtKey: record.peer), entries: record.entries))
            }
            for (account, accountBatches) in batches {
                if MTAntiDeleteAccounts.shared.postbox(for: account) == nil {
                    // The account is not running now: keep its records for the next drain.
                    let inbox = MTSharedInbox(name: MTAntiDeleteIndexQueue.inboxName)
                    for batch in accountBatches {
                        inbox.append(MTAntiDeleteInboxRecord(account: account.mt, kind: batch.kind, peer: batch.peerId.mtKey, entries: batch.entries).encode())
                    }
                    continue
                }
                self.apply(account: account, batches: accountBatches)
            }
            completion()
        }
    }
}

// MARK: - Postbox helpers shared by the queue, the menus and the maintenance tasks

/// Marks every message of a chat as deleted (a secret chat the other side cleared). Returns the
/// new index entries.
func mtMarkWholeChatDeleted(_ transaction: Transaction, peerId: PeerId) -> [MTAntiDeleteLogEntry] {
    let now = Int32(Date().timeIntervalSince1970)
    var entries: [MTAntiDeleteLogEntry] = []
    transaction.withAllMessages(peerId: peerId, { message in
        if !message.mtIsDeleted {
            entries.append(MTAntiDeleteLogEntry(namespace: message.id.namespace, id: message.id.id, threadId: message.threadId, time: now, source: MTAntiDeleteSource.secretChat.rawValue, isOutgoing: !message.flags.contains(.Incoming)))
        }
        return true
    })
    for entry in entries {
        transaction.updateMessage(MessageId(peerId: peerId, namespace: entry.namespace, id: entry.id), update: { message in
            let attributes = mtReplacingAttribute(message.attributes, with: MTDeletedMessageAttribute(deletedAt: now, source: .secretChat))
            return .update(mtStoreMessage(message, attributes: attributes))
        })
    }
    return entries
}

/// Clears the saved versions of a message (tombstone: they must not come back with the next
/// storage of the message).
func mtClearEditHistory(_ transaction: Transaction, id: MessageId) {
    transaction.updateMessage(id, update: { message in
        guard message.attributes.contains(where: { ($0 as? MTEditHistoryMessageAttribute)?.versions.isEmpty == false }) else {
            return .skip
        }
        let attributes = mtReplacingAttribute(message.attributes, with: MTEditHistoryMessageAttribute(versions: []))
        return .update(mtStoreMessage(message, attributes: attributes))
    })
}

/// Deletes messages kept by anti-delete for real (cap, age limit, «Очистить», «Удалить у себя»):
/// local only, nothing is sent. Media copies of the archive are removed by the caller.
func mtDeleteKeptMessages(_ transaction: Transaction, postbox: Postbox, ids: [MessageId]) {
    if ids.isEmpty {
        return
    }
    var archived: [(messageId: MessageId, resourceIds: [MediaResourceId])] = []
    let basePath = MTAntiDeleteAccounts.shared.basePath(forPostbox: postbox)
    if basePath != nil {
        for id in ids {
            if let message = transaction.getMessage(id) {
                let resourceIds = MTAntiDeleteMediaArchive.resources(of: message).map { $0.resource.id }
                if !resourceIds.isEmpty {
                    archived.append((id, resourceIds))
                }
            }
        }
    }
    _internal_deleteMessages(transaction: transaction, mediaBox: postbox.mediaBox, ids: ids, deleteMedia: true, manualAddMessageThreadStatsDifference: nil)
    if let basePath, !archived.isEmpty {
        // Files are touched outside the transaction, on the anti-delete queue.
        MTAntiDeleteAccounts.shared.queue.justDispatch {
            MTAntiDeleteMediaArchive.remove(basePath: basePath, items: archived)
        }
    }
}

/// The stored form of `message` with other attributes.
func mtStoreMessage(_ message: Message, attributes: [MessageAttribute]) -> StoreMessage {
    var storeForwardInfo: StoreMessageForwardInfo?
    if let forwardInfo = message.forwardInfo {
        storeForwardInfo = StoreMessageForwardInfo(forwardInfo)
    }
    return StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: storeForwardInfo, authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media)
}
