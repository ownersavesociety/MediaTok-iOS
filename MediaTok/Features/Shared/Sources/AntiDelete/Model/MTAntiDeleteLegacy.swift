import Foundation
import MTCore

// Readers of what the legacy MediaTok left behind (same bundle id, so its files are in place):
//   Documents/mediatok_deleted_archive.json   [ArchivedMessage]
//   Documents/mediatok_local_edits.json       ["<peer toInt64>_<id>": [text]]
//   Documents/mediatok_message_bookmarks.json [MessageBookmark]
//   Documents/mediatok_edited_reactions.json  (not read: the feature was removed; deleted only)
//   UserDefaults mediatok_edit_history        ["<peer toInt64>_<id>": [{text, editDate}]]
// Every reader is lenient: a damaged element is skipped, never the whole file. Peers were stored
// as `PeerId.toInt64()`, message namespaces not at all (the old code kept cloud messages).

public struct MTLegacyDeletedEntry: Equatable {
    public let peer: MTPeerKey
    public let messageId: Int32
    public let timestamp: Int32
    public let deletedAt: Int32
    public let authorName: String?
    public let authorUsername: String?
    public let text: String
    public let mediaDescription: String?
    public let threadId: Int64?
}

public struct MTLegacyEditVersion: Equatable {
    public let text: String
    public let date: Int32
}

public struct MTLegacyEditEntry: Equatable {
    public let message: MTMessageKey
    /// Oldest first.
    public let versions: [MTLegacyEditVersion]
}

public struct MTLegacyLocalEdit: Equatable {
    public let message: MTMessageKey
    /// The latest local version (legacy format showed only the last one).
    public let text: String
}

public struct MTLegacyBookmark: Equatable {
    public let message: MTMessageKey
    public let title: String
    public let messageDate: Int32
    public let createdAt: Int32
}

public enum MTAntiDeleteLegacyParser {
    /// File names in the old app's Documents directory.
    public static let deletedArchiveFiles = ["mediatok_deleted_archive.json", "mediatok_deleted_archive.backup.json"]
    public static let localEditsFile = "mediatok_local_edits.json"
    public static let bookmarksFile = "mediatok_message_bookmarks.json"
    /// Reactions of legacy format: removed without import (the feature is gone since 2026-10-27).
    public static let editedReactionsFiles = ["mediatok_edited_reactions.json", "mediatok_edited_reactions.backup.json"]
    public static let deletedReactionsFiles = ["mediatok_deleted_reactions.json", "mediatok_deleted_reactions.backup.json"]

