import Foundation
import UIKit
import CoreImage
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

public struct GGProfileTrack: Codable, Equatable {
    public var id: String
    public var title: String
    public var fileName: String
    public var url: String

    public init(id: String = UUID().uuidString, title: String, fileName: String = "", url: String = "") {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.url = url
    }
}

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
    public var musicPlaylist: [GGProfileTrack]
    public var voiceBioFileName: String
    public var voiceBioUrl: String
    public var musicServiceKind: String
    public var musicServiceUser: String
    public var twitchInput: String
    public var githubInput: String
    public var youtubeInput: String
    public var tiktokInput: String
    public var kickInput: String
    public var discordTag: String
    public var nitroThemeId: String
    public var duoUsername: String
    public var duoLabel: String
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
        case musicPlaylist
        case voiceBioFileName
        case voiceBioUrl
        case musicServiceKind
        case musicServiceUser
        case twitchInput
        case githubInput
        case youtubeInput
        case tiktokInput
        case kickInput
        case discordTag
        case nitroThemeId
        case duoUsername
        case duoLabel
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
        musicPlaylist: [GGProfileTrack] = [],
        voiceBioFileName: String = "",
        voiceBioUrl: String = "",
        musicServiceKind: String = "none",
        musicServiceUser: String = "",
        twitchInput: String = "",
        githubInput: String = "",
        youtubeInput: String = "",
        tiktokInput: String = "",
        kickInput: String = "",
        discordTag: String = "",
        nitroThemeId: String = "none",
        duoUsername: String = "",
        duoLabel: String = "",
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
        self.musicPlaylist = musicPlaylist
        self.voiceBioFileName = voiceBioFileName
        self.voiceBioUrl = voiceBioUrl
        self.musicServiceKind = musicServiceKind
        self.musicServiceUser = musicServiceUser
        self.twitchInput = twitchInput
        self.githubInput = githubInput
        self.youtubeInput = youtubeInput
        self.tiktokInput = tiktokInput
        self.kickInput = kickInput
        self.discordTag = discordTag
        self.nitroThemeId = nitroThemeId
        self.duoUsername = duoUsername
        self.duoLabel = duoLabel
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
        self.musicPlaylist = try c.decodeIfPresent([GGProfileTrack].self, forKey: .musicPlaylist) ?? []
        self.voiceBioFileName = try c.decodeIfPresent(String.self, forKey: .voiceBioFileName) ?? ""
        self.voiceBioUrl = try c.decodeIfPresent(String.self, forKey: .voiceBioUrl) ?? ""
        self.musicServiceKind = try c.decodeIfPresent(String.self, forKey: .musicServiceKind) ?? "none"
        self.musicServiceUser = try c.decodeIfPresent(String.self, forKey: .musicServiceUser) ?? ""
        self.twitchInput = try c.decodeIfPresent(String.self, forKey: .twitchInput) ?? ""
        self.githubInput = try c.decodeIfPresent(String.self, forKey: .githubInput) ?? ""
        self.youtubeInput = try c.decodeIfPresent(String.self, forKey: .youtubeInput) ?? ""
        self.tiktokInput = try c.decodeIfPresent(String.self, forKey: .tiktokInput) ?? ""
        self.kickInput = try c.decodeIfPresent(String.self, forKey: .kickInput) ?? ""
        self.discordTag = try c.decodeIfPresent(String.self, forKey: .discordTag) ?? ""
        self.nitroThemeId = try c.decodeIfPresent(String.self, forKey: .nitroThemeId) ?? "none"
        self.duoUsername = try c.decodeIfPresent(String.self, forKey: .duoUsername) ?? ""
        self.duoLabel = try c.decodeIfPresent(String.self, forKey: .duoLabel) ?? ""
        self.updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }

    public var effectivePlaylist: [GGProfileTrack] {
        if !self.musicPlaylist.isEmpty {
            return self.musicPlaylist
        }
        if !self.musicFileName.isEmpty || !self.musicUrl.isEmpty {
            return [GGProfileTrack(
                id: "legacy_single",
                title: self.musicTitle.isEmpty ? "Трек профиля" : self.musicTitle,
                fileName: self.musicFileName,
                url: self.musicUrl
            )]
        }
        return []
    }

    public var isEmpty: Bool {
        return self.bannerFileName.isEmpty
            && self.bannerUrl.isEmpty
            && (self.effectId.isEmpty || self.effectId == "none")
            && (self.avatarFrameId.isEmpty || self.avatarFrameId == "none")
            && (self.nitroThemeId.isEmpty || self.nitroThemeId == "none")
            && self.customStatus.isEmpty
            && self.steamInput.isEmpty
            && self.robloxInput.isEmpty
            && self.musicFileName.isEmpty
            && self.musicUrl.isEmpty
            && self.musicTitle.isEmpty
            && self.musicPlaylist.isEmpty
            && self.voiceBioFileName.isEmpty
            && self.voiceBioUrl.isEmpty
            && (self.musicServiceKind.isEmpty || self.musicServiceKind == "none" || self.musicServiceUser.isEmpty)
            && self.twitchInput.isEmpty
            && self.githubInput.isEmpty
            && self.youtubeInput.isEmpty
            && self.tiktokInput.isEmpty
            && self.kickInput.isEmpty
            && self.discordTag.isEmpty
            && self.duoUsername.isEmpty
    }
}

// MARK: - Infinite Playlist & Voice Bio Player

final class GGProfileMusicPlayer {
    static let shared = GGProfileMusicPlayer()

    private var player: AVPlayer?
    private var playingPeerKey: String?
    private var endObserver: NSObjectProtocol?
    private var queue: [GGProfileTrack] = []
    private var currentIndex: Int = 0
    private var isShuffle = false
    private var stateCallback: (() -> Void)?

    private var voicePlayer: AVPlayer?
    private var voicePeerKey: String?
    private var voiceEndObserver: NSObjectProtocol?
    private var voiceCallback: (() -> Void)?

    private init() {}

    var shuffleEnabled: Bool {
        return self.isShuffle
    }

    func isPlaying(peerId: PeerId) -> Bool {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        return self.playingPeerKey == key && (self.player?.rate ?? 0.0) > 0.0
    }

    func isPlayingVoiceBio(peerId: PeerId) -> Bool {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        return self.voicePeerKey == key && (self.voicePlayer?.rate ?? 0.0) > 0.0
    }

    func currentTrackSummary(peerId: PeerId, playlist: [GGProfileTrack]) -> (title: String, positionText: String) {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        if self.playingPeerKey == key,
           !self.queue.isEmpty,
           self.currentIndex >= 0,
           self.currentIndex < self.queue.count {
            let track = self.queue[self.currentIndex]
            return (track.title, "\(self.currentIndex + 1)/\(self.queue.count)")
        }
        if let first = playlist.first {
            let countStr = playlist.count > 1 ? "1/\(playlist.count)" : "Фулл"
            return (first.title, countStr)
        }
        return ("Трек профиля", "")
    }

    func stop() {
        self.player?.pause()
        self.player = nil
        self.playingPeerKey = nil
        self.queue = []
        self.currentIndex = 0
        if let obs = self.endObserver {
            NotificationCenter.default.removeObserver(obs)
            self.endObserver = nil
        }
        self.stateCallback = nil
    }

    func stopVoiceBio() {
        self.voicePlayer?.pause()
        self.voicePlayer = nil
        self.voicePeerKey = nil
        if let obs = self.voiceEndObserver {
            NotificationCenter.default.removeObserver(obs)
            self.voiceEndObserver = nil
        }
        let cb = self.voiceCallback
        self.voiceCallback = nil
        cb?()
    }

    func toggle(peerId: PeerId, profile: GGDiscordProfileData, onStateChanged: (() -> Void)?) {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        if self.isPlaying(peerId: peerId) {
            self.stop()
            onStateChanged?()
            return
        }
        let playlist = profile.effectivePlaylist
        guard !playlist.isEmpty else { return }
        self.stopVoiceBio()
        self.stop()
        self.queue = playlist
        self.playingPeerKey = key
        self.currentIndex = self.isShuffle ? Int.random(in: 0 ..< playlist.count) : 0
        self.stateCallback = onStateChanged
        self.playCurrentItem()
    }

    func next(peerId: PeerId, profile: GGDiscordProfileData, onStateChanged: (() -> Void)?) {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        let playlist = profile.effectivePlaylist
        guard !playlist.isEmpty else { return }
        if self.playingPeerKey != key || self.queue.isEmpty {
            self.toggle(peerId: peerId, profile: profile, onStateChanged: onStateChanged)
            return
        }
        self.queue = playlist
        self.stateCallback = onStateChanged ?? self.stateCallback
        if self.isShuffle && self.queue.count > 1 {
            var nextIdx = Int.random(in: 0 ..< self.queue.count)
            if nextIdx == self.currentIndex {
                nextIdx = (self.currentIndex + 1) % self.queue.count
            }
            self.currentIndex = nextIdx
        } else {
            self.currentIndex = (self.currentIndex + 1) % self.queue.count
        }
        self.playCurrentItem()
    }

    func previous(peerId: PeerId, profile: GGDiscordProfileData, onStateChanged: (() -> Void)?) {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        let playlist = profile.effectivePlaylist
        guard !playlist.isEmpty else { return }
        if self.playingPeerKey != key || self.queue.isEmpty {
            self.toggle(peerId: peerId, profile: profile, onStateChanged: onStateChanged)
            return
        }
        self.queue = playlist
        self.stateCallback = onStateChanged ?? self.stateCallback
        self.currentIndex = (self.currentIndex - 1 + self.queue.count) % self.queue.count
        self.playCurrentItem()
    }

    func toggleShuffle() {
        self.isShuffle.toggle()
        self.stateCallback?()
    }

