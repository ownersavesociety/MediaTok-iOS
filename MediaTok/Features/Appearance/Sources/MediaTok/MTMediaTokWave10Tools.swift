import Foundation
import UIKit
import AVFoundation
import Speech
import PhotosUI
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
import MTFeaturesShared
import OpusBinding

/// MediaTok Wave 10 (Roadmap Wave 4 — Chat Analytics, Voice Pro, Mini Apps, Sticker Maker, Fake Route Geo, Time Machine):
/// - #375 Voice Transcript Search with exact word timestamps (on-device Speech framework)
/// - #376 Quiet Voice Booster (+15 dB real-time AVAudioEngine EQ boost from any voice message)
/// - #380 Voicemod Preset Export / Import (JSON)
/// - #476 Chat Hourly Activity Graph (00–23 bar chart + top authors via Postbox)
/// - #477 Top Channel Posts by Reactions & Views (top 15 ranking)
/// - #451/#452/#453/#454/#455 Mini Apps Power Pack (multi-window, autoclicker config, block fullscreen/haptics, platform spoof, hidden DevTools)
/// - #456 Sticker Pack Constructor (512×512 PNG maker + direct @Stickers handoff)
/// - #485 Fake Geolocation with Live Route Simulation (`TelegramMediaMap`)
/// - #498 Channel Time Machine (jump & read posts from any selected date)
public enum MTMediaTokWave10Tools {
    private static let miniAppsBlockFullscreenKey = "mediatok.miniapps.block_fullscreen_haptics.v1"
    private static let miniAppsPlatformKey = "mediatok.miniapps.spoof_platform.v1"
    private static let miniAppsMultiWindowKey = "mediatok.miniapps.multi_window.v1"
    private static let miniAppsAutoclickMsKey = "mediatok.miniapps.autoclick_ms.v1"
    private static let miniAppsDevToolsKey = "mediatok.miniapps.devtools.v1"
    private static let voicePresetsKey = "mediatok.voicemod.presets.v1"

    private static var boostEngine: AVAudioEngine?
    private static var boostPlayerNode: AVAudioPlayerNode?
    private static var activeSpeechTask: SFSpeechRecognitionTask?

    // MARK: - #451–#455 Mini Apps Settings

    public static var isMiniAppsBlockFullscreenEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave10Tools.miniAppsBlockFullscreenKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave10Tools.miniAppsBlockFullscreenKey) }
    }

    public static var miniAppsSpoofPlatform: String {
        get { return UserDefaults.standard.string(forKey: MTMediaTokWave10Tools.miniAppsPlatformKey) ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave10Tools.miniAppsPlatformKey) }
    }

    public static var isMiniAppsMultiWindowEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave10Tools.miniAppsMultiWindowKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave10Tools.miniAppsMultiWindowKey) }
    }

    public static var miniAppsAutoclickIntervalMs: Int {
        get { return UserDefaults.standard.integer(forKey: MTMediaTokWave10Tools.miniAppsAutoclickMsKey) }
        set { UserDefaults.standard.set(max(0, min(5000, newValue)), forKey: MTMediaTokWave10Tools.miniAppsAutoclickMsKey) }
    }

    public static var isMiniAppsDevToolsEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave10Tools.miniAppsDevToolsKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave10Tools.miniAppsDevToolsKey) }
    }

    // MARK: - Registration

    public static func register() {
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave10Tools.interceptCommands(request)
        }, order: 32)

        MTChatScreenHooks.sendMenuItems.register({ sendContext in
            return MTMediaTokWave10Tools.sendMenuItems(sendContext)
        }, order: 82)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave10Tools.messageMenuItems(menuContext)
        }, order: 92)
    }

    // MARK: - Wave 4 Studio Hub

    public static func presentWave4Hub(context: AccountContext, peerId: PeerId? = nil) {
        var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
        if let peerId {
            buttons.append(("График активности чата (00–23)", false, {
                MTMediaTokWave10Tools.presentChatActivityGraph(context: context, peerId: peerId)
            }))
            buttons.append(("Топ постов по реакциям и просмотрам", false, {
                MTMediaTokWave10Tools.presentTopChannelPosts(context: context, peerId: peerId)
            }))
            buttons.append(("Машина времени (архив по дате)", false, {
                MTMediaTokWave10Tools.presentTimeMachine(context: context, peerId: peerId)
            }))
            buttons.append(("Фейк-геолокация с маршрутом", false, {
                MTMediaTokWave10Tools.presentFakeRouteGeo(context: context, peerId: peerId)
            }))
        }
        buttons.append(("Конструктор стикерпаков (512×512 PNG)", false, {
            MTMediaTokWave10Tools.presentStickerMaker(context: context)
        }))
        buttons.append(("Mini Apps Power Pack", false, {
            MTMediaTokWave10Tools.presentMiniAppsStudio(context: context)
        }))
        buttons.append(("Пресеты голоса DSP (Экспорт / Импорт)", false, {
            MTMediaTokWave10Tools.presentVoicemodPresetsSheet(context: context)
        }))
        mtPresentNativeActionSheet(context: context, title: "Аналитика, Голос и Mini Apps", buttons: buttons)
    }

    // MARK: - Launchers

    public static func presentChatActivityGraph(context: AccountContext, peerId: PeerId) {
        let controller = mtMakeNativeChatAnalyticsController(context: context, peerId: peerId, isTopPosts: false)
        mtPushNativeController(controller, context: context)
    }

    public static func presentTopChannelPosts(context: AccountContext, peerId: PeerId) {
        let controller = mtMakeNativeChatAnalyticsController(context: context, peerId: peerId, isTopPosts: true)
        mtPushNativeController(controller, context: context)
    }

    public static func presentTimeMachine(context: AccountContext, peerId: PeerId) {
        let controller = mtMakeNativeTimeMachineController(context: context, peerId: peerId)
        mtPushNativeController(controller, context: context)
    }

    public static func presentFakeRouteGeo(context: AccountContext, peerId: PeerId) {
        let controller = mtMakeNativeFakeRouteGeoController(context: context, peerId: peerId)
        mtPushNativeController(controller, context: context)
    }

    public static func presentStickerMaker(context: AccountContext) {
        DispatchQueue.main.async {
            let vc = MTStickerPackMakerViewController(context: context)
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .pageSheet
            MTMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    // MARK: - #451–#455 Mini Apps Power Pack

    public static func presentMiniAppsStudio(context: AccountContext) {
        let controller = mtMakeNativeMiniAppsStudioController(context: context)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #380 Voicemod Preset Export / Import

    public static func presentVoicemodPresetsSheet(context: AccountContext) {
        let presets = (UserDefaults.standard.dictionary(forKey: MTMediaTokWave10Tools.voicePresetsKey) as? [String: [String: Double]]) ?? [
            "Deep Bass": ["pitch": -4.0, "rate": 0.94, "gainDb": 6.0],
            "Anime High": ["pitch": 5.5, "rate": 1.08, "gainDb": 2.0],
            "Radio Studio": ["pitch": -1.0, "rate": 1.0, "gainDb": 10.0]
        ]
        let dspStatus = MTVoiceSettings.morphEnabled.value
            ? "ВКЛ (\(MTVoiceSettings.customName.value.isEmpty ? MTVoiceSettings.morphPreset.value : MTVoiceSettings.customName.value))"
            : "ВЫКЛ"

        mtPresentNativeActionSheet(
            context: context,
            title: "Пресеты голоса DSP · Сохранено: \(presets.count) · Текущий DSP: \(dspStatus)",
            buttons: [
                ("Применить пресет к движку голоса", false, {
                    let pickerButtons: [(String, Bool, () -> Void)] = presets.keys.sorted().map { name in
                        let vals = presets[name] ?? [:]
                        let pitch = vals["pitch"] ?? 0.0
                        let gain = vals["gainDb"] ?? 0.0
                        return ("\(name) (pitch \(String(format: "%.1f", pitch)), gain \(String(format: "%.0f", gain)) dB)", false, {
                            MTVoiceSettings.morphEnabled.set(true)
                            MTVoiceSettings.morphPreset.set("custom")
                            MTVoiceSettings.customName.set(name)
                            MTVoiceSettings.customReverb.set(0.0)
                            MTVoiceSettings.customDistortion.set(0.0)
                            MTVoiceSettings.customEcho.set(0.0)
                            MTVoiceSettings.customTimbre.set(0.0)
                            MTVoiceSettings.customBass.set(0.0)
                            MTVoiceSettings.customMid.set(0.0)
                            MTVoiceSettings.customTreble.set(0.0)
                            MTVoiceSettings.customRingMod.set(0.0)
                            MTVoiceSettings.customBitcrush.set(16.0)
                            MTVoiceSettings.customTelephone.set(false)
                            MTVoiceSettings.customCompression.set(0.0)
                            MTVoiceSettings.customBreathiness.set(0.0)
                            MTVoiceSettings.customChorus.set(0.0)
                            MTVoiceSettings.customFlanger.set(0.0)
                            MTVoiceSettings.customVibratoDepth.set(0.0)
                            MTVoiceSettings.customVibratoRate.set(5.0)
                            MTVoiceSettings.customWet.set(100.0)
                            MTVoiceSettings.customPitch.set(max(-12.0, min(12.0, pitch)))
                            MTVoiceSettings.customGain.set(max(-12.0, min(12.0, gain)))
                            if let reverb = vals["reverb"] {
                                MTVoiceSettings.customReverb.set(max(0.0, min(100.0, reverb)))
                            }
                            if let dist = vals["distortion"] {
                                MTVoiceSettings.customDistortion.set(max(0.0, min(100.0, dist)))
                            }
                            mtPresentNativeToast(context: context, text: "Пресет «\(name)» применён")
                        })
                    }
                    mtPresentNativeActionSheet(context: context, title: "Выберите пресет для голосовых и кружков", buttons: pickerButtons)
                }),
                ("Экспортировать пресеты (JSON)", false, {
                    if let data = try? JSONSerialization.data(withJSONObject: presets, options: [.prettyPrinted, .sortedKeys]),
                       let str = String(data: data, encoding: .utf8) {
                        UIPasteboard.general.string = str
                        let share = UIActivityViewController(activityItems: [str], applicationActivities: nil)
                        MTMediaTokWave8Tools.configurePopover(share)
                        MTMediaTokWave5Tools.presentOnRoot(share)
                    }
                }),
                ("Импортировать пресеты из буфера обмена", false, {
                    guard let raw = UIPasteboard.general.string,
                          let data = raw.data(using: .utf8),
                          let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Double]],
                          !parsed.isEmpty else {
                        mtPresentNativeToast(context: context, text: "В буфере обмена нет корректного JSON пресетов")
                        return
                    }
                    UserDefaults.standard.set(parsed, forKey: MTMediaTokWave10Tools.voicePresetsKey)
                    mtPresentNativeToast(context: context, text: "Импортировано пресетов: \(parsed.count)")
                })
            ]
        )
    }

    // MARK: - #376 Quiet Voice Booster (+15 dB) & #375 Timestamped Voice Search (Ogg/Opus Decoder)

    private static func decodeOpusOrAudioToPCMBuffer(path: String, startOffsetSeconds: Double = 0.0) -> AVAudioPCMBuffer? {
        let sampleRate: Double = 48000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }

        if let opusReader = OggOpusReader(path: path) {
            let initChannels = max(1, Int(opusReader.channelCount()))
            var samples: [Int16] = []
            samples.reserveCapacity(Int(sampleRate) * 30)
            let chunkCap = 5760 * max(2, initChannels)
            var chunk = [Int16](repeating: 0, count: chunkCap)
            let maxSamples = Int(sampleRate) * 300
            var holeRetries = 0
            while samples.count < maxSamples {
                let readCount: Int32 = chunk.withUnsafeMutableBytes { raw in
                    guard let base = raw.baseAddress else { return -1 }
                    return opusReader.read(base, bufSize: Int32(chunkCap))
                }
                if readCount == -3 {
                    holeRetries += 1
                    if holeRetries > 64 { break }
                    continue
                }
                if readCount <= 0 {
                    break
                }
                holeRetries = 0
                let curCh = max(1, Int(opusReader.channelCount()))
                let framesRead = min(Int(readCount), chunk.count / curCh)
                if curCh == 1 {
                    samples.append(contentsOf: chunk.prefix(framesRead))
                } else {
                    for f in 0 ..< framesRead {
                        var sum = 0
                        let baseIdx = f * curCh
                        for c in 0 ..< curCh {
                            sum += Int(chunk[baseIdx + c])
                        }
                        let avg = max(Int(Int16.min), min(Int(Int16.max), sum / curCh))
                        samples.append(Int16(avg))
                    }
                }
            }
            let skip = min(samples.count, max(0, Int(startOffsetSeconds * sampleRate)))
            let sliceCount = samples.count - skip
            guard sliceCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sliceCount)),
                  let channel = buffer.floatChannelData?[0] else {
                return nil
            }
            buffer.frameLength = AVAudioFrameCount(sliceCount)
            let scale: Float = 1.0 / 32768.0
            for i in 0 ..< sliceCount {
                channel[i] = Float(samples[skip + i]) * scale
            }
            return buffer
        }

        if let audioFile = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) {
            let startFrame = AVAudioFramePosition(max(0.0, startOffsetSeconds) * audioFile.processingFormat.sampleRate)
            guard startFrame < audioFile.length else {
                return nil
            }
            audioFile.framePosition = startFrame
            let maxFrames = AVAudioFramePosition(audioFile.processingFormat.sampleRate * 300.0)
            let available = max(0, min(maxFrames, audioFile.length - audioFile.framePosition))
            let remaining = AVAudioFrameCount(available)
            guard remaining > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: remaining),
                  (try? audioFile.read(into: buffer)) != nil,
                  buffer.frameLength > 0 else {
                return nil
            }
            return buffer
        }
        return nil
    }

    public static func playVoiceWith15dBBoost(context: AccountContext, resource: TelegramMediaResource, startOffsetSeconds: Double = 0.0) {
        MTMediaTokWave5Tools.showToast(context: context, text: startOffsetSeconds > 0.1 ? String(format: "Старт с %d:%02d (+15 dB)...", Int(startOffsetSeconds) / 60, Int(startOffsetSeconds) % 60) : "Подготовка усиления ГС (+15 dB)...")
        let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
            |> take(1)
            |> deliverOnMainQueue).startStandalone(next: { data in
                guard data.complete else {
                    MTMediaTokWave5Tools.showToast(context: context, text: "Сначала нажми воспроизвести ГС, чтобы оно загрузилось")
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let pcmBuffer = MTMediaTokWave10Tools.decodeOpusOrAudioToPCMBuffer(path: data.path, startOffsetSeconds: startOffsetSeconds) else {
                        DispatchQueue.main.async {
                            MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось декодировать аудиофайл ГС")
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        do {
                            MTMediaTokWave10Tools.boostPlayerNode?.stop()
                            MTMediaTokWave10Tools.boostEngine?.stop()

                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                            try AVAudioSession.sharedInstance().setActive(true)

                            let engine = AVAudioEngine()
                            let player = AVAudioPlayerNode()
                            let eq = AVAudioUnitEQ(numberOfBands: 1)
                            eq.globalGain = 15.0
                            let band = eq.bands[0]
                            band.filterType = .parametric
                            band.frequency = 1400.0
                            band.bandwidth = 1.2
                            band.gain = 6.0
                            band.bypass = false

                            engine.attach(player)
                            engine.attach(eq)
                            engine.connect(player, to: eq, format: pcmBuffer.format)
                            engine.connect(eq, to: engine.mainMixerNode, format: pcmBuffer.format)
                            try engine.start()

                            MTMediaTokWave10Tools.boostEngine = engine
                            MTMediaTokWave10Tools.boostPlayerNode = player

                            player.scheduleBuffer(pcmBuffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak engine, weak player] _ in
                                DispatchQueue.main.async {
                                    guard let engine, let player,
                                          MTMediaTokWave10Tools.boostEngine === engine,
                                          MTMediaTokWave10Tools.boostPlayerNode === player else {
                                        return
                                    }
                                    player.stop()
                                    engine.stop()
                                    MTMediaTokWave10Tools.boostPlayerNode = nil
                                    MTMediaTokWave10Tools.boostEngine = nil
                                    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                                }
                            }
                            player.play()
                            MTMediaTokWave5Tools.showToast(context: context, text: "Воспроизведение ГС (+15 dB)")
                        } catch {
                            MTMediaTokWave5Tools.showToast(context: context, text: "Ошибка аудиодвижка: \(error.localizedDescription)")
                        }
                    }
                }
            })
    }

    private static func transcribeVoiceWithTimestamps(context: AccountContext, resource: TelegramMediaResource) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    MTMediaTokWave5Tools.showToast(context: context, text: "Разреши доступ к распознаванию речи в Настройках iOS")
                    return
                }
                MTMediaTokWave5Tools.showToast(context: context, text: "Декодирую Ogg/Opus и расшифровываю ГС...")
                let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
                    |> take(1)
                    |> deliverOnMainQueue).startStandalone(next: { data in
                        guard data.complete else {
                            MTMediaTokWave5Tools.showToast(context: context, text: "Сначала загрузи ГС")
                            return
                        }
                        DispatchQueue.global(qos: .userInitiated).async {
                            guard let pcmBuffer = MTMediaTokWave10Tools.decodeOpusOrAudioToPCMBuffer(path: data.path) else {
                                DispatchQueue.main.async {
                                    MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось декодировать ГС (Ogg/Opus)")
                                }
                                return
                            }
                            DispatchQueue.main.async {
                                MTMediaTokWave10Tools.activeSpeechTask?.cancel()
                                MTMediaTokWave10Tools.activeSpeechTask = nil
                                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")) ?? SFSpeechRecognizer(),
                                      recognizer.isAvailable else {
                                    MTMediaTokWave5Tools.showToast(context: context, text: "Распознавание речи сейчас недоступно")
                                    return
                                }
                                let req = SFSpeechAudioBufferRecognitionRequest()
                                req.shouldReportPartialResults = false
                                req.append(pcmBuffer)
                                req.endAudio()
                                var createdTask: SFSpeechRecognitionTask?
                                createdTask = recognizer.recognitionTask(with: req) { result, error in
                                    DispatchQueue.main.async {
                                        guard let createdTask, MTMediaTokWave10Tools.activeSpeechTask === createdTask else {
                                            return
                                        }
                                        if let result, result.isFinal {
                                            MTMediaTokWave10Tools.activeSpeechTask = nil
                                            let items = result.bestTranscription.segments.map { MTVoiceWordSegment(timestamp: $0.timestamp, word: $0.substring) }
                                            let fullText = result.bestTranscription.formattedString
                                            let controller = mtMakeNativeVoiceTranscriptController(
                                                context: context,
                                                resource: resource,
                                                fullText: fullText,
                                                segments: items
                                            )
                                            mtPushNativeController(controller, context: context)
                                            return
                                        }
                                        if let error {
                                            MTMediaTokWave10Tools.activeSpeechTask = nil
                                            let nsErr = error as NSError
                                            if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSUserCancelledError {
                                                return
                                            }
                                            MTMediaTokWave5Tools.showToast(context: context, text: "Ошибка расшифровки: \(error.localizedDescription)")
                                        }
                                    }
                                }
                                MTMediaTokWave10Tools.activeSpeechTask = createdTask
                            }
                        }
                    })
            }
        }
    }

    // MARK: - Inline Commands & Menus

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let lower = raw.lowercased()

        if lower == ".graph" || lower == ".activity" {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            MTMediaTokWave10Tools.presentChatActivityGraph(context: request.context, peerId: peerId)
            return true
        }
        if lower == ".top" || lower == ".topposts" {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            MTMediaTokWave10Tools.presentTopChannelPosts(context: request.context, peerId: peerId)
            return true
        }
        if lower == ".timemachine" || lower == ".tm" {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            MTMediaTokWave10Tools.presentTimeMachine(context: request.context, peerId: peerId)
            return true
        }
        if lower == ".route" || lower == ".fakegeo" {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            MTMediaTokWave10Tools.presentFakeRouteGeo(context: request.context, peerId: peerId)
            return true
        }
        if lower == ".makesticker" {
            request.replace(ChatTextInputState())
            MTMediaTokWave10Tools.presentStickerMaker(context: request.context)
            return true
        }
        return false
    }

    private static func sendMenuItems(_ sendContext: MTSendMenuContext) -> [ContextMenuItem] {
        var entries: [ContextMenuItem] = []
        let ctx = sendContext.context
        let pid = sendContext.peerId
        let dismiss = sendContext.dismiss

        entries.append(.action(ContextMenuActionItem(
            text: "Аналитика / Топ постов / Машина времени",
            icon: { theme in
                return UIImage(systemName: "chart.bar.xaxis")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave10Tools.presentWave4Hub(context: ctx, peerId: pid)
            }
        )))

        entries.append(.action(ContextMenuActionItem(
            text: "Фейк-геолокация с маршрутом",
            icon: { theme in
                return UIImage(systemName: "location.north.line.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave10Tools.presentFakeRouteGeo(context: ctx, peerId: pid)
            }
        )))

        return entries
    }

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        var entries: [MTMessageMenuEntry] = []

        if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile, file.isVoice {
            let res = file.resource
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Усилить тихое ГС (+15 dB)",
                icon: { theme in
                    return UIImage(systemName: "speaker.wave.3.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave10Tools.playVoiceWith15dBBoost(context: context, resource: res)
                }
            ))))
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Расшифровать ГС с таймкодами",
                icon: { theme in
                    return UIImage(systemName: "waveform.and.magnifyingglass")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave10Tools.transcribeVoiceWithTimestamps(context: context, resource: res)
                }
            ))))
        }

        return entries
    }
}

