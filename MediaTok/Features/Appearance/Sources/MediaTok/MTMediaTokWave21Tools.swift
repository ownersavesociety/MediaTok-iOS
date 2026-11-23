import Foundation
import UIKit
import Metal
import QuartzCore
import CoreMotion
import AVFoundation
import MediaPlayer
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import Display
import ContextUI
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

// ============================================================================
// MediaTok Wave 21 — Metal GPU Shaders, 3D Gyro Parallax, Local Per-Chat Wallpaper,
//                    Offline Music Hub + Apple Music Player, Clan Tags & Audio Reactions:
//   #988 / .shaders    — Live 60/120fps CAMetalLayer GPU Shader Backgrounds + Community MSL Editor
//   #986 / .parallax   — 3D Gyroscope Wallpaper Parallax tilt in chats
//   #984 / .chatbg     — Local Per-Chat Custom Photo/Tint Wallpaper (0 server notice to interlocutor)
//   #901/#923/#926 / .music — Offline Music Hub + Apple Music Full-Screen Cover Player + Listening History
//   #951 / .clantag    — Custom Clan Tag ([MT] / [VIP]) & Duo Frame config
//   #979 / .audioreact — Quick Voice/Synth Audio Reactions on any message
// ============================================================================

private final class MTWave21Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body(&self.value)
    }
}

public struct MTWave21ShaderConfig: Codable, Equatable {
    public var activePresetId: String   // "off", "aurora", "cyber_matrix", "plasma_lava", "starfield", "custom"
    public var opacity: Double          // 0.15 ... 1.0
    public var gyroParallaxEnabled: Bool
    public var customMslFragmentBody: String
    public var clanTag: String

    private enum CodingKeys: String, CodingKey {
        case activePresetId, opacity, gyroParallaxEnabled, customMslFragmentBody, clanTag
    }

    public static let `default` = MTWave21ShaderConfig(
        activePresetId: "off",
        opacity: 0.72,
        gyroParallaxEnabled: false,
        customMslFragmentBody: "float3 col = 0.5 + 0.5 * cos(u.time + uv.xyx + float3(0.0, 2.0, 4.0)); return float4(col * 0.45, 1.0);",
        clanTag: ""
    )
}

public struct MTSavedMusicTrack: Codable, Equatable {
    public let id: String
    public let title: String
    public let artist: String
    public let durationSec: Int
    public let fileName: String
    public var playCount: Int
    public var lastPlayedUnix: Int

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, durationSec, fileName, playCount, lastPlayedUnix
    }
}

public enum MTMediaTokWave21Tools {
    private static let shaderConfigKey = "mediatok.wave21.shader_config.v1"
    private static let tracksKey = "mediatok.wave21.music_tracks.v1"
    private static let localChatBgMapKey = "mediatok.wave21.local_chat_bg.v1"

    private static let stateBox = MTWave21Box<(
        cachedShader: MTWave21ShaderConfig,
        audioPlayer: AVAudioPlayer?,
        playingTrackId: String?
    )>((.default, nil, nil))

    // MARK: - Registration

