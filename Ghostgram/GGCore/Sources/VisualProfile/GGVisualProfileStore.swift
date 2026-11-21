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
    public var avatarVideoFileName: String
    public var avatarVideoFileId: Int64
    public var remotePhotoUrl: String
    public var remoteVideoUrl: String
    public var remoteUpdatedAt: Int64

    private enum CodingKeys: String, CodingKey {
        case name
        case username
        case alsoUsernames
        case bio
        case phone
        case badgeMode
        case avatarFileName
        case avatarWidth
        case avatarHeight
        case avatarFileId
        case avatarVideoFileName
        case avatarVideoFileId
        case remotePhotoUrl
        case remoteVideoUrl
        case remoteUpdatedAt
    }

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
        avatarFileId: Int64 = 0,
        avatarVideoFileName: String = "",
        avatarVideoFileId: Int64 = 0,
        remotePhotoUrl: String = "",
        remoteVideoUrl: String = "",
        remoteUpdatedAt: Int64 = 0
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
        self.avatarVideoFileName = avatarVideoFileName
        self.avatarVideoFileId = avatarVideoFileId
        self.remotePhotoUrl = remotePhotoUrl
        self.remoteVideoUrl = remoteVideoUrl
        self.remoteUpdatedAt = remoteUpdatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.alsoUsernames = try c.decodeIfPresent(String.self, forKey: .alsoUsernames) ?? ""
        self.bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        self.phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        self.badgeMode = try c.decodeIfPresent(GGVisualBadgeMode.self, forKey: .badgeMode) ?? .default
        self.avatarFileName = try c.decodeIfPresent(String.self, forKey: .avatarFileName) ?? ""
        self.avatarWidth = try c.decodeIfPresent(Int.self, forKey: .avatarWidth) ?? 0
        self.avatarHeight = try c.decodeIfPresent(Int.self, forKey: .avatarHeight) ?? 0
        self.avatarFileId = try c.decodeIfPresent(Int64.self, forKey: .avatarFileId) ?? 0
        self.avatarVideoFileName = try c.decodeIfPresent(String.self, forKey: .avatarVideoFileName) ?? ""
        self.avatarVideoFileId = try c.decodeIfPresent(Int64.self, forKey: .avatarVideoFileId) ?? 0
        self.remotePhotoUrl = try c.decodeIfPresent(String.self, forKey: .remotePhotoUrl) ?? ""
        self.remoteVideoUrl = try c.decodeIfPresent(String.self, forKey: .remoteVideoUrl) ?? ""
        self.remoteUpdatedAt = try c.decodeIfPresent(Int64.self, forKey: .remoteUpdatedAt) ?? 0
    }

    public var isEmpty: Bool {
        return self.name.isEmpty
            && self.username.isEmpty
            && self.alsoUsernames.isEmpty
            && self.bio.isEmpty
            && self.phone.isEmpty
            && self.badgeMode == .default
            && self.avatarFileName.isEmpty
            && self.avatarVideoFileName.isEmpty
            && self.remotePhotoUrl.isEmpty
            && self.remoteVideoUrl.isEmpty
            && self.remoteUpdatedAt == 0
    }
}

public struct GGVisualAvatarInfo: Equatable {
    public let url: URL
    public let width: Int
    public let height: Int
    public let fileId: Int64
    public let videoUrl: URL?
    public let videoFileId: Int64