// MARK: - #451–#455 Native Mini Apps Power Pack Controller

private struct MTMiniAppsStudioState: Equatable {
    var blockFullscreen: Bool
    var multiWindow: Bool
    var platform: String
    var autoclickMs: Int
    var devTools: Bool
}

private func mtMakeNativeMiniAppsStudioController(context: AccountContext) -> ViewController {
    let initial = MTMiniAppsStudioState(
        blockFullscreen: MTMediaTokWave10Tools.isMiniAppsBlockFullscreenEnabled,
        multiWindow: MTMediaTokWave10Tools.isMiniAppsMultiWindowEnabled,
        platform: MTMediaTokWave10Tools.miniAppsSpoofPlatform,
        autoclickMs: MTMediaTokWave10Tools.miniAppsAutoclickIntervalMs,
        devTools: MTMediaTokWave10Tools.isMiniAppsDevToolsEnabled
    )
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let platforms = ["default", "ios", "android", "tdesktop", "web"]

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Mini Apps")

        model.sections.append([
            .init(id: "m_hdr", kind: .header("Поведение и среда")),
            .init(id: "sw_fs", kind: .toggle(title: "Блокировать Fullscreen и вибрацию", value: st.blockFullscreen, enabled: true)),
            .init(id: "sw_mw", kind: .toggle(title: "Мульти-окна Mini Apps", value: st.multiWindow, enabled: true)),
            .init(id: "pick_plat", kind: .disclosure(title: "Подмена платформы", label: st.platform, icon: .system("laptopcomputer.and.iphone"), enabled: true)),
            .init(id: "pick_ac", kind: .disclosure(title: "Интервал автокликера", label: st.autoclickMs > 0 ? "\(st.autoclickMs) мс" : "Выкл", icon: .system("hand.tap"), enabled: true)),
            .init(id: "sw_dev", kind: .toggle(title: "Консоль разработчика Eruda", value: st.devTools, enabled: true))
        ])

        model.toggle["sw_fs"] = { val in
            MTMediaTokWave10Tools.isMiniAppsBlockFullscreenEnabled = val
            let next = stateValue.modify { var c = $0; c.blockFullscreen = val; return c }
            statePromise.set(next)
        }
        model.toggle["sw_mw"] = { val in
            MTMediaTokWave10Tools.isMiniAppsMultiWindowEnabled = val
            let next = stateValue.modify { var c = $0; c.multiWindow = val; return c }
            statePromise.set(next)
        }
        model.tap["pick_plat"] = {
            mtPresentNativeActionSheet(
                context: context,
                title: "Платформа, передаваемая в Telegram.WebApp.platform",
                buttons: platforms.map { p in
                    (p, false, {
                        MTMediaTokWave10Tools.miniAppsSpoofPlatform = p
                        let next = stateValue.modify { var c = $0; c.platform = p; return c }
                        statePromise.set(next)
                    })
                }
            )
        }
        model.tap["pick_ac"] = {
            mtPresentNativePrompt(
                context: context,
                title: "Автокликер Mini Apps",
                subtitle: "Интервал клика в миллисекундах (0 — выключить):",
                value: "\(st.autoclickMs)",
                placeholder: "120",
                characterLimit: 6,
                apply: { raw in
                    let ms = max(0, min(5000, Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0))
                    MTMediaTokWave10Tools.miniAppsAutoclickIntervalMs = ms
                    let next = stateValue.modify { var c = $0; c.autoclickMs = ms; return c }
                    statePromise.set(next)
                }
            )
        }
        model.toggle["sw_dev"] = { val in
            MTMediaTokWave10Tools.isMiniAppsDevToolsEnabled = val
            let next = stateValue.modify { var c = $0; c.devTools = val; return c }
            statePromise.set(next)
        }

        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #476 Hourly Activity Graph & #477 Top Channel Posts (Native)

private struct MTAnalyticsItem: Equatable {
    let id: String
    let title: String
    let label: String
}

private struct MTAnalyticsScreenState: Equatable {
    var rows: [MTAnalyticsItem] = []
    var loaded: Bool = false
}

private func mtMakeNativeChatAnalyticsController(context: AccountContext, peerId: PeerId, isTopPosts: Bool) -> ViewController {
    let statePromise = ValuePromise(MTAnalyticsScreenState(), ignoreRepeated: true)

    let _ = (context.account.postbox.transaction { transaction -> [MTAnalyticsItem] in
        var messages: [Message] = []
        transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 400) { msg in
            messages.append(msg)
            return messages.count < 400
        }
        if !isTopPosts {
            var byHour = [Int](repeating: 0, count: 24)
            var byAuthor: [String: Int] = [:]
            let cal = Calendar.current
            for m in messages {
                let h = cal.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(m.timestamp)))
                if h >= 0 && h < 24 {
                    byHour[h] += 1
                }
                let author = m.author?.debugDisplayTitle ?? "Участник"
                byAuthor[author, default: 0] += 1
            }
            let maxH = max(1, byHour.max() ?? 1)
            var out: [MTAnalyticsItem] = []
            out.append(MTAnalyticsItem(id: "summary", title: "Проанализировано сообщений", label: "\(messages.count)"))
            for h in 0 ..< 24 {
                let cnt = byHour[h]
                let bars = Int((Double(cnt) / Double(maxH) * 12.0).rounded())
                let barStr = String(repeating: "▮", count: max(cnt > 0 ? 1 : 0, bars))
                out.append(MTAnalyticsItem(id: "h_\(h)", title: String(format: "%02d:00  %@", h, barStr), label: "\(cnt)"))
            }
            for (idx, pair) in byAuthor.sorted(by: { $0.value > $1.value }).prefix(5).enumerated() {
                out.append(MTAnalyticsItem(id: "top_a_\(idx)", title: pair.key, label: "\(pair.value) сообщ."))
            }
            return out
        } else {
            var scored: [(id: Int32, score: Int, reactions: Int, views: Int, text: String)] = []
            for m in messages {
                var reactTotal = 0
                var viewTotal = 0
                for attr in m.attributes {
                    if let r = attr as? ReactionsMessageAttribute {
                        for item in r.reactions { reactTotal += Int(item.count) }
                    } else if let v = attr as? ViewCountMessageAttribute {
                        viewTotal = v.count
                    }
                }
                let score = reactTotal * 10 + viewTotal
                let preview = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = preview.isEmpty ? "[Медиа-пост #\(m.id.id)]" : String(preview.prefix(80))
                scored.append((m.id.id, score, reactTotal, viewTotal, label))
            }
            scored.sort { $0.score > $1.score }
            return scored.prefix(15).enumerated().map { idx, item in
                MTAnalyticsItem(
                    id: "post_\(item.id)",
                    title: "#\(idx + 1)  \(item.text)",
                    label: "Реакций: \(item.reactions) · Просмотров: \(item.views)"
                )
            }
        }
    } |> deliverOnMainQueue).startStandalone(next: { result in
        statePromise.set(MTAnalyticsScreenState(rows: result, loaded: true))
    })

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: isTopPosts ? "Топ публикаций" : "Активность чата")
        var sec: [MTNativeRow] = [.init(id: "hdr", kind: .header(isTopPosts ? "Рейтинг по реакциям и просмотрам" : "Почасовая статистика (00–23)"))]
        if !st.loaded {
            sec.append(.init(id: "loading", kind: .info("Анализирую историю сообщений...")))
        } else if st.rows.isEmpty {
            sec.append(.init(id: "empty", kind: .info("Нет локальных сообщений — пролистайте чат или канал.")))
        } else {
            for r in st.rows {
                sec.append(.init(id: r.id, kind: .info("\(r.title)\n\(r.label)")))
            }
        }
        model.sections.append(sec)
        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #498 Native Channel Time Machine

