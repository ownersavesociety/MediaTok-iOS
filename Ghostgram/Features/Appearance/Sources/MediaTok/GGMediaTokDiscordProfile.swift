import Foundation
import UIKit
import ObjectiveC
import AVFoundation
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import UndoUI
import GGCore
import GGHooks
import GGSettingsUI

// MARK: - Data Model

public struct GGDiscordProfileData: Codable, Equatable {
    public var bannerFileName: String
    public var bannerUrl: String
    public var effectId: String
    public var avatarFrameId: String
    public var customStatus: String
    public var steamInput: String
    public var robloxInput: String
    public var musicFileName: String
    public var musicUrl: String
    public var musicTitle: String
    public var updatedAt: Int64

    private enum CodingKeys: String, CodingKey {
        case bannerFileName
        case bannerUrl
        case effectId
        case avatarFrameId
        case customStatus
        case steamInput
        case robloxInput
        case musicFileName
        case musicUrl
        case musicTitle
        case updatedAt
    }

    public init(
        bannerFileName: String = "",
        bannerUrl: String = "",
        effectId: String = "none",
        avatarFrameId: String = "none",
        customStatus: String = "",
        steamInput: String = "",
        robloxInput: String = "",
        musicFileName: String = "",
        musicUrl: String = "",
        musicTitle: String = "",
        updatedAt: Int64 = 0
    ) {
        self.bannerFileName = bannerFileName
        self.bannerUrl = bannerUrl
        self.effectId = effectId
        self.avatarFrameId = avatarFrameId
        self.customStatus = customStatus
        self.steamInput = steamInput
        self.robloxInput = robloxInput
        self.musicFileName = musicFileName
        self.musicUrl = musicUrl
        self.musicTitle = musicTitle
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bannerFileName = try c.decodeIfPresent(String.self, forKey: .bannerFileName) ?? ""
        self.bannerUrl = try c.decodeIfPresent(String.self, forKey: .bannerUrl) ?? ""
        self.effectId = try c.decodeIfPresent(String.self, forKey: .effectId) ?? "none"
        self.avatarFrameId = try c.decodeIfPresent(String.self, forKey: .avatarFrameId) ?? "none"
        self.customStatus = try c.decodeIfPresent(String.self, forKey: .customStatus) ?? ""
        self.steamInput = try c.decodeIfPresent(String.self, forKey: .steamInput) ?? ""
        self.robloxInput = try c.decodeIfPresent(String.self, forKey: .robloxInput) ?? ""
        self.musicFileName = try c.decodeIfPresent(String.self, forKey: .musicFileName) ?? ""
        self.musicUrl = try c.decodeIfPresent(String.self, forKey: .musicUrl) ?? ""
        self.musicTitle = try c.decodeIfPresent(String.self, forKey: .musicTitle) ?? ""
        self.updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }

    public var isEmpty: Bool {
        return self.bannerFileName.isEmpty
            && self.bannerUrl.isEmpty
            && (self.effectId.isEmpty || self.effectId == "none")
            && (self.avatarFrameId.isEmpty || self.avatarFrameId == "none")
            && self.customStatus.isEmpty
            && self.steamInput.isEmpty
            && self.robloxInput.isEmpty
            && self.musicFileName.isEmpty
            && self.musicUrl.isEmpty
            && self.musicTitle.isEmpty
    }
}

// MARK: - Full-Track Profile Music Player

final class GGProfileMusicPlayer {
    static let shared = GGProfileMusicPlayer()

    private var player: AVPlayer?
    private var playingPeerKey: String?
    private var endObserver: NSObjectProtocol?

    private init() {}

    func isPlaying(peerId: PeerId) -> Bool {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        return self.playingPeerKey == key && (self.player?.rate ?? 0.0) > 0.0
    }

    func stop() {
        self.player?.pause()
        self.player = nil
        self.playingPeerKey = nil
        if let obs = self.endObserver {
            NotificationCenter.default.removeObserver(obs)
            self.endObserver = nil
        }
    }

    func toggle(peerId: PeerId, profile: GGDiscordProfileData, onStateChanged: (() -> Void)?) {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        if self.isPlaying(peerId: peerId) {
            self.stop()
            onStateChanged?()
            return
        }
        let targetURL: URL?
        if let local = GGDiscordProfileStore.shared.musicFileURL(for: profile) {
            targetURL = local
        } else if let remote = GGMediaTokCoreLogic.isAllowedMediaURL(profile.musicUrl) {
            targetURL = remote
        } else {
            targetURL = nil
        }
        guard let url = targetURL else { return }

        self.stop()
        let _ = try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        let _ = try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let av = AVPlayer(playerItem: item)
        self.player = av
        self.playingPeerKey = key
        self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.stop()
            onStateChanged?()
        }
        av.play()
        onStateChanged?()
    }
}

// MARK: - Store & Global MediaTok Sync

final class GGDiscordProfileStore {
    static let shared = GGDiscordProfileStore()

    static let effects: [(id: String, title: String)] = [
        ("none", "Выкл."),
        ("lightning", "Молнии ⚡"),
        ("sakura", "Сакура 🌸"),
        ("fire", "Пламя / Искры 🔥"),
        ("matrix", "Матрица 💚"),
        ("neon", "Неон-волна 🌈"),
        ("snow", "Снег / Иней ❄️"),
        ("stars", "Космос ✨")
    ]

    static let avatarFrames: [(id: String, title: String, colors: [UIColor])] = [
        ("none", "Выкл.", []),
        ("neon_cyan", "Кибер-Неон 💎", [UIColor(rgb: 0x00F5FF), UIColor(rgb: 0xFF00D4), UIColor(rgb: 0x00F5FF)]),
        ("rainbow", "Радуга RGB 🌈", [UIColor(rgb: 0xFF3B5C), UIColor(rgb: 0xFFB800), UIColor(rgb: 0x00E676), UIColor(rgb: 0x00C8FF), UIColor(rgb: 0xC471FF), UIColor(rgb: 0xFF3B5C)]),
        ("fire", "Огонь 🔥", [UIColor(rgb: 0xFFF04D), UIColor(rgb: 0xFF6B00), UIColor(rgb: 0xFF1744), UIColor(rgb: 0xFFF04D)]),
        ("gold", "Золото 👑", [UIColor(rgb: 0xFFF4B8), UIColor(rgb: 0xF5B301), UIColor(rgb: 0xB87300), UIColor(rgb: 0xFFF4B8)]),
        ("toxic", "Токсик ☢️", [UIColor(rgb: 0xCCFF00), UIColor(rgb: 0x00FF66), UIColor(rgb: 0x008F39), UIColor(rgb: 0xCCFF00)]),
        ("sakura", "Сакура 🌸", [UIColor(rgb: 0xFFD1DC), UIColor(rgb: 0xFF7EB3), UIColor(rgb: 0xC471ED), UIColor(rgb: 0xFFD1DC)]),
        ("glitch", "Глитч ⚡", [UIColor(rgb: 0x00FFFF), UIColor(rgb: 0xFF0055), UIColor(rgb: 0xFFFFFF), UIColor(rgb: 0x00FFFF)]),
        ("obsidian", "Обсидиан 🖤", [UIColor(rgb: 0x6A00F4), UIColor(rgb: 0xE10098), UIColor(rgb: 0x1A1A2E), UIColor(rgb: 0x6A00F4)])
    ]

    private let lock = NSLock()
    private let ownPeersDefaultsKey = "mediatok.discord.own_peers.v1"
    private let heartbeatDefaultsKey = "mediatok.discord.last_heartbeat.v1"
    private var loaded = false
    private var entries: [String: GGDiscordProfileData] = [:]
    private var lastSyncCheck: [String: TimeInterval] = [:]
    private let revisionPromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    private var revisionCounter: Int32 = 0

    private init() {}

    private func ownPeersSet() -> Set<String> {
        return Set(UserDefaults.standard.stringArray(forKey: self.ownPeersDefaultsKey) ?? [])
    }

    private func markOwnPeer(_ key: String, isOwn: Bool) {
        var set = self.ownPeersSet()
        if isOwn {
            set.insert(key)
        } else {
            set.remove(key)
        }
        UserDefaults.standard.set(Array(set), forKey: self.ownPeersDefaultsKey)
    }

    private func lastHeartbeat(for key: String) -> TimeInterval {
        let dict = (UserDefaults.standard.dictionary(forKey: self.heartbeatDefaultsKey) as? [String: Double]) ?? [:]
        return dict[key] ?? 0.0
    }

