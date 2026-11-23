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
import GGCore
import GGHooks
import GGSettingsUI
import GGAppearanceSettings
import GGFeaturesShared
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
public enum GGMediaTokWave10Tools {
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
        get { return UserDefaults.standard.bool(forKey: GGMediaTokWave10Tools.miniAppsBlockFullscreenKey) }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave10Tools.miniAppsBlockFullscreenKey) }
    }

    public static var miniAppsSpoofPlatform: String {
        get { return UserDefaults.standard.string(forKey: GGMediaTokWave10Tools.miniAppsPlatformKey) ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave10Tools.miniAppsPlatformKey) }
    }

    public static var isMiniAppsMultiWindowEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: GGMediaTokWave10Tools.miniAppsMultiWindowKey) }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave10Tools.miniAppsMultiWindowKey) }
    }

    public static var miniAppsAutoclickIntervalMs: Int {
        get { return UserDefaults.standard.integer(forKey: GGMediaTokWave10Tools.miniAppsAutoclickMsKey) }
        set { UserDefaults.standard.set(max(0, min(5000, newValue)), forKey: GGMediaTokWave10Tools.miniAppsAutoclickMsKey) }
    }

    public static var isMiniAppsDevToolsEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: GGMediaTokWave10Tools.miniAppsDevToolsKey) }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave10Tools.miniAppsDevToolsKey) }
    }

    // MARK: - Registration

    public static func register() {
        GGChatScreenHooks.willSendText.register({ request, _ in
            return GGMediaTokWave10Tools.interceptCommands(request)
        }, order: 32)

        GGChatScreenHooks.sendMenuItems.register({ sendContext in
            return GGMediaTokWave10Tools.sendMenuItems(sendContext)
        }, order: 82)

        GGMessageMenuHooks.items.register({ menuContext in
            return GGMediaTokWave10Tools.messageMenuItems(menuContext)
        }, order: 92)
    }

    // MARK: - Wave 4 Studio Hub

    public static func presentWave4Hub(context: AccountContext, peerId: PeerId? = nil) {
        DispatchQueue.main.async {
            let sheet = UIAlertController(
                title: "🚀 MediaTok Студия b3779 (Волна 4)",
                message: "Аналитика чатов, ГС +15 dB, стикерпаки, фейк-маршрут, Mini Apps, Машина времени",
                preferredStyle: .actionSheet
            )
            if let peerId {
                sheet.addAction(UIAlertAction(title: "📊 График активности чата (00–23)", style: .default, handler: { _ in
                    GGMediaTokWave10Tools.presentChatActivityGraph(context: context, peerId: peerId)
                }))
                sheet.addAction(UIAlertAction(title: "🏆 Топ постов по реакциям и просмотрам", style: .default, handler: { _ in
                    GGMediaTokWave10Tools.presentTopChannelPosts(context: context, peerId: peerId)
                }))
                sheet.addAction(UIAlertAction(title: "⏳ Машина времени (архив по дате)", style: .default, handler: { _ in
                    GGMediaTokWave10Tools.presentTimeMachine(context: context, peerId: peerId)
                }))
                sheet.addAction(UIAlertAction(title: "📍 Фейк-геолокация с маршрутом", style: .default, handler: { _ in
                    GGMediaTokWave10Tools.presentFakeRouteGeo(context: context, peerId: peerId)
                }))
            }
            sheet.addAction(UIAlertAction(title: "🎨 Конструктор стикерпаков (512×512 PNG)", style: .default, handler: { _ in
                GGMediaTokWave10Tools.presentStickerMaker(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "🧩 Mini Apps Power Pack (#451–#455)", style: .default, handler: { _ in
                GGMediaTokWave10Tools.presentMiniAppsStudio(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "🎙 Пресеты Voicemod (Экспорт / Импорт)", style: .default, handler: { _ in
                GGMediaTokWave10Tools.presentVoicemodPresetsSheet(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))

            GGMediaTokWave8Tools.configurePopover(sheet)
            GGMediaTokWave5Tools.presentOnRoot(sheet)
        }
    }

    // MARK: - Launchers

    public static func presentChatActivityGraph(context: AccountContext, peerId: PeerId) {
        DispatchQueue.main.async {
            let vc = GGChatAnalyticsViewController(context: context, peerId: peerId, mode: .hourlyActivity)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            GGMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    public static func presentTopChannelPosts(context: AccountContext, peerId: PeerId) {
        DispatchQueue.main.async {
            let vc = GGChatAnalyticsViewController(context: context, peerId: peerId, mode: .topPosts)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            GGMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    public static func presentTimeMachine(context: AccountContext, peerId: PeerId) {
        DispatchQueue.main.async {
            let vc = GGTimeMachineViewController(context: context, peerId: peerId)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            GGMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    public static func presentFakeRouteGeo(context: AccountContext, peerId: PeerId) {
        DispatchQueue.main.async {
            let vc = GGFakeRouteGeoViewController(context: context, peerId: peerId)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            GGMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    public static func presentStickerMaker(context: AccountContext) {
        DispatchQueue.main.async {
            let vc = GGStickerPackMakerViewController(context: context)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            GGMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    // MARK: - #451–#455 Mini Apps Power Pack

    public static func presentMiniAppsStudio(context: AccountContext) {
        DispatchQueue.main.async {
            let fs = GGMediaTokWave10Tools.isMiniAppsBlockFullscreenEnabled ? "ВКЛ" : "ВЫКЛ"
            let mw = GGMediaTokWave10Tools.isMiniAppsMultiWindowEnabled ? "ВКЛ" : "ВЫКЛ"
            let plat = GGMediaTokWave10Tools.miniAppsSpoofPlatform
            let ac = GGMediaTokWave10Tools.miniAppsAutoclickIntervalMs > 0 ? "\(GGMediaTokWave10Tools.miniAppsAutoclickIntervalMs) мс" : "Выкл"
            let dev = GGMediaTokWave10Tools.isMiniAppsDevToolsEnabled ? "ВКЛ" : "ВЫКЛ"

            let sheet = UIAlertController(
                title: "🧩 Mini Apps Power Pack",
                message: "Блок fullscreen/вибрации: \(fs) | Платформа: \(plat)\nМульти-окна: \(mw) | Автокликер: \(ac)",
                preferredStyle: .actionSheet
            )
            sheet.addAction(UIAlertAction(title: "🚫 Блок fullscreen и вибрации (\(fs))", style: .default, handler: { _ in
                GGMediaTokWave10Tools.isMiniAppsBlockFullscreenEnabled.toggle()
                GGMediaTokWave5Tools.showToast(context: context, text: "Блок fullscreen/вибрации: \(GGMediaTokWave10Tools.isMiniAppsBlockFullscreenEnabled ? "ВКЛ" : "ВЫКЛ")")
            }))
            sheet.addAction(UIAlertAction(title: "📱 Подмена платформы: \(plat)", style: .default, handler: { _ in
                let order = ["default", "ios", "android", "tdesktop", "web"]
                let nextIdx = ((order.firstIndex(of: plat) ?? 0) + 1) % order.count
                GGMediaTokWave10Tools.miniAppsSpoofPlatform = order[nextIdx]
                GGMediaTokWave5Tools.showToast(context: context, text: "Платформа Mini Apps: \(order[nextIdx])")
            }))
            sheet.addAction(UIAlertAction(title: "🪟 Мульти-окна Mini Apps (\(mw))", style: .default, handler: { _ in
                GGMediaTokWave10Tools.isMiniAppsMultiWindowEnabled.toggle()
                GGMediaTokWave5Tools.showToast(context: context, text: "Мульти-окна Mini Apps: \(GGMediaTokWave10Tools.isMiniAppsMultiWindowEnabled ? "ВКЛ" : "ВЫКЛ")")
            }))
            sheet.addAction(UIAlertAction(title: "⚡ Автокликер / Макрос (\(ac))", style: .default, handler: { _ in
                let alert = UIAlertController(title: "⚡ Автокликер (мс)", message: "Интервал в миллисекундах (0 — выкл, например 120):", preferredStyle: .alert)
                alert.addTextField { tf in
                    tf.keyboardType = .numberPad
                    tf.text = "\(GGMediaTokWave10Tools.miniAppsAutoclickIntervalMs)"
                }
                alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
                    let ms = Int(alert.textFields?.first?.text ?? "0") ?? 0
                    GGMediaTokWave10Tools.miniAppsAutoclickIntervalMs = ms
                    GGMediaTokWave5Tools.showToast(context: context, text: ms > 0 ? "Автокликер: \(ms) мс" : "Автокликер выключен")
                }))
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                GGMediaTokWave5Tools.presentOnRoot(alert)
            }))
            sheet.addAction(UIAlertAction(title: "🛠 Dev: Консоль DevTools Eruda (\(dev))", style: .default, handler: { _ in
                GGMediaTokWave10Tools.isMiniAppsDevToolsEnabled.toggle()
                GGMediaTokWave5Tools.showToast(context: context, text: "DevTools Eruda: \(GGMediaTokWave10Tools.isMiniAppsDevToolsEnabled ? "ВКЛ" : "ВЫКЛ")")
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            GGMediaTokWave8Tools.configurePopover(sheet)
            GGMediaTokWave5Tools.presentOnRoot(sheet)
        }
    }

    // MARK: - #380 Voicemod Preset Export / Import

    public static func presentVoicemodPresetsSheet(context: AccountContext) {
        let presets = (UserDefaults.standard.dictionary(forKey: GGMediaTokWave10Tools.voicePresetsKey) as? [String: [String: Double]]) ?? [
            "Deep Bass": ["pitch": -4.0, "rate": 0.94, "gainDb": 6.0],
            "Anime High": ["pitch": 5.5, "rate": 1.08, "gainDb": 2.0],
            "Radio Studio": ["pitch": -1.0, "rate": 1.0, "gainDb": 10.0]
        ]
        let sheet = UIAlertController(
            title: "🎙 Пресеты Voicemod (#380)",
            message: "Сохранённых пресетов: \(presets.count)\nТекущий DSP: \(GGVoiceSettings.morphEnabled.value ? "ВКЛ (\(GGVoiceSettings.customName.value.isEmpty ? GGVoiceSettings.morphPreset.value : GGVoiceSettings.customName.value))" : "ВЫКЛ")",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "🎛 Применить пресет к движку голоса (DSP)", style: .default, handler: { _ in
            let picker = UIAlertController(title: "🎛 Выбери пресет для DSP", message: "Применится к ГС и кружочкам через GGVoiceSettings", preferredStyle: .actionSheet)
            for name in presets.keys.sorted() {
                let vals = presets[name] ?? [:]
                let pitch = vals["pitch"] ?? 0.0
                let gain = vals["gainDb"] ?? 0.0
                picker.addAction(UIAlertAction(title: "\(name) (pitch \(String(format: "%.1f", pitch)), gain \(String(format: "%.0f", gain)) dB)", style: .default, handler: { _ in
                    GGVoiceSettings.morphEnabled.set(true)
                    GGVoiceSettings.morphPreset.set("custom")
                    GGVoiceSettings.customName.set(name)
                    GGVoiceSettings.customReverb.set(0.0)
                    GGVoiceSettings.customDistortion.set(0.0)
                    GGVoiceSettings.customEcho.set(0.0)
                    GGVoiceSettings.customTimbre.set(0.0)
                    GGVoiceSettings.customBass.set(0.0)
                    GGVoiceSettings.customMid.set(0.0)
                    GGVoiceSettings.customTreble.set(0.0)
                    GGVoiceSettings.customRingMod.set(0.0)
                    GGVoiceSettings.customBitcrush.set(16.0)
                    GGVoiceSettings.customTelephone.set(false)
                    GGVoiceSettings.customCompression.set(0.0)
                    GGVoiceSettings.customBreathiness.set(0.0)
                    GGVoiceSettings.customChorus.set(0.0)
                    GGVoiceSettings.customFlanger.set(0.0)
                    GGVoiceSettings.customVibratoDepth.set(0.0)
                    GGVoiceSettings.customVibratoRate.set(5.0)
                    GGVoiceSettings.customWet.set(100.0)
                    GGVoiceSettings.customPitch.set(max(-12.0, min(12.0, pitch)))
                    GGVoiceSettings.customGain.set(max(-12.0, min(12.0, gain)))
                    if let reverb = vals["reverb"] {
                        GGVoiceSettings.customReverb.set(max(0.0, min(100.0, reverb)))
                    }
                    if let dist = vals["distortion"] {
                        GGVoiceSettings.customDistortion.set(max(0.0, min(100.0, dist)))
                    }
                    GGMediaTokWave5Tools.showToast(context: context, text: "🎙 Пресет «\(name)» применён к движку голоса!")
                }))
            }
            picker.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            GGMediaTokWave8Tools.configurePopover(picker)
            GGMediaTokWave5Tools.presentOnRoot(picker)
        }))
        sheet.addAction(UIAlertAction(title: "📤 Экспортировать пресеты (JSON)", style: .default, handler: { _ in
            if let data = try? JSONSerialization.data(withJSONObject: presets, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                UIPasteboard.general.string = str
                let share = UIActivityViewController(activityItems: [str], applicationActivities: nil)
                GGMediaTokWave8Tools.configurePopover(share)
                GGMediaTokWave5Tools.presentOnRoot(share)
            }
        }))
        sheet.addAction(UIAlertAction(title: "📥 Импортировать пресеты из буфера", style: .default, handler: { _ in
            guard let raw = UIPasteboard.general.string,
                  let data = raw.data(using: .utf8),
                  let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Double]],
                  !parsed.isEmpty else {
                GGMediaTokWave5Tools.showToast(context: context, text: "В буфере обмена нет валидного JSON пресетов")
                return
            }
            UserDefaults.standard.set(parsed, forKey: GGMediaTokWave10Tools.voicePresetsKey)
            GGMediaTokWave5Tools.showToast(context: context, text: "✅ Импортировано пресетов: \(parsed.count)")
        }))
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGMediaTokWave8Tools.configurePopover(sheet)
        GGMediaTokWave5Tools.presentOnRoot(sheet)
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
        GGMediaTokWave5Tools.showToast(context: context, text: startOffsetSeconds > 0.1 ? String(format: "🔊 Старт с %d:%02d (+15 dB)...", Int(startOffsetSeconds) / 60, Int(startOffsetSeconds) % 60) : "🔊 Подготовка усиления ГС (+15 dB)...")
        let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
            |> take(1)
            |> deliverOnMainQueue).startStandalone(next: { data in
                guard data.complete else {
                    GGMediaTokWave5Tools.showToast(context: context, text: "Сначала нажми воспроизвести ГС, чтобы оно загрузилось")
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let pcmBuffer = GGMediaTokWave10Tools.decodeOpusOrAudioToPCMBuffer(path: data.path, startOffsetSeconds: startOffsetSeconds) else {
                        DispatchQueue.main.async {
                            GGMediaTokWave5Tools.showToast(context: context, text: "Не удалось декодировать аудиофайл ГС")
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        do {
                            GGMediaTokWave10Tools.boostPlayerNode?.stop()
                            GGMediaTokWave10Tools.boostEngine?.stop()

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

                            GGMediaTokWave10Tools.boostEngine = engine
                            GGMediaTokWave10Tools.boostPlayerNode = player

                            player.scheduleBuffer(pcmBuffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak engine, weak player] _ in
                                DispatchQueue.main.async {
                                    guard let engine, let player,
                                          GGMediaTokWave10Tools.boostEngine === engine,
                                          GGMediaTokWave10Tools.boostPlayerNode === player else {
                                        return
                                    }
                                    player.stop()
                                    engine.stop()
                                    GGMediaTokWave10Tools.boostPlayerNode = nil
                                    GGMediaTokWave10Tools.boostEngine = nil
                                    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                                }
                            }
                            player.play()
                            GGMediaTokWave5Tools.showToast(context: context, text: "🔊 Воспроизведение ГС (+15 dB)")
                        } catch {
                            GGMediaTokWave5Tools.showToast(context: context, text: "Ошибка аудиодвижка: \(error.localizedDescription)")
                        }
                    }
                }
            })
    }

    private static func transcribeVoiceWithTimestamps(context: AccountContext, resource: TelegramMediaResource) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    GGMediaTokWave5Tools.showToast(context: context, text: "Разреши доступ к распознаванию речи в Настройках iOS")
                    return
                }
                GGMediaTokWave5Tools.showToast(context: context, text: "🎙 Декодирую Ogg/Opus и расшифровываю ГС...")
                let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
                    |> take(1)
                    |> deliverOnMainQueue).startStandalone(next: { data in
                        guard data.complete else {
                            GGMediaTokWave5Tools.showToast(context: context, text: "Сначала загрузи ГС")
                            return
                        }
                        DispatchQueue.global(qos: .userInitiated).async {
                            guard let pcmBuffer = GGMediaTokWave10Tools.decodeOpusOrAudioToPCMBuffer(path: data.path) else {
                                DispatchQueue.main.async {
                                    GGMediaTokWave5Tools.showToast(context: context, text: "Не удалось декодировать ГС (Ogg/Opus)")
                                }
                                return
                            }
                            DispatchQueue.main.async {
                                GGMediaTokWave10Tools.activeSpeechTask?.cancel()
                                GGMediaTokWave10Tools.activeSpeechTask = nil
                                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")) ?? SFSpeechRecognizer(),
                                      recognizer.isAvailable else {
                                    GGMediaTokWave5Tools.showToast(context: context, text: "Распознавание речи сейчас недоступно")
                                    return
                                }
                                let req = SFSpeechAudioBufferRecognitionRequest()
                                req.shouldReportPartialResults = false
                                req.append(pcmBuffer)
                                req.endAudio()
                                var createdTask: SFSpeechRecognitionTask?
                                createdTask = recognizer.recognitionTask(with: req) { result, error in
                                    DispatchQueue.main.async {
                                        guard let createdTask, GGMediaTokWave10Tools.activeSpeechTask === createdTask else {
                                            return
                                        }
                                        if let result, result.isFinal {
                                            GGMediaTokWave10Tools.activeSpeechTask = nil
                                            let items = result.bestTranscription.segments.map { (timestamp: $0.timestamp, word: $0.substring) }
                                            let fullText = result.bestTranscription.formattedString
                                            let vc = GGVoiceTranscriptSearchViewController(
                                                context: context,
                                                resource: resource,
                                                fullText: fullText,
                                                segments: items
                                            )
                                            vc.overrideUserInterfaceStyle = .dark
                                            let nav = UINavigationController(rootViewController: vc)
                                            nav.overrideUserInterfaceStyle = .dark
                                            nav.modalPresentationStyle = .pageSheet
                                            GGMediaTokWave5Tools.presentOnRoot(nav)
                                            return
                                        }
                                        if let error {
                                            GGMediaTokWave10Tools.activeSpeechTask = nil
                                            let nsErr = error as NSError
                                            if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSUserCancelledError {
                                                return
                                            }
                                            GGMediaTokWave5Tools.showToast(context: context, text: "Ошибка расшифровки: \(error.localizedDescription)")
                                        }
                                    }
                                }
                                GGMediaTokWave10Tools.activeSpeechTask = createdTask
                            }
                        }
                    })
            }
        }
    }

    // MARK: - Inline Commands & Menus

    private static func interceptCommands(_ request: GGComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let lower = raw.lowercased()

        if lower == ".graph" || lower == ".activity" {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            GGMediaTokWave10Tools.presentChatActivityGraph(context: request.context, peerId: peerId)
            return true
        }
        if lower == ".top" || lower == ".topposts" {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            GGMediaTokWave10Tools.presentTopChannelPosts(context: request.context, peerId: peerId)
            return true
        }
        if lower == ".timemachine" || lower == ".tm" {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            GGMediaTokWave10Tools.presentTimeMachine(context: request.context, peerId: peerId)
            return true
        }
        if lower == ".route" || lower == ".fakegeo" {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            GGMediaTokWave10Tools.presentFakeRouteGeo(context: request.context, peerId: peerId)
            return true
        }
        if lower == ".makesticker" {
            request.replace(ChatTextInputState())
            GGMediaTokWave10Tools.presentStickerMaker(context: request.context)
            return true
        }
        return false
    }

    private static func sendMenuItems(_ sendContext: GGSendMenuContext) -> [ContextMenuItem] {
        var entries: [ContextMenuItem] = []
        let ctx = sendContext.context
        let pid = sendContext.peerId
        let dismiss = sendContext.dismiss

        entries.append(.action(ContextMenuActionItem(
            text: "📊 Аналитика / Топ постов / Машина времени",
            icon: { theme in
                return UIImage(systemName: "chart.bar.xaxis")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                GGMediaTokWave10Tools.presentWave4Hub(context: ctx, peerId: pid)
            }
        )))

        entries.append(.action(ContextMenuActionItem(
            text: "📍 Фейк-геолокация с маршрутом",
            icon: { theme in
                return UIImage(systemName: "location.north.line.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                GGMediaTokWave10Tools.presentFakeRouteGeo(context: ctx, peerId: pid)
            }
        )))

        return entries
    }

    private static func messageMenuItems(_ menuContext: GGMessageMenuContext) -> [GGMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        var entries: [GGMessageMenuEntry] = []

        if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile, file.isVoice {
            let res = file.resource
            entries.append(GGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "🔊 Усилить тихое ГС (+15 dB)",
                icon: { theme in
                    return UIImage(systemName: "speaker.wave.3.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    GGMediaTokWave10Tools.playVoiceWith15dBBoost(context: context, resource: res)
                }
            ))))
            entries.append(GGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "🎙 Расшифровать ГС с таймкодами",
                icon: { theme in
                    return UIImage(systemName: "waveform.and.magnifyingglass")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    GGMediaTokWave10Tools.transcribeVoiceWithTimestamps(context: context, resource: res)
                }
            ))))
        }

        return entries
    }
}

// MARK: - #476 Hourly Activity Graph & #477 Top Channel Posts

public final class GGChatAnalyticsViewController: UIViewController, UITableViewDataSource {
    public enum Mode {
        case hourlyActivity
        case topPosts
    }

    private let context: AccountContext
    private let peerId: PeerId
    private let mode: Mode
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var rows: [(title: String, subtitle: String, badge: String)] = []

    public init(context: AccountContext, peerId: PeerId, mode: Mode) {
        self.context = context
        self.peerId = peerId
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = self.mode == .hourlyActivity ? "📊 Активность чата (00–23)" : "🏆 Топ постов по реакциям"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.closeTapped))

        self.tableView.backgroundColor = .clear
        self.tableView.dataSource = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.tableView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.loadAnalytics()
    }

    private func loadAnalytics() {
        let peerId = self.peerId
        let mode = self.mode
        let _ = (self.context.account.postbox.transaction { transaction -> [(String, String, String)] in
            var messages: [Message] = []
            transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 400) { msg in
                messages.append(msg)
                return messages.count < 400
            }

            if mode == .hourlyActivity {
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
                var out: [(String, String, String)] = []
                out.append(("Проанализировано сообщений: \(messages.count)", "Распределение по часам суток", "24ч"))
                for h in 0 ..< 24 {
                    let cnt = byHour[h]
                    let bars = Int((Double(cnt) / Double(maxH) * 14.0).rounded())
                    let barStr = String(repeating: "█", count: max(cnt > 0 ? 1 : 0, bars))
                    out.append((String(format: "%02d:00  %@", h, barStr), "Сообщений за час", "\(cnt)"))
                }
                let topAuthors = byAuthor.sorted { $0.value > $1.value }.prefix(5)
                for (name, count) in topAuthors {
                    out.append(("👤 \(name)", "Топ автор в выборке", "\(count)"))
                }
                return out
            } else {
                var scored: [(score: Int, reactions: Int, views: Int, text: String)] = []
                for m in messages {
                    var reactTotal = 0
                    var viewTotal = 0
                    for attr in m.attributes {
                        if let r = attr as? ReactionsMessageAttribute {
                            for item in r.reactions {
                                reactTotal += Int(item.count)
                            }
                        } else if let v = attr as? ViewCountMessageAttribute {
                            viewTotal = v.count
                        }
                    }
                    let score = reactTotal * 10 + viewTotal
                    let preview = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let label = preview.isEmpty ? "[Медиа-пост #\(m.id.id)]" : String(preview.prefix(80))
                    scored.append((score, reactTotal, viewTotal, label))
                }
                scored.sort { $0.score > $1.score }
                return scored.prefix(15).enumerated().map { idx, item in
                    return ("#\(idx + 1)  \(item.text)", "❤️ Реакций: \(item.reactions) • 👁 Просмотров: \(item.views)", "🔥 \(item.reactions)")
                }
            }
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] result in
            guard let self else { return }
            self.rows = result.isEmpty ? [("Нет локальных сообщений", "Пролистай чат/канал чтобы загрузить историю", "0")] : result
            self.tableView.reloadData()
        })
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.rows.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseId = "GGAnalyticsCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseId)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseId)
        let row = self.rows[indexPath.row]
        cell.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        cell.selectionStyle = .none
        cell.textLabel?.text = row.title
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        cell.textLabel?.numberOfLines = 2
        cell.detailTextLabel?.text = "\(row.subtitle)  •  \(row.badge)"
        cell.detailTextLabel?.textColor = UIColor(white: 0.68, alpha: 1.0)
        return cell
    }
}

