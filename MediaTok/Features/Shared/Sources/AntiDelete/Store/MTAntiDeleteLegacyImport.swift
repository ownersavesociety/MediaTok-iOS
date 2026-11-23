import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import MTCore

/// One-time import of what the legacy MediaTok kept (same bundle id, so its files are in place),
/// per account, off the main thread:
/// - an archived deletion becomes the MediaTok attribute of the very message it describes
///   (same chat, id, date and text) — never of another account's message with the same id;
///   without such a message it becomes an archive entry of a chat this account knows;
/// - previous versions, local edits, bookmarks go to their messages (replaced reactions are not
///   imported: the feature was removed on 2026-10-27; their files are only deleted).
/// The plain-text files (secret chat content included) are deleted once every account imported
/// them: from then on everything lives in the encrypted database of its account.
public enum MTAntiDeleteLegacyImport {
    private static let stashName = "mediatok_antidelete_legacy.bin"
    private static let chunkSize = 300

    private struct Sources {
        var deleted: [MTLegacyDeletedEntry] = []
        var edits: [MTLegacyEditEntry] = []
        var localEdits: [MTLegacyLocalEdit] = []
        var bookmarks: [MTLegacyBookmark] = []

        var isEmpty: Bool {
            return self.deleted.isEmpty && self.edits.isEmpty && self.localEdits.isEmpty && self.bookmarks.isEmpty
        }
    }

    private static var cachedSources: Sources?