    public init(url: URL, width: Int, height: Int, fileId: Int64, videoUrl: URL? = nil, videoFileId: Int64 = 0) {
        self.url = url
        self.width = width
        self.height = height
        self.fileId = fileId
        self.videoUrl = videoUrl
        self.videoFileId = videoFileId
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
    private var fileIdToVideoPath: [Int64: String] = [:]
    private var lastGlobalCheckAt: [GGPeerKey: TimeInterval] = [:]

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
            if !item.avatarVideoFileName.isEmpty && item.avatarVideoFileId != 0 {
                let videoURL = self.avatarsDirectoryURL().appendingPathComponent(item.avatarVideoFileName)
                if FileManager.default.fileExists(atPath: videoURL.path) {
                    self.fileIdToVideoPath[item.avatarVideoFileId] = videoURL.path
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

    private func removeAvatarFilesLocked(for peerKey: GGPeerKey, keepingFileName: String?, keepingVideoName: String? = nil) {
        let dir = self.avatarsDirectoryURL()
        let photoPrefix = "avatar_\(peerKey.namespace)_\(peerKey.id)_"
        let videoPrefix = "avatar_vid_\(peerKey.namespace)_\(peerKey.id)_"
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return
        }
        for name in items {
            if name.hasPrefix(photoPrefix) && name != keepingFileName {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            } else if name.hasPrefix(videoPrefix) && name != keepingVideoName {
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
                if let oldVideoId = existing?.avatarVideoFileId, oldVideoId != 0 {
                    self.fileIdToVideoPath.removeValue(forKey: oldVideoId)
                }
                self.removeAvatarFilesLocked(for: peerKey, keepingFileName: nil, keepingVideoName: nil)
                GGVisualProfileStore.clearOwn4kTracking(for: keyStr)
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
                    if let oldVideoId = existing?.avatarVideoFileId, oldVideoId != 0 {
                        self.fileIdToVideoPath.removeValue(forKey: oldVideoId)
                    }
                    self.removeAvatarFilesLocked(for: peerKey, keepingFileName: nil, keepingVideoName: nil)
                }
                if normalized.avatarFileName.isEmpty {
                    GGVisualProfileStore.clearOwn4kTracking(for: keyStr)
                }
                if let existing, normalized.avatarFileId != 0, normalized.avatarFileId == existing.avatarFileId, normalized.remoteUpdatedAt < existing.remoteUpdatedAt {
                    normalized.remotePhotoUrl = existing.remotePhotoUrl
                    normalized.remoteVideoUrl = existing.remoteVideoUrl
                    normalized.remoteUpdatedAt = existing.remoteUpdatedAt
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
            if cur.avatarVideoFileId != 0 {
                self.fileIdToVideoPath.removeValue(forKey: cur.avatarVideoFileId)
            }
            cur.avatarFileName = fileName
            cur.avatarWidth = max(1, width)
            cur.avatarHeight = max(1, height)
            cur.avatarFileId = fileId
            cur.avatarVideoFileName = ""
            cur.avatarVideoFileId = 0
            cur.remoteUpdatedAt = Int64(Date().timeIntervalSince1970)
            self.entries[peerKey.stringValue] = cur
            self.fileIdToPath[fileId] = url.path
            self.removeAvatarFilesLocked(for: peerKey, keepingFileName: fileName, keepingVideoName: nil)
            self.persistLocked()
            self.notifyLocked(touched: peerKey)
            return GGVisualAvatarInfo(url: url, width: cur.avatarWidth, height: cur.avatarHeight, fileId: fileId)
        }
    }

    @discardableResult
    public func saveAvatarVideoData(_ videoData: Data, coverData: Data, width: Int, height: Int, for peerKey: GGPeerKey) -> GGVisualAvatarInfo? {
        return self.lock.withLock {
            self.ensureLoadedLocked()
            let dir = self.avatarsDirectoryURL()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let baseTs = Int64(Date().timeIntervalSince1970 * 1000.0)
            let fileId = -abs(baseTs &* 1009 &+ Int64.random(in: 1 ... 999))
            let videoFileId = -abs(baseTs &* 1013 &+ Int64.random(in: 1 ... 999))
            let fileName = "avatar_\(peerKey.namespace)_\(peerKey.id)_\(abs(fileId)).jpg"
            let videoFileName = "avatar_vid_\(peerKey.namespace)_\(peerKey.id)_\(abs(videoFileId)).mp4"
            let url = dir.appendingPathComponent(fileName)
            let videoUrl = dir.appendingPathComponent(videoFileName)
            do {
                try coverData.write(to: url, options: [.atomic])
                try videoData.write(to: videoUrl, options: [.atomic])
            } catch {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: videoUrl)
                GGLog.error("visualProfile", "save video avatar failed: \(error.localizedDescription)")
                return nil
            }
            var cur = self.entries[peerKey.stringValue] ?? GGVisualPeerOverride()
            if cur.avatarFileId != 0 {
                self.fileIdToPath.removeValue(forKey: cur.avatarFileId)
            }
            if cur.avatarVideoFileId != 0 {
                self.fileIdToVideoPath.removeValue(forKey: cur.avatarVideoFileId)
            }
            cur.avatarFileName = fileName
            cur.avatarWidth = max(1, width)
            cur.avatarHeight = max(1, height)
            cur.avatarFileId = fileId
            cur.avatarVideoFileName = videoFileName
            cur.avatarVideoFileId = videoFileId
            cur.remoteUpdatedAt = Int64(Date().timeIntervalSince1970)
            self.entries[peerKey.stringValue] = cur
            self.fileIdToPath[fileId] = url.path
            self.fileIdToVideoPath[videoFileId] = videoUrl.path
            self.removeAvatarFilesLocked(for: peerKey, keepingFileName: fileName, keepingVideoName: videoFileName)
            self.persistLocked()
            self.notifyLocked(touched: peerKey)
            return GGVisualAvatarInfo(url: url, width: cur.avatarWidth, height: cur.avatarHeight, fileId: fileId, videoUrl: videoUrl, videoFileId: videoFileId)
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
            if cur.avatarVideoFileId != 0 {
                self.fileIdToVideoPath.removeValue(forKey: cur.avatarVideoFileId)
            }
            self.removeAvatarFilesLocked(for: peerKey, keepingFileName: nil, keepingVideoName: nil)
            GGVisualProfileStore.clearOwn4kTracking(for: keyStr)
            cur.avatarFileName = ""
            cur.avatarWidth = 0
            cur.avatarHeight = 0
            cur.avatarFileId = 0
            cur.avatarVideoFileName = ""
            cur.avatarVideoFileId = 0
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
            var resolvedVideoUrl: URL? = nil
            var resolvedVideoId: Int64 = 0
            if !item.avatarVideoFileName.isEmpty && item.avatarVideoFileId != 0 {
                let candidate = self.avatarsDirectoryURL().appendingPathComponent(item.avatarVideoFileName)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    self.fileIdToVideoPath[item.avatarVideoFileId] = candidate.path
                    resolvedVideoUrl = candidate
                    resolvedVideoId = item.avatarVideoFileId
                }
            }
            return GGVisualAvatarInfo(url: url, width: max(1, item.avatarWidth), height: max(1, item.avatarHeight), fileId: item.avatarFileId, videoUrl: resolvedVideoUrl, videoFileId: resolvedVideoId)
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

    public func videoPath(matchingFileId fileId: Int64) -> String? {
        if fileId == 0 {
            return nil
        }
        return self.lock.withLock {
            self.ensureLoadedLocked()
            if let path = self.fileIdToVideoPath[fileId], FileManager.default.fileExists(atPath: path) {
                return path
            }
            return nil
        }
    }

    // MARK: - Global 4K Sync (Hardened)

    private static let own4kPeersDefaultsKey = "mediatok.4k.own_peers.v1"
    private static let own4kHeartbeatDefaultsKey = "mediatok.4k.heartbeat.v1"

    private static func clearOwn4kTracking(for keyStr: String) {
        var ownSet = Set(UserDefaults.standard.stringArray(forKey: GGVisualProfileStore.own4kPeersDefaultsKey) ?? [])
        if ownSet.remove(keyStr) != nil {
            UserDefaults.standard.set(Array(ownSet), forKey: GGVisualProfileStore.own4kPeersDefaultsKey)
        }
        var hb = (UserDefaults.standard.dictionary(forKey: GGVisualProfileStore.own4kHeartbeatDefaultsKey) as? [String: Double]) ?? [:]
        if hb.removeValue(forKey: keyStr) != nil {
            UserDefaults.standard.set(hb, forKey: GGVisualProfileStore.own4kHeartbeatDefaultsKey)
        }
    }

    private static func globalDialogId(for peerKey: GGPeerKey) -> Int64? {
        switch peerKey.namespace {
        case 0:
            return peerKey.id > 0 ? peerKey.id : nil
        case 1, 2:
            return peerKey.id > 0 ? -peerKey.id : nil
        default:
            return nil
        }
    }

    private static func isAllowedCatboxURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(),
              scheme == "https",
              let host = comps.host?.lowercased(),
              host == "files.catbox.moe",
              comps.user == nil,
              comps.password == nil else {
            return nil
        }
        if let port = comps.port, port != 443 {
            return nil
        }
        let path = comps.percentEncodedPath
        guard path.count > 1, !path.contains(".."), let url = comps.url else {
            return nil
        }
        return url
    }

    private static func downloadLimitedData(from url: URL, maxBytes: Int64, completion: @escaping (Data?) -> Void) {
        let req = URLRequest(url: url, timeoutInterval: 45.0)
        URLSession.shared.downloadTask(with: req) { tempUrl, response, _ in
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let tempUrl else {
                completion(nil)
                return
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: tempUrl.path)
            let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            guard fileSize > 0, fileSize <= maxBytes,
                  let data = try? Data(contentsOf: tempUrl),
                  !data.isEmpty,
                  Int64(data.count) <= maxBytes else {
                completion(nil)
                return
            }
            completion(data)
        }.resume()
    }

    private static func unwrapNtfyJsonLine(_ line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
              let lineData = trimmed.data(using: .utf8),
              let outer = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] else {
            return nil
        }
        if let msgStr = outer["message"] as? String,
           msgStr.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
           let innerData = msgStr.data(using: .utf8),
           let inner = (try? JSONSerialization.jsonObject(with: innerData)) as? [String: Any],
           inner["ts"] != nil {
            return inner
        }
        if outer["ts"] != nil {
            return outer
        }
        return nil
    }

    private static func post4kMetadata(photoUrl: String, videoUrl: String?, ts: Int64, dialogId: Int64, completion: (() -> Void)? = nil) {
        guard let ntfyUrl = URL(string: "https://ntfy.sh/mt4k_v1_\(dialogId)") else {
            return
        }
        var payload: [String: Any] = [
            "photoUrl": photoUrl,
            "ts": ts
        ]
        if let videoUrl, !videoUrl.isEmpty {
            payload["videoUrl"] = videoUrl
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        var req = URLRequest(url: ntfyUrl, timeoutInterval: 20.0)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("MediaTok/4K", forHTTPHeaderField: "User-Agent")
        req.httpBody = jsonData
        URLSession.shared.dataTask(with: req) { _, _, _ in
            completion?()
        }.resume()
    }

    private static func parseImageDimensions(data: Data) -> (Int, Int) {
        let bytes = [UInt8](data)
        if bytes.count >= 24 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            let w = (Int(bytes[16]) << 24) | (Int(bytes[17]) << 16) | (Int(bytes[18]) << 8) | Int(bytes[19])
            let h = (Int(bytes[20]) << 24) | (Int(bytes[21]) << 16) | (Int(bytes[22]) << 8) | Int(bytes[23])
            if w > 0 && h > 0 {
                return (w, h)
            }
        }
        if bytes.count >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8 {
            var i = 2
            while i + 8 < bytes.count {
                if bytes[i] != 0xFF {
                    i += 1
                    continue
                }
                let marker = bytes[i + 1]
                if marker == 0xC0 || marker == 0xC1 || marker == 0xC2 || marker == 0xC3 {
                    let h = (Int(bytes[i + 5]) << 8) | Int(bytes[i + 6])
                    let w = (Int(bytes[i + 7]) << 8) | Int(bytes[i + 8])
                    if w > 0 && h > 0 {
                        return (w, h)
                    }
                    break
                } else if marker == 0xD8 || marker == 0xD9 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) {
                    i += 2
                } else {
                    let segLen = (Int(bytes[i + 2]) << 8) | Int(bytes[i + 3])
                    if segLen < 2 {
                        break
                    }
                    i += 2 + segLen
                }
            }
        }
        return (1920, 1920)
    }