// MARK: - #498 Channel Time Machine

public final class GGTimeMachineViewController: UIViewController, UITableViewDataSource {
    private let context: AccountContext
    private let peerId: PeerId
    private let datePicker = UIDatePicker()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var posts: [(date: String, text: String)] = []

    public init(context: AccountContext, peerId: PeerId) {
        self.context = context
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "⏳ Машина времени"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.closeTapped))

        self.datePicker.datePickerMode = .date
        self.datePicker.preferredDatePickerStyle = .compact
        self.datePicker.maximumDate = Date()
        self.datePicker.addTarget(self, action: #selector(self.dateChanged), for: .valueChanged)
        self.datePicker.translatesAutoresizingMaskIntoConstraints = false

        self.tableView.backgroundColor = .clear
        self.tableView.dataSource = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.datePicker)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.datePicker.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            self.datePicker.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.tableView.topAnchor.constraint(equalTo: self.datePicker.bottomAnchor, constant: 12),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.loadAround(date: self.datePicker.date)
    }

    @objc private func dateChanged() {
        self.loadAround(date: self.datePicker.date)
    }

    private func loadAround(date: Date) {
        let targetTs = Int32(date.timeIntervalSince1970)
        let peerId = self.peerId
        let _ = (self.context.account.postbox.transaction { transaction -> [(String, String)] in
            var messages: [Message] = []
            transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 800) { m in
                messages.append(m)
                return messages.count < 800
            }
            let sorted = messages.sorted { abs($0.timestamp - targetTs) < abs($1.timestamp - targetTs) }
            let fmt = DateFormatter()
            fmt.dateFormat = "dd.MM.yyyy HH:mm"
            return sorted.prefix(20).map { m in
                let dStr = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(m.timestamp)))
                let body = m.text.isEmpty ? "[Медиа-сообщение #\(m.id.id)]" : String(m.text.prefix(140))
                return (dStr, body)
            }
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] list in
            guard let self else { return }
            self.posts = list.isEmpty ? [("Архив пуст", "Пролистай историю канала для кэширования")] : list
            self.tableView.reloadData()
        })
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.posts.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseId = "GGTimeMachineCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseId)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseId)
        let p = self.posts[indexPath.row]
        cell.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        cell.selectionStyle = .none
        cell.textLabel?.text = p.date
        cell.textLabel?.textColor = UIColor(red: 0.35, green: 0.78, blue: 1.0, alpha: 1.0)
        cell.textLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        cell.detailTextLabel?.text = p.text
        cell.detailTextLabel?.textColor = .white
        cell.detailTextLabel?.numberOfLines = 3
        return cell
    }
}