private struct MTTimeMachinePost: Equatable {
    let id: Int32
    let date: String
    let text: String
}

private struct MTTimeMachineState: Equatable {
    var dateQuery: String
    var posts: [MTTimeMachinePost] = []
    var loaded: Bool = false
}

private func mtMakeNativeTimeMachineController(context: AccountContext, peerId: PeerId) -> ViewController {
    let dfInput = DateFormatter()
    dfInput.dateFormat = "dd.MM.yyyy"
    let todayStr = dfInput.string(from: Date())

    let initial = MTTimeMachineState(dateQuery: todayStr)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)

    let loadAroundDate: (Date) -> Void = { date in
        let targetTs = Int32(date.timeIntervalSince1970)
        let _ = (context.account.postbox.transaction { transaction -> [MTTimeMachinePost] in
            var messages: [Message] = []
            transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 800) { m in
                messages.append(m)
                return messages.count < 800
            }
            let sorted = messages.sorted { abs($0.timestamp - targetTs) < abs($1.timestamp - targetTs) }
            let fmt = DateFormatter()
            fmt.dateFormat = "dd.MM.yyyy HH:mm"
            return sorted.prefix(25).map { m in
                let dStr = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(m.timestamp)))
                let body = m.text.isEmpty ? "[Медиа-сообщение #\(m.id.id)]" : String(m.text.prefix(180))
                return MTTimeMachinePost(id: m.id.id, date: dStr, text: body)
            }
        } |> deliverOnMainQueue).startStandalone(next: { list in
            let next = stateValue.modify { cur in
                var c = cur
                c.posts = list
                c.loaded = true
                return c
            }
            statePromise.set(next)
        })
    }

    DispatchQueue.main.async {
        loadAroundDate(Date())
    }

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Машина времени")

        model.sections.append([
            .init(id: "d_hdr", kind: .header("Переход к дате (ДД.ММ.ГГГГ)")),
            .init(id: "d_in", kind: .input(text: st.dateQuery, placeholder: "Например 01.09.2026")),
            .init(id: "d_go", kind: .action(title: "Показать публикации за эту дату", destructive: false, enabled: true))
        ])

        model.text["d_in"] = { val in
            let _ = stateValue.modify { var c = $0; c.dateQuery = val; return c }
        }
        model.tap["d_go"] = {
            let raw = stateValue.with { $0.dateQuery }.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = dfInput.date(from: raw) {
                loadAroundDate(parsed)
            } else {
                mtPresentNativeToast(context: context, text: "Введите дату в формате ДД.ММ.ГГГГ (например 15.05.2026)")
            }
        }

        var postRows: [MTNativeRow] = [.init(id: "p_hdr", kind: .header("Ближайшие публикации (\(st.posts.count))"))]
        if !st.loaded {
            postRows.append(.init(id: "p_load", kind: .info("Загружаю архив...")))
        } else if st.posts.isEmpty {
            postRows.append(.init(id: "p_empty", kind: .info("Архив пуст — пролистайте историю канала для кэширования.")))
        } else {
            for p in st.posts {
                postRows.append(.init(id: "tm_\(p.id)", kind: .info("\(p.date)\n\(p.text)")))
            }
        }
        model.sections.append(postRows)
        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #485 Native Fake Geolocation with Route Presets