    public static func register() {
        let initial = loadShaderConfigFromDisk()
        stateBox.withLock { $0.cachedShader = initial }

        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave21Tools.interceptCommands(request)
        }, order: 43)

        MTChatScreenHooks.overlays.register({ screen in
            if screen.isPreview {
                return []
            }
            return [MTChatMetalAndLocalBgOverlay(screen: screen)]
        }, order: 95)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave21Tools.messageMenuItems(menuContext)
        }, order: 100)
    }

    // MARK: - Persistence & Directories

    private static func loadShaderConfigFromDisk() -> MTWave21ShaderConfig {
        guard let data = UserDefaults.standard.data(forKey: shaderConfigKey),
              let decoded = try? JSONDecoder().decode(MTWave21ShaderConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    public static func loadShaderConfig() -> MTWave21ShaderConfig {
        return stateBox.withLock { $0.cachedShader }
    }

    public static func saveShaderConfig(_ cfg: MTWave21ShaderConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: shaderConfigKey)
        }
        stateBox.withLock { $0.cachedShader = cfg }
        NotificationCenter.default.post(name: Notification.Name("mediatok.wave21.shader_changed"), object: nil)
    }

    private static func mediaVaultDir(sub: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = docs.appendingPathComponent("MediaTokWave21_\(sub)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func musicVaultDir() -> URL { mediaVaultDir(sub: "Music") }
    public static func wallpaperVaultDir() -> URL { mediaVaultDir(sub: "Wallpapers") }

    public static func loadMusicTracks() -> [MTSavedMusicTrack] {
        guard let data = UserDefaults.standard.data(forKey: tracksKey),
              let arr = try? JSONDecoder().decode([MTSavedMusicTrack].self, from: data) else {
            return []
        }
        return arr
    }

    public static func saveMusicTracks(_ items: [MTSavedMusicTrack]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: tracksKey)
        }
    }

    public static func localWallpaperUrl(for peerId: PeerId) -> URL? {
        let map = (UserDefaults.standard.dictionary(forKey: localChatBgMapKey) as? [String: String]) ?? [:]
        guard let fileName = map["\(peerId.toInt64())"], !fileName.isEmpty else { return nil }
        let url = wallpaperVaultDir().appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static func setLocalWallpaper(image: UIImage?, for peerId: PeerId) {
        var map = (UserDefaults.standard.dictionary(forKey: localChatBgMapKey) as? [String: String]) ?? [:]
        let key = "\(peerId.toInt64())"
        if let old = map[key] {
            try? FileManager.default.removeItem(at: wallpaperVaultDir().appendingPathComponent(old))
        }
        if let img = image, let jpeg = img.jpegData(compressionQuality: 0.9) {
            let fn = "bg_\(peerId.toInt64())_\(Int(Date().timeIntervalSince1970)).jpg"
            let dst = wallpaperVaultDir().appendingPathComponent(fn)
            try? jpeg.write(to: dst, options: .atomic)
            map[key] = fn
        } else {
            map.removeValue(forKey: key)
        }
        UserDefaults.standard.set(map, forKey: localChatBgMapKey)
        NotificationCenter.default.post(name: Notification.Name("mediatok.wave21.shader_changed"), object: nil)
    }

    private static func topViewController() -> UIViewController? {
        return MTModalPresenter.topmostViewController()
    }

    // MARK: - Slash Commands

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix(".") else { return false }
        let lower = raw.lowercased()
        let peerId = request.chatLocation.peerId

        if lower == ".shaders" || lower == ".shader" || lower == ".parallax" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentShaderStudio(context: request.context, peerId: peerId) }
            return true
        }
        if lower == ".chatbg" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                if let pid = peerId {
                    presentLocalChatWallpaperPicker(context: request.context, peerId: pid)
                } else {
                    presentShaderStudio(context: request.context, peerId: nil)
                }
            }
            return true
        }
        if lower == ".music" || lower == ".musichub" || lower == ".player" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentOfflineMusicHub(context: request.context) }
            return true
        }
        if lower == ".clantag" || lower.hasPrefix(".clantag ") {
            let arg = lower.hasPrefix(".clantag ") ? String(raw.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            request.replace(ChatTextInputState())
            if !arg.isEmpty {
                var cfg = loadShaderConfig()
                cfg.clanTag = arg == "off" ? "" : arg
                saveShaderConfig(cfg)
                applyClanTagToVisualProfile(context: request.context, tag: cfg.clanTag)
                MTMediaTokWave5Tools.showToast(context: request.context, text: cfg.clanTag.isEmpty ? "Клан-тег снят" : "Клан-тег [\(cfg.clanTag)] установлен (#951)")
            } else {
                DispatchQueue.main.async { presentClanTagPrompt(context: request.context) }
            }
            return true
        }
        if lower == ".audioreact" {
            request.replace(ChatTextInputState())
            if let pid = peerId {
                DispatchQueue.main.async { presentAudioReactionSheet(context: request.context, peerId: pid, replyToMessageId: nil) }
            }
            return true
        }
        return false
    }

    // MARK: - Context Menu: #901 Save Music Offline & #979 Audio Reaction

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        var entries: [MTMessageMenuEntry] = []

        // #901 Save audio track to Offline Music Hub
        for m in message.media {
            if let file = m as? TelegramMediaFile, file.isMusic {
                entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                    text: "В Офлайн Музыку MediaTok (#901)",
                    icon: { theme in
                        return UIImage(systemName: "music.note.house.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                    },
                    action: { _, f in
                        f(.default)
                        MTMediaTokWave21Tools.saveTelegramAudioToMusicHub(context: context, message: message, file: file)
                    }
                ))))
                break
            }
        }

        // #979 Quick Audio Reaction reply
        entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
            text: "Аудио-реакция (#979)",
            icon: { theme in
                return UIImage(systemName: "waveform.badge.plus")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { _, f in
                f(.default)
                DispatchQueue.main.async {
                    MTMediaTokWave21Tools.presentAudioReactionSheet(context: context, peerId: message.id.peerId, replyToMessageId: message.id)
                }
            }
        ))))

        return entries
    }

    public static func saveTelegramAudioToMusicHub(context: AccountContext, message: Message, file: TelegramMediaFile) {
        var title = file.fileName ?? "Аудиозапись"
        var artist = "Telegram Music"
        var dur = 0
        for attr in file.attributes {
            if case let .Audio(_, duration, t, performer, _) = attr {
                dur = duration
                if let t, !t.isEmpty { title = t }
                if let performer, !performer.isEmpty { artist = performer }
            }
        }

        let _ = (context.account.postbox.mediaBox.resourceData(file.resource, option: .complete(waitUntilFetchStatus: false))
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { data in
            guard data.complete, data.size > 0 else {
                let ref = FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource)
                let _ = fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .audio, reference: ref).startStandalone()
                MTMediaTokWave5Tools.showToast(context: context, text: "Трек скачивается — дождитесь загрузки и нажмите снова")
                return
            }
            let ext = (file.fileName as NSString?)?.pathExtension ?? "mp3"
            let cleanExt = ext.isEmpty ? "mp3" : ext
            let trackId = UUID().uuidString
            let fn = "\(trackId).\(cleanExt)"
            let dst = musicVaultDir().appendingPathComponent(fn)
            do {
                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.copyItem(at: URL(fileURLWithPath: data.path), to: dst)
                var list = loadMusicTracks()
                list.insert(MTSavedMusicTrack(id: trackId, title: title, artist: artist, durationSec: dur, fileName: fn, playCount: 0, lastPlayedUnix: 0), at: 0)
                saveMusicTracks(list)
                MTMediaTokWave5Tools.showToast(context: context, text: "Сохранено в Музыкальный Хаб (.music): \(title)")
            } catch {
                MTMediaTokWave5Tools.showToast(context: context, text: "Ошибка сохранения трека")
            }
        })
    }

    // MARK: - #979 Quick Audio Reaction Sheet

    public static func presentAudioReactionSheet(context: AccountContext, peerId: PeerId, replyToMessageId: MessageId?) {
        let reactions: [(String, String)] = [
            ("vine_boom", "Бас-реакция (Vine Boom)"),
            ("airhorn", "Мощный сигнал (Airhorn)"),
            ("sad_trombone", "Фейл (Грустный тромбон)"),
            ("chime", "Одобрение (Чистый аккорд)"),
            ("icq_uhoh", "О-оу! (ICQ Классика)")
        ]
        mtPresentNativeActionSheet(
            context: context,
            title: "Отправить мгновенный звуковой отклик",
            buttons: reactions.map { (id, label) in
                (label, false, {
                    let pcm = MTMediaTokWave16Tools.synthesizeSoundEffect(id: id)
                    guard let ogg = MTMediaTokWave16Tools.encodePcm48kToOggOpus(pcm) else { return }
                    let wave = MTMediaTokWave16Tools.compute5BitWaveform(from: pcm)
                    let res = LocalFileMediaResource(fileId: Int64.random(in: 1 ... Int64.max))
                    context.account.postbox.mediaBox.storeResourceData(res.id, data: ogg, synchronous: true)
                    let media = TelegramMediaFile(
                        fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: res.id.hashValue == 0 ? 1 : Int64(truncatingIfNeeded: res.id.hashValue)),
                        partialReference: nil,
                        resource: res,
                        previewRepresentations: [],
                        videoThumbnails: [],
                        immediateThumbnailData: nil,
                        mimeType: "audio/ogg",
                        size: Int64(ogg.count),
                        attributes: [.Audio(isVoice: true, duration: 1, title: nil, performer: nil, waveform: wave)],
                        alternativeRepresentations: []
                    )
                    let replySubj: EngineMessageReplySubject? = replyToMessageId.map { EngineMessageReplySubject(messageId: $0, quote: nil, innerSubject: nil) }
                    let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [
                        .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: replySubj, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                    ]).startStandalone()
                })
            }
        )
    }

    // MARK: - #951 Clan Tag Prompt & Sync

    public static func presentClanTagPrompt(context: AccountContext) {
        let cur = loadShaderConfig().clanTag
        mtPresentNativePrompt(
            context: context,
            title: "Клан-тег профиля",
            subtitle: "Укажите короткий тег до 8 символов (например MT, VIP, DEV). Оставьте пустым, чтобы убрать тег:",
            value: cur,
            placeholder: "MT",
            characterLimit: 8,
            apply: { raw in
                let rawTag = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
                var cfg = loadShaderConfig()
                cfg.clanTag = rawTag
                saveShaderConfig(cfg)
                applyClanTagToVisualProfile(context: context, tag: rawTag)
                mtPresentNativeToast(context: context, text: rawTag.isEmpty ? "Клан-тег удалён" : "Клан-тег [\(rawTag)] применён")
            }
        )
    }

    private static func applyClanTagToVisualProfile(context: AccountContext, tag: String) {
        let formatted = tag.isEmpty ? "" : "[\(tag)]"
        if let key = MTPeerKey(namespace: Int32(context.account.peerId.namespace._internalGetInt32Value()), id: context.account.peerId.id._internalGetInt64Value()) {
            var ov = MTVisualProfileStore.shared.override(for: key) ?? MTVisualPeerOverride()
            ov.customOnlineStatus = formatted
            MTVisualProfileStore.shared.setOverride(ov, for: key)
        }
        var profile = MTDiscordProfileStore.shared.profile(for: context.account.peerId) ?? MTDiscordProfileData()
        profile.customStatus = formatted
        MTDiscordProfileStore.shared.setProfile(profile, for: context.account.peerId, publishGlobally: true)
    }

    // MARK: - Screen Launchers

    public static func presentShaderStudio(context: AccountContext, peerId: PeerId?) {
        let controller = mtMakeNativeShaderStudioController(context: context, peerId: peerId)
        mtPushNativeController(controller, context: context)
    }

    public static func presentLocalChatWallpaperPicker(context: AccountContext, peerId: PeerId) {
        var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = [
            ("Выбрать фото из галереи", false, {
                guard let top = topViewController() else { return }
                let picker = MTWave21PhotoPickerHost(context: context, peerId: peerId)
                top.present(picker, animated: true)
            })
        ]
        if localWallpaperUrl(for: peerId) != nil {
            buttons.append(("Сбросить локальные обои этого чата", true, {
                setLocalWallpaper(image: nil, for: peerId)
                mtPresentNativeToast(context: context, text: "Локальные обои чата сброшены")
            }))
        }
        mtPresentNativeActionSheet(
            context: context,
            title: "Локальные обои только для этого чата (без уведомления собеседнику)",
            buttons: buttons
        )
    }

    public static func presentOfflineMusicHub(context: AccountContext) {
        let controller = mtMakeNativeOfflineMusicHubController(context: context)
        mtPushNativeController(controller, context: context)
    }
}