// MARK: - #485 Fake Geolocation with Live Route Simulation

public final class GGFakeRouteGeoViewController: UIViewController {
    private let context: AccountContext
    private let peerId: PeerId

    private let coordLabel = UILabel()
    private let routeSegment = UISegmentedControl(items: ["Москва", "Токио", "Нью-Йорк", "Париж"])
    private let speedSegment = UISegmentedControl(items: ["Пешком", "Авто", "Самолёт"])
    private var simTimer: Foundation.Timer?
    private var progress: Double = 0.0
    private var currentLat: Double = 55.7558
    private var currentLon: Double = 37.6173

    private let routes: [(startLat: Double, startLon: Double, endLat: Double, endLon: Double, title: String)] = [
        (55.7558, 37.6173, 55.7495, 37.5376, "Красная площадь → Москва-Сити"),
        (35.6595, 139.7004, 35.6895, 139.6917, "Сибуя → Синдзюку"),
        (40.7580, -73.9855, 40.7128, -74.0060, "Таймс-Сквер → Уолл-Стрит"),
        (48.8584, 2.2945, 48.8606, 2.3376, "Эйфелева башня → Лувр")
    ]

    public init(context: AccountContext, peerId: PeerId) {
        self.context = context
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.simTimer?.invalidate()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "📍 Фейк-геолокация (Маршрут)"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.closeTapped))

        self.coordLabel.font = .monospacedSystemFont(ofSize: 15, weight: .bold)
        self.coordLabel.textColor = .white
        self.coordLabel.textAlignment = .center
        self.coordLabel.numberOfLines = 4
        self.coordLabel.translatesAutoresizingMaskIntoConstraints = false

        self.routeSegment.selectedSegmentIndex = 0
        self.routeSegment.addTarget(self, action: #selector(self.routeChanged), for: .valueChanged)
        self.routeSegment.translatesAutoresizingMaskIntoConstraints = false

        self.speedSegment.selectedSegmentIndex = 1
        self.speedSegment.translatesAutoresizingMaskIntoConstraints = false

        let sendBtn = UIButton(type: .system)
        sendBtn.setTitle("✈️ Отправить текущую точку маршрута в чат", for: .normal)
        sendBtn.setTitleColor(.white, for: .normal)
        sendBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        sendBtn.backgroundColor = UIColor(red: 0.16, green: 0.52, blue: 1.0, alpha: 1.0)
        sendBtn.layer.cornerRadius = 14
        sendBtn.addTarget(self, action: #selector(self.sendLocationTapped), for: .touchUpInside)
        sendBtn.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.coordLabel)
        self.view.addSubview(self.routeSegment)
        self.view.addSubview(self.speedSegment)
        self.view.addSubview(sendBtn)

        NSLayoutConstraint.activate([
            self.coordLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 28),
            self.coordLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.coordLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            self.routeSegment.topAnchor.constraint(equalTo: self.coordLabel.bottomAnchor, constant: 24),
            self.routeSegment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.routeSegment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            self.speedSegment.topAnchor.constraint(equalTo: self.routeSegment.bottomAnchor, constant: 14),
            self.speedSegment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.speedSegment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            sendBtn.topAnchor.constraint(equalTo: self.speedSegment.bottomAnchor, constant: 24),
            sendBtn.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            sendBtn.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            sendBtn.heightAnchor.constraint(equalToConstant: 50)
        ])

        self.updateCoords()
        self.simTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.tickRoute()
        }
    }

    @objc private func routeChanged() {
        self.progress = 0.0
        self.updateCoords()
    }

    private func tickRoute() {
        let step: Double
        switch self.speedSegment.selectedSegmentIndex {
        case 0: step = 0.008
        case 2: step = 0.09
        default: step = 0.03
        }
        self.progress += step
        if self.progress > 1.0 {
            self.progress = 0.0
        }
        self.updateCoords()
    }

    private func updateCoords() {
        let r = self.routes[max(0, min(self.routeSegment.selectedSegmentIndex, self.routes.count - 1))]
        self.currentLat = r.startLat + (r.endLat - r.startLat) * self.progress
        self.currentLon = r.startLon + (r.endLon - r.startLon) * self.progress
        let pct = Int((self.progress * 100.0).rounded())
        self.coordLabel.text = "\(r.title)\nПрогресс: \(pct)%\nLat: \(String(format: "%.5f", self.currentLat))  Lon: \(String(format: "%.5f", self.currentLon))"
    }

    @objc private func sendLocationTapped() {
        let map = TelegramMediaMap(latitude: self.currentLat, longitude: self.currentLon, heading: nil, accuracyRadius: 12.0, venue: nil)
        let msg = EnqueueMessage.message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: map), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        _ = enqueueMessages(account: self.context.account, peerId: self.peerId, messages: [msg]).start()
        GGMediaTokWave5Tools.showToast(context: self.context, text: "📍 Фейк-геометка отправлена!")
        self.dismiss(animated: true)
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}