    private func playCurrentItem() {
        guard !self.queue.isEmpty else {
            self.stop()
            return
        }
        if self.currentIndex < 0 || self.currentIndex >= self.queue.count {
            self.currentIndex = 0
        }
        let track = self.queue[self.currentIndex]
        let url: URL?
        if let local = GGDiscordProfileStore.shared.trackFileURL(track) {
            url = local
        } else if let remote = GGMediaTokCoreLogic.isAllowedMediaURL(track.url) {
            url = remote
        } else {
            url = nil
        }
        guard let playableUrl = url else {
            self.stop()
            self.stateCallback?()
            return
        }
        if let obs = self.endObserver {
            NotificationCenter.default.removeObserver(obs)
            self.endObserver = nil
        }
        self.player?.pause()
        let _ = try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        let _ = try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: playableUrl)
        let av = AVPlayer(playerItem: item)
        self.player = av
        self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let strongSelf = self, !strongSelf.queue.isEmpty else { return }
            if strongSelf.isShuffle && strongSelf.queue.count > 1 {
                var nextIdx = Int.random(in: 0 ..< strongSelf.queue.count)
                if nextIdx == strongSelf.currentIndex {
                    nextIdx = (strongSelf.currentIndex + 1) % strongSelf.queue.count
                }
                strongSelf.currentIndex = nextIdx
            } else {
                strongSelf.currentIndex = (strongSelf.currentIndex + 1) % strongSelf.queue.count
            }
            strongSelf.playCurrentItem()
        }
        av.play()
        self.stateCallback?()
    }

    func toggleVoiceBio(peerId: PeerId, profile: GGDiscordProfileData, onStateChanged: (() -> Void)?) {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        if self.isPlayingVoiceBio(peerId: peerId) {
            self.stopVoiceBio()
            onStateChanged?()
            return
        }
        let targetUrl: URL?
        if let local = GGDiscordProfileStore.shared.voiceBioFileURL(for: profile) {
            targetUrl = local
        } else if let remote = GGMediaTokCoreLogic.isAllowedMediaURL(profile.voiceBioUrl) {
            targetUrl = remote
        } else {
            targetUrl = nil
        }
        guard let url = targetUrl else { return }

        self.stop()
        self.stopVoiceBio()
        let _ = try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        let _ = try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let av = AVPlayer(playerItem: item)
        self.voicePlayer = av
        self.voicePeerKey = key
        self.voiceCallback = onStateChanged
        self.voiceEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.stopVoiceBio()
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

    static let nitroThemes: [(id: String, title: String, colors: [UIColor])] = [
        ("none", "Выкл. (стандарт)", []),
        ("cyber_cyan", "Кибер-Циан 💎", [UIColor(rgb: 0x00F5FF), UIColor(rgb: 0x3A0CA3)]),
        ("neon_sakura", "Неон Сакура 🌸", [UIColor(rgb: 0xFF4D8D), UIColor(rgb: 0x7209B7)]),
        ("crimson_gold", "Багрянец и Золото 👑", [UIColor(rgb: 0xFF9F1C), UIColor(rgb: 0x9B002C)]),
        ("emerald_matrix", "Изумруд Матрицы 💚", [UIColor(rgb: 0x00F5A0), UIColor(rgb: 0x004E64)]),
        ("royal_violet", "Королевский Неон 🔮", [UIColor(rgb: 0xB5179E), UIColor(rgb: 0x240046)]),
        ("sunset_fire", "Огненный Закат 🔥", [UIColor(rgb: 0xFF512F), UIColor(rgb: 0x810034)])
    ]

    static let musicServices: [(id: String, title: String)] = [
        ("none", "Выкл."),
        ("lastfm", "Last.fm (Spotify / Яндекс / VK / Apple Music)"),
        ("listenbrainz", "ListenBrainz (Open Scrobbler)")
    ]

    private let lock = NSLock()
    private let ownPeersDefaultsKey = "mediatok.discord.own_peers.v1"
    private let heartbeatDefaultsKey = "mediatok.discord.last_heartbeat.v1"
    private var loaded = false
    private var entries: [String: GGDiscordProfileData] = [:]
    private var lastSyncCheck: [String: TimeInterval] = [:]
    private let revisionPromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    private var revisionCounter: Int32 = 0
    var activeAccountPeerId: PeerId?

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

    private func voiceBioDir() -> URL {
        return self.rootDir().appendingPathComponent("discord_voice_bio", isDirectory: true)
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

    private func recordRevisionLocked() -> Int32 {
        self.revisionCounter = self.revisionCounter &+ 1
        return self.revisionCounter
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

    func trackFileURL(_ track: GGProfileTrack) -> URL? {
        guard !track.fileName.isEmpty else { return nil }
        let url = self.musicDir().appendingPathComponent(track.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func voiceBioFileURL(for profile: GGDiscordProfileData) -> URL? {
        guard !profile.voiceBioFileName.isEmpty else { return nil }
        let url = self.voiceBioDir().appendingPathComponent(profile.voiceBioFileName)
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
        let uid = String(UUID().uuidString.prefix(8))
        let fileName = "track_\(GGDiscordProfileStore.keyString(for: peerId))_\(Int64(Date().timeIntervalSince1970 * 1000.0))_\(uid).\(cleanExt)"
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            return nil
        }
        return fileName
    }

    func saveVoiceBioData(_ data: Data, ext: String, for peerId: PeerId) -> String? {
        let dir = self.voiceBioDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cleanExt = GGMediaTokCoreLogic.sanitizeAudioExtension(ext)
        let fileName = "vbio_\(GGDiscordProfileStore.keyString(for: peerId))_\(Int64(Date().timeIntervalSince1970 * 1000.0)).\(cleanExt)"
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            return nil
        }
        return fileName
    }

    func savePlaylistTrack(data: Data, ext: String, title: String, for peerId: PeerId) -> GGProfileTrack? {
        guard !data.isEmpty, data.count <= 25 * 1024 * 1024,
              let fileName = self.saveMusicData(data, ext: ext, for: peerId) else {
            return nil
        }
        let cleanTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        return GGProfileTrack(
            id: UUID().uuidString,
            title: cleanTitle.isEmpty ? "Трек профиля" : cleanTitle,
            fileName: fileName,
            url: ""
        )
    }

    @discardableResult
    func addUploadedTrackToOwnProfile(data: Data, ext: String, title: String) -> Bool {
        guard let peerId = self.activeAccountPeerId,
              let track = self.savePlaylistTrack(data: data, ext: ext, title: title, for: peerId) else {
            return false
        }
        var current = self.profile(for: peerId) ?? GGDiscordProfileData()
        var tracks = current.effectivePlaylist
        tracks.append(track)
        current.musicPlaylist = tracks
        if current.musicFileName.isEmpty {
            current.musicFileName = track.fileName
            current.musicTitle = track.title
            current.musicUrl = track.url
        }
        self.setProfile(current, for: peerId, publishGlobally: true)
        return true
    }

    func setProfile(_ profile: GGDiscordProfileData, for peerId: PeerId, publishGlobally: Bool) {
        let key = GGDiscordProfileStore.keyString(for: peerId)
        var updated = profile
        updated.updatedAt = Int64(Date().timeIntervalSince1970)
        if let firstTrack = updated.musicPlaylist.first {
            updated.musicFileName = firstTrack.fileName
            updated.musicUrl = firstTrack.url
            updated.musicTitle = firstTrack.title
        }

        self.lock.lock()
        self.ensureLoadedLocked()
        let prev = self.entries[key]
        let oldBanner = prev?.bannerFileName ?? ""
        let oldVoice = prev?.voiceBioFileName ?? ""
        var oldMusicFiles = Set((prev?.musicPlaylist ?? []).map { $0.fileName }.filter { !$0.isEmpty })
        if let prevLegacy = prev?.musicFileName, !prevLegacy.isEmpty {
            oldMusicFiles.insert(prevLegacy)
        }
        var keptMusicFiles = Set(updated.musicPlaylist.map { $0.fileName }.filter { !$0.isEmpty })
        if !updated.musicFileName.isEmpty {
            keptMusicFiles.insert(updated.musicFileName)
        }

        if updated.isEmpty {
            self.entries.removeValue(forKey: key)
        } else {
            self.entries[key] = updated
        }
        if !oldBanner.isEmpty && oldBanner != updated.bannerFileName {
            try? FileManager.default.removeItem(at: self.bannersDir().appendingPathComponent(oldBanner))
        }
        if !oldVoice.isEmpty && oldVoice != updated.voiceBioFileName {
            try? FileManager.default.removeItem(at: self.voiceBioDir().appendingPathComponent(oldVoice))
        }
        for obsolete in oldMusicFiles where !keptMusicFiles.contains(obsolete) {
            try? FileManager.default.removeItem(at: self.musicDir().appendingPathComponent(obsolete))
        }
        self.persistLocked()
        let nextRevision = self.recordRevisionLocked()
        self.lock.unlock()
        self.revisionPromise.set(nextRevision)

        if publishGlobally {
            self.markOwnPeer(key, isOwn: !updated.isEmpty)
            self.updateHeartbeat(for: key, ts: Date().timeIntervalSince1970)
            if !updated.isEmpty {
                self.publishGlobalProfile(updated, for: peerId)
            }
        }
    }

    // MARK: - Catbox + ntfy Global Sync (4K Banner + Infinite Playlist + Voice Bio, Hardened)

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
        syncedPlaylist: [[String: String]],
        voiceBioUrl: String,
        ts: Int64,
        dialogId: Int64,
        completion: (() -> Void)? = nil
    ) {
        guard let ntfyUrl = URL(string: "https://ntfy.sh/mtprof_v1_\(dialogId)") else { return }
        var visualBio = ""
        if dialogId > 0, let peerKey = GGPeerKey(namespace: 0, id: dialogId) {
            visualBio = String((GGVisualProfileStore.shared.bio(for: peerKey) ?? "").prefix(4000))
        }
        let payload: [String: Any] = [
            "bannerUrl": bannerUrl,
            "effectId": profile.effectId,
            "avatarFrameId": profile.avatarFrameId,
            "nitroThemeId": profile.nitroThemeId,
            "customStatus": String(profile.customStatus.prefix(140)),
            "visualBio": visualBio,
            "steamInput": String(profile.steamInput.prefix(120)),
            "robloxInput": String(profile.robloxInput.prefix(120)),
            "twitchInput": String(profile.twitchInput.prefix(80)),
            "githubInput": String(profile.githubInput.prefix(80)),
            "youtubeInput": String(profile.youtubeInput.prefix(80)),
            "tiktokInput": String(profile.tiktokInput.prefix(80)),
            "kickInput": String(profile.kickInput.prefix(80)),
            "discordTag": String(profile.discordTag.prefix(64)),
            "musicServiceKind": profile.musicServiceKind,
            "musicServiceUser": String(profile.musicServiceUser.prefix(80)),
            "duoUsername": String(profile.duoUsername.prefix(64)),
            "duoLabel": String(profile.duoLabel.prefix(64)),
            "voiceBioUrl": voiceBioUrl,
            "musicUrl": musicUrl,
            "musicTitle": String(profile.musicTitle.prefix(120)),
            "musicPlaylist": syncedPlaylist,
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
        var resolvedVoiceUrl = GGMediaTokCoreLogic.isAllowedMediaURL(profile.voiceBioUrl)?.absoluteString ?? ""
        var tracks = profile.effectivePlaylist

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

        if !profile.voiceBioFileName.isEmpty && resolvedVoiceUrl.isEmpty,
           let localVoice = self.voiceBioFileURL(for: profile),
           let voiceData = try? Data(contentsOf: localVoice), !voiceData.isEmpty {
            group.enter()
            GGDiscordProfileStore.uploadToCatbox(data: voiceData, fileName: profile.voiceBioFileName) { uploaded in
                if let uploaded {
                    urlLock.lock()
                    resolvedVoiceUrl = uploaded
                    urlLock.unlock()
                }
                group.leave()
            }
        }

        let syncCap = min(tracks.count, 12)
        for idx in 0 ..< syncCap {
            let track = tracks[idx]
            let validExisting = GGMediaTokCoreLogic.isAllowedMediaURL(track.url)?.absoluteString ?? ""
            if validExisting.isEmpty,
               !track.fileName.isEmpty,
               let localTrack = self.trackFileURL(track),
               let tData = try? Data(contentsOf: localTrack), !tData.isEmpty, tData.count <= 25 * 1024 * 1024 {
                group.enter()
                GGDiscordProfileStore.uploadToCatbox(data: tData, fileName: track.fileName) { uploaded in
                    if let uploaded {
                        urlLock.lock()
                        tracks[idx].url = uploaded
                        urlLock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .global(qos: .utility)) {
            urlLock.lock()
            let finalBanner = resolvedBannerUrl
            let finalVoice = resolvedVoiceUrl
            let updatedTracks = tracks
            urlLock.unlock()

            let syncedPlaylistDicts: [[String: String]] = updatedTracks.prefix(12).compactMap { t in
                guard let valid = GGMediaTokCoreLogic.isAllowedMediaURL(t.url)?.absoluteString else { return nil }
                return ["id": t.id, "title": String(t.title.prefix(120)), "url": valid]
            }
            let firstMusicUrl = syncedPlaylistDicts.first?["url"] ?? (GGMediaTokCoreLogic.isAllowedMediaURL(profile.musicUrl)?.absoluteString ?? "")

            GGDiscordProfileStore.postProfileJson(
                profile,
                bannerUrl: finalBanner,
                musicUrl: firstMusicUrl,
                syncedPlaylist: syncedPlaylistDicts,
                voiceBioUrl: finalVoice,
                ts: profile.updatedAt,
                dialogId: dialogId
            ) {
                let key = GGDiscordProfileStore.keyString(for: peerId)
                self.lock.lock()
                if var cur = self.entries[key], cur.updatedAt <= profile.updatedAt {
                    if !finalBanner.isEmpty { cur.bannerUrl = finalBanner }
                    if !finalVoice.isEmpty { cur.voiceBioUrl = finalVoice }
                    if !firstMusicUrl.isEmpty { cur.musicUrl = firstMusicUrl }
                    if !cur.musicPlaylist.isEmpty {
                        for idx in 0 ..< min(cur.musicPlaylist.count, updatedTracks.count) {
                            if !updatedTracks[idx].url.isEmpty {
                                cur.musicPlaylist[idx].url = updatedTracks[idx].url
                            }
                        }
                    }
                    self.entries[key] = cur
                    self.persistLocked()
                }
                self.lock.unlock()
            }
        }
    }

    func syncOwnVisualBioIfNeeded(for peerId: PeerId) {
        guard let dialogId = GGDiscordProfileStore.globalDialogId(for: peerId), dialogId > 0 else { return }
        let bio = String((GGVisualProfileStore.shared.bio(for: peerId.ggKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !bio.isEmpty else { return }
        let defaultsKey = "mediatok.discord.last_synced_bio.\(dialogId)"
        let lastBio = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        guard lastBio != bio else { return }
        UserDefaults.standard.set(bio, forKey: defaultsKey)
        let key = GGDiscordProfileStore.keyString(for: peerId)
        self.markOwnPeer(key, isOwn: true)
        let prof = self.profile(for: peerId) ?? GGDiscordProfileData()
        let dicts: [[String: String]] = prof.effectivePlaylist.prefix(12).compactMap { t in
            guard let valid = GGMediaTokCoreLogic.isAllowedMediaURL(t.url)?.absoluteString else { return nil }
            return ["id": t.id, "title": String(t.title.prefix(120)), "url": valid]
        }
        GGDiscordProfileStore.postProfileJson(
            prof,
            bannerUrl: prof.bannerUrl,
            musicUrl: prof.musicUrl,
            syncedPlaylist: dicts,
            voiceBioUrl: prof.voiceBioUrl,
            ts: Int64(Date().timeIntervalSince1970),
            dialogId: dialogId
        )
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
                let needsMediaUpload = (!localProf.bannerFileName.isEmpty && localProf.bannerUrl.isEmpty)
                    || (!localProf.voiceBioFileName.isEmpty && localProf.voiceBioUrl.isEmpty)
                    || localProf.effectivePlaylist.prefix(12).contains { !$0.fileName.isEmpty && $0.url.isEmpty }
                if needsMediaUpload {
                    self.publishGlobalProfile(localProf, for: peerId)
                } else {
                    let dicts: [[String: String]] = localProf.effectivePlaylist.prefix(12).compactMap { t in
                        guard let valid = GGMediaTokCoreLogic.isAllowedMediaURL(t.url)?.absoluteString else { return nil }
                        return ["id": t.id, "title": String(t.title.prefix(120)), "url": valid]
                    }
                    GGDiscordProfileStore.postProfileJson(
                        localProf,
                        bannerUrl: localProf.bannerUrl,
                        musicUrl: localProf.musicUrl,
                        syncedPlaylist: dicts,
                        voiceBioUrl: localProf.voiceBioUrl,
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
            let rawVoiceUrl = obj["voiceBioUrl"] as? String ?? ""
            let validatedBanner = GGMediaTokCoreLogic.isAllowedMediaURL(rawBannerUrl)
            let validatedMusic = GGMediaTokCoreLogic.isAllowedMediaURL(rawMusicUrl)
            let validatedVoice = GGMediaTokCoreLogic.isAllowedMediaURL(rawVoiceUrl)
            let remoteBannerUrl = validatedBanner?.absoluteString ?? ""
            let remoteMusicUrl = validatedMusic?.absoluteString ?? ""
            let remoteVoiceUrl = validatedVoice?.absoluteString ?? ""

            let validEffects = Set(GGDiscordProfileStore.effects.map { $0.id })
            let rawEffect = obj["effectId"] as? String ?? "none"
            let safeEffect = validEffects.contains(rawEffect) ? rawEffect : "none"

            let validFrames = Set(GGDiscordProfileStore.avatarFrames.map { $0.id })
            let rawFrame = obj["avatarFrameId"] as? String ?? "none"
            let safeFrame = validFrames.contains(rawFrame) ? rawFrame : "none"

            let validNitros = Set(GGDiscordProfileStore.nitroThemes.map { $0.id })
            let rawNitro = obj["nitroThemeId"] as? String ?? "none"
            let safeNitro = validNitros.contains(rawNitro) ? rawNitro : "none"

            let rawMusicSvc = (obj["musicServiceKind"] as? String ?? "none").lowercased()
            let safeMusicSvc = ["none", "lastfm", "listenbrainz"].contains(rawMusicSvc) ? rawMusicSvc : "none"

            let safeStatus = String((obj["customStatus"] as? String ?? "").prefix(140))
            let safeSteam = String((obj["steamInput"] as? String ?? "").prefix(120))
            let safeRoblox = String((obj["robloxInput"] as? String ?? "").prefix(120))
            let safeMusicTitle = String((obj["musicTitle"] as? String ?? "").prefix(120))
            let safeTwitch = String((obj["twitchInput"] as? String ?? "").prefix(80))
            let safeGithub = String((obj["githubInput"] as? String ?? "").prefix(80))
            let safeYoutube = String((obj["youtubeInput"] as? String ?? "").prefix(80))
            let safeTiktok = String((obj["tiktokInput"] as? String ?? "").prefix(80))
            let safeKick = String((obj["kickInput"] as? String ?? "").prefix(80))
            let safeDiscord = String((obj["discordTag"] as? String ?? "").prefix(64))
            let safeMusicUser = String((obj["musicServiceUser"] as? String ?? "").prefix(80))
            let safeDuoUser = String((obj["duoUsername"] as? String ?? "").prefix(64))
            let safeDuoLabel = String((obj["duoLabel"] as? String ?? "").prefix(64))
            let safeVisualBio = String((obj["visualBio"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
            if !isOwn && dialogId > 0 && !safeVisualBio.isEmpty, let peerKey = GGPeerKey(namespace: 0, id: dialogId) {
                var ov = GGVisualProfileStore.shared.override(for: peerKey) ?? GGVisualPeerOverride()
                if ov.bio != safeVisualBio {
                    ov.bio = safeVisualBio
                    GGVisualProfileStore.shared.setOverride(ov, for: peerKey)
                }
            }

            var parsedPlaylist: [GGProfileTrack] = []
            if let arr = obj["musicPlaylist"] as? [[String: Any]] {
                for item in arr.prefix(12) {
                    if let urlStr = item["url"] as? String,
                       let validUrl = GGMediaTokCoreLogic.isAllowedMediaURL(urlStr) {
                        let tTitle = String((item["title"] as? String ?? "Трек").prefix(120))
                        let tid = String((item["id"] as? String ?? UUID().uuidString).prefix(64))
                        let prevFile = existing?.musicPlaylist.first(where: { $0.url == validUrl.absoluteString })?.fileName ?? ""
                        parsedPlaylist.append(GGProfileTrack(id: tid, title: tTitle, fileName: prevFile, url: validUrl.absoluteString))
                    }
                }
            }

            let dlGroup = DispatchGroup()
            let dlLock = NSLock()
            var savedBannerFile = (remoteBannerUrl == existing?.bannerUrl) ? (existing?.bannerFileName ?? "") : ""
            var savedMusicFile = (remoteMusicUrl == existing?.musicUrl) ? (existing?.musicFileName ?? "") : ""
            var savedVoiceFile = (remoteVoiceUrl == existing?.voiceBioUrl) ? (existing?.voiceBioFileName ?? "") : ""

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

            if let vUrl = validatedVoice, savedVoiceFile.isEmpty {
                dlGroup.enter()
                GGDiscordProfileStore.downloadLimitedData(from: vUrl, maxBytes: 5 * 1024 * 1024) { vData in
                    if let vData, let saved = self.saveVoiceBioData(vData, ext: vUrl.pathExtension, for: peerId) {
                        dlLock.lock()
                        savedVoiceFile = saved
                        dlLock.unlock()
                    }
                    dlGroup.leave()
                }
            }

            if !parsedPlaylist.isEmpty {
                for idx in 0 ..< min(parsedPlaylist.count, 3) {
                    if parsedPlaylist[idx].fileName.isEmpty,
                       let tUrl = GGMediaTokCoreLogic.isAllowedMediaURL(parsedPlaylist[idx].url) {
                        dlGroup.enter()
                        GGDiscordProfileStore.downloadLimitedData(from: tUrl, maxBytes: 25 * 1024 * 1024) { mData in
                            if let mData, let saved = self.saveMusicData(mData, ext: tUrl.pathExtension, for: peerId) {
                                dlLock.lock()
                                parsedPlaylist[idx].fileName = saved
                                if idx == 0 { savedMusicFile = saved }
                                dlLock.unlock()
                            }
                            dlGroup.leave()
                        }
                    }
                }
            } else if let mUrl = validatedMusic, savedMusicFile.isEmpty {
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
                let finalVoiceFile = savedVoiceFile
                let finalPlaylist = parsedPlaylist
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
                    musicPlaylist: finalPlaylist,
                    voiceBioFileName: finalVoiceFile,
                    voiceBioUrl: remoteVoiceUrl,
                    musicServiceKind: safeMusicSvc,
                    musicServiceUser: safeMusicUser,
                    twitchInput: safeTwitch,
                    githubInput: safeGithub,
                    youtubeInput: safeYoutube,
                    tiktokInput: safeTiktok,
                    kickInput: safeKick,
                    discordTag: safeDiscord,
                    nitroThemeId: safeNitro,
                    duoUsername: safeDuoUser,
                    duoLabel: safeDuoLabel,
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
                let nextRevision = self.recordRevisionLocked()
                self.lock.unlock()
                self.revisionPromise.set(nextRevision)
                if let onUpdated {
                    DispatchQueue.main.async { onUpdated() }
                }
            }
        }.resume()
    }
}

// MARK: - Live Steam, Roblox, Music, Twitch & GitHub Resolvers (Public Endpoints, Zero API Keys)

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
    private var musicCache: [String: GGResolvedConnection] = [:]
    private var twitchCache: [String: GGResolvedConnection] = [:]
    private var githubCache: [String: GGResolvedConnection] = [:]
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

    func liveMusicInfo(kind: String, user: String, onUpdate: @escaping () -> Void) -> (text: String, badge: String, url: URL)? {
        let cleanKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanKind == "lastfm" || cleanKind == "listenbrainz",
              !cleanUser.isEmpty,
              !cleanUser.contains(".."),
              !cleanUser.contains("/"),
              !cleanUser.contains("@"),
              let encoded = cleanUser.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        let profileUrl: URL? = (cleanKind == "lastfm")
            ? URL(string: "https://www.last.fm/user/\(encoded)")
            : URL(string: "https://listenbrainz.org/user/\(encoded)/")
        guard let targetProfileUrl = profileUrl else { return nil }

        let key = "music:\(cleanKind):\(cleanUser.lowercased())"
        let now = Date().timeIntervalSince1970

        self.lock.lock()
        let cached = self.musicCache[key]
        let needFetch = (cached == nil || (now - (cached?.fetchedAt ?? 0)) > 60.0) && !self.inFlight.contains(key)
        if needFetch { self.inFlight.insert(key) }
        self.lock.unlock()

        if needFetch {
            let storeResult: (GGMediaTokCoreLogic.LiveMusicTrack?) -> Void = { track in
                self.lock.lock()
                self.inFlight.remove(key)
                if let track {
                    let display = track.artist.isEmpty ? track.track : "\(track.artist) — \(track.track)"
                    let badge = track.isLive ? "🟢 Сейчас" : (cleanKind == "lastfm" ? "Last.fm" : "ListenBrainz")
                    self.musicCache[key] = GGResolvedConnection(
                        displayText: display,
                        statusBadge: badge,
                        profileUrl: targetProfileUrl,
                        fetchedAt: Date().timeIntervalSince1970
                    )
                }
                self.lock.unlock()
                if track != nil {
                    DispatchQueue.main.async { onUpdate() }
                }
            }

            if cleanKind == "listenbrainz",
               let liveUrl = URL(string: "https://api.listenbrainz.org/1/user/\(encoded)/playing-now") {
                var req = URLRequest(url: liveUrl, timeoutInterval: 8.0)
                req.setValue("MediaTok/Music", forHTTPHeaderField: "User-Agent")
                URLSession.shared.dataTask(with: req) { data, _, _ in
                    if let data, let live = GGMediaTokCoreLogic.parseListenBrainzJson(data) {
                        storeResult(live)
                        return
                    }
                    guard let recUrl = URL(string: "https://api.listenbrainz.org/1/user/\(encoded)/listens?count=1") else {
                        storeResult(nil)
                        return
                    }
                    var req2 = URLRequest(url: recUrl, timeoutInterval: 8.0)
                    req2.setValue("MediaTok/Music", forHTTPHeaderField: "User-Agent")
                    URLSession.shared.dataTask(with: req2) { data2, _, _ in
                        let recent = data2.flatMap { GGMediaTokCoreLogic.parseListenBrainzJson($0) }
                        storeResult(recent)
                    }.resume()
                }.resume()
            } else {
                var req = URLRequest(url: targetProfileUrl, timeoutInterval: 10.0)
                req.setValue("MediaTok/Music", forHTTPHeaderField: "User-Agent")
                URLSession.shared.dataTask(with: req) { data, _, _ in
                    let parsedTrack = data.flatMap { String(data: $0, encoding: .utf8) }.flatMap { GGMediaTokCoreLogic.parseLastFmHtml($0) }
                    storeResult(parsedTrack)
                }.resume()
            }
        }

        if let cached {
            return (cached.displayText, cached.statusBadge, cached.profileUrl)
        }
        let serviceLabel = (cleanKind == "lastfm") ? "Last.fm" : "ListenBrainz"
        return ("\(cleanUser) (\(serviceLabel))", "🎧 Sync", targetProfileUrl)
    }

    func twitchInfo(for input: String, onUpdate: @escaping () -> Void) -> (text: String, badge: String, url: URL)? {
        guard let norm = GGMediaTokCoreLogic.normalizeConnection(platform: "twitch", raw: input) else { return nil }
        let key = "twitch:\(norm.handle.lowercased())"
        let now = Date().timeIntervalSince1970

        self.lock.lock()
        let cached = self.twitchCache[key]
        let needFetch = (cached == nil || (now - (cached?.fetchedAt ?? 0)) > 120.0) && !self.inFlight.contains(key)
        if needFetch { self.inFlight.insert(key) }
        self.lock.unlock()

        if needFetch,
           let encoded = norm.handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let apiUrl = URL(string: "https://decapi.me/twitch/uptime/\(encoded)") {
            var req = URLRequest(url: apiUrl, timeoutInterval: 8.0)
            req.setValue("MediaTok/Twitch", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, response, _ in
                defer {
                    self.lock.lock()
                    self.inFlight.remove(key)
                    self.lock.unlock()
                }
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                      let data, let body = String(data: data, encoding: .utf8) else {
                    return
                }
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = trimmed.lowercased()
                let isOffline = lower.contains("offline") || lower.contains("not found") || lower.contains("error") || trimmed.isEmpty
                let badge = isOffline ? "⚫ Офлайн" : "🟣 В эфире"
                let text = isOffline ? norm.handle : "\(norm.handle) · \(String(trimmed.prefix(40)))"
                let resolved = GGResolvedConnection(
                    displayText: text,
                    statusBadge: badge,
                    profileUrl: norm.url,
                    fetchedAt: Date().timeIntervalSince1970
                )
                self.lock.lock()
                self.twitchCache[key] = resolved
                self.lock.unlock()
                DispatchQueue.main.async { onUpdate() }
            }.resume()
        }

        if let cached {
            return (cached.displayText, cached.statusBadge, cached.profileUrl)
        }
        return (norm.handle, "Twitch", norm.url)
    }

    func githubInfo(for input: String, onUpdate: @escaping () -> Void) -> (text: String, badge: String, url: URL)? {
        guard let norm = GGMediaTokCoreLogic.normalizeConnection(platform: "github", raw: input) else { return nil }
        let key = "github:\(norm.handle.lowercased())"
        let now = Date().timeIntervalSince1970

        self.lock.lock()
        let cached = self.githubCache[key]
        let needFetch = (cached == nil || (now - (cached?.fetchedAt ?? 0)) > 600.0) && !self.inFlight.contains(key)
        if needFetch { self.inFlight.insert(key) }
        self.lock.unlock()

        if needFetch,
           let encoded = norm.handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let apiUrl = URL(string: "https://api.github.com/users/\(encoded)") {
            var req = URLRequest(url: apiUrl, timeoutInterval: 8.0)
            req.setValue("MediaTok/GitHub", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer {
                    self.lock.lock()
                    self.inFlight.remove(key)
                    self.lock.unlock()
                }
                guard let data,
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let login = obj["login"] as? String else {
                    return
                }
                let repos = obj["public_repos"] as? Int ?? 0
                let followers = obj["followers"] as? Int ?? 0
                let badge = "💻 \(repos) репо"
                let text = followers > 0 ? "@\(login) · \(followers) подп." : "@\(login)"
                let resolved = GGResolvedConnection(
                    displayText: text,
                    statusBadge: badge,
                    profileUrl: norm.url,
                    fetchedAt: Date().timeIntervalSince1970
                )
                self.lock.lock()
                self.githubCache[key] = resolved
                self.lock.unlock()
                DispatchQueue.main.async { onUpdate() }
            }.resume()
        }

        if let cached {
            return (cached.displayText, cached.statusBadge, cached.profileUrl)
        }
        return ("@\(norm.handle)", "GitHub", norm.url)
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
        self.boltTimer?.invalidate()
        self.boltTimer = nil
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
            self.setupParticles(kind: "sakura", color: UIColor(rgb: 0xFFB7D5), birthRate: 6.5, velocity: 34.0, yAccel: 14.0, size: 11.0, fromBottom: false, spin: 1.6)
        case "fire":
            self.setupParticles(kind: "fire", color: UIColor(rgb: 0xFF7B00), birthRate: 13.0, velocity: -56.0, yAccel: -20.0, size: 8.5, fromBottom: true, spin: 0.35)
        case "snow":
            self.setupParticles(kind: "snow", color: UIColor.white, birthRate: 10.0, velocity: 30.0, yAccel: 10.0, size: 9.0, fromBottom: false, spin: 0.65)
        case "stars":
            self.setupParticles(kind: "stars", color: UIColor(rgb: 0xFFE57F), birthRate: 9.0, velocity: 14.0, yAccel: 0.0, size: 10.0, fromBottom: false, spin: 1.4)
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

    private func makeParticleImage(kind: String, color: UIColor, size: CGFloat) -> CGImage? {
        let side = max(24.0, size * 2.6)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            let cx = side / 2.0
            let cy = side / 2.0
            let r = side * 0.34
            cg.setShadow(offset: .zero, blur: size * 0.32, color: color.withAlphaComponent(0.75).cgColor)
            switch kind {
            case "sakura":
                // Authentic notched sakura petal silhouette instead of a plain circle.
                let path = UIBezierPath()
                path.move(to: CGPoint(x: cx, y: cy + r))
                path.addCurve(
                    to: CGPoint(x: cx - r * 0.22, y: cy - r * 0.88),
                    controlPoint1: CGPoint(x: cx - r * 0.95, y: cy + r * 0.25),
                    controlPoint2: CGPoint(x: cx - r * 0.85, y: cy - r * 0.75)
                )
                path.addLine(to: CGPoint(x: cx, y: cy - r * 0.56))
                path.addLine(to: CGPoint(x: cx + r * 0.22, y: cy - r * 0.88))
                path.addCurve(
                    to: CGPoint(x: cx, y: cy + r),
                    controlPoint1: CGPoint(x: cx + r * 0.85, y: cy - r * 0.75),
                    controlPoint2: CGPoint(x: cx + r * 0.95, y: cy + r * 0.25)
                )
                path.close()
                color.withAlphaComponent(0.95).setFill()
                path.fill()
                UIColor.white.withAlphaComponent(0.45).setFill()
                UIBezierPath(ovalIn: CGRect(x: cx - r * 0.22, y: cy - r * 0.15, width: r * 0.44, height: r * 0.70)).fill()
            case "stars":
                // Crisp 4-point sparkle star.
                let path = UIBezierPath()
                let inner = r * 0.28
                let pts: [CGPoint] = [
                    CGPoint(x: cx, y: cy - r),
                    CGPoint(x: cx + inner, y: cy - inner),
                    CGPoint(x: cx + r, y: cy),
                    CGPoint(x: cx + inner, y: cy + inner),
                    CGPoint(x: cx, y: cy + r),
                    CGPoint(x: cx - inner, y: cy + inner),
                    CGPoint(x: cx - r, y: cy),
                    CGPoint(x: cx - inner, y: cy - inner)
                ]
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.addLine(to: p) }
                path.close()
                color.withAlphaComponent(0.96).setFill()
                path.fill()
            case "snow":
                // Delicate 6-ray crystalline snowflake.
                cg.setStrokeColor(color.withAlphaComponent(0.95).cgColor)
                cg.setLineWidth(max(1.4, size * 0.14))
                cg.setLineCap(.round)
                for i in 0 ..< 6 {
                    let a = CGFloat(i) * (.pi / 3.0)
                    let ex = cx + cos(a) * r
                    let ey = cy + sin(a) * r
                    cg.move(to: CGPoint(x: cx, y: cy))
                    cg.addLine(to: CGPoint(x: ex, y: ey))
                    let branchLen = r * 0.34
                    let bx = cx + cos(a) * (r * 0.58)
                    let by = cy + sin(a) * (r * 0.58)
                    cg.move(to: CGPoint(x: bx, y: by))
                    cg.addLine(to: CGPoint(x: bx + cos(a + 0.65) * branchLen, y: by + sin(a + 0.65) * branchLen))
                    cg.move(to: CGPoint(x: bx, y: by))
                    cg.addLine(to: CGPoint(x: bx + cos(a - 0.65) * branchLen, y: by + sin(a - 0.65) * branchLen))
                }
                cg.strokePath()
            case "fire":
                // Tapered rising flame ember teardrop.
                let path = UIBezierPath()
                path.move(to: CGPoint(x: cx, y: cy - r))
                path.addQuadCurve(to: CGPoint(x: cx, y: cy + r * 0.85), controlPoint: CGPoint(x: cx + r * 0.85, y: cy + r * 0.25))
                path.addQuadCurve(to: CGPoint(x: cx, y: cy - r), controlPoint: CGPoint(x: cx - r * 0.85, y: cy + r * 0.25))
                path.close()
                color.withAlphaComponent(0.95).setFill()
                path.fill()
                UIColor(rgb: 0xFFE57F).withAlphaComponent(0.75).setFill()
                UIBezierPath(ovalIn: CGRect(x: cx - r * 0.25, y: cy, width: r * 0.5, height: r * 0.5)).fill()
            default:
                cg.setFillColor(color.withAlphaComponent(0.92).cgColor)
                cg.fillEllipse(in: CGRect(x: cx - r * 0.65, y: cy - r * 0.65, width: r * 1.3, height: r * 1.3))
            }
        }
        return img.cgImage
    }

    private func setupParticles(kind: String, color: UIColor, birthRate: Float, velocity: CGFloat, yAccel: CGFloat, size: CGFloat, fromBottom: Bool, spin: CGFloat) {
        let layer = CAEmitterLayer()
        layer.emitterShape = .line
        let cell = CAEmitterCell()
        cell.contents = self.makeParticleImage(kind: kind, color: color, size: size)
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

private enum GGBannerVerticalMode {
    case smartBlur
    case topCrop
    case centerCrop
}

private enum GGDiscordBannerProcessor {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    private static let headerDisplayCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 24 * 1024 * 1024
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
            cache.removeAllObjects()
        }
        return cache
    }()

    static func normalizedOrientationImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func isPortrait(_ image: UIImage) -> Bool {
        let norm = self.normalizedOrientationImage(image)
        guard norm.size.width > 0.0, norm.size.height > 0.0 else { return false }
        return norm.size.height > norm.size.width * 1.05
    }

    static func displayBannerImage(from image: UIImage) -> UIImage {
        let norm = self.normalizedOrientationImage(image)
        if self.isPortrait(norm) {
            return self.makeSmartVerticalComposite(from: norm)
        }
        return norm
    }

    static func makeSmartVerticalComposite(from image: UIImage, targetAspect: CGFloat = 1.65) -> UIImage {
        let source = self.normalizedOrientationImage(image)
        let srcW = max(1.0, source.size.width)
        let srcH = max(1.0, source.size.height)
        let canvasW: CGFloat = 1120.0
        let canvasH: CGFloat = (canvasW / max(1.2, targetAspect)).rounded()
        let canvasSize = CGSize(width: canvasW, height: canvasH)
        let canvasRect = CGRect(origin: .zero, size: canvasSize)

        let bgScale = max(canvasW / srcW, canvasH / srcH)
        let bgDrawSize = CGSize(width: srcW * bgScale, height: srcH * bgScale)
        let bgDrawRect = CGRect(
            x: (canvasW - bgDrawSize.width) / 2.0,
            y: (canvasH - bgDrawSize.height) / 2.0,
            width: bgDrawSize.width,
            height: bgDrawSize.height
        )
        let bgFormat = UIGraphicsImageRendererFormat()
        bgFormat.scale = 1.0
        bgFormat.opaque = true
        let bgBase = UIGraphicsImageRenderer(size: canvasSize, format: bgFormat).image { _ in
            UIColor(rgb: 0x10131C).setFill()
            UIRectFill(canvasRect)
            source.draw(in: bgDrawRect)
        }

        var blurredBg: UIImage = bgBase
        if let ciInput = CIImage(image: bgBase),
           let filter = CIFilter(name: "CIGaussianBlur") {
            let clamped = ciInput.clampedToExtent()
            filter.setValue(clamped, forKey: kCIInputImageKey)
            filter.setValue(28.0, forKey: kCIInputRadiusKey)
            if let output = filter.outputImage {
                let cropped = output.cropped(to: ciInput.extent)
                if let cg = self.ciContext.createCGImage(cropped, from: ciInput.extent) {
                    blurredBg = UIImage(cgImage: cg)
                }
            }
        }

        let fgAspect = srcW / srcH
        var cardH = canvasH * 0.90
        var cardW = cardH * fgAspect
        let maxCardW = canvasW * 0.72
        if cardW > maxCardW {
            cardW = maxCardW
            cardH = cardW / max(0.01, fgAspect)
        }
        let cardRect = CGRect(
            x: ((canvasW - cardW) / 2.0).rounded(),
            y: ((canvasH - cardH) / 2.0).rounded(),
            width: cardW.rounded(),
            height: cardH.rounded()
        )

        let outFormat = UIGraphicsImageRendererFormat()
        outFormat.scale = 1.0
        outFormat.opaque = true
        return UIGraphicsImageRenderer(size: canvasSize, format: outFormat).image { ctx in
            blurredBg.draw(in: canvasRect)
            UIColor.black.withAlphaComponent(0.32).setFill()
            ctx.fill(canvasRect)

            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 24.0)
            ctx.cgContext.saveGState()
            cardPath.addClip()
            source.draw(in: cardRect)
            ctx.cgContext.restoreGState()

            UIColor.white.withAlphaComponent(0.24).setStroke()
            cardPath.lineWidth = 2.0
            cardPath.stroke()
        }
    }

    static func downscaleToMaxDimension(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let norm = self.normalizedOrientationImage(image)
        let pxW = norm.size.width * norm.scale
        let pxH = norm.size.height * norm.scale
        let maxSide = max(pxW, pxH)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let targetSize: CGSize
        if maxSide > maxDimension && maxSide > 0.0 {
            let factor = maxDimension / maxSide
            targetSize = CGSize(width: max(1.0, (pxW * factor).rounded()), height: max(1.0, (pxH * factor).rounded()))
        } else {
            targetSize = CGSize(width: max(1.0, pxW.rounded()), height: max(1.0, pxH.rounded()))
        }
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            norm.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func renderNormalizedBannerData(from image: UIImage, verticalMode: GGBannerVerticalMode) -> Data? {
        return autoreleasepool {
            let norm = self.normalizedOrientationImage(image)
            guard norm.size.width > 1.0, norm.size.height > 1.0 else { return nil }
            if self.isPortrait(norm) {
                switch verticalMode {
                case .smartBlur:
                    return self.makeSmartVerticalComposite(from: norm, targetAspect: 1.65).jpegData(compressionQuality: 0.91)
                case .topCrop, .centerCrop:
                    let full = self.downscaleToMaxDimension(norm, maxDimension: 3840.0)
                    guard let cg = full.cgImage else {
                        return full.jpegData(compressionQuality: 0.91)
                    }
                    let srcW = CGFloat(cg.width)
                    let srcH = CGFloat(cg.height)
                    let cropH = min(srcH, max(1.0, (srcW / 1.65).rounded()))
                    let cropY: CGFloat = (verticalMode == .topCrop) ? 0.0 : max(0.0, ((srcH - cropH) / 2.0).rounded())
                    let cropRect = CGRect(x: 0.0, y: cropY, width: srcW, height: cropH)
                    if let cropped = cg.cropping(to: cropRect) {
                        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.92)
                    }
                    return full.jpegData(compressionQuality: 0.91)
                }
            }
            return self.downscaleToMaxDimension(norm, maxDimension: 3840.0).jpegData(compressionQuality: 0.92)
        }
    }

    static func loadHeaderDisplayImage(from url: URL) -> UIImage? {
        let key = url.path as NSString
        if let cached = self.headerDisplayCache.object(forKey: key) {
            return cached
        }
        return autoreleasepool {
            let decoded: UIImage?
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1440
                ]
                if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                    decoded = UIImage(cgImage: cg)
                } else {
                    decoded = self.loadImage(from: url)
                }
            } else {
                decoded = self.loadImage(from: url)
            }
            guard let raw = decoded else { return nil }
            let finalImg = self.displayBannerImage(from: raw)
            let cost = Int(finalImg.size.width * finalImg.size.height * finalImg.scale * finalImg.scale * 4.0)
            self.headerDisplayCache.setObject(finalImg, forKey: key, cost: max(1, cost))
            return finalImg
        }
    }

    static func loadImage(from url: URL) -> UIImage? {
        if let img = UIImage(contentsOfFile: url.path) {
            return self.normalizedOrientationImage(img)
        }
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            return self.normalizedOrientationImage(img)
        }
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3840
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                return UIImage(cgImage: cg)
            }
        }
        return nil
    }
}

private final class GGDiscordHeaderOverlay {
    private static var assocKey: UInt8 = 0

    private weak var node: ASDisplayNode?
    private weak var bannerContainer: UIView?
    private var peerId: PeerId?
    private var lastWidth: CGFloat = 0.0

    private var bannerImageView: UIImageView?
    private var bannerScrimLayer: CAGradientLayer?
    private var nitroTintView: UIView?
    private var nitroGradientLayer: CAGradientLayer?
    private var loadedBannerFile: String = ""
    private var effectView: GGDiscordEffectView?
    private var avatarFrameView: GGAvatarFrameRingView?
    private var voiceBioButton: UIButton?
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
        if header.isSettings {
            GGDiscordProfileStore.shared.activeAccountPeerId = header.context.account.peerId
        }
        let resolvedPeerId: PeerId? = header.peer?.id ?? (header.isSettings ? header.context.account.peerId : nil)
        guard let peerId = resolvedPeerId else { return }

        let overlay: GGDiscordHeaderOverlay
        if let existing = objc_getAssociatedObject(header.node, &GGDiscordHeaderOverlay.assocKey) as? GGDiscordHeaderOverlay {
            overlay = existing
        } else {
            overlay = GGDiscordHeaderOverlay(node: header.node)
            objc_setAssociatedObject(header.node, &GGDiscordHeaderOverlay.assocKey, overlay, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let isNewPeer = overlay.peerId != peerId
        overlay.peerId = peerId
        overlay.lastWidth = header.width
        if let bg = header.backgroundContainerView {
            overlay.bannerContainer = bg
        }
        if header.isSettings || peerId == header.context.account.peerId {
            GGDiscordProfileStore.shared.syncOwnVisualBioIfNeeded(for: peerId)
        }
        if isNewPeer {
            GGDiscordProfileStore.shared.checkGlobalProfile(for: peerId)
        }
        overlay.refresh()
    }

    @objc private func voiceBioTapped() {
        guard let peerId = self.peerId,
              let profile = GGDiscordProfileStore.shared.profile(for: peerId) else {
            return
        }
        GGProfileMusicPlayer.shared.toggleVoiceBio(peerId: peerId, profile: profile) { [weak self] in
            self?.updateVoiceButtonAppearance(peerId: peerId)
        }
    }

    private func updateVoiceButtonAppearance(peerId: PeerId) {
        guard let btn = self.voiceBioButton else { return }
        let playing = GGProfileMusicPlayer.shared.isPlayingVoiceBio(peerId: peerId)
        let symName = playing ? "pause.fill" : "play.fill"
        let cfg = UIImage.SymbolConfiguration(pointSize: 11.0, weight: .bold)
        btn.setImage(UIImage(systemName: symName, withConfiguration: cfg), for: .normal)
        btn.backgroundColor = playing
            ? UIColor(rgb: 0x00F5FF).withAlphaComponent(0.92)
            : UIColor.black.withAlphaComponent(0.78)
        btn.tintColor = playing ? .black : .white
    }

    private func refresh() {
        guard let node = self.node, let peerId = self.peerId else { return }
        let profile = GGDiscordProfileStore.shared.profile(for: peerId)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let anchor = self.bannerContainer else {
            self.bannerImageView?.removeFromSuperview()
            self.bannerImageView = nil
            self.bannerScrimLayer = nil
            self.loadedBannerFile = ""
            self.nitroTintView?.removeFromSuperview()
            self.nitroTintView = nil
            self.nitroGradientLayer = nil
            self.effectView?.removeFromSuperview()
            self.effectView = nil
            return
        }

        // 1. 4K Banner Image — full-bleed inside `backgroundBannerView` (`anchor`) behind avatar,
        //    title, status, Telegram music and header buttons (no floating rounded box or right gap).
        let visibleHeight = max(0.0, anchor.frame.maxY)
        let shouldHideBanner = anchor.bounds.width < 40.0 || visibleHeight < 20.0
        let bannerRect = CGRect(
            x: 0.0,
            y: anchor.bounds.height - visibleHeight,
            width: anchor.bounds.width,
            height: visibleHeight
        )

        var hasBanner = false
        if let profile,
           let bannerUrl = GGDiscordProfileStore.shared.bannerFileURL(for: profile) {
            hasBanner = true
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
                    UIColor.black.withAlphaComponent(0.28).cgColor,
                    UIColor.black.withAlphaComponent(0.10).cgColor,
                    UIColor.black.withAlphaComponent(0.58).cgColor
                ]
                scrim.locations = [0.0, 0.45, 1.0]
                iv.layer.addSublayer(scrim)
                self.bannerScrimLayer = scrim
                self.bannerImageView = iv
            }
            if self.loadedBannerFile != profile.bannerFileName {
                self.loadedBannerFile = profile.bannerFileName
                iv.image = GGDiscordBannerProcessor.loadHeaderDisplayImage(from: bannerUrl)
            }
            if iv.superview !== anchor {
                anchor.addSubview(iv)
            }
            anchor.bringSubviewToFront(iv)
            iv.isHidden = shouldHideBanner
            if !shouldHideBanner {
                iv.frame = bannerRect
                self.bannerScrimLayer?.frame = iv.bounds
            }
        } else {
            self.bannerImageView?.removeFromSuperview()
            self.bannerImageView = nil
            self.bannerScrimLayer = nil
            self.loadedBannerFile = ""
        }

        // 1b. Nitro 2-Color Gradient Theme
        let nitroId = profile?.nitroThemeId ?? "none"
        if nitroId != "none" && !nitroId.isEmpty,
           let spec = GGDiscordProfileStore.nitroThemes.first(where: { $0.id == nitroId }),
           spec.colors.count >= 2 {
            let tv: UIView
            let gl: CAGradientLayer
            if let existing = self.nitroTintView, let existingLayer = self.nitroGradientLayer {
                tv = existing
                gl = existingLayer
            } else {
                tv = UIView()
                tv.isUserInteractionEnabled = false
                tv.clipsToBounds = true
                gl = CAGradientLayer()
                gl.startPoint = CGPoint(x: 0.0, y: 0.0)
                gl.endPoint = CGPoint(x: 1.0, y: 1.0)
                tv.layer.addSublayer(gl)
                self.nitroTintView = tv
                self.nitroGradientLayer = gl
            }
            let alpha: CGFloat = hasBanner ? 0.34 : 0.72
            gl.colors = spec.colors.map { $0.withAlphaComponent(alpha).cgColor }
            if tv.superview !== anchor {
                anchor.addSubview(tv)
            }
            anchor.bringSubviewToFront(tv)
            tv.isHidden = shouldHideBanner
            if !shouldHideBanner {
                tv.frame = bannerRect
                gl.frame = tv.bounds
            }
        } else {
            self.nitroTintView?.removeFromSuperview()
            self.nitroTintView = nil
            self.nitroGradientLayer = nil
        }

        // 2. Animated Profile Effect
        let effectId = profile?.effectId ?? "none"
        if effectId != "none" && !effectId.isEmpty {
            let ev: GGDiscordEffectView
            if let existing = self.effectView {
                ev = existing
            } else {
                ev = GGDiscordEffectView(frame: .zero)
                ev.clipsToBounds = true
                self.effectView = ev
            }
            if ev.superview !== anchor {
                anchor.addSubview(ev)
            }
            anchor.bringSubviewToFront(ev)
            ev.isHidden = shouldHideBanner
            if !shouldHideBanner {
                ev.frame = bannerRect
            }
            ev.configure(effectId: effectId)
        } else {
            self.effectView?.removeFromSuperview()
            self.effectView = nil
        }

        // 3. Glowing Animated Avatar Frame & Tiny Circular Voice Bio Button
        let frameId = profile?.avatarFrameId ?? "none"
        let hasFrame = frameId != "none" && !frameId.isEmpty
        let hasVoiceBio = !(profile?.voiceBioFileName.isEmpty ?? true) || !(profile?.voiceBioUrl.isEmpty ?? true)
        let avatarRect: CGRect? = (hasFrame || hasVoiceBio) ? self.locateRoundAvatarFrame(in: node.view, headerWidth: self.lastWidth) : nil
        if hasFrame, let avatarRect {
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

        if hasVoiceBio, let avatarRect {
            let btn: UIButton
            if let existing = self.voiceBioButton {
                btn = existing
            } else {
                btn = UIButton(type: .system)
                btn.layer.cornerRadius = 13.0
                btn.layer.borderWidth = 1.5
                btn.layer.borderColor = UIColor(rgb: 0x00F5FF).withAlphaComponent(0.9).cgColor
                btn.layer.shadowColor = UIColor.black.cgColor
                btn.layer.shadowRadius = 4.0
                btn.layer.shadowOpacity = 0.45
                btn.layer.shadowOffset = .zero
                btn.addTarget(self, action: #selector(self.voiceBioTapped), for: .touchUpInside)
                self.voiceBioButton = btn
            }
            if btn.superview !== node.view {
                node.view.addSubview(btn)
            }
            btn.frame = CGRect(x: avatarRect.maxX - 24.0, y: avatarRect.maxY - 24.0, width: 26.0, height: 26.0)
            self.updateVoiceButtonAppearance(peerId: peerId)
            btn.isHidden = false
        } else {
            self.voiceBioButton?.isHidden = true
        }
    }

    private func locateRoundAvatarFrame(in root: UIView, headerWidth: CGFloat) -> CGRect? {
        guard headerWidth > 100.0 else { return nil }
        let centerX = headerWidth / 2.0
        var best: CGRect?
        func scan(_ view: UIView, depth: Int) {
            if depth > 4 || view.isHidden || view.alpha < 0.25 { return }
            if view is GGDiscordEffectView || view is GGAvatarFrameRingView || view === self.bannerImageView || view === self.nitroTintView || view === self.voiceBioButton { return }
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
        GGPeerInfoHooks.hasHeaderBackground.register({ peerId in
            guard let profile = GGDiscordProfileStore.shared.profile(for: peerId) else {
                return false
            }
            if GGDiscordProfileStore.shared.bannerFileURL(for: profile) != nil {
                return true
            }
            let nitroId = profile.nitroThemeId
            return !nitroId.isEmpty && nitroId != "none"
        })

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
        GGDiscordProfileStore.shared.activeAccountPeerId = info.context.account.peerId
        weak let controller = info.controller
        GGDiscordProfileStore.shared.checkGlobalProfile(for: peerId) {
            controller?.requestLayout(transition: .immediate)
        }
        guard let profile = GGDiscordProfileStore.shared.profile(for: peerId) else {
            return []
        }

        var rows: [GGPeerInfoRow] = []
        let context = info.context

        // Infinite Playlist on Profile
        let playlist = profile.effectivePlaylist
        if !playlist.isEmpty {
            let isPlaying = GGProfileMusicPlayer.shared.isPlaying(peerId: peerId)
            let summary = GGProfileMusicPlayer.shared.currentTrackSummary(peerId: peerId, playlist: playlist)
            let label = playlist.count > 1 ? "🎵 Плейлист (\(summary.positionText))" : "🎵 Музыка профиля"
            let badgeText = isPlaying ? "⏸ Пауза" : (playlist.count > 1 ? "▶️ Плейлист" : "▶️ Слушать")
            rows.append(GGPeerInfoRow(
                id: "mediatok.discord.music",
                label: label,
                text: summary.title,
                rightLabel: badgeText,
                action: {
                    GGProfileMusicPlayer.shared.toggle(peerId: peerId, profile: profile) {
                        controller?.requestLayout(transition: .immediate)
                    }
                },
                longTapAction: {
                    GGMediaTokDiscordProfile.presentPlaylistControls(peerId: peerId, profile: profile, controller: controller, context: context)
                }
            ))
            if playlist.count > 1 {
                let shuffleState = GGProfileMusicPlayer.shared.shuffleEnabled ? "🔀 Шаффл ВКЛ" : "⏭ След. трек"
                rows.append(GGPeerInfoRow(
                    id: "mediatok.discord.music.next",
                    label: "🎛 Плеер (\(playlist.count) трек.)",
                    text: "Нажми — следующий трек · Зажми — выбор / шаффл",
                    rightLabel: shuffleState,
                    action: {
                        GGProfileMusicPlayer.shared.next(peerId: peerId, profile: profile) {
                            controller?.requestLayout(transition: .immediate)
                        }
                    },
                    longTapAction: {
                        GGMediaTokDiscordProfile.presentPlaylistControls(peerId: peerId, profile: profile, controller: controller, context: context)
                    }
                ))
            }
        }

        // Live Now-Playing Music Service (Last.fm / ListenBrainz for Spotify, Yandex, VK, Apple Music)
        if !profile.musicServiceUser.isEmpty,
           profile.musicServiceKind != "none",
           let liveMusic = GGConnectionResolvers.shared.liveMusicInfo(kind: profile.musicServiceKind, user: profile.musicServiceUser, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            rows.append(GGPeerInfoRow(
                id: "mediatok.discord.liveMusic",
                label: "🎧 Слушает сейчас",
                text: liveMusic.text,
                rightLabel: liveMusic.badge,
                action: {
                    UIApplication.shared.open(liveMusic.url, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    GGMediaTokDiscordProfile.copyAndToast(liveMusic.text, context: context, controller: controller)
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

        // Duo / Couple Profile Link
        let rawDuo = profile.duoUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDuo = rawDuo.hasPrefix("@") ? String(rawDuo.dropFirst()) : rawDuo
        if !cleanDuo.isEmpty,
           !cleanDuo.contains("/"),
           !cleanDuo.contains(".."),
           let duoUrl = URL(string: "https://t.me/\(cleanDuo)") {
            let duoTitle = profile.duoLabel.isEmpty ? "В паре с @\(cleanDuo)" : "\(profile.duoLabel) · @\(cleanDuo)"
            rows.append(GGPeerInfoRow(
                id: "mediatok.discord.duo",
                label: "💞 Пара MediaTok",
                text: duoTitle,
                rightLabel: "Профиль →",
                action: {
                    UIApplication.shared.open(duoUrl, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    GGMediaTokDiscordProfile.copyAndToast("@\(cleanDuo)", context: context, controller: controller)
                }
            ))
        }

        if !profile.steamInput.isEmpty,
           let steam = GGConnectionResolvers.shared.steamInfo(for: profile.steamInput, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            rows.append(GGPeerInfoRow(
                id: "mediatok.discord.steam",
                label: "Steam ✓",
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
                label: "Roblox ✓",
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

        if !profile.twitchInput.isEmpty,
           let twitch = GGConnectionResolvers.shared.twitchInfo(for: profile.twitchInput, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            rows.append(GGPeerInfoRow(
                id: "mediatok.discord.twitch",
                label: "Twitch ✓",
                text: twitch.text,
                rightLabel: twitch.badge,
                action: {
                    UIApplication.shared.open(twitch.url, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    GGMediaTokDiscordProfile.copyAndToast(twitch.url.absoluteString, context: context, controller: controller)
                }
            ))
        }

        if !profile.githubInput.isEmpty,
           let gh = GGConnectionResolvers.shared.githubInfo(for: profile.githubInput, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            rows.append(GGPeerInfoRow(
                id: "mediatok.discord.github",
                label: "GitHub ✓",
                text: gh.text,
                rightLabel: gh.badge,
                action: {
                    UIApplication.shared.open(gh.url, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    GGMediaTokDiscordProfile.copyAndToast(gh.url.absoluteString, context: context, controller: controller)
                }
            ))
        }

        let staticConnections: [(id: String, platform: String, raw: String, badge: String)] = [
            ("youtube", "youtube", profile.youtubeInput, "▶️ Канал"),
            ("tiktok", "tiktok", profile.tiktokInput, "🎵 Профиль"),
            ("kick", "kick", profile.kickInput, "💚 Kick"),
            ("discord", "discord", profile.discordTag, "💬 Discord")
        ]
        for item in staticConnections where !item.raw.isEmpty {
            if let norm = GGMediaTokCoreLogic.normalizeConnection(platform: item.platform, raw: item.raw) {
                rows.append(GGPeerInfoRow(
                    id: "mediatok.discord.conn.\(item.id)",
                    label: "\(norm.label) ✓",
                    text: norm.handle,
                    rightLabel: item.badge,
                    action: {
                        if item.platform == "discord" {
                            GGMediaTokDiscordProfile.copyAndToast(norm.handle, context: context, controller: controller)
                        } else {
                            UIApplication.shared.open(norm.url, options: [:], completionHandler: nil)
                        }
                    },
                    longTapAction: {
                        GGMediaTokDiscordProfile.copyAndToast(norm.handle, context: context, controller: controller)
                    }
                ))
            }
        }

        return rows
    }

    private static func presentPlaylistControls(peerId: PeerId, profile: GGDiscordProfileData, controller: ViewController?, context: AccountContext) {
        DispatchQueue.main.async {
            let playlist = profile.effectivePlaylist
            let summary = GGProfileMusicPlayer.shared.currentTrackSummary(peerId: peerId, playlist: playlist)
            let sheet = UIAlertController(
                title: "🎵 Плейлист профиля (\(playlist.count))",
                message: "Сейчас: \(summary.title)",
                preferredStyle: .actionSheet
            )
            sheet.addAction(UIAlertAction(title: "⏭ Следующий трек", style: .default, handler: { _ in
                GGProfileMusicPlayer.shared.next(peerId: peerId, profile: profile) {
                    controller?.requestLayout(transition: .immediate)
                }
            }))
            sheet.addAction(UIAlertAction(title: "⏮ Предыдущий трек", style: .default, handler: { _ in
                GGProfileMusicPlayer.shared.previous(peerId: peerId, profile: profile) {
                    controller?.requestLayout(transition: .immediate)
                }
            }))
            let shufTitle = GGProfileMusicPlayer.shared.shuffleEnabled ? "🔀 Шаффл: ВКЛ (выкл)" : "🔀 Включить перемешивание"
            sheet.addAction(UIAlertAction(title: shufTitle, style: .default, handler: { _ in
                GGProfileMusicPlayer.shared.toggleShuffle()
                controller?.requestLayout(transition: .immediate)
            }))
            sheet.addAction(UIAlertAction(title: "📋 Скопировать название", style: .default, handler: { _ in
                GGMediaTokDiscordProfile.copyAndToast(summary.title, context: context, controller: controller)
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            GGModalPresenter.presentOnTopmost(sheet)
        }
    }

    private static func profileMenuItems(_ info: GGPeerInfoContext) -> [ContextMenuItem] {
        if info.isSettings { return [] }
        let peerId = info.peer.id
        let isOwn = peerId == info.context.account.peerId
        weak let controller = info.controller
        let title = isOwn ? "Discord-профиль / Плейлист / Интеграции" : "Оформление профиля MediaTok"
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
        GGDiscordProfileStore.shared.activeAccountPeerId = context.context.account.peerId
        let vc = GGDiscordProfileEditorViewController(peerId: context.context.account.peerId, isOwn: true, onDone: nil)
        vc.overrideUserInterfaceStyle = .dark
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        nav.modalPresentationStyle = .pageSheet
        context.presentNative(nav)
    }

    static func presentEditor(peerId: PeerId, isOwn: Bool, onDone: (() -> Void)?) {
        DispatchQueue.main.async {
            let vc = GGDiscordProfileEditorViewController(peerId: peerId, isOwn: isOwn, onDone: onDone)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            GGModalPresenter.presentOnTopmost(nav)
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
    private enum DocPickMode {
        case playlistTracks
        case voiceBioFile
    }

    private let peerId: PeerId
    private let isOwn: Bool
    private let onDone: (() -> Void)?

    private var draft: GGDiscordProfileData
    private var draftPlaylist: [GGProfileTrack]
    private var pendingBannerData: Data?
    private var pendingVoiceData: Data?
    private var pendingVoiceExt: String = "m4a"
    private var pickMode: DocPickMode = .playlistTracks

    private var audioRecorder: AVAudioRecorder?
    private var recordTempUrl: URL?
    private var recordTimer: Foundation.Timer?
    private var recordSeconds: Int = 0

    private let bannerPreview = UIImageView()
    private let nitroButton = UIButton(type: .system)
    private let effectButton = UIButton(type: .system)
    private let frameButton = UIButton(type: .system)
    private let playlistStatusLabel = UILabel()
    private let voiceBioStatusLabel = UILabel()
    private let recordVoiceBtn = UIButton(type: .system)
    private let musicServiceButton = UIButton(type: .system)
    private let musicServiceUserField = UITextField()
    private let statusField = UITextField()
    private let duoUserField = UITextField()
    private let duoLabelField = UITextField()
    private let steamField = UITextField()
    private let robloxField = UITextField()
    private let twitchField = UITextField()
    private let githubField = UITextField()
    private let youtubeField = UITextField()
    private let tiktokField = UITextField()
    private let kickField = UITextField()
    private let discordField = UITextField()

    init(peerId: PeerId, isOwn: Bool, onDone: (() -> Void)?) {
        self.peerId = peerId
        self.isOwn = isOwn
        self.onDone = onDone
        let existing = GGDiscordProfileStore.shared.profile(for: peerId) ?? GGDiscordProfileData()
        self.draft = existing
        self.draftPlaylist = existing.effectivePlaylist
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.invalidateRecorderOnly()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.stopRecording(saveIfValid: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = .dark
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
        stack.spacing = 11.0
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
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -28.0),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32.0)
        ])

        let infoLabel = UILabel()
        infoLabel.numberOfLines = 0
        infoLabel.font = UIFont.systemFont(ofSize: 13.0)
        infoLabel.textColor = .secondaryLabel
        infoLabel.text = self.isOwn
            ? "Ваш 4K-баннер, Nitro-градиент, рамка, бесконечный плейлист, голосовое био на аватарке, статус и все интеграции синхронизируются глобально в MediaTok!"
            : "Локальная настройка профиля (или «Обновить из облака MediaTok»)."
        stack.addArrangedSubview(infoLabel)

        // Banner Preview + Buttons
        self.bannerPreview.backgroundColor = .secondarySystemGroupedBackground
        self.bannerPreview.contentMode = .scaleAspectFill
        self.bannerPreview.clipsToBounds = true
        self.bannerPreview.layer.cornerRadius = 20.0
        self.bannerPreview.layer.cornerCurve = .continuous
        self.bannerPreview.layer.borderWidth = 1.0
        self.bannerPreview.layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
        self.bannerPreview.heightAnchor.constraint(equalToConstant: 132.0).isActive = true
        if let url = GGDiscordProfileStore.shared.bannerFileURL(for: self.draft),
           let img = GGDiscordBannerProcessor.loadImage(from: url) {
            self.bannerPreview.image = GGDiscordBannerProcessor.displayBannerImage(from: img)
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

        // Nitro Theme, Effect & Avatar Frame pickers
        stack.addArrangedSubview(self.makeSectionLabel("🎨 Nitro-тема профиля (2-цветный градиент)"))
        self.configurePickerButton(self.nitroButton, action: #selector(self.pickNitroTapped))
        stack.addArrangedSubview(self.nitroButton)

        stack.addArrangedSubview(self.makeSectionLabel("✨ Анимированный эффект профиля"))
        self.configurePickerButton(self.effectButton, action: #selector(self.pickEffectTapped))
        stack.addArrangedSubview(self.effectButton)

        stack.addArrangedSubview(self.makeSectionLabel("💍 Рамка на аватарку (анимация)"))
        self.configurePickerButton(self.frameButton, action: #selector(self.pickFrameTapped))
        stack.addArrangedSubview(self.frameButton)

        // Voice Bio (circle ▶ button on avatar corner)
        stack.addArrangedSubview(self.makeSectionLabel("🎙 Голосовое био (кругляш ▶ на аватарке, до 15 сек)"))
        self.voiceBioStatusLabel.font = UIFont.systemFont(ofSize: 12.0)
        self.voiceBioStatusLabel.textColor = .secondaryLabel
        self.voiceBioStatusLabel.numberOfLines = 1
        stack.addArrangedSubview(self.voiceBioStatusLabel)

        let voiceBtns = UIStackView()
        voiceBtns.axis = .horizontal
        voiceBtns.spacing = 8.0
        voiceBtns.distribution = .fillEqually
        self.recordVoiceBtn.setTitle("🎙 Запись", for: .normal)
        self.recordVoiceBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        self.recordVoiceBtn.backgroundColor = .secondarySystemGroupedBackground
        self.recordVoiceBtn.layer.cornerRadius = 10.0
        self.recordVoiceBtn.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
        self.recordVoiceBtn.addTarget(self, action: #selector(self.recordVoiceTapped), for: .touchUpInside)
        let pickVoiceBtn = self.makeActionButton(title: "Файл", action: #selector(self.pickVoiceFileTapped))
        let clearVoiceBtn = self.makeActionButton(title: "Убрать", action: #selector(self.clearVoiceTapped))
        clearVoiceBtn.setTitleColor(.systemRed, for: .normal)
        voiceBtns.addArrangedSubview(self.recordVoiceBtn)
        voiceBtns.addArrangedSubview(pickVoiceBtn)
        voiceBtns.addArrangedSubview(clearVoiceBtn)
        stack.addArrangedSubview(voiceBtns)

        // Infinite Profile Playlist
        stack.addArrangedSubview(self.makeSectionLabel("🎵 Бесконечный плейлист профиля (mp3/m4a/flac)"))
        self.playlistStatusLabel.font = UIFont.systemFont(ofSize: 12.0)
        self.playlistStatusLabel.textColor = .secondaryLabel
        self.playlistStatusLabel.numberOfLines = 2
        stack.addArrangedSubview(self.playlistStatusLabel)

        let playlistBtns = UIStackView()
        playlistBtns.axis = .horizontal
        playlistBtns.spacing = 8.0
        playlistBtns.distribution = .fillEqually
        let addTracksBtn = self.makeActionButton(title: "+ Добавить треки", action: #selector(self.pickMusicTapped))
        let manageTracksBtn = self.makeActionButton(title: "Треки / Удалить", action: #selector(self.managePlaylistTapped))
        playlistBtns.addArrangedSubview(addTracksBtn)
        playlistBtns.addArrangedSubview(manageTracksBtn)
        stack.addArrangedSubview(playlistBtns)

        // Live Music Service (Spotify / Yandex / VK / Apple via Last.fm or ListenBrainz)
        stack.addArrangedSubview(self.makeSectionLabel("🎧 Живой музыкальный статус (Spotify/Яндекс/VK/Apple)"))
        self.configurePickerButton(self.musicServiceButton, action: #selector(self.pickMusicServiceTapped))
        stack.addArrangedSubview(self.musicServiceButton)
        self.configureField(self.musicServiceUserField, placeholder: "Ник в Last.fm или ListenBrainz", text: self.draft.musicServiceUser)
        self.musicServiceUserField.autocapitalizationType = .none
        self.musicServiceUserField.autocorrectionType = .no
        stack.addArrangedSubview(self.musicServiceUserField)

        // Custom Status & Duo
        stack.addArrangedSubview(self.makeSectionLabel("💬 Статус профиля и 💞 Пара"))
        self.configureField(self.statusField, placeholder: "Например: 🎮 Играю в CS2 / 🎧 Вайблю", text: self.draft.customStatus)
        stack.addArrangedSubview(self.statusField)
        self.configureField(self.duoUserField, placeholder: "Ник пары в TG (напр. @username)", text: self.draft.duoUsername)
        self.duoUserField.autocapitalizationType = .none
        self.duoUserField.autocorrectionType = .no
        stack.addArrangedSubview(self.duoUserField)
        self.configureField(self.duoLabelField, placeholder: "Подпись (напр. ❤️ Моя вторая половинка)", text: self.draft.duoLabel)
        stack.addArrangedSubview(self.duoLabelField)

        // Discord-style Connections
        stack.addArrangedSubview(self.makeSectionLabel("🔗 Интеграции (как в Discord)"))
        self.configureConnectionField(self.steamField, placeholder: "Steam: ник / SteamID64 / ссылка", text: self.draft.steamInput)
        stack.addArrangedSubview(self.steamField)
        self.configureConnectionField(self.robloxField, placeholder: "Roblox: ник / UserID / ссылка", text: self.draft.robloxInput)
        stack.addArrangedSubview(self.robloxField)
        self.configureConnectionField(self.twitchField, placeholder: "Twitch: канал или twitch.tv/...", text: self.draft.twitchInput)
        stack.addArrangedSubview(self.twitchField)
        self.configureConnectionField(self.githubField, placeholder: "GitHub: username или github.com/...", text: self.draft.githubInput)
        stack.addArrangedSubview(self.githubField)
        self.configureConnectionField(self.youtubeField, placeholder: "YouTube: @handle или youtube.com/@...", text: self.draft.youtubeInput)
        stack.addArrangedSubview(self.youtubeField)
        self.configureConnectionField(self.tiktokField, placeholder: "TikTok: @username", text: self.draft.tiktokInput)
        stack.addArrangedSubview(self.tiktokField)
        self.configureConnectionField(self.kickField, placeholder: "Kick: канал", text: self.draft.kickInput)
        stack.addArrangedSubview(self.kickField)
        self.configureConnectionField(self.discordField, placeholder: "Discord тег (напр. nick)", text: self.draft.discordTag)
        stack.addArrangedSubview(self.discordField)

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

    private func configurePickerButton(_ button: UIButton, action: Selector) {
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        button.backgroundColor = .secondarySystemGroupedBackground
        button.layer.cornerRadius = 10.0
        button.heightAnchor.constraint(equalToConstant: 42.0).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func makeActionButton(title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        b.backgroundColor = .secondarySystemGroupedBackground
        b.layer.cornerRadius = 10.0
        b.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
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

    private func configureConnectionField(_ tf: UITextField, placeholder: String, text: String) {
        self.configureField(tf, placeholder: placeholder, text: text)
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
    }

    private func refreshPickers() {
        let nitroTitle = GGDiscordProfileStore.nitroThemes.first(where: { $0.id == self.draft.nitroThemeId })?.title ?? "Выкл."
        self.nitroButton.setTitle("Nitro-тема: \(nitroTitle)  ▾", for: .normal)
        let effectTitle = GGDiscordProfileStore.effects.first(where: { $0.id == self.draft.effectId })?.title ?? "Выкл."
        self.effectButton.setTitle("Эффект: \(effectTitle)  ▾", for: .normal)
        let frameTitle = GGDiscordProfileStore.avatarFrames.first(where: { $0.id == self.draft.avatarFrameId })?.title ?? "Выкл."
        self.frameButton.setTitle("Рамка: \(frameTitle)  ▾", for: .normal)
        let svcTitle = GGDiscordProfileStore.musicServices.first(where: { $0.id == self.draft.musicServiceKind })?.title ?? "Выкл."
        self.musicServiceButton.setTitle("Сервис: \(svcTitle)  ▾", for: .normal)

        if self.draftPlaylist.isEmpty {
            self.playlistStatusLabel.text = "Плейлист пуст (добавьте любое число треков или загрузите с ПК через Wi-Fi в /stickers)"
        } else {
            let names = self.draftPlaylist.prefix(3).map { $0.title }.joined(separator: " • ")
            let tail = self.draftPlaylist.count > 3 ? " +\(self.draftPlaylist.count - 3)" : ""
            self.playlistStatusLabel.text = "Треков в плейлисте: \(self.draftPlaylist.count) (\(names)\(tail))"
        }

        if let rec = self.audioRecorder, rec.isRecording {
            self.voiceBioStatusLabel.text = "🔴 Идёт запись: \(self.recordSeconds)/15 сек..."
            self.recordVoiceBtn.setTitle("⏹ Стоп (\(self.recordSeconds)с)", for: .normal)
        } else if let pendingVoiceData {
            self.voiceBioStatusLabel.text = "Новое голосовое био готово (\(pendingVoiceData.count / 1024) КБ) ✅"
            self.recordVoiceBtn.setTitle("🎙 Запись", for: .normal)
        } else if !self.draft.voiceBioFileName.isEmpty || !self.draft.voiceBioUrl.isEmpty {
            self.voiceBioStatusLabel.text = "Голосовое био прикреплено к аватарке ✅"
            self.recordVoiceBtn.setTitle("🎙 Записать заново", for: .normal)
        } else {
            self.voiceBioStatusLabel.text = "Голосовое био не задано"
            self.recordVoiceBtn.setTitle("🎙 Запись", for: .normal)
        }
    }

    @objc private func pickBannerTapped() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        GGModalPresenter.presentWhenReady(picker, from: self)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }

        let handleImage: (UIImage) -> Void = { [weak self] rawImage in
            let normalized = GGDiscordBannerProcessor.normalizedOrientationImage(rawImage)
            guard let jpegData = GGDiscordBannerProcessor.renderNormalizedBannerData(from: normalized, verticalMode: .smartBlur),
                  let previewImg = UIImage(data: jpegData) else {
                return
            }
            let isPortrait = GGDiscordBannerProcessor.isPortrait(normalized)
            DispatchQueue.main.async {
                guard let strongSelf = self else { return }
                strongSelf.pendingBannerData = jpegData
                strongSelf.draft.bannerUrl = ""
                strongSelf.bannerPreview.image = previewImg
                if isPortrait {
                    let applyMode: (GGBannerVerticalMode) -> Void = { mode in
                        DispatchQueue.global(qos: .userInitiated).async {
                            guard let updatedData = GGDiscordBannerProcessor.renderNormalizedBannerData(from: normalized, verticalMode: mode),
                                  let updatedImg = UIImage(data: updatedData) else {
                                return
                            }
                            DispatchQueue.main.async {
                                guard let innerSelf = self else { return }
                                innerSelf.pendingBannerData = updatedData
                                innerSelf.draft.bannerUrl = ""
                                innerSelf.bannerPreview.image = updatedImg
                            }
                        }
                    }
                    let sheet = UIAlertController(
                        title: "📱 Вертикальный баннер",
                        message: "Фото вертикальное — мы уже красиво вписали его в размытый 16:10 фон. При желании выберите другой режим:",
                        preferredStyle: .actionSheet
                    )
                    sheet.addAction(UIAlertAction(title: "✨ Размытый фон + по центру", style: .default, handler: { _ in
                        applyMode(.smartBlur)
                    }))
                    sheet.addAction(UIAlertAction(title: "⬆️ Обрезать верх (портрет / лицо)", style: .default, handler: { _ in
                        applyMode(.topCrop)
                    }))
                    sheet.addAction(UIAlertAction(title: "🎯 Обрезать по центру", style: .default, handler: { _ in
                        applyMode(.centerCrop)
                    }))
                    sheet.addAction(UIAlertAction(title: "Готово", style: .cancel))
                    GGModalPresenter.presentWhenReady(sheet, from: strongSelf)
                }
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                if let url, let img = GGDiscordBannerProcessor.loadImage(from: url) {
                    handleImage(img)
                    return
                }
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { obj, _ in
                        if let img = obj as? UIImage {
                            handleImage(img)
                        }
                    }
                }
            }
        } else if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { obj, _ in
                if let img = obj as? UIImage {
                    handleImage(img)
                }
            }
        }
    }

    @objc private func pickMusicTapped() {
        self.pickMode = .playlistTracks
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio, .mp3, .mpeg4Audio], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        GGModalPresenter.presentWhenReady(picker, from: self)
    }

    @objc private func pickVoiceFileTapped() {
        self.pickMode = .voiceBioFile
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio, .mp3, .mpeg4Audio], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        GGModalPresenter.presentWhenReady(picker, from: self)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        switch self.pickMode {
        case .playlistTracks:
            for url in urls {
                if let data = try? Data(contentsOf: url), !data.isEmpty {
                    let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
                    let title = url.deletingPathExtension().lastPathComponent
                    if let track = GGDiscordProfileStore.shared.savePlaylistTrack(data: data, ext: ext, title: title, for: self.peerId) {
                        self.draftPlaylist.append(track)
                    }
                }
                try? FileManager.default.removeItem(at: url)
            }
        case .voiceBioFile:
            if let url = urls.first, let data = try? Data(contentsOf: url), !data.isEmpty, data.count <= 5 * 1024 * 1024 {
                self.pendingVoiceData = data
                self.pendingVoiceExt = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
                self.draft.voiceBioUrl = ""
                try? FileManager.default.removeItem(at: url)
            }
        }
        self.refreshPickers()
    }

    @objc private func managePlaylistTapped() {
        let sheet = UIAlertController(
            title: "🎵 Треки в плейлисте (\(self.draftPlaylist.count))",
            message: self.draftPlaylist.isEmpty ? "Треков пока нет" : "Выберите трек для удаления или очистите плейлист",
            preferredStyle: .actionSheet
        )
        for (idx, track) in self.draftPlaylist.prefix(10).enumerated() {
            sheet.addAction(UIAlertAction(title: "🗑 \(idx + 1). \(track.title)", style: .destructive, handler: { [weak self] _ in
                guard let strongSelf = self, idx < strongSelf.draftPlaylist.count else { return }
                strongSelf.draftPlaylist.remove(at: idx)
                strongSelf.refreshPickers()
            }))
        }
        if !self.draftPlaylist.isEmpty {
            sheet.addAction(UIAlertAction(title: "Очистить весь плейлист", style: .destructive, handler: { [weak self] _ in
                self?.draftPlaylist.removeAll()
                self?.draft.musicFileName = ""
                self?.draft.musicUrl = ""
                self?.draft.musicTitle = ""
                GGProfileMusicPlayer.shared.stop()
                self?.refreshPickers()
            }))
        }
        sheet.addAction(UIAlertAction(title: "Готово", style: .cancel))
        GGModalPresenter.presentWhenReady(sheet, from: self, sourceView: self.playlistStatusLabel)
    }

    @objc private func recordVoiceTapped() {
        if let rec = self.audioRecorder, rec.isRecording {
            self.stopRecording(saveIfValid: true)
            return
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.beginRecording()
                    } else {
                        self?.voiceBioStatusLabel.text = "Нет доступа к микрофону в Настройках iOS"
                    }
                }
            }
        } else {
            self.beginRecording()
        }
    }

    private func beginRecording() {
        let _ = try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker])
        let _ = try? AVAudioSession.sharedInstance().setActive(true)
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("mt_vbio_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        guard let recorder = try? AVAudioRecorder(url: tempUrl, settings: settings) else {
            self.voiceBioStatusLabel.text = "Не удалось запустить микрофон"
            return
        }
        recorder.record(forDuration: 15.0)
        self.audioRecorder = recorder
        self.recordTempUrl = tempUrl
        self.recordSeconds = 0
        self.recordTimer?.invalidate()
        self.recordTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.recordSeconds += 1
            if strongSelf.recordSeconds >= 15 || !(strongSelf.audioRecorder?.isRecording ?? false) {
                strongSelf.stopRecording(saveIfValid: true)
            } else {
                strongSelf.refreshPickers()
            }
        }
        self.refreshPickers()
    }

    private func invalidateRecorderOnly() {
        self.recordTimer?.invalidate()
        self.recordTimer = nil
        if let recorder = self.audioRecorder {
            if recorder.isRecording {
                recorder.stop()
            }
            self.audioRecorder = nil
        }
        if let tempUrl = self.recordTempUrl {
            try? FileManager.default.removeItem(at: tempUrl)
            self.recordTempUrl = nil
        }
    }

    private func stopRecording(saveIfValid: Bool) {
        self.recordTimer?.invalidate()
        self.recordTimer = nil
        if let recorder = self.audioRecorder {
            if recorder.isRecording {
                recorder.stop()
            }
            self.audioRecorder = nil
        }
        if let tempUrl = self.recordTempUrl {
            if saveIfValid, let data = try? Data(contentsOf: tempUrl), data.count > 1024, data.count <= 5 * 1024 * 1024 {
                self.pendingVoiceData = data
                self.pendingVoiceExt = "m4a"
                self.draft.voiceBioUrl = ""
            }
            try? FileManager.default.removeItem(at: tempUrl)
            self.recordTempUrl = nil
        }
        self.refreshPickers()
    }

    @objc private func clearVoiceTapped() {
        self.stopRecording(saveIfValid: false)
        self.pendingVoiceData = nil
        self.draft.voiceBioFileName = ""
        self.draft.voiceBioUrl = ""
        GGProfileMusicPlayer.shared.stopVoiceBio()
        self.refreshPickers()
    }

    @objc private func clearBannerTapped() {
        self.pendingBannerData = nil
        self.draft.bannerFileName = ""
        self.draft.bannerUrl = ""
        self.bannerPreview.image = nil
    }

    @objc private func pickNitroTapped() {
        let sheet = UIAlertController(title: "Nitro-тема профиля", message: nil, preferredStyle: .actionSheet)
        for item in GGDiscordProfileStore.nitroThemes {
            sheet.addAction(UIAlertAction(title: item.title, style: .default, handler: { [weak self] _ in
                self?.draft.nitroThemeId = item.id
                self?.refreshPickers()
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGModalPresenter.presentWhenReady(sheet, from: self, sourceView: self.nitroButton)
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
        GGModalPresenter.presentWhenReady(sheet, from: self, sourceView: self.effectButton)
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
        GGModalPresenter.presentWhenReady(sheet, from: self, sourceView: self.frameButton)
    }

    @objc private func pickMusicServiceTapped() {
        let sheet = UIAlertController(title: "Музыкальный сервис (живой статус)", message: nil, preferredStyle: .actionSheet)
        for item in GGDiscordProfileStore.musicServices {
            sheet.addAction(UIAlertAction(title: item.title, style: .default, handler: { [weak self] _ in
                self?.draft.musicServiceKind = item.id
                self?.refreshPickers()
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGModalPresenter.presentWhenReady(sheet, from: self, sourceView: self.musicServiceButton)
    }

    @objc private func forceSyncTapped() {
        GGDiscordProfileStore.shared.checkGlobalProfile(for: self.peerId, force: true) { [weak self] in
            guard let strongSelf = self else { return }
            let loaded = GGDiscordProfileStore.shared.profile(for: strongSelf.peerId) ?? GGDiscordProfileData()
            strongSelf.draft = loaded
            strongSelf.draftPlaylist = loaded.effectivePlaylist
            strongSelf.statusField.text = loaded.customStatus
            strongSelf.musicServiceUserField.text = loaded.musicServiceUser
            strongSelf.duoUserField.text = loaded.duoUsername
            strongSelf.duoLabelField.text = loaded.duoLabel
            strongSelf.steamField.text = loaded.steamInput
            strongSelf.robloxField.text = loaded.robloxInput
            strongSelf.twitchField.text = loaded.twitchInput
            strongSelf.githubField.text = loaded.githubInput
            strongSelf.youtubeField.text = loaded.youtubeInput
            strongSelf.tiktokField.text = loaded.tiktokInput
            strongSelf.kickField.text = loaded.kickInput
            strongSelf.discordField.text = loaded.discordTag
            if let url = GGDiscordProfileStore.shared.bannerFileURL(for: loaded),
               let img = GGDiscordBannerProcessor.loadImage(from: url) {
                strongSelf.bannerPreview.image = GGDiscordBannerProcessor.displayBannerImage(from: img)
            }
            strongSelf.refreshPickers()
            strongSelf.onDone?()
        }
    }

    @objc private func resetAllTapped() {
        self.stopRecording(saveIfValid: false)
        self.pendingBannerData = nil
        self.pendingVoiceData = nil
        self.draft = GGDiscordProfileData()
        self.draftPlaylist = []
        self.bannerPreview.image = nil
        self.statusField.text = ""
        self.musicServiceUserField.text = ""
        self.duoUserField.text = ""
        self.duoLabelField.text = ""
        self.steamField.text = ""
        self.robloxField.text = ""
        self.twitchField.text = ""
        self.githubField.text = ""
        self.youtubeField.text = ""
        self.tiktokField.text = ""
        self.kickField.text = ""
        self.discordField.text = ""
        GGProfileMusicPlayer.shared.stop()
        GGProfileMusicPlayer.shared.stopVoiceBio()
        self.refreshPickers()
    }

    @objc private func closeTapped() {
        self.stopRecording(saveIfValid: false)
        self.dismiss(animated: true)
    }

    @objc private func saveTapped() {
        self.stopRecording(saveIfValid: true)
        self.view.endEditing(true)
        self.draft.customStatus = self.statusField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.musicServiceUser = self.musicServiceUserField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.duoUsername = self.duoUserField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.duoLabel = self.duoLabelField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.steamInput = self.steamField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.robloxInput = self.robloxField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.twitchInput = self.twitchField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.githubInput = self.githubField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.youtubeInput = self.youtubeField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.tiktokInput = self.tiktokField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.kickInput = self.kickField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.discordTag = self.discordField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.draft.musicPlaylist = self.draftPlaylist

        if let data = self.pendingBannerData,
           let saved = GGDiscordProfileStore.shared.saveBannerData(data, for: self.peerId) {
            self.draft.bannerFileName = saved
            self.draft.bannerUrl = ""
        }
        if let vData = self.pendingVoiceData,
           let savedVoice = GGDiscordProfileStore.shared.saveVoiceBioData(vData, ext: self.pendingVoiceExt, for: self.peerId) {
            self.draft.voiceBioFileName = savedVoice
            self.draft.voiceBioUrl = ""
        }

        GGDiscordProfileStore.shared.setProfile(self.draft, for: self.peerId, publishGlobally: self.isOwn)
        self.onDone?()
        self.dismiss(animated: true)
    }
}
