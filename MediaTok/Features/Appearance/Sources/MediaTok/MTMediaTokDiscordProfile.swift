import Foundation
import UIKit
import CoreImage
import CryptoKit
import ObjectiveC
import AVFoundation
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import AsyncDisplayKit
import Display
import ItemListUI
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import UndoUI
import MTCore
import MTHooks
import MTSettingsUI

// MARK: - Data Model

public struct MTProfileTrack: Codable, Equatable {
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

public struct MTDiscordProfileData: Codable, Equatable {
    public var bannerFileName: String
    public var bannerUrl: String
    public var effectId: String
    public var avatarFrameId: String
    public var customStatus: String
    public var steamInput: String
    public var spotifyInput: String
    public var robloxInput: String
    public var musicFileName: String
    public var musicUrl: String
    public var musicTitle: String
    public var musicPlaylist: [MTProfileTrack]
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
    public var fontSlug: String
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
        case spotifyInput
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
        case fontSlug
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
        spotifyInput: String = "",
        robloxInput: String = "",
        musicFileName: String = "",
        musicUrl: String = "",
        musicTitle: String = "",
        musicPlaylist: [MTProfileTrack] = [],
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
        fontSlug: String = "",
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
        self.spotifyInput = spotifyInput
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
        self.fontSlug = fontSlug
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
        self.spotifyInput = try c.decodeIfPresent(String.self, forKey: .spotifyInput) ?? ""
        self.robloxInput = try c.decodeIfPresent(String.self, forKey: .robloxInput) ?? ""
        self.musicFileName = try c.decodeIfPresent(String.self, forKey: .musicFileName) ?? ""
        self.musicUrl = try c.decodeIfPresent(String.self, forKey: .musicUrl) ?? ""
        self.musicTitle = try c.decodeIfPresent(String.self, forKey: .musicTitle) ?? ""
        self.musicPlaylist = try c.decodeIfPresent([MTProfileTrack].self, forKey: .musicPlaylist) ?? []
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
        self.fontSlug = try c.decodeIfPresent(String.self, forKey: .fontSlug) ?? ""
        self.duoUsername = try c.decodeIfPresent(String.self, forKey: .duoUsername) ?? ""
        self.duoLabel = try c.decodeIfPresent(String.self, forKey: .duoLabel) ?? ""
        self.updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }

    public var effectivePlaylist: [MTProfileTrack] {
        if !self.musicPlaylist.isEmpty {
            return self.musicPlaylist
        }
        if !self.musicFileName.isEmpty || !self.musicUrl.isEmpty {
            return [MTProfileTrack(
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
            && (self.fontSlug.isEmpty || self.fontSlug == "none")
            && self.customStatus.isEmpty
            && self.steamInput.isEmpty
            && self.spotifyInput.isEmpty
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

final class MTProfileMusicPlayer {
    static let shared = MTProfileMusicPlayer()

    private var player: AVPlayer?
    private var playingPeerKey: String?
    private var endObserver: NSObjectProtocol?
    private var queue: [MTProfileTrack] = []
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
        let key = MTDiscordProfileStore.keyString(for: peerId)
        return self.playingPeerKey == key && (self.player?.rate ?? 0.0) > 0.0
    }

    func isPlayingVoiceBio(peerId: PeerId) -> Bool {
        let key = MTDiscordProfileStore.keyString(for: peerId)
        return self.voicePeerKey == key && (self.voicePlayer?.rate ?? 0.0) > 0.0
    }

    func currentTrackSummary(peerId: PeerId, playlist: [MTProfileTrack]) -> (title: String, positionText: String) {
        let key = MTDiscordProfileStore.keyString(for: peerId)
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
        let wasPlaying = self.player != nil
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
        if wasPlaying && self.voicePlayer == nil {
            let _ = try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    func stopVoiceBio() {
        let wasPlaying = self.voicePlayer != nil
        self.voicePlayer?.pause()
        self.voicePlayer = nil
        self.voicePeerKey = nil
        if let obs = self.voiceEndObserver {
            NotificationCenter.default.removeObserver(obs)
            self.voiceEndObserver = nil
        }
        let cb = self.voiceCallback
        self.voiceCallback = nil
        if wasPlaying && self.player == nil {
            let _ = try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        cb?()
    }

    func toggle(peerId: PeerId, profile: MTDiscordProfileData, onStateChanged: (() -> Void)?) {
        let key = MTDiscordProfileStore.keyString(for: peerId)
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

    func next(peerId: PeerId, profile: MTDiscordProfileData, onStateChanged: (() -> Void)?) {
        let key = MTDiscordProfileStore.keyString(for: peerId)
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

    func previous(peerId: PeerId, profile: MTDiscordProfileData, onStateChanged: (() -> Void)?) {
        let key = MTDiscordProfileStore.keyString(for: peerId)
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
        if let local = MTDiscordProfileStore.shared.trackFileURL(track) {
            url = local
        } else if let remote = MTMediaTokCoreLogic.isAllowedMediaURL(track.url) {
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
        let _ = try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
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

    func toggleVoiceBio(peerId: PeerId, profile: MTDiscordProfileData, onStateChanged: (() -> Void)?) {
        let key = MTDiscordProfileStore.keyString(for: peerId)
        if self.isPlayingVoiceBio(peerId: peerId) {
            self.stopVoiceBio()
            onStateChanged?()
            return
        }
        let targetUrl: URL?
        if let local = MTDiscordProfileStore.shared.voiceBioFileURL(for: profile) {
            targetUrl = local
        } else if let remote = MTMediaTokCoreLogic.isAllowedMediaURL(profile.voiceBioUrl) {
            targetUrl = remote
        } else {
            targetUrl = nil
        }
        guard let url = targetUrl else { return }

        self.stop()
        self.stopVoiceBio()
        let _ = try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
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

final class MTDiscordProfileStore {
    static let shared = MTDiscordProfileStore()

    static let effects: [(id: String, title: String)] = [
        ("none", "Выкл."),
        ("aurora", "Северное сияние"),
        ("fireflies", "Золотые светлячки"),
        ("lightning", "Неоновые молнии"),
        ("sakura", "Лепестки сакуры"),
        ("fire", "Пламя и искры"),
        ("matrix", "Матрица"),
        ("neon", "Неоновая волна"),
        ("snow", "Кристальный снег"),
        ("rain", "Ливень"),
        ("stars", "Звёздный космос")
    ]

    static let avatarFrames: [(id: String, title: String, colors: [UIColor])] = [
        ("none", "Выкл.", []),
        ("neon_cyan", "Кибер-Неон", [UIColor(rgb: 0x00F5FF), UIColor(rgb: 0xFF00D4), UIColor(rgb: 0x00F5FF)]),
        ("rainbow", "Радуга RGB", [UIColor(rgb: 0xFF3B5C), UIColor(rgb: 0xFFB800), UIColor(rgb: 0x00E676), UIColor(rgb: 0x00C8FF), UIColor(rgb: 0xC471FF), UIColor(rgb: 0xFF3B5C)]),
        ("fire", "Огонь", [UIColor(rgb: 0xFFF04D), UIColor(rgb: 0xFF6B00), UIColor(rgb: 0xFF1744), UIColor(rgb: 0xFFF04D)]),
        ("gold", "Золото", [UIColor(rgb: 0xFFF4B8), UIColor(rgb: 0xF5B301), UIColor(rgb: 0xB87300), UIColor(rgb: 0xFFF4B8)]),
        ("toxic", "Токсик", [UIColor(rgb: 0xCCFF00), UIColor(rgb: 0x00FF66), UIColor(rgb: 0x008F39), UIColor(rgb: 0xCCFF00)]),
        ("sakura", "Сакура", [UIColor(rgb: 0xFFD1DC), UIColor(rgb: 0xFF7EB3), UIColor(rgb: 0xC471ED), UIColor(rgb: 0xFFD1DC)]),
        ("glitch", "Глитч", [UIColor(rgb: 0x00FFFF), UIColor(rgb: 0xFF0055), UIColor(rgb: 0xFFFFFF), UIColor(rgb: 0x00FFFF)]),
        ("obsidian", "Обсидиан", [UIColor(rgb: 0x6A00F4), UIColor(rgb: 0xE10098), UIColor(rgb: 0x1A1A2E), UIColor(rgb: 0x6A00F4)])
    ]

    static let nitroThemes: [(id: String, title: String, colors: [UIColor])] = [
        ("none", "Выкл. (стандарт)", []),
        ("cyber_cyan", "Кибер-Циан", [UIColor(rgb: 0x00F5FF), UIColor(rgb: 0x3A0CA3)]),
        ("neon_sakura", "Неон Сакура", [UIColor(rgb: 0xFF4D8D), UIColor(rgb: 0x7209B7)]),
        ("crimson_gold", "Багрянец и Золото", [UIColor(rgb: 0xFF9F1C), UIColor(rgb: 0x9B002C)]),
        ("emerald_matrix", "Изумруд Матрицы", [UIColor(rgb: 0x00F5A0), UIColor(rgb: 0x004E64)]),
        ("royal_violet", "Королевский Неон", [UIColor(rgb: 0xB5179E), UIColor(rgb: 0x240046)]),
        ("sunset_fire", "Огненный Закат", [UIColor(rgb: 0xFF512F), UIColor(rgb: 0x810034)])
    ]

    static func fontDisplayName(for slug: String) -> String {
        if slug.isEmpty || slug == "none" {
            return "Системный"
        }
        return MTMediaTokFonts.all.first(where: { $0.slug == slug })?.displayName ?? "Системный"
    }

    static func resolvedFont(slug: String, size: CGFloat, fallbackWeight: UIFont.Weight) -> UIFont {
        if !slug.isEmpty && slug != "none",
           let bundled = MTMediaTokFonts.all.first(where: { $0.slug == slug }),
           let custom = MTMediaTokFonts.menuFont(bundled, size: size) {
            return custom
        }
        return UIFont.systemFont(ofSize: size, weight: fallbackWeight)
    }

    static let musicServices: [(id: String, title: String)] = [
        ("none", "Выкл."),
        ("lastfm", "Last.fm (Spotify / Яндекс / VK / Apple Music)"),
        ("listenbrainz", "ListenBrainz (Open Scrobbler)")
    ]

    private let lock = NSLock()
    private let ownPeersDefaultsKey = "mediatok.discord.own_peers.v1"
    private let heartbeatDefaultsKey = "mediatok.discord.last_heartbeat.v1"
    private var loaded = false
    private var entries: [String: MTDiscordProfileData] = [:]
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
            return base.appendingPathComponent("mediatok/mediatok", isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("mediatok/mediatok", isDirectory: true)
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
        let primaryURL = self.configURL()
        let backupURL = primaryURL.appendingPathExtension("bak")
        if let data = try? Data(contentsOf: primaryURL),
           let decoded = try? JSONDecoder().decode([String: MTDiscordProfileData].self, from: data) {
            self.entries = decoded
            return
        }
        if let bakData = try? Data(contentsOf: backupURL),
           let decoded = try? JSONDecoder().decode([String: MTDiscordProfileData].self, from: bakData) {
            self.entries = decoded
            try? bakData.write(to: primaryURL, options: [.atomic])
        }
    }

    private func persistLocked() {
        let dir = self.rootDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let primaryURL = self.configURL()
        if let previous = try? Data(contentsOf: primaryURL), !previous.isEmpty {
            let backupURL = primaryURL.appendingPathExtension("bak")
            try? previous.write(to: backupURL, options: [.atomic])
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(self.entries) {
            try? data.write(to: primaryURL, options: [.atomic])
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

    func profile(for peerId: PeerId) -> MTDiscordProfileData? {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.ensureLoadedLocked()
        return self.entries[MTDiscordProfileStore.keyString(for: peerId)]
    }

    func bannerFileURL(for profile: MTDiscordProfileData) -> URL? {
        guard !profile.bannerFileName.isEmpty else { return nil }
        let url = self.bannersDir().appendingPathComponent(profile.bannerFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func musicFileURL(for profile: MTDiscordProfileData) -> URL? {
        guard !profile.musicFileName.isEmpty else { return nil }
        let url = self.musicDir().appendingPathComponent(profile.musicFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func trackFileURL(_ track: MTProfileTrack) -> URL? {
        guard !track.fileName.isEmpty else { return nil }
        let url = self.musicDir().appendingPathComponent(track.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func voiceBioFileURL(for profile: MTDiscordProfileData) -> URL? {
        guard !profile.voiceBioFileName.isEmpty else { return nil }
        let url = self.voiceBioDir().appendingPathComponent(profile.voiceBioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func saveBannerData(_ data: Data, for peerId: PeerId) -> String? {
        let dir = self.bannersDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = "banner_\(MTDiscordProfileStore.keyString(for: peerId))_\(Int64(Date().timeIntervalSince1970 * 1000.0)).jpg"
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
        let cleanExt = MTMediaTokCoreLogic.sanitizeAudioExtension(ext)
        let uid = String(UUID().uuidString.prefix(8))
        let fileName = "track_\(MTDiscordProfileStore.keyString(for: peerId))_\(Int64(Date().timeIntervalSince1970 * 1000.0))_\(uid).\(cleanExt)"
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
        let cleanExt = MTMediaTokCoreLogic.sanitizeAudioExtension(ext)
        let fileName = "vbio_\(MTDiscordProfileStore.keyString(for: peerId))_\(Int64(Date().timeIntervalSince1970 * 1000.0)).\(cleanExt)"
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            return nil
        }
        return fileName
    }

    func savePlaylistTrack(data: Data, ext: String, title: String, for peerId: PeerId) -> MTProfileTrack? {
        guard !data.isEmpty, data.count <= 25 * 1024 * 1024,
              let fileName = self.saveMusicData(data, ext: ext, for: peerId) else {
            return nil
        }
        let cleanTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        return MTProfileTrack(
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
        var current = self.profile(for: peerId) ?? MTDiscordProfileData()
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

    func setProfile(_ profile: MTDiscordProfileData, for peerId: PeerId, publishGlobally: Bool) {
        let key = MTDiscordProfileStore.keyString(for: peerId)
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

    private static func downloadLimitedData(from url: URL, maxBytes: Int64, attempt: Int = 1, completion: @escaping (Data?) -> Void) {
        let req = URLRequest(url: url, timeoutInterval: 45.0)
        MTMediaTokWave9Tools.urlSession(for: url).downloadTask(with: req) { tempUrl, response, _ in
            if let http = response as? HTTPURLResponse,
               (200 ... 299).contains(http.statusCode),
               let tempUrl {
                let attrs = try? FileManager.default.attributesOfItem(atPath: tempUrl.path)
                let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                if fileSize > 0, fileSize <= maxBytes,
                   let data = try? Data(contentsOf: tempUrl),
                   !data.isEmpty,
                   Int64(data.count) <= maxBytes {
                    completion(data)
                    return
                }
            }
            // #418 Auto-retry 4K banners & profile media with exponential backoff (up to 3 attempts).
            if attempt < 3 {
                let delay = attempt == 1 ? 0.6 : 1.8
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
                    MTDiscordProfileStore.downloadLimitedData(from: url, maxBytes: maxBytes, attempt: attempt + 1, completion: completion)
                }
            } else {
                completion(nil)
            }
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

    private static func canonicalSyncMaterial(dialogId: Int64, payload: [String: Any], withoutEscapingSlashes: Bool = false) -> Data? {
        var canonical = payload
        canonical.removeValue(forKey: "sig_v2")
        var opts: JSONSerialization.WritingOptions = [.sortedKeys]
        if withoutEscapingSlashes {
            opts.insert(.withoutEscapingSlashes)
        }
        guard JSONSerialization.isValidJSONObject(canonical),
              let body = try? JSONSerialization.data(withJSONObject: canonical, options: opts) else {
            return nil
        }
        var material = Data("mediatok-sync-v2:\(dialogId):".utf8)
        material.append(body)
        return material
    }

    private static func postProfileJson(
        _ profile: MTDiscordProfileData,
        bannerUrl: String,
        musicUrl: String,
        syncedPlaylist: [[String: String]],
        voiceBioUrl: String,
        ts: Int64,
        dialogId: Int64,
        completion: (() -> Void)? = nil
    ) {
        guard let ntfyUrl = URL(string: "https://ntfy.sh/mtprof_v1_\(dialogId)") else { return }
        var visualName = ""
        var visualBio = ""
        var visualPhone = ""
        var visualAlsoPhones = ""
        var visualUsername = ""
        var visualAlsoUsernames = ""
        var visualBadgeMode = MTVisualBadgeMode.default.rawValue
        var wornGiftDict: [String: Any]? = nil
        var premiumEmojiStatusFileId: Int64 = 0
        if dialogId > 0, let peerKey = MTPeerKey(namespace: 0, id: dialogId) {
            if let ov = MTVisualProfileStore.shared.override(for: peerKey) {
                visualName = String(ov.name.prefix(128))
                visualBio = String(ov.bio.prefix(4000))
                visualPhone = String(ov.phone.prefix(64))
                visualAlsoPhones = String(ov.alsoPhones.prefix(256))
                visualUsername = String(ov.username.prefix(64))
                visualAlsoUsernames = String(ov.alsoUsernames.prefix(256))
                visualBadgeMode = ov.badgeMode.rawValue
                if let worn = ov.wornStarGift {
                    wornGiftDict = [
                        "id": worn.id,
                        "fileId": worn.fileId,
                        "title": String(worn.title.prefix(128)),
                        "slug": String(worn.slug.prefix(128)),
                        "patternFileId": worn.patternFileId,
                        "innerColor": worn.innerColor,
                        "outerColor": worn.outerColor,
                        "patternColor": worn.patternColor,
                        "textColor": worn.textColor
                    ]
                }
            }
            let ownPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(dialogId))
            if let storedStatus = (UserDefaults.standard.object(forKey: "mediatok.premium_emoji.status_file.\(ownPeerId.toInt64())") as? NSNumber)?.int64Value, storedStatus != 0 {
                premiumEmojiStatusFileId = storedStatus
            }
        }
        var payload: [String: Any] = [
            "bannerUrl": bannerUrl,
            "effectId": profile.effectId,
            "avatarFrameId": profile.avatarFrameId,
            "nitroThemeId": profile.nitroThemeId,
            "fontSlug": String(profile.fontSlug.prefix(64)),
            "customStatus": String(profile.customStatus.prefix(140)),
            "visualName": visualName,
            "visualBio": visualBio,
            "visualPhone": visualPhone,
            "visualAlsoPhones": visualAlsoPhones,
            "visualUsername": visualUsername,
            "visualAlsoUsernames": visualAlsoUsernames,
            "visualBadgeMode": visualBadgeMode,
            "premiumEmojiStatusFileId": premiumEmojiStatusFileId,
            "steamInput": String(profile.steamInput.prefix(120)),
            "spotifyInput": String(profile.spotifyInput.prefix(140)),
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
        if let wornGiftDict {
            payload["wornStarGift"] = wornGiftDict
        }
        // #495 MediaTok Sync v2: attach asymmetric Ed25519 owner signature + public key (TOFU) over canonical JSON
        payload["pub_v2"] = MTMediaTokWave9Tools.syncOwnerPublicKeyBase64(dialogId: dialogId)
        if let canonicalMaterial = MTDiscordProfileStore.canonicalSyncMaterial(dialogId: dialogId, payload: payload) {
            payload["sig_v2"] = MTMediaTokWave9Tools.signSyncPayloadData(canonicalMaterial, dialogId: dialogId)
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }

        var targetUrls: [URL] = [ntfyUrl]
        let syncTopic = "mtprof_v1_\(dialogId)"
        if let customMirror = MTMediaTokWave9Tools.customSyncMirrorURL(forTopic: syncTopic) {
            targetUrls.append(customMirror)
        }
        let group = DispatchGroup()
        for url in targetUrls {
            group.enter()
            func sendAttempt(_ attempt: Int) {
                var req = URLRequest(url: url, timeoutInterval: 20.0)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("MediaTok/DiscordProfile-v2", forHTTPHeaderField: "User-Agent")
                req.httpBody = jsonData
                MTMediaTokWave9Tools.urlSession(for: url).dataTask(with: req) { _, response, _ in
                    if let http = response as? HTTPURLResponse,
                       let retryDelay = MTMediaTokCoreLogic.shouldRetryNtfyStatus(http.statusCode, attempt: attempt) {
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + retryDelay) {
                            sendAttempt(attempt + 1)
                        }
                        return
                    }
                    group.leave()
                }.resume()
            }
            sendAttempt(1)
        }
        group.notify(queue: .global(qos: .utility)) {
            completion?()
        }
    }

    private static func uploadToQuAxFallback(data: Data, fileName: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://qu.ax/upload.php") else {
            completion(nil)
            return
        }
        let boundary = "----MediaTokQuAx\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var req = URLRequest(url: url, timeoutInterval: 35.0)
        req.httpMethod = "POST"
        req.setValue("MediaTok/DiscordProfile", forHTTPHeaderField: "User-Agent")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        if let d1 = "--\(boundary)\r\nContent-Disposition: form-data; name=\"files[]\"; filename=\"\(fileName)\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8) {
            body.append(d1)
        }
        body.append(data)
        if let d2 = "\r\n--\(boundary)--\r\n".data(using: .utf8) {
            body.append(d2)
        }
        req.httpBody = body

        MTMediaTokWave9Tools.urlSession(for: url).dataTask(with: req) { respData, response, _ in
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let respData,
                  let allowed = MTMediaTokCoreLogic.parseQuAxUploadUrl(respData) else {
                completion(nil)
                return
            }
            completion(allowed.absoluteString)
        }.resume()
    }

    private static func uploadToCatbox(data: Data, fileName: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://catbox.moe/user/api.php") else {
            Self.uploadToQuAxFallback(data: data, fileName: fileName, completion: completion)
            return
        }
        let boundary = "----MediaTokSync\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var req = URLRequest(url: url, timeoutInterval: 18.0)
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

        MTMediaTokWave9Tools.urlSession(for: url).dataTask(with: req) { respData, response, _ in
            if let http = response as? HTTPURLResponse,
               (200 ... 299).contains(http.statusCode),
               let respData,
               let raw = String(data: respData, encoding: .utf8),
               let allowed = MTMediaTokCoreLogic.isAllowedMediaURL(raw) {
                completion(allowed.absoluteString)
                return
            }
            // Automatic multi-host failover when catbox.moe is throttled or blocked by mobile ISP
            Self.uploadToQuAxFallback(data: data, fileName: fileName, completion: completion)
        }.resume()
    }

    private func publishGlobalProfile(_ profile: MTDiscordProfileData, for peerId: PeerId) {
        guard let dialogId = MTDiscordProfileStore.globalDialogId(for: peerId) else { return }

        let group = DispatchGroup()
        let urlLock = NSLock()
        var resolvedBannerUrl = MTMediaTokCoreLogic.isAllowedMediaURL(profile.bannerUrl)?.absoluteString ?? ""
        var resolvedVoiceUrl = MTMediaTokCoreLogic.isAllowedMediaURL(profile.voiceBioUrl)?.absoluteString ?? ""
        var tracks = profile.effectivePlaylist

        if !profile.bannerFileName.isEmpty && resolvedBannerUrl.isEmpty,
           let localUrl = self.bannerFileURL(for: profile),
           let bannerData = try? Data(contentsOf: localUrl), !bannerData.isEmpty {
            group.enter()
            MTDiscordProfileStore.uploadToCatbox(data: bannerData, fileName: profile.bannerFileName) { uploaded in
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
            MTDiscordProfileStore.uploadToCatbox(data: voiceData, fileName: profile.voiceBioFileName) { uploaded in
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
            let validExisting = MTMediaTokCoreLogic.isAllowedMediaURL(track.url)?.absoluteString ?? ""
            if validExisting.isEmpty,
               !track.fileName.isEmpty,
               let localTrack = self.trackFileURL(track),
               let tData = try? Data(contentsOf: localTrack), !tData.isEmpty, tData.count <= 25 * 1024 * 1024 {
                group.enter()
                MTDiscordProfileStore.uploadToCatbox(data: tData, fileName: track.fileName) { uploaded in
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
                guard let valid = MTMediaTokCoreLogic.isAllowedMediaURL(t.url)?.absoluteString else { return nil }
                return ["id": t.id, "title": String(t.title.prefix(120)), "url": valid]
            }
            let firstMusicUrl = syncedPlaylistDicts.first?["url"] ?? (MTMediaTokCoreLogic.isAllowedMediaURL(profile.musicUrl)?.absoluteString ?? "")

            MTDiscordProfileStore.postProfileJson(
                profile,
                bannerUrl: finalBanner,
                musicUrl: firstMusicUrl,
                syncedPlaylist: syncedPlaylistDicts,
                voiceBioUrl: finalVoice,
                ts: profile.updatedAt,
                dialogId: dialogId
            ) {
                let key = MTDiscordProfileStore.keyString(for: peerId)
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

    func syncOwnVisualProfileIfNeeded(for peerId: PeerId) {
        guard let dialogId = MTDiscordProfileStore.globalDialogId(for: peerId), dialogId > 0 else { return }
        let ov = MTVisualProfileStore.shared.override(for: peerId.mtKey)
        let statusFileId = (UserDefaults.standard.object(forKey: "mediatok.premium_emoji.status_file.\(peerId.toInt64())") as? NSNumber)?.int64Value ?? 0
        let hasAnyVisual = (ov != nil && !(ov?.name.isEmpty ?? true && ov?.bio.isEmpty ?? true && ov?.phone.isEmpty ?? true && ov?.alsoPhones.isEmpty ?? true && ov?.username.isEmpty ?? true && ov?.alsoUsernames.isEmpty ?? true && ov?.badgeMode == .default && ov?.wornStarGift == nil)) || statusFileId != 0
        let sig = "\(ov?.name ?? "")|\(ov?.bio ?? "")|\(ov?.phone ?? "")|\(ov?.alsoPhones ?? "")|\(ov?.username ?? "")|\(ov?.alsoUsernames ?? "")|\(ov?.badgeMode.rawValue ?? MTVisualBadgeMode.default.rawValue)|\(ov?.wornStarGift?.id ?? 0)|\(statusFileId)"
        let defaultsKey = "mediatok.discord.last_synced_visual_sig.\(dialogId)"
        let lastSig = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        guard sig != lastSig else { return }
        if !hasAnyVisual && lastSig.isEmpty { return }
        UserDefaults.standard.set(sig, forKey: defaultsKey)
        let key = MTDiscordProfileStore.keyString(for: peerId)
        if hasAnyVisual {
            self.markOwnPeer(key, isOwn: true)
        }
        let prof = self.profile(for: peerId) ?? MTDiscordProfileData()
        let dicts: [[String: String]] = prof.effectivePlaylist.prefix(12).compactMap { t in
            guard let valid = MTMediaTokCoreLogic.isAllowedMediaURL(t.url)?.absoluteString else { return nil }
            return ["id": t.id, "title": String(t.title.prefix(120)), "url": valid]
        }
        MTDiscordProfileStore.postProfileJson(
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
        guard let dialogId = MTDiscordProfileStore.globalDialogId(for: peerId) else { return }
        let key = MTDiscordProfileStore.keyString(for: peerId)
        let now = Date().timeIntervalSince1970

        self.lock.lock()
        self.ensureLoadedLocked()
        let existingLocal = self.entries[key]
        let isOwn = (self.activeAccountPeerId == peerId) || self.ownPeersSet().contains(key)
        var pendingOwnHeartbeatProfile: MTDiscordProfileData? = nil
        if !force && isOwn, let localProf = existingLocal, !localProf.isEmpty {
            let needHeartbeat = (now - self.lastHeartbeat(for: key)) >= 28800.0
            if needHeartbeat {
                self.updateHeartbeat(for: key, ts: now)
                pendingOwnHeartbeatProfile = localProf
            }
            let prevOwnPoll = self.lastSyncCheck[key] ?? 0.0
            let shouldPollOwnOtherDevices = (now - prevOwnPoll) >= 180.0
            if shouldPollOwnOtherDevices || needHeartbeat {
                self.lastSyncCheck[key] = now
                self.lock.unlock()
                // Poll remote ntfy.sh FIRST so fresh edits published on Windows PC are merged before any 8h heartbeat!
            } else {
                self.lock.unlock()
                return
            }
        } else {
            let prev = self.lastSyncCheck[key] ?? 0.0
            if !force && (now - prev) < 300.0 {
                self.lock.unlock()
                return
            }
            self.lastSyncCheck[key] = now
            self.lock.unlock()
        }

        let syncTopic = "mtprof_v1_\(dialogId)"
        guard let primaryUrl = URL(string: "https://ntfy.sh/\(syncTopic)/json?poll=1&since=all") else { return }
        var pollUrls: [URL] = [primaryUrl]
        if let mirrorTopicUrl = MTMediaTokWave9Tools.customSyncMirrorURL(forTopic: syncTopic),
           let mirrorPollUrl = URL(string: "\(mirrorTopicUrl.absoluteString)/json?poll=1&since=all") {
            pollUrls.append(mirrorPollUrl)
        }

        let pollGroup = DispatchGroup()
        let bodiesLock = NSLock()
        var primaryBody: String?
        var mirrorBody: String?
        for (idx, pollUrl) in pollUrls.enumerated() {
            pollGroup.enter()
            var req = URLRequest(url: pollUrl, timeoutInterval: 12.0)
            req.setValue("MediaTok/DiscordProfile-v2", forHTTPHeaderField: "User-Agent")
            MTMediaTokWave9Tools.urlSession(for: pollUrl).dataTask(with: req) { data, response, _ in
                if let http = response as? HTTPURLResponse,
                   (200 ... 299).contains(http.statusCode),
                   let data,
                   data.count <= 262_144,
                   let body = String(data: data, encoding: .utf8),
                   !body.isEmpty {
                    bodiesLock.lock()
                    if idx == 0 {
                        primaryBody = body
                    } else {
                        mirrorBody = body
                    }
                    bodiesLock.unlock()
                }
                pollGroup.leave()
            }.resume()
        }

        pollGroup.notify(queue: DispatchQueue.global(qos: .utility)) {
            bodiesLock.lock()
            let orderedBodies = [primaryBody, mirrorBody].compactMap { $0 }
            bodiesLock.unlock()
            guard !orderedBodies.isEmpty else { return }

            let maxAllowedTs = Int64(Date().timeIntervalSince1970) + 300
            var latestSigned: [String: Any]?
            var latestSignedTs: Int64 = 0
            var latestUnsigned: [String: Any]?
            var latestUnsignedTs: Int64 = 0
            for body in orderedBodies {
                for line in body.components(separatedBy: .newlines) {
                    guard let obj = MTDiscordProfileStore.unwrapNtfyJsonLine(line) else {
                        continue
                    }
                    let candidateTs: Int64
                    if let v = obj["ts"] as? Int64 { candidateTs = v }
                    else if let v = obj["ts"] as? Int { candidateTs = Int64(v) }
                    else if let v = obj["ts"] as? Double { candidateTs = Int64(v) }
                    else { candidateTs = 0 }
                    guard candidateTs > 0 && candidateTs <= maxAllowedTs else {
                        continue
                    }
                    // #495 Sync v2: verify Ed25519 signature (TOFU per dialogId in chronological order)
                    let sigV2 = obj["sig_v2"] as? String
                    let pubV2 = obj["pub_v2"] as? String
                    if let sigV2, !sigV2.isEmpty, let pubV2, !pubV2.isEmpty {
                        let verified: Bool
                        if let canonicalMaterial = MTDiscordProfileStore.canonicalSyncMaterial(dialogId: dialogId, payload: obj),
                           MTMediaTokWave9Tools.verifySyncSignatureData(dialogId: dialogId, material: canonicalMaterial, signatureBase64: sigV2, publicKeyBase64: pubV2) {
                            verified = true
                        } else if let unescapedMaterial = MTDiscordProfileStore.canonicalSyncMaterial(dialogId: dialogId, payload: obj, withoutEscapingSlashes: true),
                                  MTMediaTokWave9Tools.verifySyncSignatureData(dialogId: dialogId, material: unescapedMaterial, signatureBase64: sigV2, publicKeyBase64: pubV2) {
                            verified = true
                        } else {
                            let cBanner = obj["bannerUrl"] as? String ?? ""
                            let cStatus = obj["customStatus"] as? String ?? ""
                            let cVName = obj["visualName"] as? String ?? ""
                            let cVUser = obj["visualUsername"] as? String ?? ""
                            let cVBadge = (obj["visualBadgeMode"] as? NSNumber)?.intValue ?? MTVisualBadgeMode.default.rawValue
                            let legacyMaterial = "\(dialogId)|\(candidateTs)|\(cBanner)|\(cStatus)|\(cVName)|\(cVUser)|\(cVBadge)"
                            verified = MTMediaTokWave9Tools.verifySyncSignature(dialogId: dialogId, material: legacyMaterial, signatureBase64: sigV2, publicKeyBase64: pubV2)
                        }
                        if verified && candidateTs >= latestSignedTs {
                            latestSigned = obj
                            latestSignedTs = candidateTs
                        }
                    } else {
                        if MTMediaTokWave9Tools.verifySyncSignature(dialogId: dialogId, material: "", signatureBase64: nil, publicKeyBase64: nil),
                           candidateTs >= latestUnsignedTs {
                            latestUnsigned = obj
                            latestUnsignedTs = candidateTs
                        }
                    }
                }
            }
            let obj: [String: Any]
            let remoteTs: Int64
            if let sObj = latestSigned, latestSignedTs > 0 {
                obj = sObj
                remoteTs = latestSignedTs
            } else if let uObj = latestUnsigned, latestUnsignedTs > 0,
                      MTMediaTokWave9Tools.verifySyncSignature(dialogId: dialogId, material: "", signatureBase64: nil, publicKeyBase64: nil) {
                obj = uObj
                remoteTs = latestUnsignedTs
            } else {
                if let hbProf = pendingOwnHeartbeatProfile {
                    self.publishHeartbeatIfNeeded(hbProf, peerId: peerId, dialogId: dialogId, now: now)
                }
                return
            }

            self.lock.lock()
            self.ensureLoadedLocked()
            let existing = self.entries[key]
            self.lock.unlock()

            if let existing, !force && remoteTs <= existing.updatedAt {
                if let hbProf = pendingOwnHeartbeatProfile {
                    self.publishHeartbeatIfNeeded(hbProf, peerId: peerId, dialogId: dialogId, now: now)
                }
                return
            }

            let rawBannerUrl = (obj["bannerUrl"] as? String) ?? existing?.bannerUrl ?? ""
            let rawMusicUrl = (obj["musicUrl"] as? String) ?? existing?.musicUrl ?? ""
            let rawVoiceUrl = (obj["voiceBioUrl"] as? String) ?? existing?.voiceBioUrl ?? ""
            let validatedBanner = MTMediaTokCoreLogic.isAllowedMediaURL(rawBannerUrl)
            let validatedMusic = MTMediaTokCoreLogic.isAllowedMediaURL(rawMusicUrl)
            let validatedVoice = MTMediaTokCoreLogic.isAllowedMediaURL(rawVoiceUrl)
            let remoteBannerUrl = validatedBanner?.absoluteString ?? ""
            let remoteMusicUrl = validatedMusic?.absoluteString ?? ""
            let remoteVoiceUrl = validatedVoice?.absoluteString ?? ""

            let validEffects = Set(MTDiscordProfileStore.effects.map { $0.id })
            let rawEffect = (obj["effectId"] as? String) ?? existing?.effectId ?? "none"
            let safeEffect = validEffects.contains(rawEffect) ? rawEffect : "none"

            let validFrames = Set(MTDiscordProfileStore.avatarFrames.map { $0.id })
            let rawFrame = (obj["avatarFrameId"] as? String) ?? existing?.avatarFrameId ?? "none"
            let safeFrame = validFrames.contains(rawFrame) ? rawFrame : "none"

            let validNitros = Set(MTDiscordProfileStore.nitroThemes.map { $0.id })
            let rawNitro = (obj["nitroThemeId"] as? String) ?? existing?.nitroThemeId ?? "none"
            let safeNitro = validNitros.contains(rawNitro) ? rawNitro : "none"

            let validFonts = Set(MTMediaTokFonts.all.map { $0.slug })
            let rawFontSlug = ((obj["fontSlug"] as? String) ?? existing?.fontSlug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let safeFontSlug = validFonts.contains(rawFontSlug) ? rawFontSlug : ""

            let rawMusicSvc = ((obj["musicServiceKind"] as? String) ?? existing?.musicServiceKind ?? "none").lowercased()
            let safeMusicSvc = ["none", "lastfm", "listenbrainz"].contains(rawMusicSvc) ? rawMusicSvc : "none"

            let safeStatus = String(((obj["customStatus"] as? String) ?? existing?.customStatus ?? "").prefix(140))
            let safeSteam = String((obj["steamInput"] as? String ?? "").prefix(120))
            let safeSpotify = String((obj["spotifyInput"] as? String ?? "").prefix(140))
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
            let safeVisualName = String((obj["visualName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
            let safeVisualPhone = String((obj["visualPhone"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
            let safeVisualAlsoPhones = String((obj["visualAlsoPhones"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
            let safeVisualUsername = String((obj["visualUsername"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
            let safeVisualAlsoUsernames = String((obj["visualAlsoUsernames"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
            let rawBadge = (obj["visualBadgeMode"] as? NSNumber)?.intValue ?? MTVisualBadgeMode.default.rawValue
            let safeBadgeMode = MTVisualBadgeMode(rawValue: rawBadge) ?? .default
            var parsedWornGift: MTWornStarGift? = nil
            if let wg = obj["wornStarGift"] as? [String: Any],
               let gid = (wg["id"] as? NSNumber)?.int64Value, gid != 0,
               let fid = (wg["fileId"] as? NSNumber)?.int64Value, fid != 0 {
                parsedWornGift = MTWornStarGift(
                    id: gid,
                    fileId: fid,
                    title: String((wg["title"] as? String ?? "").prefix(128)),
                    slug: String((wg["slug"] as? String ?? "").prefix(128)),
                    patternFileId: (wg["patternFileId"] as? NSNumber)?.int64Value ?? 0,
                    innerColor: (wg["innerColor"] as? NSNumber)?.int32Value ?? 0,
                    outerColor: (wg["outerColor"] as? NSNumber)?.int32Value ?? 0,
                    patternColor: (wg["patternColor"] as? NSNumber)?.int32Value ?? 0,
                    textColor: (wg["textColor"] as? NSNumber)?.int32Value ?? -1
                )
            }
            let remoteStatusFileId = (obj["premiumEmojiStatusFileId"] as? NSNumber)?.int64Value ?? 0
            if !isOwn && dialogId > 0, let peerKey = MTPeerKey(namespace: 0, id: dialogId) {
                let hasRemoteVisual = !safeVisualName.isEmpty || !safeVisualBio.isEmpty || !safeVisualPhone.isEmpty || !safeVisualAlsoPhones.isEmpty || !safeVisualUsername.isEmpty || !safeVisualAlsoUsernames.isEmpty || safeBadgeMode != .default || parsedWornGift != nil
                if hasRemoteVisual {
                    var ov = MTVisualProfileStore.shared.override(for: peerKey) ?? MTVisualPeerOverride()
                    var changed = false
                    if ov.name != safeVisualName { ov.name = safeVisualName; changed = true }
                    if ov.bio != safeVisualBio { ov.bio = safeVisualBio; changed = true }
                    if ov.phone != safeVisualPhone { ov.phone = safeVisualPhone; changed = true }
                    if ov.alsoPhones != safeVisualAlsoPhones { ov.alsoPhones = safeVisualAlsoPhones; changed = true }
                    if ov.username != safeVisualUsername { ov.username = safeVisualUsername; changed = true }
                    if ov.alsoUsernames != safeVisualAlsoUsernames { ov.alsoUsernames = safeVisualAlsoUsernames; changed = true }
                    if ov.badgeMode != safeBadgeMode { ov.badgeMode = safeBadgeMode; changed = true }
                    if ov.wornStarGift != parsedWornGift { ov.wornStarGift = parsedWornGift; changed = true }
                    if changed {
                        MTVisualProfileStore.shared.setOverride(ov, for: peerKey)
                    }
                } else if let existingOv = MTVisualProfileStore.shared.override(for: peerKey), existingOv.wornStarGift != nil {
                    var ov = existingOv
                    ov.wornStarGift = nil
                    MTVisualProfileStore.shared.setOverride(ov, for: peerKey)
                }
                let statusKey = "mediatok.premium_emoji.status_file.\(peerId.toInt64())"
                if remoteStatusFileId != 0 {
                    UserDefaults.standard.set(NSNumber(value: remoteStatusFileId), forKey: statusKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: statusKey)
                }
            }

            var parsedPlaylist: [MTProfileTrack] = []
            if let arr = obj["musicPlaylist"] as? [[String: Any]] {
                for item in arr.prefix(12) {
                    if let urlStr = item["url"] as? String,
                       let validUrl = MTMediaTokCoreLogic.isAllowedMediaURL(urlStr) {
                        let tTitle = String((item["title"] as? String ?? "Трек").prefix(120))
                        let tid = String((item["id"] as? String ?? UUID().uuidString).prefix(64))
                        let prevFile = existing?.musicPlaylist.first(where: { $0.url == validUrl.absoluteString })?.fileName ?? ""
                        parsedPlaylist.append(MTProfileTrack(id: tid, title: tTitle, fileName: prevFile, url: validUrl.absoluteString))
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
                MTDiscordProfileStore.downloadLimitedData(from: bUrl, maxBytes: 15 * 1024 * 1024) { bData in
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
                MTDiscordProfileStore.downloadLimitedData(from: vUrl, maxBytes: 5 * 1024 * 1024) { vData in
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
                       let tUrl = MTMediaTokCoreLogic.isAllowedMediaURL(parsedPlaylist[idx].url) {
                        dlGroup.enter()
                        MTDiscordProfileStore.downloadLimitedData(from: tUrl, maxBytes: 25 * 1024 * 1024) { mData in
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
                MTDiscordProfileStore.downloadLimitedData(from: mUrl, maxBytes: 25 * 1024 * 1024) { mData in
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
                let finalBannerFile = savedBannerFile.isEmpty && obj["bannerUrl"] == nil ? (existing?.bannerFileName ?? "") : savedBannerFile
                let finalMusicFile = savedMusicFile.isEmpty && obj["musicUrl"] == nil ? (existing?.musicFileName ?? "") : savedMusicFile
                let finalVoiceFile = savedVoiceFile.isEmpty && obj["voiceBioUrl"] == nil ? (existing?.voiceBioFileName ?? "") : savedVoiceFile
                let finalPlaylist = parsedPlaylist.isEmpty && obj["musicPlaylist"] == nil ? (existing?.musicPlaylist ?? []) : parsedPlaylist
                dlLock.unlock()

                let remote = MTDiscordProfileData(
                    bannerFileName: finalBannerFile,
                    bannerUrl: remoteBannerUrl,
                    effectId: safeEffect,
                    avatarFrameId: safeFrame,
                    customStatus: safeStatus,
                    steamInput: safeSteam,
                    spotifyInput: safeSpotify,
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
                    fontSlug: safeFontSlug,
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
        }
    }

    private func publishHeartbeatIfNeeded(_ localProf: MTDiscordProfileData, peerId: PeerId, dialogId: Int64, now: TimeInterval) {
        let needsMediaUpload = (!localProf.bannerFileName.isEmpty && localProf.bannerUrl.isEmpty)
            || (!localProf.voiceBioFileName.isEmpty && localProf.voiceBioUrl.isEmpty)
            || localProf.effectivePlaylist.prefix(12).contains { !$0.fileName.isEmpty && $0.url.isEmpty }
        if needsMediaUpload {
            self.publishGlobalProfile(localProf, for: peerId)
        } else {
            let dicts: [[String: String]] = localProf.effectivePlaylist.prefix(12).compactMap { t in
                guard let valid = MTMediaTokCoreLogic.isAllowedMediaURL(t.url)?.absoluteString else { return nil }
                return ["id": t.id, "title": String(t.title.prefix(120)), "url": valid]
            }
            MTDiscordProfileStore.postProfileJson(
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
}

// MARK: - Live Steam, Roblox, Music, Twitch & GitHub Resolvers (Public Endpoints, Zero API Keys)

private struct MTResolvedConnection {
    let username: String
    let memberSinceText: String?
    let primaryStatBold: String?
    let primaryStatLabel: String?
    let secondaryStatBold: String?
    let secondaryStatLabel: String?
    let isVerified: Bool
    let displayText: String
    let statusBadge: String
    let profileUrl: URL
    let fetchedAt: TimeInterval
}

private final class MTConnectionResolvers {
    static let shared = MTConnectionResolvers()

    private let lock = NSLock()
    private var steamCache: [String: MTResolvedConnection] = [:]
    private var robloxCache: [String: MTResolvedConnection] = [:]
    private var musicCache: [String: MTResolvedConnection] = [:]
    private var twitchCache: [String: MTResolvedConnection] = [:]
    private var githubCache: [String: MTResolvedConnection] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    static func normalizeSteam(_ raw: String) -> (profileUrl: URL, xmlUrl: URL, cleanLabel: String)? {
        return MTMediaTokCoreLogic.normalizeSteam(raw)
    }

    static func formatRussianMemberSince(isoOrSteamDate raw: String?) -> String? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        let monthsRu = ["янв.", "февр.", "марта", "апр.", "мая", "июня", "июля", "авг.", "сент.", "окт.", "нояб.", "дек."]

        // ISO-8601 (GitHub / Roblox): "2023-11-29T..."
        if s.count >= 10, s[s.index(s.startIndex, offsetBy: 4)] == "-", s[s.index(s.startIndex, offsetBy: 7)] == "-" {
            let parts = s.prefix(10).split(separator: "-")
            if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), (1 ... 12).contains(m) {
                return "В числе участников с \(d) \(monthsRu[m - 1]) \(y) г."
            }
        }

        // Steam XML English date: "November 29, 2023" or "November 29th, 2023"
        let cleaned = s.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "st", with: "")
            .replacingOccurrences(of: "nd", with: "")
            .replacingOccurrences(of: "rd", with: "")
            .replacingOccurrences(of: "th", with: "")
        let tokens = cleaned.split(separator: " ")
        if tokens.count >= 3 {
            let monthMap: [String: Int] = [
                "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3,
                "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
                "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9,
                "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12
            ]
            if let m = monthMap[tokens[0].lowercased()], let d = Int(tokens[1]), let y = Int(tokens[2]) {
                return "В числе участников с \(d) \(monthsRu[m - 1]) \(y) г."
            }
            if let d = Int(tokens[0]), let m = monthMap[tokens[1].lowercased()], let y = Int(tokens[2]) {
                return "В числе участников с \(d) \(monthsRu[m - 1]) \(y) г."
            }
        }
        return nil
    }

    func steamResolved(for input: String, onUpdate: @escaping () -> Void) -> MTResolvedConnection? {
        guard let norm = MTConnectionResolvers.normalizeSteam(input) else { return nil }
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
                let nick = MTConnectionResolvers.extractXmlTag("steamID", in: xml) ?? norm.cleanLabel
                let memberSince = MTConnectionResolvers.formatRussianMemberSince(
                    isoOrSteamDate: MTConnectionResolvers.extractXmlTag("memberSince", in: xml)
                )
                let onlineState = (MTConnectionResolvers.extractXmlTag("onlineState", in: xml) ?? "").lowercased()
                let rawStateMsg = MTConnectionResolvers.extractXmlTag("stateMessage", in: xml) ?? ""
                let cleanStateMsg = rawStateMsg
                    .replacingOccurrences(of: "<br/>", with: " · ")
                    .replacingOccurrences(of: "<br>", with: " · ")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let topGame = MTConnectionResolvers.extractXmlTag("gameName", in: xml)
                let hours = MTConnectionResolvers.extractXmlTag("hoursPlayed", in: xml)
                let hours2Wk = MTConnectionResolvers.extractXmlTag("hoursPlayed2Wk", in: xml)
                let recentGamesCount = xml.components(separatedBy: "<mostPlayedGame>").count - 1

                let badge: String
                if onlineState == "in-game" {
                    badge = "В игре"
                } else if onlineState == "online" {
                    badge = "В сети"
                } else {
                    badge = "Офлайн"
                }

                var primaryBold: String?
                var primaryLabel: String?
                var secondaryBold: String?
                var secondaryLabel: String?

                if let hours, !hours.isEmpty, let topGame, !topGame.isEmpty {
                    primaryBold = "\(hours) ч"
                    primaryLabel = topGame
                    if let hours2Wk, !hours2Wk.isEmpty {
                        secondaryBold = "\(hours2Wk) ч"
                        secondaryLabel = "за 2 нед."
                    } else if recentGamesCount > 1 {
                        secondaryBold = "\(recentGamesCount)"
                        secondaryLabel = "игр"
                    }
                } else if recentGamesCount > 0 {
                    primaryBold = "\(recentGamesCount)"
                    primaryLabel = "Games"
                    if let hours2Wk, !hours2Wk.isEmpty {
                        secondaryBold = "\(hours2Wk) ч"
                        secondaryLabel = "за 2 нед."
                    }
                } else if onlineState == "in-game", !cleanStateMsg.isEmpty {
                    primaryBold = "В игре"
                    primaryLabel = cleanStateMsg
                } else if !cleanStateMsg.isEmpty {
                    primaryBold = badge
                    primaryLabel = cleanStateMsg
                }

                let resolved = MTResolvedConnection(
                    username: nick,
                    memberSinceText: memberSince,
                    primaryStatBold: primaryBold,
                    primaryStatLabel: primaryLabel,
                    secondaryStatBold: secondaryBold,
                    secondaryStatLabel: secondaryLabel,
                    isVerified: true,
                    displayText: nick,
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
            return cached
        }
        return MTResolvedConnection(
            username: norm.cleanLabel,
            memberSinceText: "Steam",
            primaryStatBold: nil,
            primaryStatLabel: nil,
            secondaryStatBold: nil,
            secondaryStatLabel: nil,
            isVerified: true,
            displayText: norm.cleanLabel,
            statusBadge: "Steam",
            profileUrl: norm.profileUrl,
            fetchedAt: 0
        )
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

    func robloxResolved(for input: String, onUpdate: @escaping () -> Void) -> MTResolvedConnection? {
        guard let parsed = MTConnectionResolvers.parseRobloxInput(input) else { return nil }
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
                var createdRaw: String?
                var verified = false
                var presenceType = 0
                var lastLocation = ""

                if let infoUrl = URL(string: "https://users.roblox.com/v1/users/\(uid)") {
                    group.enter()
                    URLSession.shared.dataTask(with: infoUrl) { data, _, _ in
                        if let data, let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                            displayName = obj["displayName"] as? String ?? ""
                            userName = obj["name"] as? String ?? ""
                            createdRaw = obj["created"] as? String
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
                    case 2: badge = "В игре"
                    case 1: badge = "В сети"
                    case 3: badge = "Studio"
                    default: badge = "Офлайн"
                    }
                    let title = !displayName.isEmpty ? displayName : (!userName.isEmpty ? userName : "ID \(uid)")
                    let memberSince = MTConnectionResolvers.formatRussianMemberSince(isoOrSteamDate: createdRaw)
                    let primaryBold = badge
                    let primaryLabel = (!lastLocation.isEmpty && presenceType == 2) ? lastLocation : (!userName.isEmpty ? "@\(userName)" : nil)
                    let profileUrl = URL(string: "https://www.roblox.com/users/\(uid)/profile") ?? parsed.fallbackUrl
                    let resolved = MTResolvedConnection(
                        username: title,
                        memberSinceText: memberSince,
                        primaryStatBold: primaryBold,
                        primaryStatLabel: primaryLabel,
                        secondaryStatBold: nil,
                        secondaryStatLabel: nil,
                        isVerified: verified || true,
                        displayText: title,
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
            return cached
        }
        let fallbackName = parsed.username ?? "ID \(parsed.userId ?? 0)"
        return MTResolvedConnection(
            username: fallbackName,
            memberSinceText: "Roblox",
            primaryStatBold: nil,
            primaryStatLabel: nil,
            secondaryStatBold: nil,
            secondaryStatLabel: nil,
            isVerified: true,
            displayText: fallbackName,
            statusBadge: "Roblox",
            profileUrl: parsed.fallbackUrl,
            fetchedAt: 0
        )
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
            let storeResult: (MTMediaTokCoreLogic.LiveMusicTrack?) -> Void = { track in
                self.lock.lock()
                self.inFlight.remove(key)
                if let track {
                    let display = track.artist.isEmpty ? track.track : "\(track.artist) — \(track.track)"
                    let badge = track.isLive ? "Сейчас" : (cleanKind == "lastfm" ? "Last.fm" : "ListenBrainz")
                    self.musicCache[key] = MTResolvedConnection(
                        username: cleanUser,
                        memberSinceText: cleanKind == "lastfm" ? "Last.fm" : "ListenBrainz",
                        primaryStatBold: track.isLive ? "Сейчас" : "Недавно",
                        primaryStatLabel: display,
                        secondaryStatBold: nil,
                        secondaryStatLabel: nil,
                        isVerified: true,
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
                    if let data, let live = MTMediaTokCoreLogic.parseListenBrainzJson(data) {
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
                        let recent = data2.flatMap { MTMediaTokCoreLogic.parseListenBrainzJson($0) }
                        storeResult(recent)
                    }.resume()
                }.resume()
            } else {
                var req = URLRequest(url: targetProfileUrl, timeoutInterval: 10.0)
                req.setValue("MediaTok/Music", forHTTPHeaderField: "User-Agent")
                URLSession.shared.dataTask(with: req) { data, _, _ in
                    let parsedTrack = data.flatMap { String(data: $0, encoding: .utf8) }.flatMap { MTMediaTokCoreLogic.parseLastFmHtml($0) }
                    storeResult(parsedTrack)
                }.resume()
            }
        }

        if let cached {
            return (cached.displayText, cached.statusBadge, cached.profileUrl)
        }
        let serviceLabel = (cleanKind == "lastfm") ? "Last.fm" : "ListenBrainz"
        return ("\(cleanUser) (\(serviceLabel))", "Sync", targetProfileUrl)
    }

    func twitchResolved(for input: String, onUpdate: @escaping () -> Void) -> MTResolvedConnection? {
        guard let norm = MTMediaTokCoreLogic.normalizeConnection(platform: "twitch", raw: input) else { return nil }
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
                let badge = isOffline ? "Офлайн" : "В эфире"
                let resolved = MTResolvedConnection(
                    username: norm.handle,
                    memberSinceText: "Twitch",
                    primaryStatBold: badge,
                    primaryStatLabel: isOffline ? nil : String(trimmed.prefix(40)),
                    secondaryStatBold: nil,
                    secondaryStatLabel: nil,
                    isVerified: true,
                    displayText: norm.handle,
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
            return cached
        }
        return MTResolvedConnection(
            username: norm.handle,
            memberSinceText: "Twitch",
            primaryStatBold: nil,
            primaryStatLabel: nil,
            secondaryStatBold: nil,
            secondaryStatLabel: nil,
            isVerified: true,
            displayText: norm.handle,
            statusBadge: "Twitch",
            profileUrl: norm.url,
            fetchedAt: 0
        )
    }

    func githubResolved(for input: String, onUpdate: @escaping () -> Void) -> MTResolvedConnection? {
        guard let norm = MTMediaTokCoreLogic.normalizeConnection(platform: "github", raw: input) else { return nil }
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
                let memberSince = MTConnectionResolvers.formatRussianMemberSince(isoOrSteamDate: obj["created_at"] as? String)
                let resolved = MTResolvedConnection(
                    username: login,
                    memberSinceText: memberSince ?? "GitHub",
                    primaryStatBold: "\(repos)",
                    primaryStatLabel: "Repos",
                    secondaryStatBold: followers > 0 ? "\(followers)" : nil,
                    secondaryStatLabel: followers > 0 ? "Followers" : nil,
                    isVerified: true,
                    displayText: "@\(login)",
                    statusBadge: "\(repos) репо",
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
            return cached
        }
        return MTResolvedConnection(
            username: norm.handle,
            memberSinceText: "GitHub",
            primaryStatBold: nil,
            primaryStatLabel: nil,
            secondaryStatBold: nil,
            secondaryStatLabel: nil,
            isVerified: true,
            displayText: "@\(norm.handle)",
            statusBadge: "GitHub",
            profileUrl: norm.url,
            fetchedAt: 0
        )
    }
}

// MARK: - Animated Profile Effects & Avatar Frame Views

internal final class MTDiscordProfileEffectView: UIView {
    private var activeEffectId: String = "none"
    private var foregroundEmitter: CAEmitterLayer?
    private var backgroundEmitter: CAEmitterLayer?
    private var auroraPrimaryLayer: CAGradientLayer?
    private var auroraSecondaryLayer: CAGradientLayer?
    private var neonGradient: CAGradientLayer?
    private var boltFlashBackdrop: CALayer?
    private var boltLayer: CAShapeLayer?
    private var boltCoreLayer: CAShapeLayer?
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
        case "aurora":
            self.setupAurora()
        case "fireflies":
            self.setupFireflies()
        case "sakura":
            self.setupDualParticles(
                kind: "sakura",
                fgColor: UIColor(rgb: 0xFFB7D5),
                bgColor: UIColor(rgb: 0xFF85B3),
                fgBirthRate: 5.5,
                bgBirthRate: 4.5,
                velocity: 32.0,
                yAccel: 12.0,
                xDrift: 14.0,
                size: 12.5,
                fromBottom: false,
                spin: 1.8
            )
        case "fire":
            self.setupDualParticles(
                kind: "fire",
                fgColor: UIColor(rgb: 0xFF8C00),
                bgColor: UIColor(rgb: 0xFF3D00),
                fgBirthRate: 11.0,
                bgBirthRate: 9.0,
                velocity: -62.0,
                yAccel: -24.0,
                xDrift: 6.0,
                size: 9.5,
                fromBottom: true,
                spin: 0.45
            )
        case "snow":
            self.setupDualParticles(
                kind: "snow",
                fgColor: UIColor(white: 1.0, alpha: 0.72),
                bgColor: UIColor(rgb: 0xCBE8FF).withAlphaComponent(0.5),
                fgBirthRate: 4.0,
                bgBirthRate: 4.5,
                velocity: 24.0,
                yAccel: 7.0,
                xDrift: 8.0,
                size: 5.5,
                fromBottom: false,
                spin: 0.4
            )
        case "rain":
            self.setupDualParticles(
                kind: "rain",
                fgColor: UIColor(rgb: 0x8CD4FF).withAlphaComponent(0.55),
                bgColor: UIColor(rgb: 0x4EA8DE).withAlphaComponent(0.4),
                fgBirthRate: 9.0,
                bgBirthRate: 7.0,
                velocity: 165.0,
                yAccel: 110.0,
                xDrift: 14.0,
                size: 6.5,
                fromBottom: false,
                spin: 0.0
            )
        case "stars":
            self.setupDualParticles(
                kind: "stars",
                fgColor: UIColor(rgb: 0xFFF099),
                bgColor: UIColor(rgb: 0x9BB8FF),
                fgBirthRate: 6.5,
                bgBirthRate: 6.0,
                velocity: 12.0,
                yAccel: 0.0,
                xDrift: 4.0,
                size: 11.0,
                fromBottom: false,
                spin: 1.2
            )
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
        self.foregroundEmitter?.removeFromSuperlayer()
        self.foregroundEmitter = nil
        self.backgroundEmitter?.removeFromSuperlayer()
        self.backgroundEmitter = nil
        self.auroraPrimaryLayer?.removeFromSuperlayer()
        self.auroraPrimaryLayer = nil
        self.auroraSecondaryLayer?.removeFromSuperlayer()
        self.auroraSecondaryLayer = nil
        self.neonGradient?.removeFromSuperlayer()
        self.neonGradient = nil
        self.boltFlashBackdrop?.removeFromSuperlayer()
        self.boltFlashBackdrop = nil
        self.boltLayer?.removeFromSuperlayer()
        self.boltLayer = nil
        self.boltCoreLayer?.removeFromSuperlayer()
        self.boltCoreLayer = nil
        for lbl in self.matrixLabels { lbl.removeFromSuperview() }
        self.matrixLabels.removeAll()
    }

    private func makeParticleImage(kind: String, color: UIColor, size: CGFloat, softBlur: Bool) -> CGImage? {
        let side = max(26.0, size * 2.8)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            let cx = side / 2.0
            let cy = side / 2.0
            let r = side * (softBlur ? 0.28 : 0.35)
            cg.setShadow(
                offset: .zero,
                blur: size * (softBlur ? 0.55 : 0.34),
                color: color.withAlphaComponent(softBlur ? 0.65 : 0.82).cgColor
            )
            switch kind {
            case "sakura":
                let path = UIBezierPath()
                path.move(to: CGPoint(x: cx, y: cy + r))
                path.addCurve(
                    to: CGPoint(x: cx - r * 0.24, y: cy - r * 0.90),
                    controlPoint1: CGPoint(x: cx - r * 0.98, y: cy + r * 0.28),
                    controlPoint2: CGPoint(x: cx - r * 0.86, y: cy - r * 0.76)
                )
                path.addLine(to: CGPoint(x: cx, y: cy - r * 0.56))
                path.addLine(to: CGPoint(x: cx + r * 0.24, y: cy - r * 0.90))
                path.addCurve(
                    to: CGPoint(x: cx, y: cy + r),
                    controlPoint1: CGPoint(x: cx + r * 0.86, y: cy - r * 0.76),
                    controlPoint2: CGPoint(x: cx + r * 0.98, y: cy + r * 0.28)
                )
                path.close()
                cg.saveGState()
                path.addClip()
                let colors = [
                    UIColor.white.withAlphaComponent(softBlur ? 0.70 : 0.96).cgColor,
                    color.withAlphaComponent(softBlur ? 0.62 : 0.94).cgColor,
                    UIColor(rgb: 0xFF6FA5).withAlphaComponent(softBlur ? 0.55 : 0.88).cgColor
                ] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.55, 1.0]) {
                    cg.drawLinearGradient(
                        grad,
                        start: CGPoint(x: cx, y: cy - r),
                        end: CGPoint(x: cx, y: cy + r),
                        options: []
                    )
                } else {
                    color.withAlphaComponent(softBlur ? 0.60 : 0.95).setFill()
                    path.fill()
                }
                cg.restoreGState()
            case "firefly":
                let colors = [
                    UIColor.white.withAlphaComponent(softBlur ? 0.65 : 0.98).cgColor,
                    color.withAlphaComponent(softBlur ? 0.52 : 0.86).cgColor,
                    color.withAlphaComponent(0.0).cgColor
                ] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.42, 1.0]) {
                    cg.drawRadialGradient(
                        grad,
                        startCenter: CGPoint(x: cx, y: cy),
                        startRadius: 0.0,
                        endCenter: CGPoint(x: cx, y: cy),
                        endRadius: r * 1.3,
                        options: []
                    )
                }
            case "stars":
                let path = UIBezierPath()
                let inner = r * 0.26
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
                color.withAlphaComponent(softBlur ? 0.58 : 0.96).setFill()
                path.fill()
                UIColor.white.withAlphaComponent(softBlur ? 0.45 : 0.85).setFill()
                UIBezierPath(ovalIn: CGRect(x: cx - inner * 0.65, y: cy - inner * 0.65, width: inner * 1.3, height: inner * 1.3)).fill()
            case "snow":
                if softBlur {
                    let bokehColors = [
                        color.withAlphaComponent(0.70).cgColor,
                        color.withAlphaComponent(0.25).cgColor,
                        color.withAlphaComponent(0.0).cgColor
                    ] as CFArray
                    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bokehColors, locations: [0.0, 0.55, 1.0]) {
                        cg.drawRadialGradient(
                            grad,
                            startCenter: CGPoint(x: cx, y: cy),
                            startRadius: 0.0,
                            endCenter: CGPoint(x: cx, y: cy),
                            endRadius: r * 1.15,
                            options: []
                        )
                    }
                } else {
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
                }
            case "fire":
                let path = UIBezierPath()
                path.move(to: CGPoint(x: cx, y: cy - r))
                path.addQuadCurve(to: CGPoint(x: cx, y: cy + r * 0.85), controlPoint: CGPoint(x: cx + r * 0.85, y: cy + r * 0.25))
                path.addQuadCurve(to: CGPoint(x: cx, y: cy - r), controlPoint: CGPoint(x: cx - r * 0.85, y: cy + r * 0.25))
                path.close()
                color.withAlphaComponent(softBlur ? 0.55 : 0.95).setFill()
                path.fill()
                UIColor(rgb: 0xFFF3B0).withAlphaComponent(softBlur ? 0.45 : 0.85).setFill()
                UIBezierPath(ovalIn: CGRect(x: cx - r * 0.26, y: cy - r * 0.05, width: r * 0.52, height: r * 0.52)).fill()
            case "rain":
                let w = max(1.6, size * (softBlur ? 0.14 : 0.20))
                let h = r * (softBlur ? 1.8 : 2.35)
                let streak = UIBezierPath(roundedRect: CGRect(x: cx - w / 2.0, y: cy - h / 2.0, width: w, height: h), cornerRadius: w / 2.0)
                color.withAlphaComponent(softBlur ? 0.42 : 0.88).setFill()
                streak.fill()
            default:
                cg.setFillColor(color.withAlphaComponent(softBlur ? 0.50 : 0.92).cgColor)
                cg.fillEllipse(in: CGRect(x: cx - r * 0.65, y: cy - r * 0.65, width: r * 1.3, height: r * 1.3))
            }
        }
        return img.cgImage
    }

    private func setupDualParticles(
        kind: String,
        fgColor: UIColor,
        bgColor: UIColor,
        fgBirthRate: Float,
        bgBirthRate: Float,
        velocity: CGFloat,
        yAccel: CGFloat,
        xDrift: CGFloat,
        size: CGFloat,
        fromBottom: Bool,
        spin: CGFloat
    ) {
        let bgLayer = CAEmitterLayer()
        bgLayer.emitterShape = (kind == "stars") ? .rectangle : .line
        let bgCell = CAEmitterCell()
        bgCell.contents = self.makeParticleImage(kind: kind, color: bgColor, size: size * 0.78, softBlur: true)
        bgCell.birthRate = bgBirthRate
        bgCell.lifetime = (kind == "rain") ? 2.4 : 6.2
        bgCell.lifetimeRange = 1.8
        bgCell.velocity = velocity * 0.62
        bgCell.velocityRange = abs(velocity) * 0.35
        bgCell.yAcceleration = yAccel * 0.65
        bgCell.xAcceleration = xDrift * 0.6
        bgCell.emissionLongitude = fromBottom ? -.pi / 2.0 : (kind == "rain" ? .pi / 2.0 + 0.16 : .pi / 2.0)
        bgCell.emissionRange = (kind == "rain") ? 0.06 : .pi / 3.5
        bgCell.scale = 0.56
        bgCell.scaleRange = 0.28
        bgCell.alphaRange = 0.25
        bgCell.alphaSpeed = -0.13
        bgCell.spin = spin * 0.65
        bgCell.spinRange = 0.9
        bgLayer.emitterCells = [bgCell]
        self.layer.addSublayer(bgLayer)
        self.backgroundEmitter = bgLayer

        let fgLayer = CAEmitterLayer()
        fgLayer.emitterShape = (kind == "stars") ? .rectangle : .line
        let fgCell = CAEmitterCell()
        fgCell.contents = self.makeParticleImage(kind: kind, color: fgColor, size: size, softBlur: false)
        fgCell.birthRate = fgBirthRate
        fgCell.lifetime = (kind == "rain") ? 1.9 : 5.2
        fgCell.lifetimeRange = 1.6
        fgCell.velocity = velocity
        fgCell.velocityRange = abs(velocity) * 0.42
        fgCell.yAcceleration = yAccel
        fgCell.xAcceleration = xDrift
        fgCell.emissionLongitude = fromBottom ? -.pi / 2.0 : (kind == "rain" ? .pi / 2.0 + 0.16 : .pi / 2.0)
        fgCell.emissionRange = (kind == "rain") ? 0.05 : .pi / 4.0
        fgCell.scale = 0.82
        fgCell.scaleRange = 0.38
        fgCell.alphaRange = 0.18
        fgCell.alphaSpeed = -0.17
        fgCell.spin = spin
        fgCell.spinRange = 1.35
        fgLayer.emitterCells = [fgCell]
        self.layer.addSublayer(fgLayer)
        self.foregroundEmitter = fgLayer
    }

    private func setupAurora() {
        let primary = CAGradientLayer()
        primary.colors = [
            UIColor(rgb: 0x00FFA3).withAlphaComponent(0.0).cgColor,
            UIColor(rgb: 0x00F5D4).withAlphaComponent(0.42).cgColor,
            UIColor(rgb: 0x00BBF9).withAlphaComponent(0.36).cgColor,
            UIColor(rgb: 0x9B5DE5).withAlphaComponent(0.38).cgColor,
            UIColor(rgb: 0x7209B7).withAlphaComponent(0.0).cgColor
        ]
        primary.locations = [0.0, 0.25, 0.5, 0.78, 1.0]
        primary.startPoint = CGPoint(x: 0.0, y: 0.15)
        primary.endPoint = CGPoint(x: 1.0, y: 0.85)

        let shiftColors = CABasicAnimation(keyPath: "colors")
        shiftColors.toValue = [
            UIColor(rgb: 0x7209B7).withAlphaComponent(0.0).cgColor,
            UIColor(rgb: 0x4CC9F0).withAlphaComponent(0.40).cgColor,
            UIColor(rgb: 0x00F5A0).withAlphaComponent(0.46).cgColor,
            UIColor(rgb: 0xF15BB5).withAlphaComponent(0.32).cgColor,
            UIColor(rgb: 0x00BBF9).withAlphaComponent(0.0).cgColor
        ]
        shiftColors.duration = 4.6
        shiftColors.autoreverses = true
        shiftColors.repeatCount = .infinity
        primary.add(shiftColors, forKey: "auroraPrimaryColors")

        let waveStart = CABasicAnimation(keyPath: "startPoint")
        waveStart.fromValue = CGPoint(x: 0.0, y: 0.10)
        waveStart.toValue = CGPoint(x: 0.28, y: 0.42)
        waveStart.duration = 5.4
        waveStart.autoreverses = true
        waveStart.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        waveStart.repeatCount = .infinity
        primary.add(waveStart, forKey: "auroraWaveStart")

        self.layer.addSublayer(primary)
        self.auroraPrimaryLayer = primary

        let secondary = CAGradientLayer()
        secondary.colors = [
            UIColor.clear.cgColor,
            UIColor(rgb: 0x80FFDB).withAlphaComponent(0.30).cgColor,
            UIColor(rgb: 0x7400B8).withAlphaComponent(0.28).cgColor,
            UIColor.clear.cgColor
        ]
        secondary.locations = [0.0, 0.38, 0.72, 1.0]
        secondary.startPoint = CGPoint(x: 1.0, y: 0.0)
        secondary.endPoint = CGPoint(x: 0.0, y: 1.0)

        let waveEnd = CABasicAnimation(keyPath: "endPoint")
        waveEnd.fromValue = CGPoint(x: 0.0, y: 1.0)
        waveEnd.toValue = CGPoint(x: 0.35, y: 0.55)
        waveEnd.duration = 3.9
        waveEnd.autoreverses = true
        waveEnd.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        waveEnd.repeatCount = .infinity
        secondary.add(waveEnd, forKey: "auroraSecondaryWave")

        self.layer.addSublayer(secondary)
        self.auroraSecondaryLayer = secondary

        // Subtle shimmering stardust inside the aurora curtain
        let dustLayer = CAEmitterLayer()
        dustLayer.emitterShape = .rectangle
        let dust = CAEmitterCell()
        dust.contents = self.makeParticleImage(kind: "firefly", color: UIColor(rgb: 0xA8FFEB), size: 7.5, softBlur: true)
        dust.birthRate = 5.0
        dust.lifetime = 4.5
        dust.velocity = 8.0
        dust.velocityRange = 6.0
        dust.emissionRange = .pi * 2.0
        dust.scale = 0.55
        dust.scaleRange = 0.30
        dust.alphaSpeed = -0.20
        dustLayer.emitterCells = [dust]
        self.layer.addSublayer(dustLayer)
        self.foregroundEmitter = dustLayer
    }

    private func setupFireflies() {
        let bgLayer = CAEmitterLayer()
        bgLayer.emitterShape = .rectangle
        let bgBokeh = CAEmitterCell()
        bgBokeh.contents = self.makeParticleImage(kind: "firefly", color: UIColor(rgb: 0xFFB703), size: 16.0, softBlur: true)
        bgBokeh.birthRate = 5.0
        bgBokeh.lifetime = 6.0
        bgBokeh.lifetimeRange = 2.0
        bgBokeh.velocity = 10.0
        bgBokeh.velocityRange = 8.0
        bgBokeh.yAcceleration = -3.5
        bgBokeh.emissionRange = .pi * 2.0
        bgBokeh.scale = 0.85
        bgBokeh.scaleRange = 0.45
        bgBokeh.alphaRange = 0.35
        bgBokeh.alphaSpeed = -0.14
        bgLayer.emitterCells = [bgBokeh]
        self.layer.addSublayer(bgLayer)
        self.backgroundEmitter = bgLayer

        let fgLayer = CAEmitterLayer()
        fgLayer.emitterShape = .rectangle
        let fgGlow = CAEmitterCell()
        fgGlow.contents = self.makeParticleImage(kind: "firefly", color: UIColor(rgb: 0xFFE169), size: 11.5, softBlur: false)
        fgGlow.birthRate = 7.5
        fgGlow.lifetime = 4.6
        fgGlow.lifetimeRange = 1.6
        fgGlow.velocity = 16.0
        fgGlow.velocityRange = 10.0
        fgGlow.yAcceleration = -5.0
        fgGlow.xAcceleration = 3.0
        fgGlow.emissionRange = .pi * 2.0
        fgGlow.scale = 0.65
        fgGlow.scaleRange = 0.35
        fgGlow.alphaRange = 0.30
        fgGlow.alphaSpeed = -0.20
        fgLayer.emitterCells = [fgGlow]
        self.layer.addSublayer(fgLayer)
        self.foregroundEmitter = fgLayer
    }

    private func setupNeonWave() {
        let g = CAGradientLayer()
        g.colors = [
            UIColor(rgb: 0x00F5FF).withAlphaComponent(0.36).cgColor,
            UIColor(rgb: 0xFF00D4).withAlphaComponent(0.30).cgColor,
            UIColor(rgb: 0x7A1FFF).withAlphaComponent(0.36).cgColor
        ]
        g.startPoint = CGPoint(x: 0.0, y: 0.0)
        g.endPoint = CGPoint(x: 1.0, y: 1.0)
        let anim = CABasicAnimation(keyPath: "colors")
        anim.toValue = [
            UIColor(rgb: 0xFF007F).withAlphaComponent(0.36).cgColor,
            UIColor(rgb: 0x00F5FF).withAlphaComponent(0.32).cgColor,
            UIColor(rgb: 0xFFE600).withAlphaComponent(0.28).cgColor
        ]
        anim.duration = 2.8
        anim.autoreverses = true
        anim.repeatCount = .infinity
        g.add(anim, forKey: "neonShift")
        self.layer.addSublayer(g)
        self.neonGradient = g

        let sparkLayer = CAEmitterLayer()
        sparkLayer.emitterShape = .rectangle
        let spark = CAEmitterCell()
        spark.contents = self.makeParticleImage(kind: "firefly", color: UIColor(rgb: 0x00F5FF), size: 9.0, softBlur: false)
        spark.birthRate = 5.5
        spark.lifetime = 3.6
        spark.velocity = 18.0
        spark.velocityRange = 10.0
        spark.emissionRange = .pi * 2.0
        spark.scale = 0.55
        spark.scaleRange = 0.25
        spark.alphaSpeed = -0.24
        sparkLayer.emitterCells = [spark]
        self.layer.addSublayer(sparkLayer)
        self.foregroundEmitter = sparkLayer
    }

    private func setupLightning() {
        let backdrop = CALayer()
        backdrop.backgroundColor = UIColor(rgb: 0x64DFDF).withAlphaComponent(0.22).cgColor
        backdrop.opacity = 0.0
        self.layer.addSublayer(backdrop)
        self.boltFlashBackdrop = backdrop

        let glowShape = CAShapeLayer()
        glowShape.strokeColor = UIColor(rgb: 0x48CAE4).cgColor
        glowShape.fillColor = UIColor.clear.cgColor
        glowShape.lineWidth = 4.2
        glowShape.lineCap = .round
        glowShape.lineJoin = .round
        glowShape.shadowColor = UIColor(rgb: 0x00F5FF).cgColor
        glowShape.shadowRadius = 12.0
        glowShape.shadowOpacity = 1.0
        glowShape.shadowOffset = .zero
        glowShape.opacity = 0.0
        self.layer.addSublayer(glowShape)
        self.boltLayer = glowShape

        let coreShape = CAShapeLayer()
        coreShape.strokeColor = UIColor.white.cgColor
        coreShape.fillColor = UIColor.clear.cgColor
        coreShape.lineWidth = 1.6
        coreShape.lineCap = .round
        coreShape.lineJoin = .round
        coreShape.opacity = 0.0
        self.layer.addSublayer(coreShape)
        self.boltCoreLayer = coreShape

        self.boltTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.55, repeats: true) { [weak self] _ in
            self?.flashBolt()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.flashBolt()
        }
    }

    private func flashBolt() {
        guard let glowShape = self.boltLayer,
              let coreShape = self.boltCoreLayer,
              self.bounds.width > 40.0,
              self.bounds.height > 40.0 else {
            return
        }
        let path = UIBezierPath()
        var x = CGFloat.random(in: self.bounds.width * 0.16 ... self.bounds.width * 0.84)
        var y: CGFloat = 0.0
        path.move(to: CGPoint(x: x, y: y))
        let steps = 8
        let dy = self.bounds.height / CGFloat(steps)
        for step in 0 ..< steps {
            let nextX = max(10.0, min(self.bounds.width - 10.0, x + CGFloat.random(in: -30.0 ... 30.0)))
            let nextY = y + dy
            path.addLine(to: CGPoint(x: nextX, y: nextY))
            if step == 2 || step == 4 || (step == 3 && Bool.random()) {
                let branchDir: CGFloat = Bool.random() ? 1.0 : -1.0
                var bx = nextX
                var by = nextY
                for _ in 0 ..< 3 {
                    path.move(to: CGPoint(x: bx, y: by))
                    bx = max(6.0, min(self.bounds.width - 6.0, bx + branchDir * CGFloat.random(in: 12.0 ... 26.0)))
                    by += dy * CGFloat.random(in: 0.55 ... 0.85)
                    path.addLine(to: CGPoint(x: bx, y: by))
                }
                path.move(to: CGPoint(x: nextX, y: nextY))
            }
            x = nextX
            y = nextY
        }
        glowShape.path = path.cgPath
        coreShape.path = path.cgPath

        let flash = CAKeyframeAnimation(keyPath: "opacity")
        flash.values = [0.0, 1.0, 0.22, 0.96, 0.0]
        flash.keyTimes = [0.0, 0.10, 0.26, 0.42, 1.0]
        flash.duration = 0.46
        glowShape.add(flash, forKey: "boltGlowFlash")
        coreShape.add(flash, forKey: "boltCoreFlash")

        if let backdrop = self.boltFlashBackdrop {
            let skyFlash = CAKeyframeAnimation(keyPath: "opacity")
            skyFlash.values = [0.0, 0.85, 0.15, 0.65, 0.0]
            skyFlash.keyTimes = [0.0, 0.10, 0.26, 0.42, 1.0]
            skyFlash.duration = 0.48
            backdrop.add(skyFlash, forKey: "skyFlash")
        }
    }

    private func setupMatrix() {
        let glyphs = ["0", "1", "ｱ", "ｲ", "ｳ", "ｴ", "ｵ", "ｶ", "ｷ", "ｸ", "ｹ", "ｺ", "7", "9"]
        for i in 0 ..< 18 {
            let isForeground = (i % 2 == 0)
            let lbl = UILabel()
            lbl.font = UIFont.monospacedSystemFont(ofSize: isForeground ? 11.5 : 9.0, weight: isForeground ? .bold : .medium)
            lbl.textColor = isForeground
                ? UIColor(rgb: 0x38FF88).withAlphaComponent(0.78)
                : UIColor(rgb: 0x00B84C).withAlphaComponent(0.42)
            lbl.numberOfLines = 0
            let len = isForeground ? 7 : 5
            lbl.text = (0 ..< len).map { _ in glyphs.randomElement() ?? "1" }.joined(separator: "\n")
            lbl.sizeToFit()
            lbl.tag = i
            self.addSubview(lbl)
            self.matrixLabels.append(lbl)
        }
    }

    private func layoutEmitter(_ emitter: CAEmitterLayer) {
        emitter.frame = self.bounds
        let id = self.activeEffectId
        if id == "fireflies" || id == "aurora" || id == "neon" || id == "stars" {
            emitter.emitterPosition = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            emitter.emitterSize = CGSize(width: max(1.0, self.bounds.width), height: max(1.0, self.bounds.height))
        } else if id == "fire" {
            emitter.emitterPosition = CGPoint(x: self.bounds.midX, y: self.bounds.height + 4.0)
            emitter.emitterSize = CGSize(width: max(1.0, self.bounds.width), height: 2.0)
        } else {
            emitter.emitterPosition = CGPoint(x: self.bounds.midX, y: -8.0)
            emitter.emitterSize = CGSize(width: max(1.0, self.bounds.width * 1.1), height: 2.0)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let bg = self.backgroundEmitter {
            self.layoutEmitter(bg)
        }
        if let fg = self.foregroundEmitter {
            self.layoutEmitter(fg)
        }
        self.auroraPrimaryLayer?.frame = self.bounds.insetBy(dx: -20.0, dy: -20.0)
        self.auroraSecondaryLayer?.frame = self.bounds.insetBy(dx: -12.0, dy: -12.0)
        self.neonGradient?.frame = self.bounds
        self.boltFlashBackdrop?.frame = self.bounds
        self.boltLayer?.frame = self.bounds
        self.boltCoreLayer?.frame = self.bounds
        if !self.matrixLabels.isEmpty && self.bounds.width > 20.0 {
            let step = self.bounds.width / CGFloat(self.matrixLabels.count)
            for (idx, lbl) in self.matrixLabels.enumerated() {
                let x = CGFloat(idx) * step + 2.0
                lbl.frame = CGRect(x: x, y: -lbl.bounds.height, width: 16.0, height: lbl.bounds.height)
                if lbl.layer.animation(forKey: "fall") == nil {
                    let isFg = (idx % 2 == 0)
                    let anim = CABasicAnimation(keyPath: "position.y")
                    anim.fromValue = -lbl.bounds.height
                    anim.toValue = self.bounds.height + lbl.bounds.height
                    anim.duration = isFg ? Double.random(in: 2.0 ... 3.5) : Double.random(in: 3.4 ... 5.2)
                    anim.beginTime = CACurrentMediaTime() + Double.random(in: 0.0 ... 2.2)
                    anim.repeatCount = .infinity
                    lbl.layer.add(anim, forKey: "fall")
                }
            }
        }
    }
}

internal final class MTAvatarFrameRingView: UIView {
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
        guard let spec = MTDiscordProfileStore.avatarFrames.first(where: { $0.id == frameId }),
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

private enum MTBannerVerticalMode {
    case smartBlur
    case topCrop
    case centerCrop
}

private enum MTDiscordBannerProcessor {
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

    static func renderNormalizedBannerData(from image: UIImage, verticalMode: MTBannerVerticalMode) -> Data? {
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

private final class MTDiscordHeaderOverlay {
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
    private var effectView: MTDiscordProfileEffectView?
    private var avatarFrameView: MTAvatarFrameRingView?
    private var voiceBioButton: UIButton?
    private var statusPillView: UIVisualEffectView?
    private var statusPillLabel: UILabel?
    private var disposable: Disposable?

    private init(node: ASDisplayNode) {
        self.node = node
        self.disposable = (MTDiscordProfileStore.shared.revisionSignal
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.refresh()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    static func update(_ header: MTPeerInfoHeader) {
        if header.isSettings {
            MTDiscordProfileStore.shared.activeAccountPeerId = header.context.account.peerId
        }
        let resolvedPeerId: PeerId? = header.peer?.id ?? (header.isSettings ? header.context.account.peerId : nil)
        guard let peerId = resolvedPeerId else { return }

        let overlay: MTDiscordHeaderOverlay
        if let existing = objc_getAssociatedObject(header.node, &MTDiscordHeaderOverlay.assocKey) as? MTDiscordHeaderOverlay {
            overlay = existing
        } else {
            overlay = MTDiscordHeaderOverlay(node: header.node)
            objc_setAssociatedObject(header.node, &MTDiscordHeaderOverlay.assocKey, overlay, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let isNewPeer = overlay.peerId != peerId
        overlay.peerId = peerId
        overlay.lastWidth = header.width
        if let bg = header.backgroundContainerView {
            overlay.bannerContainer = bg
        }
        if header.isSettings || peerId == header.context.account.peerId {
            MTDiscordProfileStore.shared.activeAccountPeerId = header.context.account.peerId
            MTDiscordProfileStore.shared.syncOwnVisualProfileIfNeeded(for: peerId)
        } else if isNewPeer {
            MTDiscordProfileStore.shared.checkGlobalProfile(for: peerId)
        }
        overlay.refresh()
    }

    @objc private func voiceBioTapped() {
        guard let peerId = self.peerId,
              let profile = MTDiscordProfileStore.shared.profile(for: peerId) else {
            return
        }
        MTProfileMusicPlayer.shared.toggleVoiceBio(peerId: peerId, profile: profile) { [weak self] in
            self?.updateVoiceButtonAppearance(peerId: peerId)
        }
    }

    private func updateVoiceButtonAppearance(peerId: PeerId) {
        guard let btn = self.voiceBioButton else { return }
        let playing = MTProfileMusicPlayer.shared.isPlayingVoiceBio(peerId: peerId)
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
        let profile = MTDiscordProfileStore.shared.profile(for: peerId)

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
            self.statusPillView?.removeFromSuperview()
            self.statusPillView = nil
            self.statusPillLabel = nil
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
           let bannerUrl = MTDiscordProfileStore.shared.bannerFileURL(for: profile) {
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
                iv.image = MTDiscordBannerProcessor.loadHeaderDisplayImage(from: bannerUrl)
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
           let spec = MTDiscordProfileStore.nitroThemes.first(where: { $0.id == nitroId }),
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
            let ev: MTDiscordProfileEffectView
            if let existing = self.effectView {
                ev = existing
            } else {
                ev = MTDiscordProfileEffectView(frame: .zero)
                ev.clipsToBounds = true
                ev.alpha = 0.65
                self.effectView = ev
            }
            if let tv = self.nitroTintView, tv.superview === anchor {
                anchor.insertSubview(ev, aboveSubview: tv)
            } else if let bv = self.bannerImageView, bv.superview === anchor {
                anchor.insertSubview(ev, aboveSubview: bv)
            } else if ev.superview !== anchor {
                anchor.insertSubview(ev, at: 0)
            }
            ev.isHidden = shouldHideBanner
            if !shouldHideBanner {
                ev.frame = bannerRect
            }
            ev.configure(effectId: effectId)
        } else {
            self.effectView?.configure(effectId: "none")
            self.effectView?.removeFromSuperview()
            self.effectView = nil
        }

        // 3. Glowing Animated Avatar Frame, Voice Bio Button & Styled Custom Status Pill
        let frameId = profile?.avatarFrameId ?? "none"
        let hasFrame = frameId != "none" && !frameId.isEmpty
        let hasVoiceBio = !(profile?.voiceBioFileName.isEmpty ?? true) || !(profile?.voiceBioUrl.isEmpty ?? true)
        let customStatusText = profile?.customStatus.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fontSlug = profile?.fontSlug ?? ""
        let hasStatusPill = !customStatusText.isEmpty && !shouldHideBanner
        let avatarRect: CGRect? = (hasFrame || hasVoiceBio || hasStatusPill) ? self.locateRoundAvatarFrame(in: node.view, headerWidth: self.lastWidth) : nil
        if hasFrame, let avatarRect {
            let ring: MTAvatarFrameRingView
            if let existing = self.avatarFrameView {
                ring = existing
            } else {
                ring = MTAvatarFrameRingView(frame: .zero)
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

        if hasStatusPill, let avatarRect, visibleHeight > 120.0 {
            let pill: UIVisualEffectView
            let lbl: UILabel
            if let existingPill = self.statusPillView, let existingLbl = self.statusPillLabel {
                pill = existingPill
                lbl = existingLbl
            } else {
                let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
                pill = UIVisualEffectView(effect: blur)
                pill.isUserInteractionEnabled = false
                pill.clipsToBounds = true
                pill.layer.cornerRadius = 11.0
                pill.layer.cornerCurve = .continuous
                pill.layer.borderWidth = 0.8
                pill.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor

                lbl = UILabel()
                lbl.textColor = .white
                lbl.textAlignment = .center
                lbl.numberOfLines = 1
                lbl.lineBreakMode = .byTruncatingTail
                pill.contentView.addSubview(lbl)
                self.statusPillView = pill
                self.statusPillLabel = lbl
            }
            lbl.font = MTDiscordProfileStore.resolvedFont(slug: fontSlug, size: 11.5, fallbackWeight: .semibold)
            lbl.text = customStatusText
            let maxPillW = min(max(110.0, self.lastWidth - 64.0), 230.0)
            let fit = lbl.sizeThatFits(CGSize(width: maxPillW - 20.0, height: 22.0))
            let pillW = min(maxPillW, max(56.0, ceil(fit.width) + 20.0))
            let pillH: CGFloat = 22.0
            let pillY = max(6.0, avatarRect.minY - pillH - 5.0)
            if pillY + pillH <= avatarRect.minY + 4.0 && avatarRect.width >= 76.0 {
                if pill.superview !== node.view {
                    node.view.addSubview(pill)
                }
                pill.frame = CGRect(x: floor((self.lastWidth - pillW) / 2.0), y: pillY, width: pillW, height: pillH)
                lbl.frame = CGRect(x: 10.0, y: 0.0, width: pillW - 20.0, height: pillH)
                pill.isHidden = false
            } else {
                pill.isHidden = true
            }
        } else {
            self.statusPillView?.isHidden = true
        }
    }

    private func locateRoundAvatarFrame(in root: UIView, headerWidth: CGFloat) -> CGRect? {
        guard headerWidth > 100.0 else { return nil }
        let centerX = headerWidth / 2.0
        var best: CGRect?
        func scan(_ view: UIView, depth: Int) {
            if depth > 4 || view.isHidden || view.alpha < 0.25 { return }
            if view is MTDiscordProfileEffectView || view is MTAvatarFrameRingView || view === self.bannerImageView || view === self.nitroTintView || view === self.voiceBioButton || view === self.statusPillView { return }
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

enum MTMediaTokDiscordProfile {
    static func register() {
        MTPeerInfoHooks.hasHeaderBackground.register({ peerId in
            guard let profile = MTDiscordProfileStore.shared.profile(for: peerId) else {
                return false
            }
            if MTDiscordProfileStore.shared.bannerFileURL(for: profile) != nil {
                return true
            }
            let nitroId = profile.nitroThemeId
            return !nitroId.isEmpty && nitroId != "none"
        })

        MTPeerInfoHooks.headerDidLayout.register({ header in
            MTDiscordHeaderOverlay.update(header)
        }, order: 120)

        MTPeerInfoHooks.infoRows.register({ info in
            return MTMediaTokDiscordProfile.infoRows(info)
        }, order: 120)

        MTPeerInfoHooks.integrationCards.register({ info in
            return MTMediaTokDiscordProfile.integrationCards(info)
        }, order: 120)

        MTPeerInfoHooks.menuItems.register({ info in
            return MTMediaTokDiscordProfile.profileMenuItems(info)
        }, order: 70)
    }

    private static func infoRows(_ info: MTPeerInfoContext) -> [MTPeerInfoRow] {
        let peerId = info.peer.id
        MTDiscordProfileStore.shared.activeAccountPeerId = info.context.account.peerId
        weak let controller = info.controller
        MTDiscordProfileStore.shared.checkGlobalProfile(for: peerId) {
            controller?.requestLayout(transition: .immediate)
        }
        guard let profile = MTDiscordProfileStore.shared.profile(for: peerId) else {
            return []
        }

        var rows: [MTPeerInfoRow] = []
        let context = info.context

        // Infinite Playlist on Profile
        let playlist = profile.effectivePlaylist
        if !playlist.isEmpty {
            let isPlaying = MTProfileMusicPlayer.shared.isPlaying(peerId: peerId)
            let summary = MTProfileMusicPlayer.shared.currentTrackSummary(peerId: peerId, playlist: playlist)
            let label = playlist.count > 1 ? "Плейлист (\(summary.positionText))" : "Музыка профиля"
            let badgeText = isPlaying ? "Пауза" : (playlist.count > 1 ? "Плейлист" : "Слушать")
            rows.append(MTPeerInfoRow(
                id: "mediatok.discord.music",
                label: label,
                text: summary.title,
                rightLabel: badgeText,
                action: {
                    MTProfileMusicPlayer.shared.toggle(peerId: peerId, profile: profile) {
                        controller?.requestLayout(transition: .immediate)
                    }
                },
                longTapAction: {
                    MTMediaTokDiscordProfile.presentPlaylistControls(peerId: peerId, profile: profile, controller: controller, context: context)
                }
            ))
            if playlist.count > 1 {
                let shuffleState = MTProfileMusicPlayer.shared.shuffleEnabled ? "Шаффл ВКЛ" : "След. трек"
                rows.append(MTPeerInfoRow(
                    id: "mediatok.discord.music.next",
                    label: "Плеер (\(playlist.count) трек.)",
                    text: "Нажми — следующий трек · Зажми — выбор / шаффл",
                    rightLabel: shuffleState,
                    action: {
                        MTProfileMusicPlayer.shared.next(peerId: peerId, profile: profile) {
                            controller?.requestLayout(transition: .immediate)
                        }
                    },
                    longTapAction: {
                        MTMediaTokDiscordProfile.presentPlaylistControls(peerId: peerId, profile: profile, controller: controller, context: context)
                    }
                ))
            }
        }

        // Live Now-Playing Music Service (Last.fm / ListenBrainz for Spotify, Yandex, VK, Apple Music)
        if !profile.musicServiceUser.isEmpty,
           profile.musicServiceKind != "none",
           let liveMusic = MTConnectionResolvers.shared.liveMusicInfo(kind: profile.musicServiceKind, user: profile.musicServiceUser, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            rows.append(MTPeerInfoRow(
                id: "mediatok.discord.liveMusic",
                label: "Слушает сейчас",
                text: liveMusic.text,
                rightLabel: liveMusic.badge,
                action: {
                    UIApplication.shared.open(liveMusic.url, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    MTMediaTokDiscordProfile.copyAndToast(liveMusic.text, context: context, controller: controller)
                }
            ))
        }

        if !profile.customStatus.isEmpty {
            let status = profile.customStatus
            rows.append(MTPeerInfoRow(
                id: "mediatok.discord.status",
                label: "Статус MediaTok",
                text: status,
                longTapAction: {
                    MTMediaTokDiscordProfile.copyAndToast(status, context: context, controller: controller)
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
            rows.append(MTPeerInfoRow(
                id: "mediatok.discord.duo",
                label: "Пара MediaTok",
                text: duoTitle,
                rightLabel: "Профиль →",
                action: {
                    UIApplication.shared.open(duoUrl, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    MTMediaTokDiscordProfile.copyAndToast("@\(cleanDuo)", context: context, controller: controller)
                }
            ))
        }

        return rows
    }

    private static func integrationCards(_ info: MTPeerInfoContext) -> [MTPeerInfoIntegrationCard] {
        let peerId = info.peer.id
        MTDiscordProfileStore.shared.activeAccountPeerId = info.context.account.peerId
        weak let controller = info.controller
        guard let profile = MTDiscordProfileStore.shared.profile(for: peerId) else {
            return []
        }

        var cards: [MTPeerInfoIntegrationCard] = []
        let context = info.context

        if !profile.steamInput.isEmpty,
           let steam = MTConnectionResolvers.shared.steamResolved(for: profile.steamInput, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            cards.append(MTPeerInfoIntegrationCard(
                id: "steam",
                platform: "steam",
                username: steam.username,
                isVerified: steam.isVerified,
                memberSinceText: steam.memberSinceText,
                primaryStatBold: steam.primaryStatBold,
                primaryStatLabel: steam.primaryStatLabel,
                secondaryStatBold: steam.secondaryStatBold,
                secondaryStatLabel: steam.secondaryStatLabel,
                action: {
                    UIApplication.shared.open(steam.profileUrl, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    MTMediaTokDiscordProfile.copyAndToast(steam.profileUrl.absoluteString, context: context, controller: controller)
                }
            ))
        }

        if !profile.spotifyInput.isEmpty {
            let parts = profile.spotifyInput.split(separator: "|", maxSplits: 1).map(String.init)
            let displayName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackUrl = URL(string: "https://open.spotify.com/")!
            let rawUrlStr = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            var targetUrl = fallbackUrl
            if let parsed = URL(string: rawUrlStr),
               parsed.scheme?.lowercased() == "https",
               let host = parsed.host?.lowercased(),
               host == "open.spotify.com" || host == "spotify.com" || host.hasSuffix(".spotify.com"),
               parsed.user == nil,
               parsed.port == nil {
                targetUrl = parsed
            }
            cards.append(MTPeerInfoIntegrationCard(
                id: "spotify",
                platform: "spotify",
                username: displayName.isEmpty ? "Spotify" : displayName,
                isVerified: true,
                memberSinceText: "Spotify",
                action: {
                    UIApplication.shared.open(targetUrl, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    MTMediaTokDiscordProfile.copyAndToast(targetUrl.absoluteString, context: context, controller: controller)
                }
            ))
        }

        if !profile.robloxInput.isEmpty,
           let roblox = MTConnectionResolvers.shared.robloxResolved(for: profile.robloxInput, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            cards.append(MTPeerInfoIntegrationCard(
                id: "roblox",
                platform: "roblox",
                username: roblox.username,
                isVerified: roblox.isVerified,
                memberSinceText: roblox.memberSinceText,
                primaryStatBold: roblox.primaryStatBold,
                primaryStatLabel: roblox.primaryStatLabel,
                secondaryStatBold: roblox.secondaryStatBold,
                secondaryStatLabel: roblox.secondaryStatLabel,
                action: {
                    UIApplication.shared.open(roblox.profileUrl, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    MTMediaTokDiscordProfile.copyAndToast(roblox.profileUrl.absoluteString, context: context, controller: controller)
                }
            ))
        }

        if !profile.twitchInput.isEmpty,
           let twitch = MTConnectionResolvers.shared.twitchResolved(for: profile.twitchInput, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            cards.append(MTPeerInfoIntegrationCard(
                id: "twitch",
                platform: "twitch",
                username: twitch.username,
                isVerified: twitch.isVerified,
                memberSinceText: twitch.memberSinceText,
                primaryStatBold: twitch.primaryStatBold,
                primaryStatLabel: twitch.primaryStatLabel,
                secondaryStatBold: twitch.secondaryStatBold,
                secondaryStatLabel: twitch.secondaryStatLabel,
                action: {
                    UIApplication.shared.open(twitch.profileUrl, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    MTMediaTokDiscordProfile.copyAndToast(twitch.profileUrl.absoluteString, context: context, controller: controller)
                }
            ))
        }

        if !profile.githubInput.isEmpty,
           let gh = MTConnectionResolvers.shared.githubResolved(for: profile.githubInput, onUpdate: {
               controller?.requestLayout(transition: .immediate)
           }) {
            cards.append(MTPeerInfoIntegrationCard(
                id: "github",
                platform: "github",
                username: gh.username,
                isVerified: gh.isVerified,
                memberSinceText: gh.memberSinceText,
                primaryStatBold: gh.primaryStatBold,
                primaryStatLabel: gh.primaryStatLabel,
                secondaryStatBold: gh.secondaryStatBold,
                secondaryStatLabel: gh.secondaryStatLabel,
                action: {
                    UIApplication.shared.open(gh.profileUrl, options: [:], completionHandler: nil)
                },
                longTapAction: {
                    MTMediaTokDiscordProfile.copyAndToast(gh.profileUrl.absoluteString, context: context, controller: controller)
                }
            ))
        }

        let staticConnections: [(id: String, platform: String, raw: String, subtitle: String)] = [
            ("youtube", "youtube", profile.youtubeInput, "YouTube"),
            ("tiktok", "tiktok", profile.tiktokInput, "TikTok"),
            ("kick", "kick", profile.kickInput, "Kick"),
            ("discord", "discord", profile.discordTag, "Discord")
        ]
        for item in staticConnections where !item.raw.isEmpty {
            if let norm = MTMediaTokCoreLogic.normalizeConnection(platform: item.platform, raw: item.raw) {
                cards.append(MTPeerInfoIntegrationCard(
                    id: item.id,
                    platform: item.platform,
                    username: norm.handle,
                    isVerified: true,
                    memberSinceText: item.subtitle,
                    action: {
                        if item.platform == "discord" {
                            MTMediaTokDiscordProfile.copyAndToast(norm.handle, context: context, controller: controller)
                        } else {
                            UIApplication.shared.open(norm.url, options: [:], completionHandler: nil)
                        }
                    },
                    longTapAction: {
                        MTMediaTokDiscordProfile.copyAndToast(norm.handle, context: context, controller: controller)
                    }
                ))
            }
        }

        return cards
    }

    private static func presentPlaylistControls(peerId: PeerId, profile: MTDiscordProfileData, controller: ViewController?, context: AccountContext) {
        DispatchQueue.main.async {
            let playlist = profile.effectivePlaylist
            let summary = MTProfileMusicPlayer.shared.currentTrackSummary(peerId: peerId, playlist: playlist)
            let shufTitle = MTProfileMusicPlayer.shared.shuffleEnabled ? "Перемешивание: ВКЛ (выключить)" : "Включить перемешивание"
            mtPresentNativeActionSheet(
                context: context,
                from: controller,
                title: "Плейлист профиля (\(playlist.count)) — \(summary.title)",
                buttons: [
                    (title: "Следующий трек", isDestructive: false, action: {
                        MTProfileMusicPlayer.shared.next(peerId: peerId, profile: profile) {
                            controller?.requestLayout(transition: .immediate)
                        }
                    }),
                    (title: "Предыдущий трек", isDestructive: false, action: {
                        MTProfileMusicPlayer.shared.previous(peerId: peerId, profile: profile) {
                            controller?.requestLayout(transition: .immediate)
                        }
                    }),
                    (title: shufTitle, isDestructive: false, action: {
                        MTProfileMusicPlayer.shared.toggleShuffle()
                        controller?.requestLayout(transition: .immediate)
                    }),
                    (title: "Скопировать название", isDestructive: false, action: {
                        MTMediaTokDiscordProfile.copyAndToast(summary.title, context: context, controller: controller)
                    })
                ]
            )
        }
    }

    private static func profileMenuItems(_ info: MTPeerInfoContext) -> [ContextMenuItem] {
        if info.isSettings { return [] }
        let peerId = info.peer.id
        let isOwn = peerId == info.context.account.peerId
        weak let controller = info.controller
        let title = isOwn ? "Discord-профиль / Плейлист / Интеграции" : "Оформление профиля MediaTok"
        return [.action(ContextMenuActionItem(text: title, icon: { theme in
            return UIImage(systemName: "sparkles")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
        }, action: { contextController, _ in
            contextController?.dismiss(completion: nil)
            MTMediaTokDiscordProfile.presentEditor(context: info.context, peerId: peerId, isOwn: isOwn, onDone: {
                controller?.requestLayout(transition: .immediate)
            })
        }))]
    }

    static func presentOwnEditor(context: MTMenuContext) {
        MTDiscordProfileStore.shared.activeAccountPeerId = context.context.account.peerId
        let editor = mtMakeNativeDiscordProfileEditorController(
            context: context.context,
            peerId: context.context.account.peerId,
            isOwn: true,
            onDone: nil
        )
        context.push(editor)
    }

    static func presentEditor(context: AccountContext, peerId: PeerId, isOwn: Bool, onDone: (() -> Void)?) {
        DispatchQueue.main.async {
            let editor = mtMakeNativeDiscordProfileEditorController(
                context: context,
                peerId: peerId,
                isOwn: isOwn,
                onDone: onDone
            )
            mtPushNativeController(editor, context: context)
        }
    }

    private static func copyAndToast(_ text: String, context: AccountContext, controller: ViewController?) {
        UIPasteboard.general.string = text
        guard let controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(
            presentationData: presentationData,
            content: .copy(text: MTStrings.Appearance.Profile.copied),
            elevatedLayout: false,
            animateInAsReplacement: false,
            action: { _ in return false }
        ), in: .current)
    }
}

// MARK: - 100% Native Telegram ItemListController Discord Profile Studio & Font Picker

internal func mtMakeNativeFontPickerController(
    context: AccountContext,
    selectedSlug: String,
    onSelect: @escaping (String) -> Void
) -> ItemListController {
    let queryAtomic = Atomic<String>(value: "")
    let selectedAtomic = Atomic<String>(value: selectedSlug)
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    weak var controllerRef: ItemListController?

    let model = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let query = queryAtomic.with { $0 }.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let curSel = selectedAtomic.with { $0 }
        let filtered = query.isEmpty
            ? MTMediaTokFonts.all
            : MTMediaTokFonts.all.filter {
                $0.displayName.lowercased().contains(query)
                    || $0.category.lowercased().contains(query)
                    || $0.slug.lowercased().contains(query)
            }

        var screen = MTNativeScreenModel(title: "Шрифт карточки")
        screen.sections.append([
            MTNativeRow(id: "search", kind: .input(text: queryAtomic.with { $0 }, placeholder: "Поиск шрифта (Unbounded, Montserrat...)"))
        ])
        screen.text["search"] = { text in
            let _ = queryAtomic.swap(text)
            revision.set(Int.random(in: 1 ... Int.max))
        }

        let isSystem = curSel.isEmpty || curSel == "none"
        screen.sections.append([
            MTNativeRow(id: "h_sys", kind: .header("Стандартный")),
            MTNativeRow(id: "sys", kind: .check(title: "Системный (SF Pro)", subtitle: "Стандартный шрифт iOS", checked: isSystem))
        ])
        screen.tap["sys"] = {
            let _ = selectedAtomic.swap("")
            onSelect("")
            if let nav = controllerRef?.navigationController as? NavigationController {
                _ = nav.popViewController(animated: true)
            } else {
                controllerRef?.dismiss()
            }
        }

        var fontRows: [MTNativeRow] = [MTNativeRow(id: "h_fonts", kind: .header("Шрифты MediaTok (\(filtered.count))"))]
        for item in filtered {
            let rowId = "font_\(item.slug)"
            fontRows.append(MTNativeRow(
                id: rowId,
                kind: .check(title: item.displayName, subtitle: item.category, checked: curSel == item.slug)
            ))
            screen.tap[rowId] = {
                let _ = selectedAtomic.swap(item.slug)
                onSelect(item.slug)
                if let nav = controllerRef?.navigationController as? NavigationController {
                    _ = nav.popViewController(animated: true)
                } else {
                    controllerRef?.dismiss()
                }
            }
        }
        screen.sections.append(fontRows)
        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: model)
    controllerRef = controller
    return controller
}

private final class MTDiscordNativePickerBridge: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    static let shared = MTDiscordNativePickerBridge()

    private var onBannerImage: ((UIImage) -> Void)?
    private var onPickedDocs: (([URL]) -> Void)?

    func pickBanner(from presenter: UIViewController?, onImage: @escaping (UIImage) -> Void) {
        self.onBannerImage = onImage
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        if let presenter {
            MTModalPresenter.presentWhenReady(picker, from: presenter)
        } else {
            MTModalPresenter.presentOnTopmost(picker)
        }
    }

    func pickAudio(multiple: Bool, from presenter: UIViewController?, onURLs: @escaping ([URL]) -> Void) {
        self.onPickedDocs = onURLs
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio, .mp3, .mpeg4Audio], asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.delegate = self
        if let presenter {
            MTModalPresenter.presentWhenReady(picker, from: presenter)
        } else {
            MTModalPresenter.presentOnTopmost(picker)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        let callback = self.onBannerImage
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                if let url, let img = MTDiscordBannerProcessor.loadImage(from: url) {
                    callback?(img)
                    return
                }
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { obj, _ in
                        if let img = obj as? UIImage { callback?(img) }
                    }
                }
            }
        } else if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { obj, _ in
                if let img = obj as? UIImage { callback?(img) }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let cb = self.onPickedDocs
        cb?(urls)
    }
}

private struct MTDiscordEditorState {
    var draft: MTDiscordProfileData
    var playlist: [MTProfileTrack]
    var pendingBannerData: Data?
    var pendingVoiceData: Data?
    var pendingVoiceExt: String = "m4a"
}

private func mtMakeNativeDiscordProfileEditorController(
    context: AccountContext,
    peerId: PeerId,
    isOwn: Bool,
    onDone: (() -> Void)?
) -> ItemListController {
    let existing = MTDiscordProfileStore.shared.profile(for: peerId) ?? MTDiscordProfileData()
    let stateAtomic = Atomic<MTDiscordEditorState>(value: MTDiscordEditorState(
        draft: existing,
        playlist: existing.effectivePlaylist,
        pendingBannerData: nil,
        pendingVoiceData: nil,
        pendingVoiceExt: "m4a"
    ))
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    weak var controllerRef: ItemListController?

    let bump: () -> Void = {
        revision.set(Int.random(in: 1 ... Int.max))
    }

    let model = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let st = stateAtomic.with { $0 }
        let draft = st.draft
        var screen = MTNativeScreenModel(title: isOwn ? "Discord-профиль" : "Оформление профиля")
        screen.rightButton = (title: "Сохранить", enabled: true, action: {
            let cur = stateAtomic.with { $0 }
            var toSave = cur.draft
            toSave.customStatus = toSave.customStatus.trimmingCharacters(in: .whitespacesAndNewlines)
            toSave.musicServiceUser = toSave.musicServiceUser.trimmingCharacters(in: .whitespacesAndNewlines)
            toSave.duoUsername = toSave.duoUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            toSave.duoLabel = toSave.duoLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            toSave.musicPlaylist = cur.playlist
            if let bData = cur.pendingBannerData,
               let saved = MTDiscordProfileStore.shared.saveBannerData(bData, for: peerId) {
                toSave.bannerFileName = saved
                toSave.bannerUrl = ""
            }
            if let vData = cur.pendingVoiceData,
               let savedVoice = MTDiscordProfileStore.shared.saveVoiceBioData(vData, ext: cur.pendingVoiceExt, for: peerId) {
                toSave.voiceBioFileName = savedVoice
                toSave.voiceBioUrl = ""
            }
            toSave.updatedAt = Int64(Date().timeIntervalSince1970)
            MTDiscordProfileStore.shared.setProfile(toSave, for: peerId, publishGlobally: isOwn)
            onDone?()
            mtPresentNativeToast(context: context, from: controllerRef, text: "Профиль сохранён")
            if let nav = controllerRef?.navigationController as? NavigationController {
                _ = nav.popViewController(animated: true)
            } else {
                controllerRef?.dismiss()
            }
        })

        let hasBanner = st.pendingBannerData != nil || !draft.bannerFileName.isEmpty || !draft.bannerUrl.isEmpty
        let themeTitle = MTDiscordProfileStore.nitroThemes.first(where: { $0.id == draft.nitroThemeId })?.title ?? "Выкл."
        let frameTitle = MTDiscordProfileStore.avatarFrames.first(where: { $0.id == draft.avatarFrameId })?.title ?? "Выкл."
        let effectTitle = MTDiscordProfileStore.effects.first(where: { $0.id == draft.effectId })?.title ?? "Выкл."
        let fontTitle = MTDiscordProfileStore.fontDisplayName(for: draft.fontSlug)
        let musicSvcTitle = MTDiscordProfileStore.musicServices.first(where: { $0.id == draft.musicServiceKind })?.title ?? "Выкл."

        // Section 1: 4K Banner & Visuals
        var styleRows: [MTNativeRow] = [
            MTNativeRow(id: "h_visual", kind: .header("Баннер 4K и Стиль")),
            MTNativeRow(id: "pickBanner", kind: .disclosure(title: "Баннер профиля (4K)", label: hasBanner ? "Установлен" : "Выбрать", icon: nil, enabled: true)),
            MTNativeRow(id: "theme", kind: .disclosure(title: "Nitro-тема профиля", label: themeTitle, icon: nil, enabled: true)),
            MTNativeRow(id: "frame", kind: .disclosure(title: "Рамка аватарки", label: frameTitle, icon: nil, enabled: true)),
            MTNativeRow(id: "effect", kind: .disclosure(title: "Эффект профиля", label: effectTitle, icon: nil, enabled: true)),
            MTNativeRow(id: "font", kind: .disclosure(title: "Шрифт карточки", label: fontTitle, icon: nil, enabled: true))
        ]
        if hasBanner {
            styleRows.append(MTNativeRow(id: "clearBanner", kind: .action(title: "Удалить баннер", destructive: true, enabled: true)))
        }
        screen.sections.append(styleRows)

        // Section 2: Status & Duo
        screen.sections.append([
            MTNativeRow(id: "h_status", kind: .header("Статус и Парный профиль (Duo)")),
            MTNativeRow(id: "status", kind: .input(text: draft.customStatus, placeholder: "Свой статус под ником...")),
            MTNativeRow(id: "duoUser", kind: .input(text: draft.duoUsername, placeholder: "Партнёр Duo (@username)...")),
            MTNativeRow(id: "duoLabel", kind: .input(text: draft.duoLabel, placeholder: "Подпись Duo (например: Лучшие друзья)"))
        ])

        // Section 3: Audio & Playlist
        let hasVoice = st.pendingVoiceData != nil || !draft.voiceBioFileName.isEmpty || !draft.voiceBioUrl.isEmpty
        var audioRows: [MTNativeRow] = [
            MTNativeRow(id: "h_audio", kind: .header("Голосовое био и Плейлист")),
            MTNativeRow(id: "voiceFile", kind: .disclosure(title: "Голосовое био (аудиофайл)", label: hasVoice ? "Загружено" : "Выбрать", icon: nil, enabled: true)),
            MTNativeRow(id: "playlistAdd", kind: .disclosure(title: "Плейлист профиля (MP3/M4A)", label: st.playlist.isEmpty ? "Пусто" : "\(st.playlist.count) трек.", icon: nil, enabled: true)),
            MTNativeRow(id: "musicSvc", kind: .disclosure(title: "Музыкальный статус (Last.fm / др.)", label: musicSvcTitle, icon: nil, enabled: true)),
            MTNativeRow(id: "musicUser", kind: .input(text: draft.musicServiceUser, placeholder: "Ник в музыкальном сервисе..."))
        ]
        if hasVoice {
            audioRows.append(MTNativeRow(id: "clearVoice", kind: .action(title: "Удалить голосовое био", destructive: true, enabled: true)))
        }
        if !st.playlist.isEmpty {
            audioRows.append(MTNativeRow(id: "clearPlaylist", kind: .action(title: "Очистить плейлист", destructive: true, enabled: true)))
        }
        screen.sections.append(audioRows)

        // Section 4: Integrations
        screen.sections.append([
            MTNativeRow(id: "h_int", kind: .header("Интеграции (Steam, Spotify, Discord и др.)")),
            MTNativeRow(id: "int_steam", kind: .disclosure(title: "Steam", label: draft.steamInput.isEmpty ? "Не привязан" : "Привязан", icon: nil, enabled: true)),
            MTNativeRow(id: "int_spotify", kind: .disclosure(title: "Spotify", label: draft.spotifyInput.isEmpty ? "Не привязан" : "Привязан", icon: nil, enabled: true)),
            MTNativeRow(id: "int_discord", kind: .disclosure(title: "Discord", label: draft.discordTag.isEmpty ? "Не привязан" : draft.discordTag, icon: nil, enabled: true)),
            MTNativeRow(id: "int_youtube", kind: .disclosure(title: "YouTube", label: draft.youtubeInput.isEmpty ? "Не привязан" : "Привязан", icon: nil, enabled: true)),
            MTNativeRow(id: "int_twitch", kind: .disclosure(title: "Twitch", label: draft.twitchInput.isEmpty ? "Не привязан" : "Привязан", icon: nil, enabled: true)),
            MTNativeRow(id: "int_github", kind: .disclosure(title: "GitHub", label: draft.githubInput.isEmpty ? "Не привязан" : "Привязан", icon: nil, enabled: true)),
            MTNativeRow(id: "int_roblox", kind: .disclosure(title: "Roblox", label: draft.robloxInput.isEmpty ? "Не привязан" : "Привязан", icon: nil, enabled: true))
        ])

        // Section 5: Sync & Reset
        screen.sections.append([
            MTNativeRow(id: "sync", kind: .action(title: "Синхронизировать профиль из облака", destructive: false, enabled: true)),
            MTNativeRow(id: "resetAll", kind: .action(title: "Сбросить весь Discord-профиль", destructive: true, enabled: true))
        ])

        // Text bindings
        screen.text["status"] = { val in let _ = stateAtomic.modify { var n = $0; n.draft.customStatus = val; return n } }
        screen.text["duoUser"] = { val in let _ = stateAtomic.modify { var n = $0; n.draft.duoUsername = val; return n } }
        screen.text["duoLabel"] = { val in let _ = stateAtomic.modify { var n = $0; n.draft.duoLabel = val; return n } }
        screen.text["musicUser"] = { val in let _ = stateAtomic.modify { var n = $0; n.draft.musicServiceUser = val; return n } }

        // Actions
        screen.tap["pickBanner"] = {
            MTDiscordNativePickerBridge.shared.pickBanner(from: controllerRef) { rawImg in
                let normalized = MTDiscordBannerProcessor.normalizedOrientationImage(rawImg)
                guard let jpegData = MTDiscordBannerProcessor.renderNormalizedBannerData(from: normalized, verticalMode: .smartBlur) else { return }
                let isPortrait = MTDiscordBannerProcessor.isPortrait(normalized)
                DispatchQueue.main.async {
                    let _ = stateAtomic.modify { var n = $0; n.pendingBannerData = jpegData; n.draft.bannerUrl = ""; return n }
                    bump()
                    if isPortrait {
                        let applyMode: (MTBannerVerticalMode) -> Void = { mode in
                            DispatchQueue.global(qos: .userInitiated).async {
                                guard let updated = MTDiscordBannerProcessor.renderNormalizedBannerData(from: normalized, verticalMode: mode) else { return }
                                DispatchQueue.main.async {
                                    let _ = stateAtomic.modify { var n = $0; n.pendingBannerData = updated; n.draft.bannerUrl = ""; return n }
                                    bump()
                                }
                            }
                        }
                        mtPresentNativeActionSheet(context: context, from: controllerRef, title: "Вертикальный баннер — выберите кадрирование", buttons: [
                            (title: "Размытый фон + по центру", isDestructive: false, action: { applyMode(.smartBlur) }),
                            (title: "Обрезать верх (портрет)", isDestructive: false, action: { applyMode(.topCrop) }),
                            (title: "Обрезать по центру", isDestructive: false, action: { applyMode(.centerCrop) })
                        ])
                    }
                }
            }
        }
        screen.tap["clearBanner"] = {
            let _ = stateAtomic.modify { var n = $0; n.pendingBannerData = nil; n.draft.bannerFileName = ""; n.draft.bannerUrl = ""; return n }
            bump()
        }
        screen.tap["theme"] = {
            let btns = MTDiscordProfileStore.nitroThemes.map { t in
                (title: t.title, isDestructive: false, action: {
                    let _ = stateAtomic.modify { var n = $0; n.draft.nitroThemeId = t.id; return n }
                    bump()
                })
            }
            mtPresentNativeActionSheet(context: context, from: controllerRef, title: "Nitro-тема профиля", buttons: btns)
        }
        screen.tap["frame"] = {
            let btns = MTDiscordProfileStore.avatarFrames.map { f in
                (title: f.title, isDestructive: false, action: {
                    let _ = stateAtomic.modify { var n = $0; n.draft.avatarFrameId = f.id; return n }
                    bump()
                })
            }
            mtPresentNativeActionSheet(context: context, from: controllerRef, title: "Рамка аватарки", buttons: btns)
        }
        screen.tap["effect"] = {
            let btns = MTDiscordProfileStore.effects.map { e in
                (title: e.title, isDestructive: false, action: {
                    let _ = stateAtomic.modify { var n = $0; n.draft.effectId = e.id; return n }
                    bump()
                })
            }
            mtPresentNativeActionSheet(context: context, from: controllerRef, title: "Эффект профиля", buttons: btns)
        }
        screen.tap["font"] = {
            let slug = stateAtomic.with { $0.draft.fontSlug }
            let picker = mtMakeNativeFontPickerController(context: context, selectedSlug: slug) { chosen in
                let _ = stateAtomic.modify { var n = $0; n.draft.fontSlug = chosen; return n }
                bump()
            }
            mtPushNativeController(picker, context: context, from: controllerRef)
        }
        screen.tap["voiceFile"] = {
            MTDiscordNativePickerBridge.shared.pickAudio(multiple: false, from: controllerRef) { urls in
                guard let url = urls.first, let data = try? Data(contentsOf: url), data.count > 1024, data.count <= 5 * 1024 * 1024 else { return }
                let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
                DispatchQueue.main.async {
                    let _ = stateAtomic.modify { var n = $0; n.pendingVoiceData = data; n.pendingVoiceExt = ext; n.draft.voiceBioUrl = ""; return n }
                    bump()
                }
            }
        }
        screen.tap["clearVoice"] = {
            MTProfileMusicPlayer.shared.stopVoiceBio()
            let _ = stateAtomic.modify { var n = $0; n.pendingVoiceData = nil; n.draft.voiceBioFileName = ""; n.draft.voiceBioUrl = ""; return n }
            bump()
        }
        screen.tap["playlistAdd"] = {
            MTDiscordNativePickerBridge.shared.pickAudio(multiple: true, from: controllerRef) { urls in
                var added: [MTProfileTrack] = []
                for url in urls {
                    if let data = try? Data(contentsOf: url), !data.isEmpty {
                        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
                        let title = url.deletingPathExtension().lastPathComponent
                        if let track = MTDiscordProfileStore.shared.savePlaylistTrack(data: data, ext: ext, title: title, for: peerId) {
                            added.append(track)
                        }
                    }
                }
                guard !added.isEmpty else { return }
                DispatchQueue.main.async {
                    let _ = stateAtomic.modify { var n = $0; n.playlist.append(contentsOf: added); return n }
                    bump()
                }
            }
        }
        screen.tap["clearPlaylist"] = {
            MTProfileMusicPlayer.shared.stop()
            let _ = stateAtomic.modify { var n = $0; n.playlist = []; return n }
            bump()
        }
        screen.tap["musicSvc"] = {
            let btns = MTDiscordProfileStore.musicServices.map { s in
                (title: s.title, isDestructive: false, action: {
                    let _ = stateAtomic.modify { var n = $0; n.draft.musicServiceKind = s.id; return n }
                    bump()
                })
            }
            mtPresentNativeActionSheet(context: context, from: controllerRef, title: "Музыкальный сервис", buttons: btns)
        }

        let editIntegration: (MTIntegrationPlatform, String, String, @escaping (inout MTDiscordProfileData, String) -> Void) -> Void = { platform, currentVal, placeholder, applyVal in
            var btns: [(title: String, isDestructive: Bool, action: () -> Void)] = []
            btns.append((title: "Войти в аккаунт \(platform.title)", isDestructive: false, action: {
                guard let host = controllerRef else { return }
                MTIntegrationAuthCoordinator.shared.signIn(platform: platform, from: host) { res in
                    switch res {
                    case let .success(val):
                        let _ = stateAtomic.modify { var n = $0; applyVal(&n.draft, val); return n }
                        bump()
                        mtPresentNativeToast(context: context, from: controllerRef, text: "\(platform.title) подключён")
                    case let .failure(err):
                        let ns = err as NSError
                        if ns.code != -10 {
                            mtPresentNativeToast(context: context, from: controllerRef, text: err.localizedDescription)
                        }
                    }
                }
            }))
            btns.append((title: "Указать ник или ссылку вручную", isDestructive: false, action: {
                mtPresentNativePrompt(context: context, from: controllerRef, title: platform.title, subtitle: "Введите никнейм или ссылку:", value: currentVal, placeholder: placeholder) { entered in
                    let _ = stateAtomic.modify { var n = $0; applyVal(&n.draft, entered.trimmingCharacters(in: .whitespacesAndNewlines)); return n }
                    bump()
                }
            }))
            if !currentVal.isEmpty {
                btns.append((title: "Отключить \(platform.title)", isDestructive: true, action: {
                    let _ = stateAtomic.modify { var n = $0; applyVal(&n.draft, ""); return n }
                    bump()
                }))
            }
            mtPresentNativeActionSheet(context: context, from: controllerRef, title: platform.title, buttons: btns)
        }

        screen.tap["int_steam"] = { editIntegration(.steam, draft.steamInput, "https://steamcommunity.com/id/...", { $0.steamInput = $1 }) }
        screen.tap["int_spotify"] = { editIntegration(.spotify, draft.spotifyInput, "Имя|https://open.spotify.com/user/...", { $0.spotifyInput = $1 }) }
        screen.tap["int_discord"] = { editIntegration(.discord, draft.discordTag, "username", { $0.discordTag = $1 }) }
        screen.tap["int_youtube"] = { editIntegration(.youtube, draft.youtubeInput, "@channel", { $0.youtubeInput = $1 }) }
        screen.tap["int_twitch"] = { editIntegration(.twitch, draft.twitchInput, "twitch_login", { $0.twitchInput = $1 }) }
        screen.tap["int_github"] = { editIntegration(.github, draft.githubInput, "github_login", { $0.githubInput = $1 }) }
        screen.tap["int_roblox"] = { editIntegration(.roblox, draft.robloxInput, "roblox_user", { $0.robloxInput = $1 }) }

        screen.tap["sync"] = {
            MTDiscordProfileStore.shared.checkGlobalProfile(for: peerId, force: true) {
                let loaded = MTDiscordProfileStore.shared.profile(for: peerId) ?? MTDiscordProfileData()
                let _ = stateAtomic.modify { var n = $0; n.draft = loaded; n.playlist = loaded.effectivePlaylist; return n }
                bump()
                mtPresentNativeToast(context: context, from: controllerRef, text: "Профиль синхронизирован")
            }
        }
        screen.tap["resetAll"] = {
            MTProfileMusicPlayer.shared.stop()
            MTProfileMusicPlayer.shared.stopVoiceBio()
            let _ = stateAtomic.modify { _ in MTDiscordEditorState(draft: MTDiscordProfileData(), playlist: [], pendingBannerData: nil, pendingVoiceData: nil) }
            bump()
        }
        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: model)
    controllerRef = controller
    return controller
}