// MARK: - #456 Sticker Pack Constructor (`512×512 PNG` → `@Stickers`)

public final class GGStickerPackMakerViewController: UIViewController, PHPickerViewControllerDelegate {
    private let context: AccountContext
    private let imageView = UIImageView()
    private let statusLabel = UILabel()
    private var stickerPngURL: URL?

    public init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🎨 Конструктор стикеров"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.closeTapped))

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        self.imageView.layer.cornerRadius = 22
        self.imageView.clipsToBounds = true
        self.imageView.translatesAutoresizingMaskIntoConstraints = false

        self.statusLabel.text = "Выбери фото — соберу готовый 512×512 PNG стикер с белой обводкой для @Stickers"
        self.statusLabel.textColor = UIColor(white: 0.72, alpha: 1.0)
        self.statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 2
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let pickBtn = UIButton(type: .system)
        pickBtn.setTitle("🖼 Выбрать фото", for: .normal)
        pickBtn.setTitleColor(.white, for: .normal)
        pickBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        pickBtn.backgroundColor = UIColor(red: 0.16, green: 0.52, blue: 1.0, alpha: 1.0)
        pickBtn.layer.cornerRadius = 14
        pickBtn.addTarget(self, action: #selector(self.pickTapped), for: .touchUpInside)
        pickBtn.translatesAutoresizingMaskIntoConstraints = false

        let exportBtn = UIButton(type: .system)
        exportBtn.setTitle("📤 Экспорт 512×512 PNG / Открыть @Stickers", for: .normal)
        exportBtn.setTitleColor(.white, for: .normal)
        exportBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        exportBtn.backgroundColor = UIColor(white: 0.18, alpha: 1.0)
        exportBtn.layer.cornerRadius = 14
        exportBtn.addTarget(self, action: #selector(self.exportTapped), for: .touchUpInside)
        exportBtn.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.imageView)
        self.view.addSubview(self.statusLabel)
        self.view.addSubview(pickBtn)
        self.view.addSubview(exportBtn)

        NSLayoutConstraint.activate([
            self.imageView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            self.imageView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.imageView.widthAnchor.constraint(equalToConstant: 260),
            self.imageView.heightAnchor.constraint(equalToConstant: 260),
            self.statusLabel.topAnchor.constraint(equalTo: self.imageView.bottomAnchor, constant: 14),
            self.statusLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.statusLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            pickBtn.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 18),
            pickBtn.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            pickBtn.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            pickBtn.heightAnchor.constraint(equalToConstant: 48),
            exportBtn.topAnchor.constraint(equalTo: pickBtn.bottomAnchor, constant: 10),
            exportBtn.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            exportBtn.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            exportBtn.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func pickTapped() {
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
            guard let img = obj as? UIImage else { return }
            let size = CGSize(width: 512, height: 512)
            let format = UIGraphicsImageRendererFormat()
            format.opaque = false
            format.scale = 1.0
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let insetRect = CGRect(x: 16, y: 16, width: 480, height: 480)
                let path = UIBezierPath(roundedRect: insetRect, cornerRadius: 96)
                ctx.cgContext.saveGState()
                path.addClip()
                let scale = max(insetRect.width / img.size.width, insetRect.height / img.size.height)
                let drawW = img.size.width * scale
                let drawH = img.size.height * scale
                img.draw(in: CGRect(x: insetRect.midX - drawW / 2, y: insetRect.midY - drawH / 2, width: drawW, height: drawH))
                ctx.cgContext.restoreGState()
                UIColor.white.setStroke()
                path.lineWidth = 14
                path.stroke()
            }
            let outUrl = FileManager.default.temporaryDirectory.appendingPathComponent("MediaTok_Sticker_\(Int(Date().timeIntervalSince1970)).png")
            if let png = rendered.pngData() {
                try? png.write(to: outUrl, options: [.atomic])
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.imageView.image = rendered
                self.stickerPngURL = outUrl
                self.statusLabel.text = "✅ Готов стикер 512×512 PNG! Нажми Экспорт для отправки в @Stickers"
            }
        }
    }