    private static func uploadToCatbox(data: Data, fileName: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://catbox.moe/user/api.php") else {
            completion(nil)
            return
        }
        let boundary = "----MediaTok4k\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var req = URLRequest(url: url, timeoutInterval: 60.0)
        req.httpMethod = "POST"
        req.setValue("MediaTok/4K", forHTTPHeaderField: "User-Agent")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        if let d1 = "--\(boundary)\r\nContent-Disposition: form-data; name=\"reqtype\"\r\n\r\nfileupload\r\n".data(using: .utf8) {
            body.append(d1)
        }
        if let d2 = "--\(boundary)\r\nContent-Disposition: form-data; name=\"fileToUpload\"; filename=\"\(fileName)\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8) {
            body.append(d2)
        }
        body.append(data)
        if let d3 = "\r\n--\(boundary)--\r\n".data(using: .utf8) {
            body.append(d3)
        }
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { respData, response, _ in
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let respData,
                  let text = String(data: respData, encoding: .utf8),
                  let allowed = GGVisualProfileStore.isAllowedCatboxURL(text) else {
                completion(nil)
                return
            }
            completion(allowed.absoluteString)
        }.resume()
    }

    public func publishGlobal4kAvatar(for peerKey: GGPeerKey, photoData: Data, videoData: Data?) {
        guard let dialogId = GGVisualProfileStore.globalDialogId(for: peerKey),
              !photoData.isEmpty else {
            return
        }
        let ts = Int64(Date().timeIntervalSince1970)
        let photoFileName = "avatar_\(peerKey.namespace)_\(peerKey.id)_\(ts).jpg"
        GGVisualProfileStore.uploadToCatbox(data: photoData, fileName: photoFileName) { photoUrl in
            guard let photoUrl, !photoUrl.isEmpty else {
                return
            }
            let sendMetadata: (String?) -> Void = { videoUrl in
                GGVisualProfileStore.post4kMetadata(photoUrl: photoUrl, videoUrl: videoUrl, ts: ts, dialogId: dialogId) {
                    let keyStr = peerKey.stringValue
                    var ownSet = Set(UserDefaults.standard.stringArray(forKey: GGVisualProfileStore.own4kPeersDefaultsKey) ?? [])
                    ownSet.insert(keyStr)
                    UserDefaults.standard.set(Array(ownSet), forKey: GGVisualProfileStore.own4kPeersDefaultsKey)
                    var hb = (UserDefaults.standard.dictionary(forKey: GGVisualProfileStore.own4kHeartbeatDefaultsKey) as? [String: Double]) ?? [:]
                    hb[keyStr] = Date().timeIntervalSince1970
                    UserDefaults.standard.set(hb, forKey: GGVisualProfileStore.own4kHeartbeatDefaultsKey)

                    self.lock.withLock {
                        self.ensureLoadedLocked()
                        var cur = self.entries[keyStr] ?? GGVisualPeerOverride()
                        if cur.remoteUpdatedAt <= ts {
                            cur.remotePhotoUrl = photoUrl
                            cur.remoteVideoUrl = videoUrl ?? ""
                            cur.remoteUpdatedAt = ts
                            self.entries[keyStr] = cur
                            self.persistLocked()
                        }
                    }
                }
            }

            if let videoData, !videoData.isEmpty {
                let videoFileName = "avatar_vid_\(peerKey.namespace)_\(peerKey.id)_\(ts).mp4"
                GGVisualProfileStore.uploadToCatbox(data: videoData, fileName: videoFileName) { videoUrl in
                    sendMetadata(videoUrl)
                }
            } else {
                sendMetadata(nil)
            }
        }
    }

    public func checkGlobal4kAvatar(for peerKey: GGPeerKey) {
        guard let dialogId = GGVisualProfileStore.globalDialogId(for: peerKey) else {
            return
        }
        let keyStr = peerKey.stringValue
        let now = Date().timeIntervalSince1970

        let ownHeartbeatTarget: (photoUrl: String, videoUrl: String?)? = self.lock.withLock {
            self.ensureLoadedLocked()
            let ownSet = Set(UserDefaults.standard.stringArray(forKey: GGVisualProfileStore.own4kPeersDefaultsKey) ?? [])
            guard ownSet.contains(keyStr),
                  let existing = self.entries[keyStr],
                  GGVisualProfileStore.isAllowedCatboxURL(existing.remotePhotoUrl) != nil else {
                return nil
            }
            let hb = (UserDefaults.standard.dictionary(forKey: GGVisualProfileStore.own4kHeartbeatDefaultsKey) as? [String: Double]) ?? [:]
            let lastHb = hb[keyStr] ?? 0.0
            if (now - lastHb) >= 28800.0 {
                var nextHb = hb
                nextHb[keyStr] = now
                UserDefaults.standard.set(nextHb, forKey: GGVisualProfileStore.own4kHeartbeatDefaultsKey)
                let vid = existing.remoteVideoUrl.isEmpty ? nil : existing.remoteVideoUrl
                return (existing.remotePhotoUrl, vid)
            }
            return ("", nil)
        }
        if let target = ownHeartbeatTarget {
            if !target.photoUrl.isEmpty {
                GGVisualProfileStore.post4kMetadata(photoUrl: target.photoUrl, videoUrl: target.videoUrl, ts: Int64(now), dialogId: dialogId)
            }
            return
        }

        let shouldCheck: Bool = self.lock.withLock {
            let prev = self.lastGlobalCheckAt[peerKey] ?? 0.0
            if now - prev < 600.0 {
                return false
            }
            self.lastGlobalCheckAt[peerKey] = now
            return true
        }
        guard shouldCheck, let url = URL(string: "https://ntfy.sh/mt4k_v1_\(dialogId)/json?poll=1&since=all") else {
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 15.0)
        req.setValue("MediaTok/4K", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let data,
                  data.count <= 262_144,
                  let body = String(data: data, encoding: .utf8) else {
                return
            }
            let maxAllowedTs = Int64(Date().timeIntervalSince1970) + 300
            var latestObj: [String: Any]?
            var latestTs: Int64 = 0
            for line in body.components(separatedBy: .newlines).reversed() {
                guard let parsed = GGVisualProfileStore.unwrapNtfyJsonLine(line) else {
                    continue
                }
                let p = parsed["photoUrl"] as? String ?? ""
                guard GGVisualProfileStore.isAllowedCatboxURL(p) != nil else {
                    continue
                }
                let candidateTs: Int64
                if let v = parsed["ts"] as? Int64 { candidateTs = v }
                else if let v = parsed["ts"] as? Int { candidateTs = Int64(v) }
                else if let v = parsed["ts"] as? Double { candidateTs = Int64(v) }
                else { candidateTs = 0 }
                if candidateTs > 0 && candidateTs <= maxAllowedTs && candidateTs > latestTs {
                    latestObj = parsed
                    latestTs = candidateTs
                }
            }
            guard let obj = latestObj, latestTs > 0 else {
                return
            }
            let remoteTs = latestTs
            let photoUrlStr = obj["photoUrl"] as? String ?? ""
            let rawVideoUrlStr = obj["videoUrl"] as? String ?? ""
            guard let photoUrl = GGVisualProfileStore.isAllowedCatboxURL(photoUrlStr) else {
                return
            }
            let validatedVideoUrl = GGVisualProfileStore.isAllowedCatboxURL(rawVideoUrlStr)
            let safeVideoUrlStr = validatedVideoUrl?.absoluteString ?? ""

            let alreadyNewer = self.lock.withLock {
                self.ensureLoadedLocked()
                return remoteTs <= (self.entries[peerKey.stringValue]?.remoteUpdatedAt ?? 0)
            }
            if alreadyNewer {
                return
            }
            GGVisualProfileStore.downloadLimitedData(from: photoUrl, maxBytes: 15 * 1024 * 1024) { photoData in
                guard let photoData, !photoData.isEmpty else {
                    return
                }
                let (w, h) = GGVisualProfileStore.parseImageDimensions(data: photoData)
                let applyRemote: (Data?) -> Void = { videoData in
                    let stillNeeded = self.lock.withLock {
                        self.ensureLoadedLocked()
                        return remoteTs > (self.entries[peerKey.stringValue]?.remoteUpdatedAt ?? 0)
                    }
                    guard stillNeeded else {
                        return
                    }
                    if let videoData, !videoData.isEmpty {
                        self.saveAvatarVideoData(videoData, coverData: photoData, width: w, height: h, for: peerKey)
                    } else {
                        self.saveAvatarData(photoData, width: w, height: h, for: peerKey)
                    }
                    self.lock.withLock {
                        if var updated = self.entries[peerKey.stringValue] {
                            updated.remotePhotoUrl = photoUrl.absoluteString
                            updated.remoteVideoUrl = videoData != nil ? safeVideoUrlStr : ""
                            updated.remoteUpdatedAt = remoteTs
                            self.entries[peerKey.stringValue] = updated
                            self.persistLocked()
                        }
                    }
                }
                if let videoUrl = validatedVideoUrl {
                    GGVisualProfileStore.downloadLimitedData(from: videoUrl, maxBytes: 25 * 1024 * 1024) { videoData in
                        if let videoData, !videoData.isEmpty {
                            applyRemote(videoData)
                        } else {
                            applyRemote(nil)
                        }
                    }
                } else {
                    applyRemote(nil)
                }
            }
        }.resume()
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
