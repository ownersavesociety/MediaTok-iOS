import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import MTCore

/// The anti-delete index inside the account's own Postbox (ItemCache): encrypted like the rest of
/// the account, removed together with it, readable reactively through `combinedView`.
/// Collection ids 120–124 belong to MediaTok (upstream uses 0…59, `Namespaces.CachedItemCollection`).
public enum MTAntiDeleteIndexStore {
    static let deletedLogsCollection: Int8 = 120
    static let editedLogsCollection: Int8 = 121
    static let bookmarksCollection: Int8 = 122
    static let archivedCollection: Int8 = 123
    static let summariesCollection: Int8 = 124

    private static func logsCollection(_ kind: MTAntiDeleteLogKind) -> Int8 {
        switch kind {
        case .deleted:
            return MTAntiDeleteIndexStore.deletedLogsCollection
        case .edited:
            return MTAntiDeleteIndexStore.editedLogsCollection
        }
    }

    private static func peerKey(_ peerId: PeerId) -> ValueBoxKey {
        let key = peerId.mtKey
        let result = ValueBoxKey(length: 4 + 8)
        result.setInt32(0, value: key.namespace)
        result.setInt64(4, value: key.id)
        return result
    }

    private static func messageKey(_ id: MessageId) -> ValueBoxKey {
        let key = id.peerId.mtKey
        let result = ValueBoxKey(length: 4 + 8 + 4 + 4)
        result.setInt32(0, value: key.namespace)
        result.setInt64(4, value: key.id)
        result.setInt32(12, value: id.namespace)
        result.setInt32(16, value: id.id)
        return result
    }

    private static func singleKey(_ value: UInt8) -> ValueBoxKey {
        let result = ValueBoxKey(length: 1)
        result.setUInt8(0, value: value)
        return result
    }

    // MARK: Entry ids (also the keys of reactive views)

    public static func logEntryId(kind: MTAntiDeleteLogKind, peerId: PeerId) -> ItemCacheEntryId {
        return ItemCacheEntryId(collectionId: MTAntiDeleteIndexStore.logsCollection(kind), key: MTAntiDeleteIndexStore.peerKey(peerId))
    }

    public static func summaryEntryId(kind: MTAntiDeleteLogKind) -> ItemCacheEntryId {
        return ItemCacheEntryId(collectionId: MTAntiDeleteIndexStore.summariesCollection, key: MTAntiDeleteIndexStore.singleKey(kind.rawValue))
    }

    public static var bookmarksEntryId: ItemCacheEntryId {
        return ItemCacheEntryId(collectionId: MTAntiDeleteIndexStore.bookmarksCollection, key: MTAntiDeleteIndexStore.singleKey(0))
    }

    public static func archivedEntryId(_ id: MessageId) -> ItemCacheEntryId {
        return ItemCacheEntryId(collectionId: MTAntiDeleteIndexStore.archivedCollection, key: MTAntiDeleteIndexStore.messageKey(id))
    }

    // MARK: Read / write (inside a transaction)

    public static func readLog(_ transaction: Transaction, kind: MTAntiDeleteLogKind, peerId: PeerId) -> MTAntiDeletePeerLog {
        guard let entry = transaction.retrieveItemCacheEntry(id: MTAntiDeleteIndexStore.logEntryId(kind: kind, peerId: peerId)) else {
            return MTAntiDeletePeerLog()
        }
        return MTAntiDeletePeerLog(data: entry.data) ?? MTAntiDeletePeerLog()
    }

    static func writeLog(_ transaction: Transaction, kind: MTAntiDeleteLogKind, peerId: PeerId, log: MTAntiDeletePeerLog) {
        let id = MTAntiDeleteIndexStore.logEntryId(kind: kind, peerId: peerId)
        if log.isEmpty {
            transaction.removeItemCacheEntry(id: id)
        } else {
            transaction.putItemCacheEntry(id: id, entry: CodableEntry(data: log.encode()))
        }
    }

    public static func readSummary(_ transaction: Transaction, kind: MTAntiDeleteLogKind) -> MTAntiDeleteSummary {
        guard let entry = transaction.retrieveItemCacheEntry(id: MTAntiDeleteIndexStore.summaryEntryId(kind: kind)) else {
            return MTAntiDeleteSummary()
        }
        return MTAntiDeleteSummary(data: entry.data) ?? MTAntiDeleteSummary()
    }

    static func writeSummary(_ transaction: Transaction, kind: MTAntiDeleteLogKind, summary: MTAntiDeleteSummary) {
        let id = MTAntiDeleteIndexStore.summaryEntryId(kind: kind)
        if summary.peers.isEmpty {
            transaction.removeItemCacheEntry(id: id)
        } else {
            transaction.putItemCacheEntry(id: id, entry: CodableEntry(data: summary.encode()))
        }
    }

    public static func readBookmarks(_ transaction: Transaction) -> MTBookmarkList {
        guard let entry = transaction.retrieveItemCacheEntry(id: MTAntiDeleteIndexStore.bookmarksEntryId) else {
            return MTBookmarkList()
        }
        return MTBookmarkList(data: entry.data) ?? MTBookmarkList()
    }