    private func updateHeartbeat(for key: String, ts: TimeInterval) {
        var dict = (UserDefaults.standard.dictionary(forKey: self.heartbeatDefaultsKey) as? [String: Double]) ?? [:]
        dict[key] = ts
        UserDefaults.standard.set(dict, forKey: self.heartbeatDefaultsKey)
    }

    var revisionSignal: Signal<Int32, NoError> {
        return self.revisionPromise.get()
    }

    private func rootDir() -> URL {
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return base.appendingPathComponent("ghostgram/mediatok", isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("ghostgram/mediatok", isDirectory: true)
    }

    private func configURL() -> URL {
        return self.rootDir().appendingPathComponent("discord_profiles.json")
    }

    private func bannersDir() -> URL {
        return self.rootDir().appendingPathComponent("discord_banners", isDirectory: true)
    }

    private func musicDir() -> URL {
        return self.rootDir().appendingPathComponent("discord_music", isDirectory: true)
    }

    private func ensureLoadedLocked() {
        if self.loaded { return }
        self.loaded = true
        guard let data = try? Data(contentsOf: self.configURL()),
              let decoded = try? JSONDecoder().decode([String: GGDiscordProfileData].self, from: data) else {
            return
        }
        self.entries = decoded
    }

    private func persistLocked() {
        let dir = self.rootDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(self.entries) {
            try? data.write(to: self.configURL(), options: [.atomic])
        }
    }

    private func bumpRevisionLocked() {
        self.revisionCounter = self.revisionCounter &+ 1
        let next = self.revisionCounter
        self.revisionPromise.set(next)
    }

    static func keyString(for peerId: PeerId) -> String {
        return "\(peerId.namespace._internalGetInt32Value())_\(peerId.id._internalGetInt64Value())"
    }

    static func globalDialogId(for peerId: PeerId) -> Int64? {
        let ns = peerId.namespace._internalGetInt32Value()
        let raw = peerId.id._internalGetInt64Value()
        guard raw > 0 else { return nil }
        if ns == 0 { return raw }
        if ns == 1 || ns == 2 { return -raw }
        return nil
    }

    func profile(for peerId: PeerId) -> GGDiscordProfileData? {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.ensureLoadedLocked()
        return self.entries[GGDiscordProfileStore.keyString(for: peerId)]
    }

    func bannerFileURL(for profile: GGDiscordProfileData) -> URL? {
        guard !profile.bannerFileName.isEmpty else { return nil }
        let url = self.bannersDir().appendingPathComponent(profile.bannerFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func musicFileURL(for profile: GGDiscordProfileData) -> URL? {
        guard !profile.musicFileName.isEmpty else { return nil }
        let url = self.musicDir().appendingPathComponent(profile.musicFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func saveBannerData(_ data: Data, for peerId: PeerId) -> String? {
        let dir = self.bannersDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = "banner_\(GGDiscordProfileStore.keyString(for: peerId))_\(Int64(Date().timeIntervalSince1970 * 1000.0)).jpg"
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            return nil
        }
        return fileName
    }

    func saveMusicData(_ data: Data, ext: String, for peerId: PeerId) -> String? {
        let dir = self.musicDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cleanExt = GGMediaTokCoreLogic.sanitizeAudioExtension(ext)
        let fileName = "track_\(GGDiscordProfileStore.keyString(for: peerId))_\(Int64(Date().timeIntervalSince1970 * 1000.0)).\(cleanExt)"
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            return nil
        }
        return fileName
    }

    func setProfile(_ profile: GGDiscordProfileData, for peerId: PeerId, publishGlobally: Bool) {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        var updated = profile
        updated.updatedAt = Int64(Date().timeIntervalSince1970)

        self.lock.lock()
        self.ensureLoadedLocked()
        let oldBanner = self.entries[key]?.bannerFileName ?? ""
        let oldMusic = self.entries[key]?.musicFileName ?? ""
        if updated.isEmpty {
            self.entries.removeValue(forKey: key)
        } else {
            self.entries[key] = updated
        }
        if !oldBanner.isEmpty && oldBanner != updated.bannerFileName {
            try? FileManager.default.removeItem(at: self.bannersDir().appendingPathComponent(oldBanner))
        }
        if !oldMusic.isEmpty && oldMusic != updated.musicFileName {
            try? FileManager.default.removeItem(at: self.musicDir().appendingPathComponent(oldMusic))
        }
        self.persistLocked()
        self.bumpRevisionLocked()
        self.lock.unlock()

        if publishGlobally {
            self.markOwnPeer(key, isOwn: !updated.isEmpty)
            self.updateHeartbeat(for: key, ts: Date().timeIntervalSince1970)
            if !updated.isEmpty {
                self.publishGlobalProfile(updated, for: peerId)
            }
        }
    }

    // MARK: - Catbox + ntfy Global Sync (4K Banner + Full Track Music, Hardened)

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

    private static func postProfileJson(
        _ profile: GGDiscordProfileData,
        bannerUrl: String,
        musicUrl: String,
        ts: Int64,
        dialogId: Int64,
        completion: (() -> Void)? = nil
    ) {
        guard let ntfyUrl = URL(string: "https://ntfy.sh/mtprof_v1_\(dialogId)") else { return }
        let payload: [String: Any] = [
            "bannerUrl": bannerUrl,
            "effectId": profile.effectId,
            "avatarFrameId": profile.avatarFrameId,
            "customStatus": String(profile.customStatus.prefix(140)),
            "steamInput": String(profile.steamInput.prefix(120)),
            "robloxInput": String(profile.robloxInput.prefix(120)),
            "musicUrl": musicUrl,
            "musicTitle": String(profile.musicTitle.prefix(120)),
            "ts": ts
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        var req = URLRequest(url: ntfyUrl, timeoutInterval: 20.0)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("MediaTok/DiscordProfile", forHTTPHeaderField: "User-Agent")
        req.httpBody = jsonData
        URLSession.shared.dataTask(with: req) { _, _, _ in
            completion?()
        }.resume()
    }

    private static func uploadToCatbox(data: Data, fileName: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://catbox.moe/user/api.php") else {
            completion(nil)
            return
        }
        let boundary = "----MediaTokSync\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var req = URLRequest(url: url, timeoutInterval: 90.0)
        req.httpMethod = "POST"
        req.setValue("MediaTok/DiscordProfile", forHTTPHeaderField: "User-Agent")
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
                  let raw = String(data: respData, encoding: .utf8),
                  let allowed = GGMediaTokCoreLogic.isAllowedMediaURL(raw) else {
                completion(nil)
                return
            }
            completion(allowed.absoluteString)
        }.resume()
    }

    private func publishGlobalProfile(_ profile: GGDiscordProfileData, for peerId: PeerId) {
        guard let dialogId = GGDiscordProfileStore.globalDialogId(for: peerId) else { return }

        let group = DispatchGroup()
        let urlLock = NSLock()
        var resolvedBannerUrl = GGMediaTokCoreLogic.isAllowedMediaURL(profile.bannerUrl)?.absoluteString ?? ""
        var resolvedMusicUrl = GGMediaTokCoreLogic.isAllowedMediaURL(profile.musicUrl)?.absoluteString ?? ""

        if !profile.bannerFileName.isEmpty && resolvedBannerUrl.isEmpty,
           let localUrl = self.bannerFileURL(for: profile),
           let bannerData = try? Data(contentsOf: localUrl), !bannerData.isEmpty {
            group.enter()
            GGDiscordProfileStore.uploadToCatbox(data: bannerData, fileName: profile.bannerFileName) { uploaded in
                if let uploaded {
                    urlLock.lock()
                    resolvedBannerUrl = uploaded
                    urlLock.unlock()
                }
                group.leave()
            }
        }

        if !profile.musicFileName.isEmpty && resolvedMusicUrl.isEmpty,
           let localMusic = self.musicFileURL(for: profile),
           let musicData = try? Data(contentsOf: localMusic), !musicData.isEmpty {
            group.enter()
            GGDiscordProfileStore.uploadToCatbox(data: musicData, fileName: profile.musicFileName) { uploaded in
                if let uploaded {
                    urlLock.lock()
                    resolvedMusicUrl = uploaded
                    urlLock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .global(qos: .utility)) {
            urlLock.lock()
            let finalBanner = resolvedBannerUrl
            let finalMusic = resolvedMusicUrl
            urlLock.unlock()

            GGDiscordProfileStore.postProfileJson(
                profile,
                bannerUrl: finalBanner,
                musicUrl: finalMusic,
                ts: profile.updatedAt,
                dialogId: dialogId
            ) {
                let key = GGDiscordProfileStore.keyString(for: peerId)
                self.lock.lock()
                if var cur = self.entries[key], cur.updatedAt <= profile.updatedAt {
                    if !finalBanner.isEmpty { cur.bannerUrl = finalBanner }
                    if !finalMusic.isEmpty { cur.musicUrl = finalMusic }
                    self.entries[key] = cur
                    self.persistLocked()
                }
                self.lock.unlock()
            }
        }
    }

    func checkGlobalProfile(for peerId: PeerId, force: Bool = false, onUpdated: (() -> Void)? = nil) {
        guard let dialogId = GGDiscordProfileStore.globalDialogId(for: peerId) else { return }
        let key = GGDiscordProfileStore.keyString(for: peerId)
        let now = Date().timeIntervalSince1970

        self.lock.lock()
        self.ensureLoadedLocked()
        let existingLocal = self.entries[key]
        let isOwn = self.ownPeersSet().contains(key)
        if !force && isOwn, let localProf = existingLocal, !localProf.isEmpty {
            let needHeartbeat = (now - self.lastHeartbeat(for: key)) >= 28800.0
            if needHeartbeat {
                self.updateHeartbeat(for: key, ts: now)
            }
            self.lock.unlock()
            if needHeartbeat {
                if (!localProf.bannerFileName.isEmpty && localProf.bannerUrl.isEmpty) ||
                   (!localProf.musicFileName.isEmpty && localProf.musicUrl.isEmpty) {
                    self.publishGlobalProfile(localProf, for: peerId)
                } else {
                    GGDiscordProfileStore.postProfileJson(
                        localProf,
                        bannerUrl: localProf.bannerUrl,
                        musicUrl: localProf.musicUrl,
                        ts: Int64(now),
                        dialogId: dialogId
                    )
                }
            }
            return
        }

        let prev = self.lastSyncCheck[key] ?? 0.0
        if !force && (now - prev) < 300.0 {
            self.lock.unlock()
            return
        }
        self.lastSyncCheck[key] = now
        self.lock.unlock()

        guard let url = URL(string: "https://ntfy.sh/mtprof_v1_\(dialogId)/json?poll=1&since=all") else { return }
        var req = URLRequest(url: url, timeoutInterval: 12.0)
        req.setValue("MediaTok/DiscordProfile", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let data,
                  data.count <= 262_144,
                  let body = String(data: data, encoding: .utf8) else {
                return
            }

            let maxAllowedTs = Int64(Date().timeIntervalSince1970) + 300
            var latest: [String: Any]?
            var latestTs: Int64 = 0
            for line in body.components(separatedBy: .newlines).reversed() {
                guard let obj = GGDiscordProfileStore.unwrapNtfyJsonLine(line) else {
                    continue
                }
                let candidateTs: Int64
                if let v = obj["ts"] as? Int64 { candidateTs = v }
                else if let v = obj["ts"] as? Int { candidateTs = Int64(v) }
                else if let v = obj["ts"] as? Double { candidateTs = Int64(v) }
                else { candidateTs = 0 }
                if candidateTs > 0 && candidateTs <= maxAllowedTs && candidateTs > latestTs {
                    latest = obj
                    latestTs = candidateTs
                }
            }
            guard let obj = latest, latestTs > 0 else { return }
            let remoteTs = latestTs

            self.lock.lock()
            self.ensureLoadedLocked()
            let existing = self.entries[key]
            self.lock.unlock()

            if let existing, !force && remoteTs <= existing.updatedAt {
                return
            }

            let rawBannerUrl = obj["bannerUrl"] as? String ?? ""
            let rawMusicUrl = obj["musicUrl"] as? String ?? ""
            let validatedBanner = GGMediaTokCoreLogic.isAllowedMediaURL(rawBannerUrl)
            let validatedMusic = GGMediaTokCoreLogic.isAllowedMediaURL(rawMusicUrl)
            let remoteBannerUrl = validatedBanner?.absoluteString ?? ""
            let remoteMusicUrl = validatedMusic?.absoluteString ?? ""

            let validEffects = Set(GGDiscordProfileStore.effects.map { $0.id })
            let rawEffect = obj["effectId"] as? String ?? "none"
            let safeEffect = validEffects.contains(rawEffect) ? rawEffect : "none"

            let validFrames = Set(GGDiscordProfileStore.avatarFrames.map { $0.id })
            let rawFrame = obj["avatarFrameId"] as? String ?? "none"
            let safeFrame = validFrames.contains(rawFrame) ? rawFrame : "none"

            let safeStatus = String((obj["customStatus"] as? String ?? "").prefix(140))
            let safeSteam = String((obj["steamInput"] as? String ?? "").prefix(120))
            let safeRoblox = String((obj["robloxInput"] as? String ?? "").prefix(120))
            let safeMusicTitle = String((obj["musicTitle"] as? String ?? "").prefix(120))

            let dlGroup = DispatchGroup()
            let dlLock = NSLock()
            var savedBannerFile = (remoteBannerUrl == existing?.bannerUrl) ? (existing?.bannerFileName ?? "") : ""
            var savedMusicFile = (remoteMusicUrl == existing?.musicUrl) ? (existing?.musicFileName ?? "") : ""

            if let bUrl = validatedBanner, savedBannerFile.isEmpty {
                dlGroup.enter()
                GGDiscordProfileStore.downloadLimitedData(from: bUrl, maxBytes: 15 * 1024 * 1024) { bData in
                    if let bData, let saved = self.saveBannerData(bData, for: peerId) {
                        dlLock.lock()
                        savedBannerFile = saved
                        dlLock.unlock()
                    }
                    dlGroup.leave()
                }
            }

            if let mUrl = validatedMusic, savedMusicFile.isEmpty {
                dlGroup.enter()
                GGDiscordProfileStore.downloadLimitedData(from: mUrl, maxBytes: 25 * 1024 * 1024) { mData in
                    if let mData, let saved = self.saveMusicData(mData, ext: mUrl.pathExtension, for: peerId) {
                        dlLock.lock()
                        savedMusicFile = saved
                        dlLock.unlock()
                    }
                    dlGroup.leave()
                }
            }

            dlGroup.notify(queue: .global(qos: .utility)) {
                dlLock.lock()
                let finalBannerFile = savedBannerFile
                let finalMusicFile = savedMusicFile
                dlLock.unlock()

                let remote = GGDiscordProfileData(
                    bannerFileName: finalBannerFile,
                    bannerUrl: remoteBannerUrl,
                    effectId: safeEffect,
                    avatarFrameId: safeFrame,
                    customStatus: safeStatus,
                    steamInput: safeSteam,
                    robloxInput: safeRoblox,
                    musicFileName: finalMusicFile,
                    musicUrl: remoteMusicUrl,
                    musicTitle: safeMusicTitle,
                    updatedAt: remoteTs
                )
                self.lock.lock()
                self.ensureLoadedLocked()
                if let cur = self.entries[key], !force && remoteTs <= cur.updatedAt {
                    self.lock.unlock()
                    return
                }
                if remote.isEmpty {
                    self.entries.removeValue(forKey: key)
                } else {
                    self.entries[key] = remote
                }
                self.persistLocked()
                self.bumpRevisionLocked()
                self.lock.unlock()
                if let onUpdated {
                    DispatchQueue.main.async { onUpdated() }
                }
            }
        }.resume()
    }
}

// MARK: - Live Steam & Roblox Resolvers (Public Endpoints, Zero API Keys)

private struct GGResolvedConnection {
    let displayText: String
    let statusBadge: String
    let profileUrl: URL
    let fetchedAt: TimeInterval
}

private final class GGConnectionResolvers {
    static let shared = GGConnectionResolvers()

    private let lock = NSLock()
    private var steamCache: [String: GGResolvedConnection] = [:]
    private var robloxCache: [String: GGResolvedConnection] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    static func normalizeSteam(_ raw: String) -> (profileUrl: URL, xmlUrl: URL, cleanLabel: String)? {
        return GGMediaTokCoreLogic.normalizeSteam(raw)
    }

    func steamInfo(for input: String, onUpdate: @escaping () -> Void) -> (text: String, badge: String, url: URL)? {
        guard let norm = GGConnectionResolvers.normalizeSteam(input) else { return nil }
        let key = "steam:\(norm.profileUrl.absoluteString.lowercased())"
        let now = Date().timeIntervalSince1970

        self.lock.lock()
        let cached = self.steamCache[key]
        let needFetch = (cached == nil || (now - (cached?.fetchedAt ?? 0)) > 600.0) && !self.inFlight.contains(key)
        if needFetch { self.inFlight.insert(key) }
        self.lock.unlock()

        if needFetch {
            var req = URLRequest(url: norm.xmlUrl, timeoutInterval: 10.0)
            req.setValue("MediaTok/Steam", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer {
                    self.lock.lock()
                    self.inFlight.remove(key)
                    self.lock.unlock()
                }
                guard let data, let xml = String(data: data, encoding: .utf8) else { return }
                let nick = GGConnectionResolvers.extractXmlTag("steamID", in: xml) ?? norm.cleanLabel
                let onlineState = (GGConnectionResolvers.extractXmlTag("onlineState", in: xml) ?? "").lowercased()
                let rawStateMsg = GGConnectionResolvers.extractXmlTag("stateMessage", in: xml) ?? ""
                let cleanStateMsg = rawStateMsg
                    .replacingOccurrences(of: "<br/>", with: " · ")
                    .replacingOccurrences(of: "<br>", with: " · ")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let topGame = GGConnectionResolvers.extractXmlTag("gameName", in: xml)
                let hours = GGConnectionResolvers.extractXmlTag("hoursPlayed", in: xml)

                let badge: String
                if onlineState == "in-game" {
                    badge = "🟢 В игре"
                } else if onlineState == "online" {
                    badge = "🔵 В сети"
                } else {
                    badge = "⚫ Офлайн"
                }

                var parts = [nick]
                if onlineState == "in-game" && !cleanStateMsg.isEmpty {
                    parts.append(cleanStateMsg)
                } else if let topGame, !topGame.isEmpty {
                    if let hours, !hours.isEmpty {
                        parts.append("\(topGame) (\(hours) ч)")
                    } else {
                        parts.append(topGame)
                    }
                } else if !cleanStateMsg.isEmpty {
                    parts.append(cleanStateMsg)
                }
                let resolved = GGResolvedConnection(
                    displayText: parts.joined(separator: " · "),
                    statusBadge: badge,
                    profileUrl: norm.profileUrl,
                    fetchedAt: Date().timeIntervalSince1970
                )
                self.lock.lock()
                self.steamCache[key] = resolved
                self.lock.unlock()
                DispatchQueue.main.async { onUpdate() }
            }.resume()
        }

        if let cached {
            return (cached.displayText, cached.statusBadge, cached.profileUrl)
        }
        return ("\(norm.cleanLabel) · Steam", "Steam", norm.profileUrl)
    }

    private static func extractXmlTag(_ tag: String, in xml: String) -> String? {
        guard let startRange = xml.range(of: "<\(tag)>"),
              let endRange = xml.range(of: "</\(tag)>", range: startRange.upperBound ..< xml.endIndex) else {
            return nil
        }
        var raw = String(xml[startRange.upperBound ..< endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("<![CDATA[") && raw.hasSuffix("]]>") {
            raw = String(raw.dropFirst(9).dropLast(3))
        }
        return raw.isEmpty ? nil : raw
    }

    static func parseRobloxInput(_ raw: String) -> (userId: Int64?, username: String?, fallbackUrl: URL)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("@") { s.removeFirst() }
        if let range = s.range(of: "roblox.com/users/", options: .caseInsensitive) {
            let tail = s[range.upperBound...]
            let digits = tail.prefix(while: { $0.isNumber })
            if let uid = Int64(digits), let u = URL(string: "https://www.roblox.com/users/\(uid)/profile") {
                return (uid, nil, u)
            }
        }
        if let uid = Int64(s), uid > 0, let u = URL(string: "https://www.roblox.com/users/\(uid)/profile") {
            return (uid, nil, u)
        }
        let encoded = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        guard let u = URL(string: "https://www.roblox.com/search/users?keyword=\(encoded)") else { return nil }
        return (nil, s, u)
    }

    func robloxInfo(for input: String, onUpdate: @escaping () -> Void) -> (text: String, badge: String, url: URL)? {
        guard let parsed = GGConnectionResolvers.parseRobloxInput(input) else { return nil }
        let key = "roblox:\(input.lowercased())"
        let now = Date().timeIntervalSince1970

        self.lock.lock()
        let cached = self.robloxCache[key]
        let needFetch = (cached == nil || (now - (cached?.fetchedAt ?? 0)) > 600.0) && !self.inFlight.contains(key)
        if needFetch { self.inFlight.insert(key) }
        self.lock.unlock()

        if needFetch {
            let fetchById: (Int64) -> Void = { uid in
                let group = DispatchGroup()
                var displayName = ""
                var userName = ""
                var verified = false
                var presenceType = 0
                var lastLocation = ""

                if let infoUrl = URL(string: "https://users.roblox.com/v1/users/\(uid)") {
                    group.enter()
                    URLSession.shared.dataTask(with: infoUrl) { data, _, _ in
                        if let data, let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                            displayName = obj["displayName"] as? String ?? ""
                            userName = obj["name"] as? String ?? ""
                            verified = obj["hasVerifiedBadge"] as? Bool ?? false
                        }
                        group.leave()
                    }.resume()
                }
                if let presUrl = URL(string: "https://presence.roblox.com/v1/presence/users") {
                    group.enter()
                    var req = URLRequest(url: presUrl, timeoutInterval: 8.0)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONSerialization.data(withJSONObject: ["userIds": [uid]])
                    URLSession.shared.dataTask(with: req) { data, _, _ in
                        if let data,
                           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                           let arr = obj["userPresences"] as? [[String: Any]],
                           let first = arr.first {
                            presenceType = first["userPresenceType"] as? Int ?? 0
                            lastLocation = first["lastLocation"] as? String ?? ""
                        }
                        group.leave()
                    }.resume()
                }
                group.notify(queue: .global(qos: .utility)) {
                    defer {
                        self.lock.lock()
                        self.inFlight.remove(key)
                        self.lock.unlock()
                    }
                    let badge: String
                    switch presenceType {
                    case 2: badge = "🟢 В игре"
                    case 1: badge = "🔵 В сети"
                    case 3: badge = "🛠 Studio"
                    default: badge = "⚫ Офлайн"
                    }
                    let namePart: String
                    if !displayName.isEmpty && !userName.isEmpty && displayName.lowercased() != userName.lowercased() {
                        namePart = "\(displayName) (@\(userName))\(verified ? " ✓" : "")"
                    } else if !userName.isEmpty {
                        namePart = "@\(userName)\(verified ? " ✓" : "")"
                    } else {
                        namePart = "ID \(uid)"
                    }
                    let text = (!lastLocation.isEmpty && presenceType == 2) ? "\(namePart) · \(lastLocation)" : namePart
                    let profileUrl = URL(string: "https://www.roblox.com/users/\(uid)/profile") ?? parsed.fallbackUrl
                    let resolved = GGResolvedConnection(
                        displayText: text,
                        statusBadge: badge,
                        profileUrl: profileUrl,
                        fetchedAt: Date().timeIntervalSince1970
                    )
                    self.lock.lock()
                    self.robloxCache[key] = resolved
                    self.lock.unlock()
                    DispatchQueue.main.async { onUpdate() }
                }
            }

            if let uid = parsed.userId {
                fetchById(uid)
            } else if let uname = parsed.username, let lookupUrl = URL(string: "https://users.roblox.com/v1/usernames/users") {
                var req = URLRequest(url: lookupUrl, timeoutInterval: 8.0)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["usernames": [uname], "excludeBannedUsers": false])
                URLSession.shared.dataTask(with: req) { data, _, _ in
                    if let data,
                       let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                       let arr = obj["data"] as? [[String: Any]],
                       let first = arr.first,
                       let uidNum = first["id"] as? NSNumber {
                        fetchById(uidNum.int64Value)
                    } else {
                        self.lock.lock()
                        self.inFlight.remove(key)
                        self.lock.unlock()
                    }
                }.resume()
            } else {
                self.lock.lock()
                self.inFlight.remove(key)
                self.lock.unlock()
            }
        }

        if let cached {
            return (cached.displayText, cached.statusBadge, cached.profileUrl)
        }
        let fallbackText = parsed.username.map { "@\($0) · Roblox" } ?? "Roblox ID \(parsed.userId ?? 0)"
        return (fallbackText, "Roblox", parsed.fallbackUrl)
    }
}

// MARK: - Animated Profile Effects & Avatar Frame Views

private final class GGDiscordEffectView: UIView {
    private var activeEffectId: String = "none"
    private var emitter: CAEmitterLayer?
    private var neonGradient: CAGradientLayer?
    private var boltLayer: CAShapeLayer?
    private var boltTimer: Foundation.Timer?
    private var matrixLabels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.clearEffect()
    }

    func configure(effectId: String) {
        let reduced = UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
        let resolved = reduced ? "none" : effectId
        if resolved == self.activeEffectId {
            return
        }
        self.clearEffect()
        self.activeEffectId = resolved
        if resolved == "none" || resolved.isEmpty {
            return
        }
        switch resolved {
        case "sakura":
            self.setupParticles(color: UIColor(rgb: 0xFFA6C9), birthRate: 7.0, velocity: 38.0, yAccel: 18.0, size: 9.0, fromBottom: false, spin: 1.8)
        case "fire":
            self.setupParticles(color: UIColor(rgb: 0xFF7B00), birthRate: 14.0, velocity: -58.0, yAccel: -22.0, size: 6.5, fromBottom: true, spin: 0.4)
        case "snow":
            self.setupParticles(color: UIColor.white, birthRate: 12.0, velocity: 32.0, yAccel: 12.0, size: 6.0, fromBottom: false, spin: 0.5)
        case "stars":
            self.setupParticles(color: UIColor(rgb: 0xFFE57F), birthRate: 10.0, velocity: 14.0, yAccel: 0.0, size: 7.0, fromBottom: false, spin: 2.2)
        case "neon":
            self.setupNeonWave()
        case "lightning":
            self.setupLightning()
        case "matrix":
            self.setupMatrix()
        default:
            break
        }
        self.setNeedsLayout()
    }

    private func clearEffect() {
        self.boltTimer?.invalidate()
        self.boltTimer = nil
        self.emitter?.removeFromSuperlayer()
        self.emitter = nil
        self.neonGradient?.removeFromSuperlayer()
        self.neonGradient = nil
        self.boltLayer?.removeFromSuperlayer()
        self.boltLayer = nil
        for lbl in self.matrixLabels { lbl.removeFromSuperview() }
        self.matrixLabels.removeAll()
    }

    private func makeParticleImage(color: UIColor, size: CGFloat) -> CGImage? {
        let r = UIGraphicsImageRenderer(size: CGSize(width: size * 2.0, height: size * 2.0))
        let img = r.image { ctx in
            let rect = CGRect(x: 0.0, y: 0.0, width: size * 2.0, height: size * 2.0)
            ctx.cgContext.setFillColor(color.withAlphaComponent(0.92).cgColor)
            ctx.cgContext.setShadow(offset: .zero, blur: size * 0.5, color: color.cgColor)
            ctx.cgContext.fillEllipse(in: rect.insetBy(dx: size * 0.35, dy: size * 0.35))
        }
        return img.cgImage
    }

    private func setupParticles(color: UIColor, birthRate: Float, velocity: CGFloat, yAccel: CGFloat, size: CGFloat, fromBottom: Bool, spin: CGFloat) {
        let layer = CAEmitterLayer()
        layer.emitterShape = .line
        let cell = CAEmitterCell()
        cell.contents = self.makeParticleImage(color: color, size: size)
        cell.birthRate = birthRate
        cell.lifetime = 5.0
        cell.lifetimeRange = 1.8
        cell.velocity = velocity
        cell.velocityRange = abs(velocity) * 0.45
        cell.yAcceleration = yAccel
        cell.xAcceleration = fromBottom ? 0.0 : 8.0
        cell.emissionLongitude = fromBottom ? -.pi / 2.0 : .pi / 2.0
        cell.emissionRange = .pi / 4.0
        cell.scale = 0.75
        cell.scaleRange = 0.45
        cell.alphaSpeed = -0.18
        cell.spin = spin
        cell.spinRange = 1.2
        layer.emitterCells = [cell]
        self.layer.addSublayer(layer)
        self.emitter = layer
    }

    private func setupNeonWave() {
        let g = CAGradientLayer()
        g.colors = [
            UIColor(rgb: 0x00F5FF).withAlphaComponent(0.32).cgColor,
            UIColor(rgb: 0xFF00D4).withAlphaComponent(0.28).cgColor,
            UIColor(rgb: 0x7A1FFF).withAlphaComponent(0.32).cgColor
        ]
        g.startPoint = CGPoint(x: 0.0, y: 0.0)
        g.endPoint = CGPoint(x: 1.0, y: 1.0)
        let anim = CABasicAnimation(keyPath: "colors")
        anim.toValue = [
            UIColor(rgb: 0xFF007F).withAlphaComponent(0.32).cgColor,
            UIColor(rgb: 0x00F5FF).withAlphaComponent(0.28).cgColor,
            UIColor(rgb: 0xFFE600).withAlphaComponent(0.26).cgColor
        ]
        anim.duration = 3.2
        anim.autoreverses = true
        anim.repeatCount = .infinity
        g.add(anim, forKey: "neonShift")
        self.layer.addSublayer(g)
        self.neonGradient = g
    }

    private func setupLightning() {
        let shape = CAShapeLayer()
        shape.strokeColor = UIColor(rgb: 0x9EEBFF).cgColor
        shape.fillColor = UIColor.clear.cgColor
        shape.lineWidth = 2.4
        shape.shadowColor = UIColor(rgb: 0x00E5FF).cgColor
        shape.shadowRadius = 8.0
        shape.shadowOpacity = 0.95
        shape.shadowOffset = .zero
        shape.opacity = 0.0
        self.layer.addSublayer(shape)
        self.boltLayer = shape

        self.boltTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.7, repeats: true) { [weak self] _ in
            self?.flashBolt()
        }
    }

    private func flashBolt() {
        guard let shape = self.boltLayer, self.bounds.width > 40.0, self.bounds.height > 40.0 else { return }
        let path = UIBezierPath()
        var x = CGFloat.random(in: self.bounds.width * 0.12 ... self.bounds.width * 0.88)
        var y: CGFloat = 0.0
        path.move(to: CGPoint(x: x, y: y))
        let steps = 7
        let dy = self.bounds.height / CGFloat(steps)
        for _ in 0 ..< steps {
            x = max(8.0, min(self.bounds.width - 8.0, x + CGFloat.random(in: -34.0 ... 34.0)))
            y += dy
            path.addLine(to: CGPoint(x: x, y: y))
        }
        shape.path = path.cgPath
        let flash = CAKeyframeAnimation(keyPath: "opacity")
        flash.values = [0.0, 1.0, 0.25, 0.95, 0.0]
        flash.keyTimes = [0.0, 0.12, 0.3, 0.45, 1.0]
        flash.duration = 0.42
        shape.add(flash, forKey: "boltFlash")
    }

    private func setupMatrix() {
        let glyphs = ["0", "1", "ｱ", "ｲ", "ｳ", "ｴ", "ｵ", "ｶ", "ｷ", "ｸ", "7", "9"]
        for i in 0 ..< 14 {
            let lbl = UILabel()
            lbl.font = UIFont.monospacedSystemFont(ofSize: 11.0, weight: .bold)
            lbl.textColor = UIColor(rgb: 0x00FF66).withAlphaComponent(0.65)
            lbl.numberOfLines = 0
            lbl.text = (0 ..< 6).map { _ in glyphs.randomElement() ?? "1" }.joined(separator: "\n")
            lbl.sizeToFit()
            lbl.tag = i
            self.addSubview(lbl)
            self.matrixLabels.append(lbl)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let emitter = self.emitter {
            let isFire = self.activeEffectId == "fire"
            emitter.frame = self.bounds
            emitter.emitterPosition = CGPoint(x: self.bounds.midX, y: isFire ? self.bounds.height : -6.0)
            emitter.emitterSize = CGSize(width: max(1.0, self.bounds.width), height: 2.0)
        }
        self.neonGradient?.frame = self.bounds
        self.boltLayer?.frame = self.bounds
        if !self.matrixLabels.isEmpty && self.bounds.width > 20.0 {
            let step = self.bounds.width / CGFloat(self.matrixLabels.count)
            for (idx, lbl) in self.matrixLabels.enumerated() {
                let x = CGFloat(idx) * step + 4.0
                lbl.frame = CGRect(x: x, y: -lbl.bounds.height, width: 16.0, height: lbl.bounds.height)
                if lbl.layer.animation(forKey: "fall") == nil {
                    let anim = CABasicAnimation(keyPath: "position.y")
                    anim.fromValue = -lbl.bounds.height
                    anim.toValue = self.bounds.height + lbl.bounds.height
                    anim.duration = Double.random(in: 2.2 ... 4.4)
                    anim.beginTime = CACurrentMediaTime() + Double.random(in: 0.0 ... 2.0)
                    anim.repeatCount = .infinity
                    lbl.layer.add(anim, forKey: "fall")
                }
            }
        }
    }
}

private final class GGAvatarFrameRingView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()
    private var activeFrameId: String = "none"

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.gradientLayer.type = .conic
        self.gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        self.maskLayer.fillColor = UIColor.clear.cgColor
        self.maskLayer.strokeColor = UIColor.white.cgColor
        self.maskLayer.lineWidth = 4.5
        self.gradientLayer.mask = self.maskLayer
        self.layer.addSublayer(self.gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(frameId: String) {
        if frameId == self.activeFrameId { return }
        self.activeFrameId = frameId
        guard let spec = GGDiscordProfileStore.avatarFrames.first(where: { $0.id == frameId }),
              !spec.colors.isEmpty else {
            self.isHidden = true
            self.gradientLayer.removeAllAnimations()
            return
        }
        self.isHidden = false
        self.gradientLayer.colors = spec.colors.map { $0.cgColor }
        self.layer.shadowColor = (spec.colors.first ?? UIColor.cyan).cgColor
        self.layer.shadowRadius = 7.0
        self.layer.shadowOpacity = 0.85
        self.layer.shadowOffset = .zero

        self.gradientLayer.removeAnimation(forKey: "spin")
        if !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0.0
            spin.toValue = Double.pi * 2.0
            spin.duration = (frameId == "glitch") ? 1.6 : 4.2
            spin.repeatCount = .infinity
            self.gradientLayer.add(spin, forKey: "spin")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.gradientLayer.frame = self.bounds
        let inset = self.maskLayer.lineWidth / 2.0 + 1.0
        self.maskLayer.frame = self.bounds
        self.maskLayer.path = UIBezierPath(ovalIn: self.bounds.insetBy(dx: inset, dy: inset)).cgPath
    }
}

// MARK: - Profile Header & Info Hook Integration

private final class GGDiscordHeaderOverlay {
    private static var assocKey: UInt8 = 0

    private weak var node: ASDisplayNode?
    private weak var bannerContainer: UIView?
    private var peerId: PeerId?
    private var lastWidth: CGFloat = 0.0

    private var bannerImageView: UIImageView?
    private var bannerScrimLayer: CAGradientLayer?
    private var loadedBannerFile: String = ""
    private var effectView: GGDiscordEffectView?
    private var avatarFrameView: GGAvatarFrameRingView?
    private var disposable: Disposable?

    private init(node: ASDisplayNode) {
        self.node = node
        self.disposable = (GGDiscordProfileStore.shared.revisionSignal
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.refresh()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    static func update(_ header: GGPeerInfoHeader) {
        let resolvedPeerId: PeerId? = header.peer?.id ?? (header.isSettings ? header.context.account.peerId : nil)
        guard let peerId = resolvedPeerId else { return }

        let overlay: GGDiscordHeaderOverlay
        if let existing = objc_getAssociatedObject(header.node, &GGDiscordHeaderOverlay.assocKey) as? GGDiscordHeaderOverlay {
            overlay = existing
        } else {
            overlay = GGDiscordHeaderOverlay(node: header.node)
            objc_setAssociatedObject(header.node, &GGDiscordHeaderOverlay.assocKey, overlay, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        overlay.peerId = peerId
        overlay.lastWidth = header.width
        if let bg = header.backgroundContainerView {
            overlay.bannerContainer = bg
        }
        GGDiscordProfileStore.shared.checkGlobalProfile(for: peerId)
        overlay.refresh()
    }

    private func refresh() {
        guard let node = self.node, let peerId = self.peerId else { return }
        let profile = GGDiscordProfileStore.shared.profile(for: peerId)
        let bannerAnchor = self.bannerContainer ?? node.view.subviews.first

        // 1. 4K Banner Image
        if let profile,
           let bannerUrl = GGDiscordProfileStore.shared.bannerFileURL(for: profile),
           let anchor = bannerAnchor {
            let iv: UIImageView
            if let existing = self.bannerImageView {
                iv = existing
            } else {
                iv = UIImageView()
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.isUserInteractionEnabled = false
                let scrim = CAGradientLayer()
                scrim.colors = [
                    UIColor.black.withAlphaComponent(0.18).cgColor,
                    UIColor.clear.cgColor,
                    UIColor.black.withAlphaComponent(0.35).cgColor
                ]
                iv.layer.addSublayer(scrim)
                self.bannerScrimLayer = scrim
                self.bannerImageView = iv
            }
            if self.loadedBannerFile != profile.bannerFileName {
                self.loadedBannerFile = profile.bannerFileName
                iv.image = UIImage(contentsOfFile: bannerUrl.path)
            }
            if iv.superview !== node.view {
                node.view.insertSubview(iv, aboveSubview: anchor)
            }
            let rect = CGRect(x: 0.0, y: 0.0, width: max(self.lastWidth, anchor.frame.width), height: max(0.0, anchor.frame.maxY))
            iv.frame = rect
            self.bannerScrimLayer?.frame = iv.bounds
        } else {
            self.bannerImageView?.removeFromSuperview()
            self.bannerImageView = nil
            self.bannerScrimLayer = nil
            self.loadedBannerFile = ""
        }

        // 2. Animated Profile Effect
        let effectId = profile?.effectId ?? "none"
        if effectId != "none" && !effectId.isEmpty, let anchor = bannerAnchor {
            let ev: GGDiscordEffectView
            if let existing = self.effectView {
                ev = existing
            } else {
                ev = GGDiscordEffectView(frame: .zero)
                self.effectView = ev
            }
            let targetBelow = self.bannerImageView ?? anchor
            if ev.superview !== node.view {
                node.view.insertSubview(ev, aboveSubview: targetBelow)
            }
            ev.frame = CGRect(x: 0.0, y: 0.0, width: max(self.lastWidth, anchor.frame.width), height: max(0.0, anchor.frame.maxY))
            ev.configure(effectId: effectId)
        } else {
            self.effectView?.removeFromSuperview()
            self.effectView = nil
        }

        // 3. Glowing Animated Avatar Frame
        let frameId = profile?.avatarFrameId ?? "none"
        if frameId != "none" && !frameId.isEmpty,
           let avatarRect = self.locateRoundAvatarFrame(in: node.view, headerWidth: self.lastWidth) {
            let ring: GGAvatarFrameRingView
            if let existing = self.avatarFrameView {
                ring = existing
            } else {
                ring = GGAvatarFrameRingView(frame: .zero)
                self.avatarFrameView = ring
            }
            if ring.superview !== node.view {
                node.view.addSubview(ring)
            }
            ring.frame = avatarRect.insetBy(dx: -5.5, dy: -5.5)
            ring.configure(frameId: frameId)
            ring.isHidden = false
        } else {
            self.avatarFrameView?.isHidden = true
        }
    }

    private func locateRoundAvatarFrame(in root: UIView, headerWidth: CGFloat) -> CGRect? {
        guard headerWidth > 100.0 else { return nil }
        let centerX = headerWidth / 2.0
        var best: CGRect?
        func scan(_ view: UIView, depth: Int) {
            if depth > 4 || view.isHidden || view.alpha < 0.25 { return }
            if view is GGDiscordEffectView || view is GGAvatarFrameRingView || view === self.bannerImageView { return }
            let rect = view.convert(view.bounds, to: root)
            let w = rect.width
            let h = rect.height
            if w >= 72.0 && w <= 128.0 && abs(w - h) <= 4.0 && abs(rect.midX - centerX) <= 12.0 && rect.minY >= 10.0 && rect.minY <= 180.0 {
                if view.layer.cornerRadius >= w * 0.35 || view.clipsToBounds {
                    best = rect
                    return
                }
            }
            for sub in view.subviews {
                scan(sub, depth: depth + 1)
                if best != nil { return }
            }
        }
        scan(root, depth: 0)
        return best
    }
}

// MARK: - Public Feature Entry Point

enum GGMediaTokDiscordProfile {
    static func register() {
        GGPeerInfoHooks.headerDidLayout.register({ header in
            GGDiscordHeaderOverlay.update(header)
        }, order: 120)

        GGPeerInfoHooks.infoRows.register({ info in
            return GGMediaTokDiscordProfile.infoRows(info)
        }, order: 120)

        GGPeerInfoHooks.menuItems.register({ info in
            return GGMediaTokDiscordProfile.profileMenuItems(info)
        }, order: 70)
    }

    private static func infoRows(_ info: GGPeerInfoContext) -> [GGPeerInfoRow] {
        let peerId = info.peer.id
        weak let controller = info.controller
        GGDiscordProfileStore.shared.checkGlobalProfile(for: peerId) {
            controller?.requestLayout(transition: .immediate)
        }
        guard let profile = GGDiscordProfileStore.shared.profile(for: peerId) else {
            return []
        }

        var rows: [GGPeerInfoRow] = []
        let context = info.context

        // Full Music Track on Profile
        if !profile.musicFileName.isEmpty || !profile.musicUrl.isEmpty {
            let isPlaying = GGProfileMusicPlayer.shared.isPlaying(peerId: peerId)
            let titleText = profile.musicTitle.isEmpty ? "Трек профиля (нажмите для воспроизведения)" : profile.musicTitle
            let badgeText = isPlaying ? "⏸ Пауза" : "▶️ Слушать (Фулл)"
            rows.append(GGPeerInfoRow(
                id: "mediatok.discord.music",
                label: "🎵 Музыка профиля",
                text: titleText,
                rightLabel: badgeText,
                action: {
                    GGProfileMusicPlayer.shared.toggle(peerId: peerId, profile: profile) {
                        controller?.requestLayout(transition: .immediate)
                    }
                },
                longTapAction: {
                    GGMediaTokDiscordProfile.copyAndToast(titleText, context: context, controller: controller)
                }
            ))
        }

        if !profile.customStatus.isEmpty {
            let status = profile.customStatus
            rows.append(GGPeerInfoRow(
                id: "mediatok.discord.status",
                label: "Статус MediaTok",
                text: status,
                longTapAction: {
                    GGMediaTokDiscordProfile.copyAndToast(status, context: context, controller: controller)
                }
            ))
        }

        if !profile.steamInput.isEmpty,
           let steam = GGConnectionResolvers.shared.steamInfo(for: profile.steamInput, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            rows.append(GGPeerInfoRow(
                id: "mediatok.discord.steam",
                label: "Steam",
                text: steam.text,
                rightLabel: steam.badge,
                action: {
                    UIApplication.shared.open(steam.url, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    GGMediaTokDiscordProfile.copyAndToast(steam.url.absoluteString, context: context, controller: controller)
                }
            ))
        }

        if !profile.robloxInput.isEmpty,
           let roblox = GGConnectionResolvers.shared.robloxInfo(for: profile.robloxInput, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            rows.append(GGPeerInfoRow(
                id: "mediatok.discord.roblox",
                label: "Roblox",
                text: roblox.text,
                rightLabel: roblox.badge,
                action: {
                    UIApplication.shared.open(roblox.url, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    GGMediaTokDiscordProfile.copyAndToast(roblox.url.absoluteString, context: context, controller: controller)
                }
            ))
        }

        return rows
    }

    private static func profileMenuItems(_ info: GGPeerInfoContext) -> [ContextMenuItem] {
        if info.isSettings { return [] }
        let peerId = info.peer.id
        let isOwn = peerId == info.context.account.peerId
        weak let controller = info.controller
        let title = isOwn ? "Discord-профиль / Музыка / Steam" : "Оформление профиля MediaTok"
        return [.action(ContextMenuActionItem(text: title, icon: { theme in
            return UIImage(systemName: "sparkles")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
        }, action: { contextController, _ in
            contextController?.dismiss(completion: nil)
            GGMediaTokDiscordProfile.presentEditor(peerId: peerId, isOwn: isOwn, onDone: {
                controller?.requestLayout(transition: .immediate)
            })
        }))]
    }

    static func presentOwnEditor(context: GGMenuContext) {
        let vc = GGDiscordProfileEditorViewController(peerId: context.context.account.peerId, isOwn: true, onDone: nil)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        context.presentNative(nav)
    }

    static func presentEditor(peerId: PeerId, isOwn: Bool, onDone: (() -> Void)?) {
        DispatchQueue.main.async {
            let vc = GGDiscordProfileEditorViewController(peerId: peerId, isOwn: isOwn, onDone: onDone)
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .pageSheet
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let root = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
                return
            }
            var presenter = root
            while let next = presenter.presentedViewController {
                presenter = next
            }
            presenter.present(nav, animated: true)
        }
    }

    private static func copyAndToast(_ text: String, context: AccountContext, controller: ViewController?) {
        UIPasteboard.general.string = text
        guard let controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(
            presentationData: presentationData,
            content: .copy(text: GGStrings.Appearance.Profile.copied),
            elevatedLayout: false,
            animateInAsReplacement: false,
            action: { _ in return false }
        ), in: .current)
    }
}

// MARK: - Native UIKit Discord Profile Studio Editor

private final class GGDiscordProfileEditorViewController: UIViewController, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let peerId: PeerId
    private let isOwn: Bool
    private let onDone: (() -> Void)?

    private var draft: GGDiscordProfileData
    private var pendingBannerData: Data?
    private var pendingMusicData: Data?
    private var pendingMusicExt: String = "mp3"

    private let bannerPreview = UIImageView()
    private let effectButton = UIButton(type: .system)
    private let frameButton = UIButton(type: .system)
    private let statusField = UITextField()
    private let musicTitleField = UITextField()
    private let musicFileStatusLabel = UILabel()
    private let steamField = UITextField()
    private let robloxField = UITextField()

    init(peerId: PeerId, isOwn: Bool, onDone: (() -> Void)?) {
        self.peerId = peerId
        self.isOwn = isOwn
        self.onDone = onDone
        self.draft = GGDiscordProfileStore.shared.profile(for: peerId) ?? GGDiscordProfileData()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = self.isOwn ? "Discord-профиль MediaTok" : "Профиль MediaTok"
        self.view.backgroundColor = .systemGroupedBackground

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(self.saveTapped))

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .onDrag
        self.view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 14.0),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16.0),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -24.0),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32.0)
        ])

        let infoLabel = UILabel()
        infoLabel.numberOfLines = 0
        infoLabel.font = UIFont.systemFont(ofSize: 13.0)
        infoLabel.textColor = .secondaryLabel
        infoLabel.text = self.isOwn
            ? "Ваш 4K-баннер, эффект, рамка, ФУЛЛ-ТРЕК музыки, статус, Steam и Roblox автоматически синхронизируются для всех пользователей MediaTok!"
            : "Локальная настройка оформления для этого профиля (или нажмите «Обновить из облака» для загрузки профиля MediaTok)."
        stack.addArrangedSubview(infoLabel)

        // Banner Preview + Buttons
        self.bannerPreview.backgroundColor = .secondarySystemGroupedBackground
        self.bannerPreview.contentMode = .scaleAspectFill
        self.bannerPreview.clipsToBounds = true
        self.bannerPreview.layer.cornerRadius = 12.0
        self.bannerPreview.heightAnchor.constraint(equalToConstant: 120.0).isActive = true
        if let url = GGDiscordProfileStore.shared.bannerFileURL(for: self.draft) {
            self.bannerPreview.image = UIImage(contentsOfFile: url.path)
        }
        stack.addArrangedSubview(self.bannerPreview)

        let bannerBtns = UIStackView()
        bannerBtns.axis = .horizontal
        bannerBtns.spacing = 8.0
        bannerBtns.distribution = .fillEqually
        let pickBtn = self.makeActionButton(title: "Выбрать 4K баннер", action: #selector(self.pickBannerTapped))
        let clearBannerBtn = self.makeActionButton(title: "Убрать баннер", action: #selector(self.clearBannerTapped))
        clearBannerBtn.setTitleColor(.systemRed, for: .normal)
        bannerBtns.addArrangedSubview(pickBtn)
        bannerBtns.addArrangedSubview(clearBannerBtn)
        stack.addArrangedSubview(bannerBtns)

        // Effect & Avatar Frame pickers
        stack.addArrangedSubview(self.makeSectionLabel("Анимированный эффект профиля"))
        self.effectButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.effectButton.backgroundColor = .secondarySystemGroupedBackground
        self.effectButton.layer.cornerRadius = 10.0
        self.effectButton.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        self.effectButton.addTarget(self, action: #selector(self.pickEffectTapped), for: .touchUpInside)
        stack.addArrangedSubview(self.effectButton)

        stack.addArrangedSubview(self.makeSectionLabel("Рамка на аватарку (анимация)"))
        self.frameButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.frameButton.backgroundColor = .secondarySystemGroupedBackground
        self.frameButton.layer.cornerRadius = 10.0
        self.frameButton.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        self.frameButton.addTarget(self, action: #selector(self.pickFrameTapped), for: .touchUpInside)
        stack.addArrangedSubview(self.frameButton)

        // Full Track Music on Profile
        stack.addArrangedSubview(self.makeSectionLabel("🎵 Музыкальный трек на профиле (ФУЛЛ ТРЕК без обрезки)"))
        self.configureField(self.musicTitleField, placeholder: "Название трека (напр. Miyagi — Captain)", text: self.draft.musicTitle)
        stack.addArrangedSubview(self.musicTitleField)

        self.musicFileStatusLabel.font = UIFont.systemFont(ofSize: 12.0)
        self.musicFileStatusLabel.textColor = .secondaryLabel
        self.musicFileStatusLabel.numberOfLines = 1
        stack.addArrangedSubview(self.musicFileStatusLabel)

        let musicBtns = UIStackView()
        musicBtns.axis = .horizontal
        musicBtns.spacing = 8.0
        musicBtns.distribution = .fillEqually
        let pickMusicBtn = self.makeActionButton(title: "Выбрать аудио (.mp3/.m4a)", action: #selector(self.pickMusicTapped))
        let clearMusicBtn = self.makeActionButton(title: "Убрать трек", action: #selector(self.clearMusicTapped))
        clearMusicBtn.setTitleColor(.systemRed, for: .normal)
        musicBtns.addArrangedSubview(pickMusicBtn)
        musicBtns.addArrangedSubview(clearMusicBtn)
        stack.addArrangedSubview(musicBtns)

        // Custom Status
        stack.addArrangedSubview(self.makeSectionLabel("Статус профиля (как в Discord)"))
        self.configureField(self.statusField, placeholder: "Например: 🎮 Играю в CS2 / 🎧 Вайблю", text: self.draft.customStatus)
        stack.addArrangedSubview(self.statusField)

        // Steam Integration
        stack.addArrangedSubview(self.makeSectionLabel("Интеграция Steam (ник / SteamID64 / ссылка)"))
        self.configureField(self.steamField, placeholder: "Например: gaben или 76561197960287930", text: self.draft.steamInput)
        self.steamField.autocapitalizationType = .none
        self.steamField.autocorrectionType = .no
        stack.addArrangedSubview(self.steamField)

        // Roblox Integration
        stack.addArrangedSubview(self.makeSectionLabel("Интеграция Roblox (ник / UserID / ссылка)"))
        self.configureField(self.robloxField, placeholder: "Например: Builderman или 156", text: self.draft.robloxInput)
        self.robloxField.autocapitalizationType = .none
        self.robloxField.autocorrectionType = .no
        stack.addArrangedSubview(self.robloxField)

        if !self.isOwn {
            let syncBtn = self.makeActionButton(title: "Обновить профиль из облака MediaTok", action: #selector(self.forceSyncTapped))
            stack.addArrangedSubview(syncBtn)
        }

        let resetBtn = self.makeActionButton(title: "Сбросить оформление", action: #selector(self.resetAllTapped))
        resetBtn.setTitleColor(.systemRed, for: .normal)
        stack.addArrangedSubview(resetBtn)

        self.refreshPickers()
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let lbl = UILabel()
        lbl.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        lbl.textColor = .secondaryLabel
        lbl.text = text
        return lbl
    }

    private func makeActionButton(title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        b.backgroundColor = .secondarySystemGroupedBackground
        b.layer.cornerRadius = 10.0
        b.heightAnchor.constraint(equalToConstant: 42.0).isActive = true
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func configureField(_ tf: UITextField, placeholder: String, text: String) {
        tf.borderStyle = .roundedRect
        tf.backgroundColor = .secondarySystemGroupedBackground
        tf.placeholder = placeholder
        tf.text = text
        tf.clearButtonMode = .whileEditing
        tf.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
    }

    private func refreshPickers() {
        let effectTitle = GGDiscordProfileStore.effects.first(where: { $0.id == self.draft.effectId })?.title ?? "Выкл."
        self.effectButton.setTitle("Эффект: \(effectTitle)  ▾", for: .normal)
        let frameTitle = GGDiscordProfileStore.avatarFrames.first(where: { $0.id == self.draft.avatarFrameId })?.title ?? "Выкл."
        self.frameButton.setTitle("Рамка: \(frameTitle)  ▾", for: .normal)
        if let data = self.pendingMusicData {
            self.musicFileStatusLabel.text = "Выбран фулл-трек (\(data.count / 1024) КБ) — готов к загрузке"
        } else if !self.draft.musicFileName.isEmpty || !self.draft.musicUrl.isEmpty {
            self.musicFileStatusLabel.text = "Фулл-трек прикреплён ✅"
        } else {
            self.musicFileStatusLabel.text = "Трек не выбран"
        }
    }

    @objc private func pickBannerTapped() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        self.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
            guard let url, let jpegData = GGDiscordProfileEditorViewController.encode4kBanner(from: url) else { return }
            DispatchQueue.main.async {
                guard let strongSelf = self else { return }
                strongSelf.pendingBannerData = jpegData
                strongSelf.draft.bannerUrl = ""
                strongSelf.bannerPreview.image = UIImage(data: jpegData)
            }
        }
    }

    @objc private func pickMusicTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio, .mp3, .mpeg4Audio], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        self.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first,
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            return
        }
        self.pendingMusicData = data
        self.pendingMusicExt = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        self.draft.musicUrl = ""
        if (self.musicTitleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.musicTitleField.text = url.deletingPathExtension().lastPathComponent
        }
        try? FileManager.default.removeItem(at: url)
        self.refreshPickers()
    }

    @objc private func clearMusicTapped() {
        self.pendingMusicData = nil
        self.draft.musicFileName = ""
        self.draft.musicUrl = ""
        self.draft.musicTitle = ""
        self.musicTitleField.text = ""
        GGProfileMusicPlayer.shared.stop()
        self.refreshPickers()
    }

    private static func encode4kBanner(from url: URL) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3840
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    @objc private func clearBannerTapped() {
        self.pendingBannerData = nil
        self.draft.bannerFileName = ""
        self.draft.bannerUrl = ""
        self.bannerPreview.image = nil
    }

    @objc private func pickEffectTapped() {
        let sheet = UIAlertController(title: "Эффект профиля", message: nil, preferredStyle: .actionSheet)
        for item in GGDiscordProfileStore.effects {
            sheet.addAction(UIAlertAction(title: item.title, style: .default, handler: { [weak self] _ in
                self?.draft.effectId = item.id
                self?.refreshPickers()
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.configurePopover(sheet, source: self.effectButton)
        self.present(sheet, animated: true)
    }

    @objc private func pickFrameTapped() {
        let sheet = UIAlertController(title: "Рамка аватарки", message: nil, preferredStyle: .actionSheet)
        for item in GGDiscordProfileStore.avatarFrames {
            sheet.addAction(UIAlertAction(title: item.title, style: .default, handler: { [weak self] _ in
                self?.draft.avatarFrameId = item.id
                self?.refreshPickers()
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.configurePopover(sheet, source: self.frameButton)
        self.present(sheet, animated: true)
    }

    private func configurePopover(_ sheet: UIAlertController, source: UIView) {
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = source
            pop.sourceRect = source.bounds
        }
    }

    @objc private func forceSyncTapped() {
        GGDiscordProfileStore.shared.checkGlobalProfile(for: self.peerId, force: true) { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.draft = GGDiscordProfileStore.shared.profile(for: strongSelf.peerId) ?? GGDiscordProfileData()
            strongSelf.statusField.text = strongSelf.draft.customStatus
            strongSelf.musicTitleField.text = strongSelf.draft.musicTitle
            strongSelf.steamField.text = strongSelf.draft.steamInput
            strongSelf.robloxField.text = strongSelf.draft.robloxInput
            if let url = GGDiscordProfileStore.shared.bannerFileURL(for: strongSelf.draft) {
                strongSelf.bannerPreview.image = UIImage(contentsOfFile: url.path)
            }
            strongSelf.refreshPickers()
            strongSelf.onDone?()
        }
    }

    @objc private func resetAllTapped() {
        self.pendingBannerData = nil
        self.pendingMusicData = nil
        self.draft = GGDiscordProfileData()
        self.bannerPreview.image = nil
        self.statusField.text = ""
        self.musicTitleField.text = ""
        self.steamField.text = ""
        self.robloxField.text = ""
        GGProfileMusicPlayer.shared.stop()
        self.refreshPickers()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func saveTapped() {
        self.view.endEditing(true)
        self.draft.customStatus = self.statusField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.musicTitle = self.musicTitleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.steamInput = self.steamField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.robloxInput = self.robloxField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let data = self.pendingBannerData,
           let saved = GGDiscordProfileStore.shared.saveBannerData(data, for: self.peerId) {
            self.draft.bannerFileName = saved
            self.draft.bannerUrl = ""
        }
        if let mData = self.pendingMusicData,
           let savedMusic = GGDiscordProfileStore.shared.saveMusicData(mData, ext: self.pendingMusicExt, for: self.peerId) {
            self.draft.musicFileName = savedMusic
            self.draft.musicUrl = ""
        }

        GGDiscordProfileStore.shared.setProfile(self.draft, for: self.peerId, publishGlobally: self.isOwn)
        self.onDone?()
        self.dismiss(animated: true)
    }
}