private struct MTFakeRouteState: Equatable {
    var routeIdx: Int = 0
    var progressSteps: Int = 0 // 0..10 (0%..100%)
}

private func mtMakeNativeFakeRouteGeoController(context: AccountContext, peerId: PeerId) -> ViewController {
    let routes: [(startLat: Double, startLon: Double, endLat: Double, endLon: Double, title: String)] = [
        (55.7558, 37.6173, 55.7495, 37.5376, "Москва: Красная площадь → Москва-Сити"),
        (35.6595, 139.7004, 35.6895, 139.6917, "Токио: Сибуя → Синдзюку"),
        (40.7580, -73.9855, 40.7128, -74.0060, "Нью-Йорк: Таймс-Сквер → Уолл-Стрит"),
        (48.8584, 2.2945, 48.8606, 2.3376, "Париж: Эйфелева башня → Лувр")
    ]
    let statePromise = ValuePromise(MTFakeRouteState(), ignoreRepeated: true)
    let stateValue = Atomic(value: MTFakeRouteState())

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Фейк-геолокация")
        let r = routes[st.routeIdx]
        let progress = Double(st.progressSteps) / 10.0
        let lat = r.startLat + (r.endLat - r.startLat) * progress
        let lon = r.startLon + (r.endLon - r.startLon) * progress

        var routeRows: [MTNativeRow] = [.init(id: "r_hdr", kind: .header("Маршрут"))]
        for (idx, item) in routes.enumerated() {
            let id = "rt_\(idx)"
            routeRows.append(.init(id: id, kind: .check(title: item.title, subtitle: nil, checked: st.routeIdx == idx)))
            model.tap[id] = {
                let next = stateValue.modify { var c = $0; c.routeIdx = idx; c.progressSteps = 0; return c }
                statePromise.set(next)
            }
        }
        model.sections.append(routeRows)

        model.sections.append([
            .init(id: "p_hdr", kind: .header("Текущая точка на маршруте")),
            .init(id: "coords", kind: .info(String(format: "Прогресс маршрута: %d%%\nШирота: %.5f · Долгота: %.5f", st.progressSteps * 10, lat, lon))),
            .init(id: "step_fwd", kind: .action(title: "Сдвинуть точку вперёд по маршруту (+10%)", destructive: false, enabled: true)),
            .init(id: "send_geo", kind: .action(title: "Отправить эту геометку в чат", destructive: false, enabled: true)),
            .init(id: "custom_geo", kind: .disclosure(title: "Свои координаты вручную", label: "Lat, Lon", icon: .system("location"), enabled: true))
        ])

        model.tap["step_fwd"] = {
            let next = stateValue.modify { cur in
                var c = cur
                c.progressSteps = (c.progressSteps + 1) % 11
                return c
            }
            statePromise.set(next)
        }
        model.tap["send_geo"] = {
            let map = TelegramMediaMap(latitude: lat, longitude: lon, heading: nil, accuracyRadius: 12.0, venue: nil)
            let msg = EnqueueMessage.message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: map), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            _ = enqueueMessages(account: context.account, peerId: peerId, messages: [msg]).start()
            mtPresentNativeToast(context: context, text: "Геометка отправлена в чат")
        }
        model.tap["custom_geo"] = {
            mtPresentNativePrompt(
                context: context,
                title: "Произвольные координаты",
                subtitle: "Введите широту и долготу через запятую:",
                value: String(format: "%.5f, %.5f", lat, lon),
                placeholder: "55.75580, 37.61730",
                characterLimit: 48,
                apply: { raw in
                    let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    guard parts.count == 2, let cLat = Double(parts[0]), let cLon = Double(parts[1]),
                          (-90.0 ... 90.0).contains(cLat), (-180.0 ... 180.0).contains(cLon) else {
                        mtPresentNativeToast(context: context, text: "Укажите корректные Lat, Lon")
                        return
                    }
                    let map = TelegramMediaMap(latitude: cLat, longitude: cLon, heading: nil, accuracyRadius: 12.0, venue: nil)
                    let msg = EnqueueMessage.message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: map), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                    _ = enqueueMessages(account: context.account, peerId: peerId, messages: [msg]).start()
                    mtPresentNativeToast(context: context, text: "Геометка отправлена в чат")
                }
            )
        }

        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #456 Sticker Pack Constructor (`512×512 PNG` → `@Stickers`)