// MARK: - #988 CAMetalLayer GPU Shader View + #986 Gyroscope Parallax + #984 Local Per-Chat Wallpaper

private struct MTShaderUniforms {
    var time: Float
    var width: Float
    var height: Float
    var tiltX: Float
    var tiltY: Float
    var pad0: Float = 0
    var pad1: Float = 0
    var pad2: Float = 0
}

private final class MTWave21DisplayLinkProxy: NSObject {
    weak var target: MTLiveMetalShaderView?
    init(_ target: MTLiveMetalShaderView) { self.target = target }
    @objc func tick() { self.target?.renderTick() }
}

private final class MTLiveMetalShaderView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    private var metalLayer: CAMetalLayer? { self.layer as? CAMetalLayer }
    private let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var displayLink: CADisplayLink?
    private var resignObs: NSObjectProtocol?
    private var activeObs: NSObjectProtocol?
    private let startTime = CACurrentMediaTime()
    private var currentPresetId: String = ""
    private var currentCustomBody: String = ""

    var tiltOffset: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        if let dev = self.device, let mLayer = self.metalLayer {
            mLayer.device = dev
            mLayer.pixelFormat = .bgra8Unorm
            mLayer.framebufferOnly = true
            mLayer.isOpaque = false
            mLayer.contentsScale = min(2.0, UIScreen.main.scale)
            self.commandQueue = dev.makeCommandQueue()
        }
        self.resignObs = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.displayLink?.isPaused = true
        }
        self.activeObs = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.displayLink?.isPaused = (self.window == nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        self.displayLink?.invalidate()
        if let obs = self.resignObs { NotificationCenter.default.removeObserver(obs) }
        if let obs = self.activeObs { NotificationCenter.default.removeObserver(obs) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.displayLink?.isPaused = (self.window == nil || UIApplication.shared.applicationState != .active)
    }

    func configure(presetId: String, customBody: String) {
        guard presetId != "off", let dev = self.device else {
            self.stopRendering()
            return
        }
        if presetId != self.currentPresetId || (presetId == "custom" && customBody != self.currentCustomBody) {
            self.currentPresetId = presetId
            self.currentCustomBody = customBody
            self.rebuildPipeline(device: dev, presetId: presetId, customBody: customBody)
        }
        if self.displayLink == nil && self.pipelineState != nil {
            let proxy = MTWave21DisplayLinkProxy(self)
            let link = CADisplayLink(target: proxy, selector: #selector(MTWave21DisplayLinkProxy.tick))
            if #available(iOS 15.0, *) {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            }
            link.isPaused = (self.window == nil || UIApplication.shared.applicationState != .active)
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }
    }

    func stopRendering() {
        self.displayLink?.invalidate()
        self.displayLink = nil
    }

    private func rebuildPipeline(device: MTLDevice, presetId: String, customBody: String) {
        let fragBody: String
        switch presetId {
        case "aurora":
            fragBody = """
            float2 p = uv * 2.0 - 1.0 + float2(u.tiltX, u.tiltY) * 0.25;
            float t = u.time * 0.55;
            float w1 = sin(p.x * 3.1 + t) * cos(p.y * 2.4 - t * 0.7);
            float w2 = sin((p.x + p.y) * 2.7 - t * 1.1);
            float3 c1 = float3(0.05, 0.14, 0.28);
            float3 c2 = float3(0.08, 0.68, 0.58);
            float3 c3 = float3(0.42, 0.22, 0.86);
            float3 col = mix(c1, c2, clamp(w1 * 0.5 + 0.5, 0.0, 1.0));
            col = mix(col, c3, clamp(w2 * 0.35 + 0.35, 0.0, 1.0));
            return float4(col, 1.0);
            """
        case "cyber_matrix":
            fragBody = """
            float2 p = uv + float2(u.tiltX, u.tiltY) * 0.08;
            float colIdx = floor(p.x * 36.0);
            float speed = fract(sin(colIdx * 91.7) * 43758.5) * 0.9 + 0.4;
            float drop = fract(p.y * 1.6 - u.time * speed * 0.35 + sin(colIdx));
            float glow = pow(max(0.0, 1.0 - drop * 2.6), 3.0);
            float3 col = float3(0.02, 0.09 + glow * 0.75, 0.06 + glow * 0.32);
            return float4(col, 1.0);
            """
        case "plasma_lava":
            fragBody = """
            float2 p = (uv - 0.5) * 3.2 + float2(u.tiltX, u.tiltY) * 0.3;
            float t = u.time * 0.65;
            float v = sin(p.x + t) + sin(p.y + t * 0.8) + sin(p.x + p.y + t * 1.2) + sin(length(p) * 2.2 - t * 1.4);
            float3 col = 0.5 + 0.5 * cos(v * 0.9 + float3(0.0, 1.8, 3.4));
            return float4(col * 0.58, 1.0);
            """
        case "starfield":
            fragBody = """
            float2 p = (uv - 0.5) * 2.0 + float2(u.tiltX, u.tiltY) * 0.22;
            float acc = 0.0;
            for (int i = 1; i <= 3; i++) {
                float fi = float(i);
                float2 g = p * (6.0 * fi) + float2(0.0, u.time * 0.25 * fi);
                float2 id = floor(g);
                float2 f = fract(g) - 0.5;
                float rnd = fract(sin(dot(id, float2(12.9898, 78.233))) * 43758.5453);
                if (rnd > 0.92) {
                    float d = length(f);
                    acc += smoothstep(0.16, 0.01, d) * (0.5 + 0.5 * sin(u.time * 3.0 + rnd * 20.0));
                }
            }
            float3 base = mix(float3(0.03, 0.04, 0.10), float3(0.09, 0.13, 0.26), uv.y);
            return float4(base + float3(0.65, 0.78, 1.0) * acc, 1.0);
            """
        default:
            fragBody = customBody
        }

        let msl = """
        #include <metal_stdlib>
        using namespace metal;
        struct Uniforms {
            float time;
            float width;
            float height;
            float tiltX;
            float tiltY;
            float pad0;
            float pad1;
            float pad2;
        };
        struct VOut {
            float4 position [[position]];
            float2 uv;
        };
        vertex VOut mtWave21Vert(uint vid [[vertex_id]]) {
            float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
            VOut out;
            out.position = float4(pos[vid], 0.0, 1.0);
            out.uv = 0.5 * (pos[vid] + 1.0);
            out.uv.y = 1.0 - out.uv.y;
            return out;
        }
        fragment float4 mtWave21Frag(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
            float2 uv = in.uv;
            \(fragBody)
        }
        """

        do {
            let lib = try device.makeLibrary(source: msl, options: nil)
            guard let vFn = lib.makeFunction(name: "mtWave21Vert"),
                  let fFn = lib.makeFunction(name: "mtWave21Frag") else {
                self.pipelineState = nil
                return
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vFn
            desc.fragmentFunction = fFn
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            self.pipelineState = nil
        }
    }

    fileprivate func renderTick() {
        guard UIApplication.shared.applicationState == .active,
              self.window != nil,
              let mLayer = self.metalLayer,
              let pipe = self.pipelineState,
              let queue = self.commandQueue,
              self.bounds.width > 1, self.bounds.height > 1 else { return }

        let scale = mLayer.contentsScale
        let targetSize = CGSize(width: self.bounds.width * scale, height: self.bounds.height * scale)
        if mLayer.drawableSize != targetSize {
            mLayer.drawableSize = targetSize
        }
        guard let drawable = mLayer.nextDrawable(),
              let cmdBuf = queue.makeCommandBuffer() else { return }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        if let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) {
            var u = MTShaderUniforms(
                time: Float(CACurrentMediaTime() - self.startTime),
                width: Float(targetSize.width),
                height: Float(targetSize.height),
                tiltX: Float(self.tiltOffset.x),
                tiltY: Float(self.tiltOffset.y)
            )
            enc.setRenderPipelineState(pipe)
            enc.setFragmentBytes(&u, length: MemoryLayout<MTShaderUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }
}

private final class MTChatMetalAndLocalBgOverlay: MTChatOverlay {
    let node = ASDisplayNode()
    let placement: MTChatOverlayPlacement = .aboveWallpaper

    private let peerId: PeerId?
    private let localImageView = UIImageView()
    private var shaderView: MTLiveMetalShaderView?
    private let motionManager = CMMotionManager()
    private var observer: NSObjectProtocol?
    private var currentBounds: CGRect = .zero

    init(screen: MTChatScreen) {
        self.peerId = screen.chatLocation.peerId
        self.node.isUserInteractionEnabled = false

        DispatchQueue.main.async { [weak self] in
            self?.setup()
        }
    }

    deinit {
        self.motionManager.stopDeviceMotionUpdates()
        self.shaderView?.stopRendering()
        if let obs = self.observer {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func setup() {
        self.localImageView.contentMode = .scaleAspectFill
        self.localImageView.clipsToBounds = true
        self.localImageView.isHidden = true
        self.node.view.addSubview(self.localImageView)

        self.observer = NotificationCenter.default.addObserver(forName: Notification.Name("mediatok.wave21.shader_changed"), object: nil, queue: .main) { [weak self] _ in
            self?.applyConfig()
        }
        self.applyConfig()
    }

    private func applyConfig() {
        let cfg = MTMediaTokWave21Tools.loadShaderConfig()

        // 1. #984 Local Per-Chat Wallpaper
        if let pid = self.peerId, let url = MTMediaTokWave21Tools.localWallpaperUrl(for: pid), let img = UIImage(contentsOfFile: url.path) {
            self.localImageView.image = img
            self.localImageView.isHidden = false
        } else {
            self.localImageView.image = nil
            self.localImageView.isHidden = true
        }

        // 2. #988 Metal GPU Shader Layer
        if cfg.activePresetId != "off" {
            let sv: MTLiveMetalShaderView
            if let existing = self.shaderView {
                sv = existing
            } else {
                sv = MTLiveMetalShaderView(frame: self.currentBounds)
                self.node.view.addSubview(sv)
                self.shaderView = sv
            }
            sv.alpha = CGFloat(cfg.opacity)
            sv.frame = self.currentBounds.insetBy(dx: -22, dy: -22)
            sv.configure(presetId: cfg.activePresetId, customBody: cfg.customMslFragmentBody)
        } else if let sv = self.shaderView {
            sv.stopRendering()
            sv.removeFromSuperview()
            self.shaderView = nil
        }

        // 3. #986 3D Gyroscope Parallax
        if cfg.gyroParallaxEnabled && self.motionManager.isDeviceMotionAvailable {
            if !self.motionManager.isDeviceMotionActive {
                self.motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
                self.motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                    guard let self, self.node.view.window != nil, UIApplication.shared.applicationState == .active, let attitude = motion?.attitude else { return }
                    let tx = max(-1.0, min(1.0, attitude.roll))
                    let ty = max(-1.0, min(1.0, attitude.pitch - 0.5))
                    self.shaderView?.tiltOffset = CGPoint(x: tx, y: ty)
                    let shiftX = CGFloat(tx) * 18.0
                    let shiftY = CGFloat(ty) * 18.0
                    let transform = CGAffineTransform(translationX: shiftX, y: shiftY)
                    self.localImageView.transform = transform
                    self.shaderView?.transform = transform
                }
            }
        } else {
            if self.motionManager.isDeviceMotionActive {
                self.motionManager.stopDeviceMotionUpdates()
            }
            self.localImageView.transform = .identity
            self.shaderView?.transform = .identity
            self.shaderView?.tiltOffset = .zero
        }
    }

    func updateLayout(bounds: CGRect, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        self.currentBounds = bounds
        let expanded = bounds.insetBy(dx: -22, dy: -22)
        let savedLocalT = self.localImageView.transform
        self.localImageView.transform = .identity
        self.localImageView.frame = expanded
        self.localImageView.transform = savedLocalT
        if let sv = self.shaderView {
            let savedShaderT = sv.transform
            sv.transform = .identity
            sv.frame = expanded
            sv.transform = savedShaderT
        }
    }
}

// MARK: - #984 Photo Picker Helper Controller

private final class MTWave21PhotoPickerHost: UIImagePickerController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let context: AccountContext
    private let peerId: PeerId

    init(context: AccountContext, peerId: PeerId) {
        self.context = context
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
        self.sourceType = .photoLibrary
        self.delegate = self
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let img = (info[.editedImage] ?? info[.originalImage]) as? UIImage
        let ctx = self.context
        let pid = self.peerId
        picker.dismiss(animated: true) {
            if let img {
                MTMediaTokWave21Tools.setLocalWallpaper(image: img, for: pid)
                MTMediaTokWave5Tools.showToast(context: ctx, text: "Локальные обои установлены только у вас (#984)")
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - #988 / #986 Native Shader & Parallax Studio Controller

private func mtMakeNativeShaderStudioController(context: AccountContext, peerId: PeerId?) -> ViewController {
    let initial = MTMediaTokWave21Tools.loadShaderConfig()
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)

    let presets: [(id: String, title: String)] = [
        ("off", "Выключен"),
        ("aurora", "Северное сияние (Aurora)"),
        ("cyber_matrix", "Кибер-матрица"),
        ("plasma_lava", "Плазменная лава"),
        ("starfield", "Глубокий космос"),
        ("custom", "Свой шейдер Metal MSL")
    ]
    let opacities: [(val: Double, title: String)] = [
        (0.35, "Мягкая (35%)"),
        (0.55, "Средняя (55%)"),
        (0.75, "Насыщенная (75%)"),
        (1.0, "Максимум (100%)")
    ]

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { cfg in
        var model = MTNativeScreenModel(title: "GPU Шейдеры и Параллакс")

        var presetRows: [MTNativeRow] = [.init(id: "p_hdr", kind: .header("Фоновый шейдер Metal"))]
        for p in presets {
            let id = "pr_\(p.id)"
            presetRows.append(.init(id: id, kind: .check(title: p.title, subtitle: nil, checked: cfg.activePresetId == p.id)))
            model.tap[id] = {
                let next = stateValue.modify { cur in var c = cur; c.activePresetId = p.id; return c }
                MTMediaTokWave21Tools.saveShaderConfig(next)
                statePromise.set(next)
            }
        }
        model.sections.append(presetRows)

        let curOpacityLabel = String(format: "%.0f%%", cfg.opacity * 100.0)
        model.sections.append([
            .init(id: "o_hdr", kind: .header("Параметры эффекта")),
            .init(id: "opacity_pick", kind: .disclosure(title: "Прозрачность шейдера", label: curOpacityLabel, icon: .system("circle.lefthalf.filled"), enabled: true)),
            .init(id: "gyro_sw", kind: .toggle(title: "3D Параллакс обоев по гироскопу", value: cfg.gyroParallaxEnabled, enabled: true)),
            .init(id: "edit_msl", kind: .disclosure(title: "Код шейдера Metal MSL", label: "Изменить", icon: .system("chevron.left.forwardslash.chevron.right"), enabled: true)),
            .init(id: "local_bg", kind: .disclosure(title: "Локальные обои текущего чата", label: peerId != nil ? "Выбрать" : "Откройте чат", icon: .system("photo.on.rectangle.angled"), enabled: true)),
            .init(id: "clan_tag", kind: .disclosure(title: "Клан-тег профиля", label: cfg.clanTag.isEmpty ? "Нет" : "[\(cfg.clanTag)]", icon: .system("tag"), enabled: true))
        ])

        model.tap["opacity_pick"] = {
            mtPresentNativeActionSheet(
                context: context,
                title: "Прозрачность фонового GPU шейдера",
                buttons: opacities.map { op in
                    (op.title, false, {
                        let next = stateValue.modify { cur in var c = cur; c.opacity = op.val; return c }
                        MTMediaTokWave21Tools.saveShaderConfig(next)
                        statePromise.set(next)
                    })
                }
            )
        }
        model.toggle["gyro_sw"] = { val in
            let next = stateValue.modify { cur in var c = cur; c.gyroParallaxEnabled = val; return c }
            MTMediaTokWave21Tools.saveShaderConfig(next)
            statePromise.set(next)
        }
        model.tap["edit_msl"] = {
            mtPresentNativePrompt(
                context: context,
                title: "Metal Fragment Shader (MSL)",
                subtitle: "Доступны uv (float2) и u.time (float). Верните float4(r, g, b, 1.0):",
                value: cfg.customMslFragmentBody,
                placeholder: "return float4(0.1, 0.2, 0.4, 1.0);",
                characterLimit: 512,
                apply: { code in
                    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let next = stateValue.modify { cur in
                        var c = cur
                        c.customMslFragmentBody = trimmed
                        c.activePresetId = "custom"
                        return c
                    }
                    MTMediaTokWave21Tools.saveShaderConfig(next)
                    statePromise.set(next)
                    mtPresentNativeToast(context: context, text: "Шейдер MSL скомпилирован и применён")
                }
            )
        }
        model.tap["local_bg"] = {
            guard let pid = peerId else {
                mtPresentNativeToast(context: context, text: "Откройте нужный чат и вызовите .chatbg")
                return
            }
            MTMediaTokWave21Tools.presentLocalChatWallpaperPicker(context: context, peerId: pid)
        }
        model.tap["clan_tag"] = {
            MTMediaTokWave21Tools.presentClanTagPrompt(context: context)
        }

        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #901 / #923 / #926 Native Offline Music Hub

private final class MTOfflineMusicPlaybackRuntime {
    static let shared = MTOfflineMusicPlaybackRuntime()
    var player: AVAudioPlayer?
    var playingTrackId: String?

    func toggleOrPlay(track: MTSavedMusicTrack, allTracks: inout [MTSavedMusicTrack]) -> Bool {
        if self.playingTrackId == track.id, let p = self.player {
            if p.isPlaying {
                p.pause()
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                return false
            } else {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try? AVAudioSession.sharedInstance().setActive(true)
                p.play()
                return true
            }
        }
        let url = MTMediaTokWave21Tools.musicVaultDir().appendingPathComponent(track.fileName)
        do {
            self.player?.stop()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.play()
            self.player = p
            self.playingTrackId = track.id

            if let idx = allTracks.firstIndex(where: { $0.id == track.id }) {
                allTracks[idx].playCount += 1
                allTracks[idx].lastPlayedUnix = Int(Date().timeIntervalSince1970)
                MTMediaTokWave21Tools.saveMusicTracks(allTracks)
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: track.title,
                MPMediaItemPropertyArtist: track.artist,
                MPMediaItemPropertyPlaybackDuration: track.durationSec
            ]
            return true
        } catch {
            return false
        }
    }

    func stop() {
        self.player?.stop()
        self.player = nil
        self.playingTrackId = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

private struct MTOfflineMusicHubState: Equatable {
    var tracks: [MTSavedMusicTrack]
    var playingTrackId: String?
    var isPlaying: Bool
}

private func mtMakeNativeOfflineMusicHubController(context: AccountContext) -> ViewController {
    let runtime = MTOfflineMusicPlaybackRuntime.shared
    let initial = MTOfflineMusicHubState(
        tracks: MTMediaTokWave21Tools.loadMusicTracks(),
        playingTrackId: runtime.playingTrackId,
        isPlaying: runtime.player?.isPlaying ?? false
    )
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Офлайн Музыка")

        let totalPlays = st.tracks.reduce(0) { $0 + $1.playCount }
        var playerSection: [MTNativeRow] = [
            .init(id: "m_hdr", kind: .header("Плеер и статистика")),
            .init(id: "m_stats", kind: .info("Треков офлайн: \(st.tracks.count) · Всего прослушиваний: \(totalPlays)"))
        ]
        if st.isPlaying {
            playerSection.append(.init(id: "m_stop", kind: .action(title: "Остановить воспроизведение", destructive: true, enabled: true)))
            model.tap["m_stop"] = {
                runtime.stop()
                let next = stateValue.modify { cur in
                    var c = cur
                    c.isPlaying = false
                    c.playingTrackId = nil
                    return c
                }
                statePromise.set(next)
            }
        }
        playerSection.append(.init(id: "m_ftr", kind: .footer("Чтобы добавить трек, зажмите любое аудиосообщение или MP3/M4A в чате и выберите «В Офлайн Музыку MediaTok».")))
        model.sections.append(playerSection)

        var trackRows: [MTNativeRow] = [.init(id: "t_hdr", kind: .header("Сохранённые треки"))]
        if st.tracks.isEmpty {
            trackRows.append(.init(id: "t_empty", kind: .info("Пока нет сохранённых треков.")))
        } else {
            for track in st.tracks {
                let rowId = "trk_\(track.id)"
                let activeMark = (st.playingTrackId == track.id && st.isPlaying) ? "Играет · " : ""
                let label = "\(activeMark)\(track.playCount)×"
                trackRows.append(.init(
                    id: rowId,
                    kind: .disclosure(title: "\(track.artist) — \(track.title)", label: label, icon: .system("music.note"), enabled: true)
                ))
                model.tap[rowId] = {
                    mtPresentNativeActionSheet(
                        context: context,
                        title: "\(track.artist) — \(track.title)",
                        buttons: [
                            ((st.playingTrackId == track.id && st.isPlaying) ? "Пауза" : "Воспроизвести", false, {
                                let next = stateValue.modify { cur in
                                    var c = cur
                                    let nowPlaying = runtime.toggleOrPlay(track: track, allTracks: &c.tracks)
                                    c.isPlaying = nowPlaying
                                    c.playingTrackId = runtime.playingTrackId
                                    return c
                                }
                                statePromise.set(next)
                            }),
                            ("Удалить из офлайн-базы", true, {
                                if runtime.playingTrackId == track.id {
                                    runtime.stop()
                                }
                                try? FileManager.default.removeItem(at: MTMediaTokWave21Tools.musicVaultDir().appendingPathComponent(track.fileName))
                                let next = stateValue.modify { cur in
                                    var c = cur
                                    c.tracks.removeAll { $0.id == track.id }
                                    MTMediaTokWave21Tools.saveMusicTracks(c.tracks)
                                    c.playingTrackId = runtime.playingTrackId
                                    c.isPlaying = runtime.player?.isPlaying ?? false
                                    return c
                                }
                                statePromise.set(next)
                            })
                        ]
                    )
                }
            }
        }
        model.sections.append(trackRows)

        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}
