import Foundation
import SwiftSignalKit

public enum GGVisualBadgeMode: Int, Codable, Equatable, CaseIterable {
    case `default` = 0
    case verified = 1
    case premium = 2
    case scam = 3
    case fake = 4
    case hide = 5
}

public struct GGVisualPeerOverride: Codable, Equatable, GGSettingValue {
    public var name: String
    public var username: String
    public var alsoUsernames: String
    public var bio: String
    public var phone: String
    public var badgeMode: GGVisualBadgeMode
    public var avatarFileName: String
    public var avatarWidth: Int
    public var avatarHeight: Int
    public var avatarFileId: Int64

    public init(
        name: String = "",
        username: String = "",
        alsoUsernames: String = "",
        bio: String = "",
        phone: String = "",
        badgeMode: GGVisualBadgeMode = .default,
        avatarFileName: String = "",
        avatarWidth: Int = 0,
        avatarHeight: Int = 0,
        avatarFileId: Int64 = 0
    ) {
        self.name = name
        self.username = username
        self.alsoUsernames = alsoUsernames
        self.bio = bio
        self.phone = phone
        self.badgeMode = badgeMode
        self.avatarFileName = avatarFileName
        self.avatarWidth = avatarWidth
        self.avatarHeight = avatarHeight
        self.avatarFileId = avatarFileId
    }

    public var isEmpty: Bool {
        return self.name.isEmpty
            && self.username.isEmpty
            && self.alsoUsernames.isEmpty
            && self.bio.isEmpty
            && self.phone.isEmpty
            && self.badgeMode == .default
            && self.avatarFileName.isEmpty
    }
}

public struct GGVisualAvatarInfo: Equatable {
    public let url: URL
    public let width: Int
    public let height: Int
    public let fileId: Int64

    public init(url: URL, width: Int, height: Int, fileId: Int64) {
        self.url = url
        self.width = width
        self.height = height
        self.fileId = fileId
    }
}

public final class GGVisualProfileStore {
    public static let shared = GGVisualProfileStore()

    private let lock = GGUnfairLock()
    private var loaded = false
    private var entries: [String: GGVisualPeerOverride] = [:]
    private var touchedKeys: Set<GGPeerKey> = []
    private var revisionValue: Int32 = 0
    private let revisionPromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    private var fileIdToPath: [Int64: String] = [:]

    private init() {}

    public var revisionSignal: Signal<Int32, NoError> {
        return self.revisionPromise.get()
    }

    public var currentRevision: Int32 {
        return self.lock.withLock {
            return self.revisionValue
        }
    }

    public var trackedPeerKeys: Set<GGPeerKey> {
        return self.lock.withLock {
            self.ensureLoadedLocked()
            return self.touchedKeys
        }
    }

    private func rootDirectoryPathLocked() -> String {
        if let env = GGCore.environment {
            return env.ghostgramPath
        }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("ghostgram")
    }

    private func configFileURL() -> URL {
        return URL(fileURLWithPath: (self.rootDirectoryPathLocked() as NSString).appendingPathComponent("visual_profiles.json"))
    }

    private func avatarsDirectoryURL() -> URL {
        return URL(fileURLWithPath: (self.rootDirectoryPathLocked() as NSString).appendingPathComponent("visual_avatars"), isDirectory: true)
    }