public typealias MTStickerMakerViewController = MTStickerPackMakerViewController

public final class MTStickerPackMakerViewController: UIViewController, PHPickerViewControllerDelegate, UITextFieldDelegate {
    private let context: AccountContext
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let imageView = UIImageView()
    private let captionField = UITextField()
    private let statusLabel = UILabel()
    private let sendToStickersBtn = UIButton(type: .system)
    private let sharePngBtn = UIButton(type: .system)

    private var sourceImage: UIImage?
    private var stickerPngURL: URL?
    private var isSendingToStickers = false
    private let resolveDisposable = MetaDisposable()

    public init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.resolveDisposable.dispose()
        NotificationCenter.default.removeObserver(self)
        if let oldUrl = self.stickerPngURL {
            try? FileManager.default.removeItem(at: oldUrl)
        }
    }

    public override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [self.scrollView]
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.isBeingPresented || self.navigationController?.isBeingPresented == true {
            self.view.endEditing(true)
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Конструктор стикеров"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.closeTapped))

        let bgTap = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboardTapped))
        bgTap.cancelsTouchesInView = false
        self.view.addGestureRecognizer(bgTap)

        self.scrollView.keyboardDismissMode = .interactive
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.scrollView)
        self.scrollView.addSubview(self.contentView)

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        self.imageView.layer.cornerRadius = 22
        self.imageView.clipsToBounds = true
        self.imageView.translatesAutoresizingMaskIntoConstraints = false

        self.captionField.attributedPlaceholder = NSAttributedString(
            string: "Текст на стикере (необязательно)...",
            attributes: [.foregroundColor: UIColor(white: 0.50, alpha: 1.0)]
        )
        self.captionField.textColor = .white
        self.captionField.font = .systemFont(ofSize: 15, weight: .medium)
        self.captionField.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        self.captionField.layer.cornerRadius = 12
        self.captionField.layer.borderWidth = 1.0
        self.captionField.layer.borderColor = UIColor(white: 1.0, alpha: 0.10).cgColor
        self.captionField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 44))
        self.captionField.leftViewMode = .always
        self.captionField.clearButtonMode = .whileEditing
        self.captionField.returnKeyType = .done
        self.captionField.delegate = self
        self.captionField.addTarget(self, action: #selector(self.captionEditingChanged), for: .editingChanged)
        self.captionField.translatesAutoresizingMaskIntoConstraints = false

        self.statusLabel.text = "Выбери фото — соберу готовый 512×512 PNG стикер с белой обводкой для @Stickers"
        self.statusLabel.textColor = UIColor(white: 0.72, alpha: 1.0)
        self.statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 2
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let symCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)

        let pickBtn = UIButton(type: .system)
        pickBtn.setImage(UIImage(systemName: "photo.on.rectangle.angled", withConfiguration: symCfg), for: .normal)
        pickBtn.tintColor = .white
        pickBtn.setTitle("  Выбрать фото", for: .normal)
        pickBtn.setTitleColor(.white, for: .normal)
        pickBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        pickBtn.backgroundColor = UIColor(white: 0.20, alpha: 1.0)
        pickBtn.layer.cornerRadius = 14
        pickBtn.addTarget(self, action: #selector(self.pickTapped), for: .touchUpInside)
        pickBtn.translatesAutoresizingMaskIntoConstraints = false

        self.sendToStickersBtn.setImage(UIImage(systemName: "paperplane.fill", withConfiguration: symCfg), for: .normal)
        self.sendToStickersBtn.tintColor = .white
        self.sendToStickersBtn.setTitle("  Отправить в @Stickers", for: .normal)
        self.sendToStickersBtn.setTitleColor(.white, for: .normal)
        self.sendToStickersBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        self.sendToStickersBtn.backgroundColor = UIColor(red: 0.16, green: 0.52, blue: 1.0, alpha: 1.0)
        self.sendToStickersBtn.layer.cornerRadius = 14
        self.sendToStickersBtn.addTarget(self, action: #selector(self.sendToStickersTapped), for: .touchUpInside)
        self.sendToStickersBtn.translatesAutoresizingMaskIntoConstraints = false

        self.sharePngBtn.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: symCfg), for: .normal)
        self.sharePngBtn.tintColor = .white
        self.sharePngBtn.setTitle("  Поделиться / Сохранить PNG", for: .normal)
        self.sharePngBtn.setTitleColor(.white, for: .normal)
        self.sharePngBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        self.sharePngBtn.backgroundColor = UIColor(white: 0.16, alpha: 1.0)
        self.sharePngBtn.layer.cornerRadius = 14
        self.sharePngBtn.addTarget(self, action: #selector(self.exportTapped), for: .touchUpInside)
        self.sharePngBtn.translatesAutoresizingMaskIntoConstraints = false

        self.contentView.addSubview(self.imageView)
        self.contentView.addSubview(self.captionField)
        self.contentView.addSubview(self.statusLabel)
        self.contentView.addSubview(pickBtn)
        self.contentView.addSubview(self.sendToStickersBtn)
        self.contentView.addSubview(self.sharePngBtn)

        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),

            self.contentView.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor),
            self.contentView.leadingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.leadingAnchor),
            self.contentView.trailingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.trailingAnchor),
            self.contentView.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor),
            self.contentView.widthAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.widthAnchor),

            self.imageView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 16),
            self.imageView.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.imageView.widthAnchor.constraint(equalToConstant: 240),
            self.imageView.heightAnchor.constraint(equalToConstant: 240),

            self.captionField.topAnchor.constraint(equalTo: self.imageView.bottomAnchor, constant: 14),
            self.captionField.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 20),
            self.captionField.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -20),
            self.captionField.heightAnchor.constraint(equalToConstant: 44),

            self.statusLabel.topAnchor.constraint(equalTo: self.captionField.bottomAnchor, constant: 12),
            self.statusLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 20),
            self.statusLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -20),

            pickBtn.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 14),
            pickBtn.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 20),
            pickBtn.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -20),
            pickBtn.heightAnchor.constraint(equalToConstant: 48),

            self.sendToStickersBtn.topAnchor.constraint(equalTo: pickBtn.bottomAnchor, constant: 10),
            self.sendToStickersBtn.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 20),
            self.sendToStickersBtn.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -20),
            self.sendToStickersBtn.heightAnchor.constraint(equalToConstant: 50),

            self.sharePngBtn.topAnchor.constraint(equalTo: self.sendToStickersBtn.bottomAnchor, constant: 10),
            self.sharePngBtn.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 20),
            self.sharePngBtn.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -20),
            self.sharePngBtn.heightAnchor.constraint(equalToConstant: 46),
            self.sharePngBtn.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -24)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let converted = self.view.convert(endFrame, from: nil)
        let overlap = max(0, self.view.bounds.maxY - converted.minY)
        self.scrollView.contentInset.bottom = overlap + 16
        self.scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        self.scrollView.contentInset.bottom = 0
        self.scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    @objc private func dismissKeyboardTapped() {
        self.view.endEditing(true)
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    @objc private func captionEditingChanged() {
        guard self.sourceImage != nil else { return }
        self.rebuildStickerImage()
    }

    private static func normalizedStickerSourceImage(_ img: UIImage) -> UIImage {
        if img.imageOrientation == .up {
            return img
        }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: img.size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: img.size))
        }
    }

    private func rebuildStickerImage() {
        guard let img = self.sourceImage else { return }
        let captionText = (self.captionField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let size = CGSize(width: 512, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1.0
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let insetRect = CGRect(x: 16, y: 16, width: 480, height: 480)
            let path = UIBezierPath(roundedRect: insetRect, cornerRadius: 96)
            ctx.cgContext.saveGState()
            path.addClip()
            let imgW = max(1.0, img.size.width)
            let imgH = max(1.0, img.size.height)
            let scale = max(insetRect.width / imgW, insetRect.height / imgH)
            let drawW = imgW * scale
            let drawH = imgH * scale
            img.draw(in: CGRect(x: insetRect.midX - drawW / 2.0, y: insetRect.midY - drawH / 2.0, width: drawW, height: drawH))
            ctx.cgContext.restoreGState()

            UIColor.white.setStroke()
            path.lineWidth = 14
            path.stroke()

            if !captionText.isEmpty {
                let maxBox = CGSize(width: 424, height: 180)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byWordWrapping

                var chosenFont = UIFont.systemFont(ofSize: 58, weight: .heavy)
                for candidate in stride(from: CGFloat(58), through: CGFloat(26), by: -4) {
                    let testFont = UIFont.systemFont(ofSize: candidate, weight: .heavy)
                    let rect = (captionText as NSString).boundingRect(
                        with: CGSize(width: maxBox.width, height: 1000),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: testFont, .paragraphStyle: paragraph],
                        context: nil
                    )
                    if rect.height <= maxBox.height && rect.width <= maxBox.width {
                        chosenFont = testFont
                        break
                    }
                    chosenFont = testFont
                }

                let textBounds = (captionText as NSString).boundingRect(
                    with: maxBox,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: chosenFont, .paragraphStyle: paragraph],
                    context: nil
                )
                let drawHText = ceil(min(maxBox.height, textBounds.height))
                let textRect = CGRect(
                    x: (512.0 - maxBox.width) * 0.5,
                    y: 472.0 - drawHText,
                    width: maxBox.width,
                    height: drawHText
                )

                let shadow = NSShadow()
                shadow.shadowColor = UIColor.black.withAlphaComponent(0.75)
                shadow.shadowBlurRadius = 6.0
                shadow.shadowOffset = CGSize(width: 0, height: 3)

                let strokeAttrs: [NSAttributedString.Key: Any] = [
                    .font: chosenFont,
                    .paragraphStyle: paragraph,
                    .strokeColor: UIColor.black,
                    .strokeWidth: 9.0,
                    .shadow: shadow
                ]
                (captionText as NSString).draw(in: textRect, withAttributes: strokeAttrs)

                let fillAttrs: [NSAttributedString.Key: Any] = [
                    .font: chosenFont,
                    .paragraphStyle: paragraph,
                    .foregroundColor: UIColor.white
                ]
                (captionText as NSString).draw(in: textRect, withAttributes: fillAttrs)
            }
        }

        if let oldUrl = self.stickerPngURL {
            try? FileManager.default.removeItem(at: oldUrl)
        }
        let outUrl = FileManager.default.temporaryDirectory.appendingPathComponent("mediatok_sticker_\(UUID().uuidString.prefix(8)).png")
        if let png = rendered.pngData() {
            try? png.write(to: outUrl, options: [.atomic])
        }
        self.imageView.image = rendered
        self.stickerPngURL = outUrl
        self.statusLabel.text = "Готов стикер 512×512 PNG — отправь напрямую в @Stickers или сохрани"
    }

    @objc private func pickTapped() {
        self.view.endEditing(true)
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = self
        self.present(picker, animated: true)
    }

    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
            guard let rawImg = obj as? UIImage else { return }
            let normalized = MTStickerPackMakerViewController.normalizedStickerSourceImage(rawImg)
            DispatchQueue.main.async {
                guard let self else { return }
                self.sourceImage = normalized
                self.rebuildStickerImage()
            }
        }
    }

    private static func findTelegramNavigationController(context: AccountContext) -> NavigationController? {
        if let nav = context.sharedContext.mainWindow?.viewController as? NavigationController {
            return nav
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap({ $0.windows }) {
            if let nav = window.rootViewController as? NavigationController {
                return nav
            }
            if let children = window.rootViewController?.children {
                for child in children {
                    if let nav = child as? NavigationController {
                        return nav
                    }
                }
            }
        }
        return nil
    }

    @objc private func sendToStickersTapped() {
        self.view.endEditing(true)
        guard !self.isSendingToStickers else { return }
        guard let url = self.stickerPngURL,
              let pngData = try? Data(contentsOf: url),
              !pngData.isEmpty else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Сначала выбери фото для стикера")
            return
        }

        self.isSendingToStickers = true
        self.sendToStickersBtn.isEnabled = false
        self.statusLabel.text = "Подключение к @Stickers и отправка PNG 512×512..."

        let ctx = self.context
        let resolveSignal = ctx.engine.peers.resolvePeerByName(name: "Stickers", referrer: nil)
            |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                switch result {
                case .progress:
                    return .complete()
                case let .result(peer):
                    return .single(peer)
                }
            }
            |> take(1)
            |> deliverOnMainQueue

        self.resolveDisposable.set(resolveSignal.start(next: { [weak self] resolvedPeer in
            guard let peer = resolvedPeer else {
                self?.isSendingToStickers = false
                self?.sendToStickersBtn.isEnabled = true
                self?.statusLabel.text = "Не удалось найти бота @Stickers — проверь подключение к сети"
                MTMediaTokWave5Tools.showToast(context: ctx, text: "Не удалось найти @Stickers — проверь сеть")
                return
            }

            let fileId = Int64.random(in: Int64.min ... Int64.max)
            let resource = LocalFileMediaResource(fileId: fileId, size: Int64(pngData.count), isSecretRelated: false)
            ctx.account.postbox.mediaBox.storeResourceData(resource.id, data: pngData, synchronous: true)

            let attrs: [TelegramMediaFileAttribute] = [
                .FileName(fileName: "mediatok_sticker.png"),
                .ImageSize(size: PixelDimensions(width: 512, height: 512))
            ]
            let media = TelegramMediaFile(
                fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: fileId),
                partialReference: nil,
                resource: resource,
                previewRepresentations: [],
                videoThumbnails: [],
                immediateThumbnailData: nil,
                mimeType: "image/png",
                size: Int64(pngData.count),
                attributes: attrs,
                alternativeRepresentations: []
            )
            let msg: EnqueueMessage = .message(
                text: "",
                attributes: [],
                inlineStickers: [:],
                mediaReference: .standalone(media: media),
                threadId: nil,
                replyToMessageId: nil,
                replyToStoryId: nil,
                localGroupingKey: nil,
                correlationId: nil,
                bubbleUpEmojiOrStickersets: []
            )
            _ = enqueueMessages(account: ctx.account, peerId: peer.id, messages: [msg]).start()

            let openChatAndToast: () -> Void = {
                if let navigationController = MTStickerPackMakerViewController.findTelegramNavigationController(context: ctx) {
                    ctx.sharedContext.navigateToChatController(NavigateToChatControllerParams(
                        navigationController: navigationController,
                        context: ctx,
                        chatLocation: .peer(peer),
                        keepStack: .always
                    ))
                }
                MTMediaTokWave5Tools.showToast(context: ctx, text: "Стикер 512×512 PNG отправлен в @Stickers")
            }

            if let self {
                self.isSendingToStickers = false
                self.sendToStickersBtn.isEnabled = true
                self.dismiss(animated: true) {
                    openChatAndToast()
                }
            } else {
                openChatAndToast()
            }
        }))
    }

    @objc private func exportTapped() {
        self.view.endEditing(true)
        guard let url = self.stickerPngURL else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Сначала выбери фото")
            return
        }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        MTMediaTokWave8Tools.configurePopover(share)
        self.present(share, animated: true)
    }

    @objc private func closeTapped() {
        self.view.endEditing(true)
        self.dismiss(animated: true)
    }
}