    static func writeBookmarks(_ transaction: Transaction, list: MTBookmarkList) {
        if list.isEmpty {
            transaction.removeItemCacheEntry(id: MTAntiDeleteIndexStore.bookmarksEntryId)
        } else {
            transaction.putItemCacheEntry(id: MTAntiDeleteIndexStore.bookmarksEntryId, entry: CodableEntry(data: list.encode()))
        }
    }

    /// Bookmarks the list's cap pushed out lose their mark on the message too: a «🔖» that no list
    /// shows would be a bookmark the user can not find.
    static func deactivateBookmarks(_ transaction: Transaction, _ entries: [MTBookmarkEntry], now: Int32) {
        for entry in entries {
            transaction.updateMessage(MessageId(mtKey: entry.message), update: { current in
                let isActive = current.attributes.contains(where: { attribute in
                    return (attribute as? MTBookmarkMessageAttribute)?.isActive == true
                })
                if !isActive {
                    return .skip
                }
                return .update(mtStoreMessage(current, attributes: mtReplacingAttribute(current.attributes, with: MTBookmarkMessageAttribute(title: "", createdAt: now, isActive: false))))
            })
        }
    }

    public static func readArchived(_ transaction: Transaction, id: MessageId) -> MTAntiDeleteArchivedContent? {
        guard let entry = transaction.retrieveItemCacheEntry(id: MTAntiDeleteIndexStore.archivedEntryId(id)) else {
            return nil
        }
        return MTAntiDeleteArchivedContent(data: entry.data)
    }

    static func writeArchived(_ transaction: Transaction, id: MessageId, content: MTAntiDeleteArchivedContent?) {
        let entryId = MTAntiDeleteIndexStore.archivedEntryId(id)
        if let content {
            transaction.putItemCacheEntry(id: entryId, entry: CodableEntry(data: content.encode()))
        } else {
            transaction.removeItemCacheEntry(id: entryId)
        }
    }

    /// Adds entries of one chat and updates the summary. Returns the new summary and what the cap
    /// pushed out (their messages are deleted for real by the caller: nothing lists them anymore).
    @discardableResult
    static func apply(_ transaction: Transaction, kind: MTAntiDeleteLogKind, peerId: PeerId, entries: [MTAntiDeleteLogEntry], summary: inout MTAntiDeleteSummary) -> [MTAntiDeleteLogEntry] {
        var log = MTAntiDeleteIndexStore.readLog(transaction, kind: kind, peerId: peerId)
        let dropped = log.upsert(entries)
        MTAntiDeleteIndexStore.writeLog(transaction, kind: kind, peerId: peerId, log: log)
        summary.update(peer: peerId.mtKey, log: log)
        return dropped
    }

    /// Removes entries of one chat and updates the summary.
    static func remove(_ transaction: Transaction, kind: MTAntiDeleteLogKind, peerId: PeerId, refs: Set<MTAntiDeleteMessageRef>, summary: inout MTAntiDeleteSummary) {
        if refs.isEmpty {
            return
        }
        var log = MTAntiDeleteIndexStore.readLog(transaction, kind: kind, peerId: peerId)
        if log.remove(refs) == 0 {
            return
        }
        MTAntiDeleteIndexStore.writeLog(transaction, kind: kind, peerId: peerId, log: log)
        summary.update(peer: peerId.mtKey, log: log)
    }

    // MARK: Reactive reads (UI)

    public static func summarySignal(postbox: Postbox, kind: MTAntiDeleteLogKind) -> Signal<MTAntiDeleteSummary, NoError> {
        let key = PostboxViewKey.cachedItem(MTAntiDeleteIndexStore.summaryEntryId(kind: kind))
        return postbox.combinedView(keys: [key])
        |> map { views -> MTAntiDeleteSummary in
            guard let view = views.views[key] as? CachedItemView, let value = view.value else {
                return MTAntiDeleteSummary()
            }
            return MTAntiDeleteSummary(data: value.data) ?? MTAntiDeleteSummary()
        }
        |> distinctUntilChanged
    }

    public static func logSignal(postbox: Postbox, kind: MTAntiDeleteLogKind, peerId: PeerId) -> Signal<MTAntiDeletePeerLog, NoError> {
        let key = PostboxViewKey.cachedItem(MTAntiDeleteIndexStore.logEntryId(kind: kind, peerId: peerId))
        return postbox.combinedView(keys: [key])
        |> map { views -> MTAntiDeletePeerLog in
            guard let view = views.views[key] as? CachedItemView, let value = view.value else {
                return MTAntiDeletePeerLog()
            }
            return MTAntiDeletePeerLog(data: value.data) ?? MTAntiDeletePeerLog()
        }
        |> distinctUntilChanged
    }

    public static func bookmarksSignal(postbox: Postbox) -> Signal<MTBookmarkList, NoError> {
        let key = PostboxViewKey.cachedItem(MTAntiDeleteIndexStore.bookmarksEntryId)
        return postbox.combinedView(keys: [key])
        |> map { views -> MTBookmarkList in
            guard let view = views.views[key] as? CachedItemView, let value = view.value else {
                return MTBookmarkList()
            }
            return MTBookmarkList(data: value.data) ?? MTBookmarkList()
        }
        |> distinctUntilChanged
    }
}