    private func ensureLoadedLocked() {
        if self.loaded {
            return
        }
        self.loaded = true
        let url = self.configFileURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: GGVisualPeerOverride].self, from: data) else {
            return
        }
        self.entries = decoded
        for (rawKey, item) in decoded {
            if let key = GGPeerKey(string: rawKey) {
                self.touchedKeys.insert(key)
            }
            if !item.avatarFileName.isEmpty && item.avatarFileId != 0 {
                let avatarURL = self.avatarsDirectoryURL().appendingPathComponent(item.avatarFileName)
                if FileManager.default.fileExists(atPath: avatarURL.path) {
                    self.fileIdToPath[item.avatarFileId] = avatarURL.path
                }
            }
        }
    }

    private func persistLocked() {
        let dir = URL(fileURLWithPath: self.rootDirectoryPathLocked(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(self.entries) {
            try? data.write(to: self.configFileURL(), options: [.atomic])
        }
    }

    private func notifyLocked(touched key: GGPeerKey?) {
        if let key {
            self.touchedKeys.insert(key)
        }
        self.revisionValue = self.revisionValue &+ 1
        let next = self.revisionValue
        self.revisionPromise.set(next)
    }

    private func removeAvatarFilesLocked(for peerKey: GGPeerKey, keepingFileName: String?) {
        let dir = self.avatarsDirectoryURL()
        let prefix = "avatar_\(peerKey.namespace)_\(peerKey.id)_"
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return
        }
        for name in items {
            if name.hasPrefix(prefix) && name != keepingFileName {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    public func allOverrides() -> [(key: GGPeerKey, value: GGVisualPeerOverride)] {
        return self.lock.withLock {
            self.ensureLoadedLocked()
            return self.entries.compactMap { rawKey, value in
                guard let key = GGPeerKey(string: rawKey), !value.isEmpty else {
                    return nil
                }
                return (key, value)
            }
            .sorted { $0.key < $1.key }
        }
    }

    public func override(for peerKey: GGPeerKey) -> GGVisualPeerOverride? {
        return self.lock.withLock {
            self.ensureLoadedLocked()
            return self.entries[peerKey.stringValue]
        }
    }

    public func setOverride(_ override: GGVisualPeerOverride, for peerKey: GGPeerKey) {
        self.lock.withLock {
            self.ensureLoadedLocked()
            let keyStr = peerKey.stringValue
            let existing = self.entries[keyStr]
            if override.isEmpty {
                if let oldFileId = existing?.avatarFileId, oldFileId != 0 {
                    self.fileIdToPath.removeValue(forKey: oldFileId)
                }
                self.removeAvatarFilesLocked(for: peerKey, keepingFileName: nil)
                self.entries.removeValue(forKey: keyStr)
            } else {
                var normalized = override
                let mainList = GGVisualProfileStore.splitUsernames(override.username)
                var alsoList = [String]()
                let mainToken = mainList.first ?? ""
                if mainList.count > 1 {
                    alsoList.append(contentsOf: mainList.dropFirst())
                }
                for item in GGVisualProfileStore.splitUsernames(override.alsoUsernames) {
                    if item.lowercased() != mainToken.lowercased() && !alsoList.contains(where: { $0.lowercased() == item.lowercased() }) {
                        alsoList.append(item)
                    }
                }
                normalized.name = override.name.trimmingCharacters(in: .whitespacesAndNewlines)
                normalized.username = mainToken
                normalized.alsoUsernames = alsoList.joined(separator: ", ")
                normalized.bio = override.bio.trimmingCharacters(in: .whitespacesAndNewlines)
                normalized.phone = override.phone.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.avatarFileName.isEmpty, let oldFileId = existing?.avatarFileId, oldFileId != 0 {
                    self.fileIdToPath.removeValue(forKey: oldFileId)
                    self.removeAvatarFilesLocked(for: peerKey, keepingFileName: nil)
                }
                self.entries[keyStr] = normalized
            }
            self.persistLocked()
            self.notifyLocked(touched: peerKey)
        }
    }

    @discardableResult
    public func saveAvatarData(_ data: Data, width: Int, height: Int, for peerKey: GGPeerKey) -> GGVisualAvatarInfo? {
        return self.lock.withLock {
            self.ensureLoadedLocked()
            let dir = self.avatarsDirectoryURL()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileId = -abs(Int64(Date().timeIntervalSince1970 * 1000.0) &* 1009 &+ Int64.random(in: 1 ... 999))
            let fileName = "avatar_\(peerKey.namespace)_\(peerKey.id)_\(abs(fileId)).jpg"
            let url = dir.appendingPathComponent(fileName)
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                GGLog.error("visualProfile", "save avatar failed: \(error.localizedDescription)")
                return nil
            }
            var cur = self.entries[peerKey.stringValue] ?? GGVisualPeerOverride()
            if cur.avatarFileId != 0 {
                self.fileIdToPath.removeValue(forKey: cur.avatarFileId)
            }
            cur.avatarFileName = fileName
            cur.avatarWidth = max(1, width)
            cur.avatarHeight = max(1, height)
            cur.avatarFileId = fileId
            self.entries[peerKey.stringValue] = cur
            self.fileIdToPath[fileId] = url.path
            self.removeAvatarFilesLocked(for: peerKey, keepingFileName: fileName)
            self.persistLocked()
            self.notifyLocked(touched: peerKey)
            return GGVisualAvatarInfo(url: url, width: cur.avatarWidth, height: cur.avatarHeight, fileId: fileId)
        }
    }

    public func removeAvatar(for peerKey: GGPeerKey) {
        self.lock.withLock {
            self.ensureLoadedLocked()
            let keyStr = peerKey.stringValue
            guard var cur = self.entries[keyStr] else {
                return
            }
            if cur.avatarFileId != 0 {
                self.fileIdToPath.removeValue(forKey: cur.avatarFileId)
            }
            self.removeAvatarFilesLocked(for: peerKey, keepingFileName: nil)
            cur.avatarFileName = ""
            cur.avatarWidth = 0
            cur.avatarHeight = 0
            cur.avatarFileId = 0
            if cur.isEmpty {
                self.entries.removeValue(forKey: keyStr)
            } else {
                self.entries[keyStr] = cur
            }
            self.persistLocked()
            self.notifyLocked(touched: peerKey)
        }
    }

    // MARK: - Query helpers

    public func name(for peerKey: GGPeerKey) -> String? {
        guard let v = self.override(for: peerKey)?.name, !v.isEmpty else {
            return nil
        }
        return v
    }

    public func bio(for peerKey: GGPeerKey) -> String? {
        guard let v = self.override(for: peerKey)?.bio, !v.isEmpty else {
            return nil
        }
        return v
    }

    public func phone(for peerKey: GGPeerKey) -> String? {
        guard let v = self.override(for: peerKey)?.phone, !v.isEmpty else {
            return nil
        }
        return v
    }

    public func badgeMode(for peerKey: GGPeerKey) -> GGVisualBadgeMode {
        return self.override(for: peerKey)?.badgeMode ?? .default
    }

    public func resolveBadges(
        for peerKey: GGPeerKey,
        isVerified: Bool,
        isPremium: Bool,
        isScam: Bool,
        isFake: Bool
    ) -> (verified: Bool, premium: Bool, scam: Bool, fake: Bool, allowEmojiStatus: Bool) {
        switch self.badgeMode(for: peerKey) {
        case .default:
            return (isVerified, isPremium, isScam, isFake, true)
        case .verified:
            return (true, isPremium, false, false, true)
        case .premium:
            return (isVerified, true, false, false, false)
        case .scam:
            return (false, false, true, false, false)
        case .fake:
            return (false, false, false, true, false)
        case .hide:
            return (false, false, false, false, false)
        }
    }

    public func avatarInfo(for peerKey: GGPeerKey) -> GGVisualAvatarInfo? {
        return self.lock.withLock {
            self.ensureLoadedLocked()
            guard let item = self.entries[peerKey.stringValue],
                  !item.avatarFileName.isEmpty,
                  item.avatarFileId != 0 else {
                return nil
            }
            let url = self.avatarsDirectoryURL().appendingPathComponent(item.avatarFileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            self.fileIdToPath[item.avatarFileId] = url.path
            return GGVisualAvatarInfo(url: url, width: max(1, item.avatarWidth), height: max(1, item.avatarHeight), fileId: item.avatarFileId)
        }
    }

    public func hasAvatar(for peerKey: GGPeerKey) -> Bool {
        return self.avatarInfo(for: peerKey) != nil
    }

    public func avatarPath(matchingFileId fileId: Int64) -> String? {
        if fileId == 0 {
            return nil
        }
        return self.lock.withLock {
            self.ensureLoadedLocked()
            if let path = self.fileIdToPath[fileId], FileManager.default.fileExists(atPath: path) {
                return path
            }
            return nil
        }
    }

    // MARK: - Usernames

    public static func normalizeUsername(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://t.me/", "http://t.me/", "t.me/"] {
            if s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        while s.hasPrefix("@") || s.hasPrefix("/") {
            s.removeFirst()
        }
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func splitUsernames(_ raw: String) -> [String] {
        let separators = CharacterSet(charactersIn: " ,;\n\r\t")
        var seen = Set<String>()
        var result = [String]()
        for part in raw.components(separatedBy: separators) {
            let clean = self.normalizeUsername(part)
            guard !clean.isEmpty else {
                continue
            }
            let lower = clean.lowercased()
            if seen.insert(lower).inserted {
                result.append(clean)
            }
        }
        return result
    }

    public func resolveMainUsername(for peerKey: GGPeerKey, realMain: String?) -> String? {
        guard let ov = self.override(for: peerKey) else {
            return realMain
        }
        let mainTokens = GGVisualProfileStore.splitUsernames(ov.username)
        if let first = mainTokens.first {
            return first
        }
        if let realMain, !realMain.isEmpty {
            return realMain
        }
        let alsoTokens = GGVisualProfileStore.splitUsernames(ov.alsoUsernames)
        return alsoTokens.first ?? realMain
    }

    public func resolveAdditionalUsernames(for peerKey: GGPeerKey, realActive: [String], resolvedMain: String?) -> [String] {
        var result = [String]()
        var seen = Set<String>()
        if let mainLower = resolvedMain?.lowercased(), !mainLower.isEmpty {
            seen.insert(mainLower)
        }
        for name in realActive {
            let lower = name.lowercased()
            if !lower.isEmpty && seen.insert(lower).inserted {
                result.append(name)
            }
        }
        if let ov = self.override(for: peerKey) {
            for token in GGVisualProfileStore.splitUsernames(ov.username).dropFirst() + GGVisualProfileStore.splitUsernames(ov.alsoUsernames) {
                let lower = token.lowercased()
                if seen.insert(lower).inserted {
                    result.append(token)
                }
            }
        }
        return result
    }

    public func isVisualOnlyUsername(_ rawUsername: String, for peerKey: GGPeerKey) -> Bool {
        let clean = GGVisualProfileStore.normalizeUsername(rawUsername).lowercased()
        guard !clean.isEmpty, let ov = self.override(for: peerKey) else {
            return false
        }
        let all = GGVisualProfileStore.splitUsernames(ov.username) + GGVisualProfileStore.splitUsernames(ov.alsoUsernames)
        return all.contains { $0.lowercased() == clean }
    }
}