// MARK: - #375 Native Voice Transcript Search & Jump-to-Second Controller

private struct MTVoiceWordSegment: Equatable {
    let timestamp: TimeInterval
    let word: String
}

private struct MTVoiceTranscriptState: Equatable {
    var query: String = ""
}

private func mtMakeNativeVoiceTranscriptController(
    context: AccountContext,
    resource: TelegramMediaResource,
    fullText: String,
    segments: [MTVoiceWordSegment]
) -> ViewController {
    let statePromise = ValuePromise(MTVoiceTranscriptState(), ignoreRepeated: true)
    let stateValue = Atomic(value: MTVoiceTranscriptState())

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Расшифровка ГС")
        model.rightButton = ("Копировать", true, {
            UIPasteboard.general.string = fullText
            mtPresentNativeToast(context: context, text: "Расшифровка скопирована")
        })

        model.sections.append([
            .init(id: "t_hdr", kind: .header("Полный текст (\(segments.count) слов)")),
            .init(id: "t_body", kind: .info(fullText.isEmpty ? "Текст не распознан." : fullText)),
            .init(id: "q_in", kind: .input(text: st.query, placeholder: "Найти слово по таймкоду..."))
        ])

        model.text["q_in"] = { val in
            let next = stateValue.modify { var c = $0; c.query = val; return c }
            statePromise.set(next)
        }

        let q = st.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = q.isEmpty ? segments : segments.filter { $0.word.lowercased().contains(q) }
        var wordRows: [MTNativeRow] = [.init(id: "w_hdr", kind: .header("Слова с переходом к секунде"))]
        for (idx, seg) in filtered.prefix(120).enumerated() {
            let sec = Int(seg.timestamp)
            let rowId = "seg_\(idx)_\(sec)"
            wordRows.append(.init(id: rowId, kind: .disclosure(title: seg.word, label: String(format: "%d:%02d", sec / 60, sec % 60), icon: .system("play.circle"), enabled: true)))
            model.tap[rowId] = {
                MTMediaTokWave10Tools.playVoiceWith15dBBoost(context: context, resource: resource, startOffsetSeconds: seg.timestamp)
            }
        }
        model.sections.append(wordRows)
        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}