    private static func array(_ data: Data) -> [[String: Any]] {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return []
        }
        return (object as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private static func dictionary(_ data: Data) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return [:]
        }
        return object as? [String: Any] ?? [:]
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let string = value as? String {
            return Int64(string)
        }
        return nil
    }

    private static func int32(_ value: Any?) -> Int32? {
        guard let value = int64(value) else {
            return nil
        }
        return Int32(exactly: value)
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    /// `mediatok_deleted_archive.json`. Duplicates (same chat and id) keep the first entry.
    public static func deletedArchive(_ data: Data) -> [MTLegacyDeletedEntry] {
        var result: [MTLegacyDeletedEntry] = []
        var seen = Set<MTMessageKey>()
        for item in array(data) {
            guard let peerValue = int64(item["peerId"]), let messageId = int32(item["messageId"]) else {
                continue
            }
            let peer = MTLegacyKeys.peerKey(fromLegacyInt64: peerValue)
            let key = MTMessageKey(peer: peer, namespace: 0, id: messageId)
            if !seen.insert(key).inserted {
                continue
            }
            let text = item["text"] as? String ?? ""
            let entry = MTLegacyDeletedEntry(
                peer: peer,
                messageId: messageId,
                timestamp: int32(item["timestamp"]) ?? 0,
                deletedAt: int32(item["deletedAt"]) ?? 0,
                authorName: string(item["authorName"]),
                authorUsername: string(item["authorUsername"]),
                text: text,
                mediaDescription: string(item["mediaDescription"]),
                threadId: int64(item["threadId"])
            )
            result.append(entry)
        }
        return result
    }

    /// `mediatok_edit_history` (UserDefaults data).
    public static func editHistory(_ data: Data) -> [MTLegacyEditEntry] {
        var result: [MTLegacyEditEntry] = []
        for (key, value) in dictionary(data) {
            guard let message = MTLegacyKeys.messageKey(fromLegacyString: key), let records = value as? [Any] else {
                continue
            }
            var versions: [MTLegacyEditVersion] = []
            for case let record as [String: Any] in records {
                guard let text = record["text"] as? String else {
                    continue
                }
                versions.append(MTLegacyEditVersion(text: text, date: int32(record["editDate"]) ?? 0))
            }
            if versions.isEmpty {
                continue
            }
            versions.sort(by: { $0.date < $1.date })
            result.append(MTLegacyEditEntry(message: message, versions: versions))
        }
        result.sort(by: { $0.message < $1.message })
        return result
    }

    /// `mediatok_local_edits.json`.
    public static func localEdits(_ data: Data) -> [MTLegacyLocalEdit] {
        var result: [MTLegacyLocalEdit] = []
        for (key, value) in dictionary(data) {
            guard let message = MTLegacyKeys.messageKey(fromLegacyString: key), let versions = value as? [Any] else {
                continue
            }
            guard let text = versions.compactMap({ $0 as? String }).last, !text.isEmpty else {
                continue
            }
            result.append(MTLegacyLocalEdit(message: message, text: text))
        }
        result.sort(by: { $0.message < $1.message })
        return result
    }

    /// `mediatok_message_bookmarks.json`.
    public static func bookmarks(_ data: Data) -> [MTLegacyBookmark] {
        var result: [MTLegacyBookmark] = []
        var seen = Set<MTMessageKey>()
        for item in array(data) {
            guard let peerValue = int64(item["peerId"]), let namespace = int32(item["namespace"]), let id = int32(item["id"]) else {
                continue
            }
            let message = MTMessageKey(peer: MTLegacyKeys.peerKey(fromLegacyInt64: peerValue), namespace: namespace, id: id)
            if !seen.insert(message).inserted {
                continue
            }
            let createdAt: Int32
            if let value = item["createdAt"] as? NSNumber {
                createdAt = Int32(clamping: Int64(value.doubleValue))
            } else {
                createdAt = 0
            }
            result.append(MTLegacyBookmark(message: message, title: item["title"] as? String ?? "", messageDate: int32(item["timestamp"]) ?? 0, createdAt: createdAt))
        }
        return result
    }
}

/// UserDefaults blobs of legacy format, moved out of UserDefaults by the global migration and
/// imported per account later (off the main thread). Plain JSON in the app's own container,
/// removed as soon as every account has imported it.
public struct MTAntiDeleteLegacyStash: Equatable {
    public var editHistory: Data?
    public var archiveMirror: Data?

    public init(editHistory: Data?, archiveMirror: Data?) {
        self.editHistory = editHistory
        self.archiveMirror = archiveMirror
    }

    public var isEmpty: Bool {
        return self.editHistory == nil && self.archiveMirror == nil
    }

    public func encode() -> Data {
        var writer = MTBinaryWriter()
        writer.writeUInt8(1)
        writer.writeOptionalString(self.editHistory.map { $0.base64EncodedString() })
        writer.writeOptionalString(self.archiveMirror.map { $0.base64EncodedString() })
        return writer.data
    }

    public init?(data: Data) {
        var reader = MTBinaryReader(data)
        guard let version = reader.readUInt8(), version == 1 else {
            return nil
        }
        guard let editHistory = reader.readOptionalString(), let archiveMirror = reader.readOptionalString() else {
            return nil
        }
        self.editHistory = editHistory.flatMap { Data(base64Encoded: $0) }
        self.archiveMirror = archiveMirror.flatMap { Data(base64Encoded: $0) }
    }
}