    private static var documentsPath: String? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
    }

    private static var stashPath: String? {
        return MTAntiDeleteLegacyImport.documentsPath.map { $0 + "/" + MTAntiDeleteLegacyImport.stashName }
    }

    /// The global migration (main thread) hands over the UserDefaults blobs; they are written to
    /// the stash on the anti-delete queue and only then removed from UserDefaults.
    public static func stash(editHistory: Data?, archiveMirror: Data?, didStash: @escaping () -> Void) {
        let stash = MTAntiDeleteLegacyStash(editHistory: editHistory, archiveMirror: archiveMirror)
        if stash.isEmpty {
            didStash()
            return
        }
        MTAntiDeleteAccounts.shared.queue.justDispatch {
            guard let path = MTAntiDeleteLegacyImport.stashPath else {
                return
            }
            do {
                try stash.encode().write(to: URL(fileURLWithPath: path), options: [.atomic])
                didStash()
            } catch {
                MTLog.warning("antiDelete", "legacy stash failed, the old data stays in place")
            }
        }
    }

    private static func readFile(_ name: String) -> Data? {
        guard let documentsPath = MTAntiDeleteLegacyImport.documentsPath else {
            return nil
        }
        return try? Data(contentsOf: URL(fileURLWithPath: documentsPath + "/" + name))
    }

    /// Anti-delete queue.
    private static func loadSources() -> Sources {
        if let cached = MTAntiDeleteLegacyImport.cachedSources {
            return cached
        }
        var sources = Sources()
        var stash: MTAntiDeleteLegacyStash?
        if let path = MTAntiDeleteLegacyImport.stashPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            stash = MTAntiDeleteLegacyStash(data: data)
        }
        for name in MTAntiDeleteLegacyParser.deletedArchiveFiles {
            if let data = MTAntiDeleteLegacyImport.readFile(name) {
                let entries = MTAntiDeleteLegacyParser.deletedArchive(data)
                if !entries.isEmpty {
                    sources.deleted = entries
                    break
                }
            }
        }
        if sources.deleted.isEmpty, let mirror = stash?.archiveMirror {
            sources.deleted = MTAntiDeleteLegacyParser.deletedArchive(mirror)
        }
        if let editHistory = stash?.editHistory {
            sources.edits = MTAntiDeleteLegacyParser.editHistory(editHistory)
        }
        if let data = MTAntiDeleteLegacyImport.readFile(MTAntiDeleteLegacyParser.localEditsFile) {
            sources.localEdits = MTAntiDeleteLegacyParser.localEdits(data)
        }
        if let data = MTAntiDeleteLegacyImport.readFile(MTAntiDeleteLegacyParser.bookmarksFile) {
            sources.bookmarks = MTAntiDeleteLegacyParser.bookmarks(data)
        }
        MTAntiDeleteLegacyImport.cachedSources = sources
        return sources
    }

    /// Account start (app). Runs once per account; does nothing when there is nothing old.
    static func importIfNeeded(accountId: AccountRecordId, postbox: Postbox) {
        MTAntiDeleteAccounts.shared.queue.justDispatch {
            if MTAntiDeleteSettings.legacyImportDone.value(for: accountId.mt) {
                return
            }
            let sources = MTAntiDeleteLegacyImport.loadSources()
            if sources.isEmpty {
                MTAntiDeleteSettings.legacyImportDone.set(true, for: accountId.mt)
                MTAntiDeleteLegacyImport.removeFilesIfEveryAccountImported()
                return
            }
            // Read here, not inside a transaction (a directory listing).
            let isSingleAccount = MTLegacyAccounts.isSingleAccount
            var signals: [Signal<Never, NoError>] = []
            var offset = 0
            while offset < sources.deleted.count {
                let chunk = Array(sources.deleted[offset ..< min(offset + MTAntiDeleteLegacyImport.chunkSize, sources.deleted.count)])
                signals.append(postbox.transaction { transaction -> Void in
                    MTAntiDeleteLegacyImport.importDeleted(transaction, entries: chunk)
                } |> ignoreValues)
                offset += MTAntiDeleteLegacyImport.chunkSize
            }
            signals.append(postbox.transaction { transaction -> Void in
                MTAntiDeleteLegacyImport.importOthers(transaction, sources: sources, isSingleAccount: isSingleAccount)
            } |> ignoreValues)

            var chain: Signal<Never, NoError> = .complete()
            for signal in signals {
                chain = chain |> then(signal)
            }
            let _ = (chain |> deliverOn(MTAntiDeleteAccounts.shared.queue)).start(completed: {
                MTAntiDeleteSettings.legacyImportDone.set(true, for: accountId.mt)
                MTLog.info("antiDelete", "legacy archive imported into an account")
                // Summaries changed under the account: reload them.
                let _ = (postbox.transaction { transaction -> [MTAntiDeleteLogKind: MTAntiDeleteSummary] in
                    var result: [MTAntiDeleteLogKind: MTAntiDeleteSummary] = [:]
                    for kind in MTAntiDeleteLogKind.allCases {
                        result[kind] = MTAntiDeleteIndexStore.readSummary(transaction, kind: kind)
                    }
                    return result
                } |> deliverOn(MTAntiDeleteAccounts.shared.queue)).start(next: { summaries in
                    MTAntiDeleteAccounts.shared.updateSummaries(account: accountId, summaries, flushedPeers: [])
                    MTAntiDeleteLegacyImport.removeFilesIfEveryAccountImported()
                })
            })
        }
    }

    /// The message an old record describes in this account, if it is really that message.
    private static func matchingMessage(_ transaction: Transaction, peerId: PeerId, id: Int32, timestamp: Int32, text: String) -> Message? {
        let namespaces: [MessageId.Namespace]
        if peerId.namespace == Namespaces.Peer.SecretChat {
            namespaces = [Namespaces.Message.SecretIncoming, Namespaces.Message.Local]
        } else {
            namespaces = [Namespaces.Message.Cloud]
        }
        for namespace in namespaces {
            guard let message = transaction.getMessage(MessageId(peerId: peerId, namespace: namespace, id: id)) else {
                continue
            }
            if timestamp != 0 && message.timestamp != timestamp {
                continue
            }
            if !text.isEmpty && message.text != text {
                continue
            }
            return message
        }
        return nil
    }

    private static func importDeleted(_ transaction: Transaction, entries: [MTLegacyDeletedEntry]) {
        var summary = MTAntiDeleteIndexStore.readSummary(transaction, kind: .deleted)
        var byPeer: [PeerId: [MTAntiDeleteLogEntry]] = [:]
        for entry in entries {
            let peerId = PeerId(mtKey: entry.peer)
            // Only chats this account knows: the old archive mixed all accounts.
            if transaction.getPeer(peerId) == nil {
                continue
            }
            let deletedAt = entry.deletedAt != 0 ? entry.deletedAt : entry.timestamp
            if let message = MTAntiDeleteLegacyImport.matchingMessage(transaction, peerId: peerId, id: entry.messageId, timestamp: entry.timestamp, text: entry.text) {
                if !message.mtIsDeleted {
                    transaction.updateMessage(message.id, update: { current in
                        return .update(mtStoreMessage(current, attributes: mtReplacingAttribute(current.attributes, with: MTDeletedMessageAttribute(deletedAt: deletedAt, source: .imported))))
                    })
                }
                byPeer[peerId, default: []].append(MTAntiDeleteLogEntry(namespace: message.id.namespace, id: message.id.id, threadId: message.threadId, time: deletedAt, source: MTAntiDeleteSource.imported.rawValue, isOutgoing: !message.flags.contains(.Incoming)))
            } else {
                let id = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: entry.messageId)
                if transaction.getMessage(id) != nil {
                    // A live message with the same id but other content: not ours to mark.
                    continue
                }
                MTAntiDeleteIndexStore.writeArchived(transaction, id: id, content: MTAntiDeleteArchivedContent(date: entry.timestamp, deletedAt: deletedAt, authorName: entry.authorName, authorUsername: entry.authorUsername, text: entry.text, mediaDescription: entry.mediaDescription))
                byPeer[peerId, default: []].append(MTAntiDeleteLogEntry(namespace: id.namespace, id: id.id, threadId: entry.threadId, time: deletedAt, source: MTAntiDeleteSource.imported.rawValue, isArchiveOnly: true))
            }
        }
        for (peerId, logEntries) in byPeer {
            MTAntiDeleteIndexStore.apply(transaction, kind: .deleted, peerId: peerId, entries: logEntries, summary: &summary)
        }
        MTAntiDeleteIndexStore.writeSummary(transaction, kind: .deleted, summary: summary)
    }

    /// Whether a message id names the same message in every account: channels (and supergroups) number
    /// their messages themselves; private chats, basic groups and secret chats use the account's own
    /// counter, so the same id in another account is another message.
    private static func idIsSharedByAccounts(_ id: MessageId) -> Bool {
        return id.peerId.namespace == Namespaces.Peer.CloudChannel
    }

    /// The old edit records carry no date or text of the message itself: in a chat with per-account ids
    /// and several accounts, only a message that was edited and already existed at the first recorded
    /// edit can be the one (the device clock may be behind the server: 15 minutes of slack).
    private static func mayBeRecordedEditedMessage(_ message: Message, firstEditDate: Int32) -> Bool {
        if !message.attributes.contains(where: { $0 is EditedMessageAttribute }) {
            return false
        }
        if firstEditDate != 0 && message.timestamp > firstEditDate + 15 * 60 {
            return false
        }
        return true
    }

    private static func importOthers(_ transaction: Transaction, sources: Sources, isSingleAccount: Bool) {
        let now = Int32(Date().timeIntervalSince1970)

        var editedSummary = MTAntiDeleteIndexStore.readSummary(transaction, kind: .edited)
        var editedByPeer: [PeerId: [MTAntiDeleteLogEntry]] = [:]
        for entry in sources.edits {
            let id = MessageId(mtKey: entry.message)
            guard transaction.getPeer(id.peerId) != nil, let message = transaction.getMessage(id) else {
                continue
            }
            if !isSingleAccount && !MTAntiDeleteLegacyImport.idIsSharedByAccounts(id) && !MTAntiDeleteLegacyImport.mayBeRecordedEditedMessage(message, firstEditDate: entry.versions.first?.date ?? 0) {
                // Another account's message with the same id: not ours to attach versions to.
                continue
            }
            if MTAntiDeleteMessageState(attributes: message.attributes).history != nil {
                continue
            }
            let history = MTEditHistoryMessageAttribute(versions: entry.versions.map { MTEditVersion(text: $0.text, entities: [], date: $0.date, mediaDescription: nil) })
            transaction.updateMessage(id, update: { current in
                return .update(mtStoreMessage(current, attributes: mtReplacingAttribute(current.attributes, with: history)))
            })
            editedByPeer[id.peerId, default: []].append(MTAntiDeleteLogEntry(namespace: id.namespace, id: id.id, threadId: message.threadId, time: entry.versions.last?.date ?? message.timestamp, count: Int32(history.versions.count), isOutgoing: !message.flags.contains(.Incoming)))
        }
        for (peerId, entries) in editedByPeer {
            MTAntiDeleteIndexStore.apply(transaction, kind: .edited, peerId: peerId, entries: entries, summary: &editedSummary)
        }
        MTAntiDeleteIndexStore.writeSummary(transaction, kind: .edited, summary: editedSummary)

        for entry in sources.localEdits {
            let id = MessageId(mtKey: entry.message)
            // A local edit keeps only its new text: nothing to check the message against. With several
            // accounts it is taken only where ids are the same message in every account.
            if !isSingleAccount && !MTAntiDeleteLegacyImport.idIsSharedByAccounts(id) {
                continue
            }
            guard transaction.getPeer(id.peerId) != nil, let message = transaction.getMessage(id) else {
                continue
            }
            if MTAntiDeleteMessageState(attributes: message.attributes).localEdit != nil {
                continue
            }
            transaction.updateMessage(id, update: { current in
                return .update(mtStoreMessage(current, attributes: mtReplacingAttribute(current.attributes, with: MTLocalEditMessageAttribute(text: entry.text, entities: [], date: now, isActive: true))))
            })
        }

        var bookmarks = MTAntiDeleteIndexStore.readBookmarks(transaction)
        var evicted: [MTBookmarkEntry] = []
        for entry in sources.bookmarks {
            let id = MessageId(mtKey: entry.message)
            if entry.messageDate == 0 && !isSingleAccount && !MTAntiDeleteLegacyImport.idIsSharedByAccounts(id) {
                // No date to check the message against, and the id may be another account's message.
                continue
            }
            guard transaction.getPeer(id.peerId) != nil, let message = transaction.getMessage(id) else {
                continue
            }
            if entry.messageDate != 0 && message.timestamp != entry.messageDate {
                continue
            }
            let createdAt = entry.createdAt != 0 ? entry.createdAt : now
            transaction.updateMessage(id, update: { current in
                return .update(mtStoreMessage(current, attributes: mtReplacingAttribute(current.attributes, with: MTBookmarkMessageAttribute(title: entry.title, createdAt: createdAt, isActive: true))))
            })
            evicted.append(contentsOf: bookmarks.set(MTBookmarkEntry(message: entry.message, threadId: message.threadId, title: entry.title, createdAt: createdAt, messageDate: message.timestamp)))
        }
        // Over the cap: the oldest lose their mark as well (a later import may bring one back, so only
        // what is not in the list in the end).
        let kept = Set(bookmarks.entries.map(\.message))
        MTAntiDeleteIndexStore.deactivateBookmarks(transaction, evicted.filter { !kept.contains($0.message) }, now: now)
        MTAntiDeleteIndexStore.writeBookmarks(transaction, list: bookmarks)
    }

    /// Deletes the old plain-text files once no registered account still needs them.
    private static func removeFilesIfEveryAccountImported() {
        for account in MTSettingsStore.shared.registeredAccounts where !MTAntiDeleteSettings.legacyImportDone.value(for: account) {
            return
        }
        guard let documentsPath = MTAntiDeleteLegacyImport.documentsPath else {
            return
        }
        var names = MTAntiDeleteLegacyParser.deletedArchiveFiles
        names.append(MTAntiDeleteLegacyParser.localEditsFile)
        names.append(MTAntiDeleteLegacyParser.bookmarksFile)
        names.append(contentsOf: MTAntiDeleteLegacyParser.editedReactionsFiles)
        names.append(contentsOf: MTAntiDeleteLegacyParser.deletedReactionsFiles)
        names.append(MTAntiDeleteLegacyImport.stashName)
        for name in names {
            let path = documentsPath + "/" + name
            if FileManager.default.fileExists(atPath: path) {
                let _ = try? FileManager.default.removeItem(atPath: path)
            }
        }
        MTAntiDeleteLegacyImport.cachedSources = nil
    }
}