    @objc private func exportTapped() {
        guard let url = self.stickerPngURL else {
            GGMediaTokWave5Tools.showToast(context: self.context, text: "Сначала выбери фото")
            return
        }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        GGMediaTokWave8Tools.configurePopover(share)
        self.present(share, animated: true)
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}

// MARK: - #375 Interactive Voice Transcript Search & Jump-to-Second ViewController

private final class GGVoiceTranscriptSearchViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let context: AccountContext
    private let resource: TelegramMediaResource
    private let fullText: String
    private let allSegments: [(timestamp: TimeInterval, word: String)]
    private var filteredSegments: [(timestamp: TimeInterval, word: String)]

    private let searchBar = UISearchBar()
    private let fullTextView = UITextView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(context: AccountContext, resource: TelegramMediaResource, fullText: String, segments: [(timestamp: TimeInterval, word: String)]) {
        self.context = context
        self.resource = resource
        self.fullText = fullText
        self.allSegments = segments
        self.filteredSegments = segments
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🎙 Поиск по ГС (\(self.allSegments.count) слов)"
        self.view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Копировать", style: .done, target: self, action: #selector(copyTapped))

        self.searchBar.placeholder = "Найти слово в голосовом..."
        self.searchBar.delegate = self
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false

        self.fullTextView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        self.fullTextView.textColor = .white
        self.fullTextView.font = .systemFont(ofSize: 14)
        self.fullTextView.isEditable = false
        self.fullTextView.layer.cornerRadius = 10
        self.fullTextView.text = self.fullText
        self.fullTextView.translatesAutoresizingMaskIntoConstraints = false

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.backgroundColor = .clear
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.searchBar)
        self.view.addSubview(self.fullTextView)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.searchBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 4),
            self.searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 8),
            self.searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -8),

            self.fullTextView.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor, constant: 6),
            self.fullTextView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.fullTextView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.fullTextView.heightAnchor.constraint(equalToConstant: 96),

            self.tableView.topAnchor.constraint(equalTo: self.fullTextView.bottomAnchor, constant: 8),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            self.filteredSegments = self.allSegments
        } else {
            self.filteredSegments = self.allSegments.filter { $0.word.lowercased().contains(q) }
        }
        self.tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.filteredSegments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "seg") ?? UITableViewCell(style: .value1, reuseIdentifier: "seg")
        let seg = self.filteredSegments[indexPath.row]
        let sec = Int(seg.timestamp)
        cell.textLabel?.text = seg.word
        cell.detailTextLabel?.text = String(format: "▶️ %d:%02d", sec / 60, sec % 60)
        cell.detailTextLabel?.textColor = .systemBlue
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let seg = self.filteredSegments[indexPath.row]
        GGMediaTokWave10Tools.playVoiceWith15dBBoost(context: self.context, resource: self.resource, startOffsetSeconds: seg.timestamp)
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = self.fullText
        GGMediaTokWave5Tools.showToast(context: self.context, text: "📋 Расшифровка ГС скопирована")
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}
