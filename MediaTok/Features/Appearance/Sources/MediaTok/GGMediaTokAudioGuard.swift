import Foundation
import UIKit
import AVFoundation
import Postbox
import TelegramCore
import AccountContext
import OpusBinding
import GGVoiceDSP
import GGCore
import GGHooks
import GGSettingsUI

/// MediaTok Anti-Screamer, Loud Bad Sounds & Moan Prank Filter (`GGMediaTokAudioGuard`):
/// 1) Pre-scans downloaded Ogg Opus voice messages (`OggOpusReader`), round video notes, and chat
///    videos (`AVAssetReader` 16 kHz mono Int16 PCM) via `GGMediaTokCoreLogic.analyzeAudioPcm16k`.
/// 2) Marks suspicious voice/round-video/video bubbles BEFORE playback with `⚠️` badge + footnote.
/// 3) Suppresses screamer & moan frequencies (`910 Hz` and `3.6 kHz` cut by `-12 dB`) in real-time
///    PCM via `GGAudioEqualizerSetParameters` and automatically restores neutral DSP afterward.
enum GGMediaTokAudioGuard {
    private static let modeKey = "mediatok.audioguard.mode.v1"
    private static let lock = NSLock()
    private static var verdicts: [Int64: GGMediaTokCoreLogic.AudioVerdict] = [:]
    private static var inFlight: Set<Int64> = []
    private static let scanQueue = DispatchQueue(label: "org.mediatok.audioguard.scan", qos: .utility)
    private static var routeObserver: NSObjectProtocol?
    private static var isSuppressionActive = false
    private static var suppressionRestoreWorkItem: DispatchWorkItem?

    /// 0 = Off, 1 = Auto-detect & suppress loud sounds / moans (default ON), 2 = Always suppress on speaker without headphones
    static var mode: Int {
        get {
            if UserDefaults.standard.object(forKey: GGMediaTokAudioGuard.modeKey) == nil {
                return 1
            }
            return UserDefaults.standard.integer(forKey: GGMediaTokAudioGuard.modeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: GGMediaTokAudioGuard.modeKey)
            if newValue == 0 {
                GGMediaTokAudioGuard.restoreNeutralDsp()
            } else if newValue == 2 {
                GGMediaTokAudioGuard.applyDspProtection(forceForFlaggedClip: false)
            } else {
                GGMediaTokAudioGuard.restoreNeutralDsp()
            }
            GGMessageDecorationHooks.redrawAll()
        }
    }

    static var modeLabel: String {
        switch GGMediaTokAudioGuard.mode {
        case 0: return "Выкл."
        case 2: return "Строгий"
        default: return "Авто"
        }
    }

    static func register() {
        GGMessageDecorationHooks.decorations.register({ decoration, context in
            GGMediaTokAudioGuard.decorate(&decoration, message: context.message, context: context.context)
        }, order: 45)

        GGChatScreenHooks.lifecycle.register({ event, _ in
            if case .willDisappear = event, GGMediaTokAudioGuard.mode == 1 {
                GGMediaTokAudioGuard.restoreNeutralDsp()
            }
        }, order: 125)

        GGMediaTokAudioGuard.routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            if GGMediaTokAudioGuard.mode == 2 {
                GGMediaTokAudioGuard.applyDspProtection(forceForFlaggedClip: false)
            }
        }
        if GGMediaTokAudioGuard.mode == 2 {
            GGMediaTokAudioGuard.applyDspProtection(forceForFlaggedClip: false)
        }
    }

    static func isSpeakerOutputWithoutHeadphones() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        for out in outputs {
            if out.portType == .headphones || out.portType == .bluetoothA2DP || out.portType == .bluetoothHFP || out.portType == .bluetoothLE || out.portType == .usbAudio {
                return false
            }
        }
        return true
    }

    static func restoreNeutralDsp() {
        let applyBlock = {
            GGMediaTokAudioGuard.suppressionRestoreWorkItem?.cancel()
            GGMediaTokAudioGuard.suppressionRestoreWorkItem = nil
            guard GGMediaTokAudioGuard.isSuppressionActive else { return }
            let neutral: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0]
            neutral.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    GGAudioEqualizerSetParameters(base, false, false, false)
                }
            }
            GGMediaTokAudioGuard.isSuppressionActive = false
        }
        if Thread.isMainThread {
            applyBlock()
        } else {
            DispatchQueue.main.async(execute: applyBlock)
        }
    }

    static func applyDspProtection(forceForFlaggedClip: Bool) {
        let currentMode = GGMediaTokAudioGuard.mode
        guard currentMode != 0 else {
            GGMediaTokAudioGuard.restoreNeutralDsp()
            return
        }
        let shouldSuppress: Bool
        if currentMode == 2 {
            shouldSuppress = GGMediaTokAudioGuard.isSpeakerOutputWithoutHeadphones() || forceForFlaggedClip
        } else {
            shouldSuppress = forceForFlaggedClip
        }
        guard shouldSuppress else {
            GGMediaTokAudioGuard.restoreNeutralDsp()
            return
        }

        let applyBlock = {
            GGMediaTokAudioGuard.suppressionRestoreWorkItem?.cancel()
            GGMediaTokAudioGuard.suppressionRestoreWorkItem = nil
            GGMediaTokAudioGuard.isSuppressionActive = true
            // 5 bands: 60 Hz, 230 Hz, 910 Hz (moan/scream fundamental), 3.6 kHz (ear-piercing screamer formant), 14 kHz
            let safeGains: [Float] = [-6.0, -5.0, -12.0, -12.0, -9.0]
            safeGains.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    GGAudioEqualizerSetParameters(base, true, true, true)
                }
            }
            if currentMode == 1 {
                let restore = DispatchWorkItem {
                    GGMediaTokAudioGuard.restoreNeutralDsp()
                }
                GGMediaTokAudioGuard.suppressionRestoreWorkItem = restore
                DispatchQueue.main.asyncAfter(deadline: .now() + 45.0, execute: restore)
            }
        }
        if Thread.isMainThread {
            applyBlock()
        } else {
            DispatchQueue.main.async(execute: applyBlock)
        }
    }

    private static func decorate(_ decoration: inout GGMessageDecoration, message: Message, context: AccountContext) {
        let currentMode = GGMediaTokAudioGuard.mode
        guard currentMode != 0 else { return }
        guard let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile else {
            return
        }
        let isAudioOrVideo = file.isVoice || file.isInstantVideo || file.isVideo
        guard isAudioOrVideo else { return }

        let fileId = file.fileId.id
        GGMediaTokAudioGuard.lock.lock()
        let cached = GGMediaTokAudioGuard.verdicts[fileId]
        let alreadyScanning = GGMediaTokAudioGuard.inFlight.contains(fileId)
        GGMediaTokAudioGuard.lock.unlock()

        if let cached {
            GGMediaTokAudioGuard.applyVerdict(cached, to: &decoration)
            return
        }

        guard !alreadyScanning,
              let localPath = context.account.postbox.mediaBox.completedResourcePath(file.resource),
              FileManager.default.fileExists(atPath: localPath) else {
            return
        }

        GGMediaTokAudioGuard.lock.lock()
        GGMediaTokAudioGuard.inFlight.insert(fileId)
        GGMediaTokAudioGuard.lock.unlock()

        let msgId = message.id
        GGMediaTokAudioGuard.scanQueue.async {
            let verdict = GGMediaTokAudioGuard.analyzeAudioFile(at: URL(fileURLWithPath: localPath))
            GGMediaTokAudioGuard.lock.lock()
            if GGMediaTokAudioGuard.verdicts.count > 2048 {
                GGMediaTokAudioGuard.verdicts.removeAll()
            }
            GGMediaTokAudioGuard.verdicts[fileId] = verdict
            GGMediaTokAudioGuard.inFlight.remove(fileId)
            GGMediaTokAudioGuard.lock.unlock()

            if verdict != .clean {
                DispatchQueue.main.async {
                    GGMediaTokAudioGuard.applyDspProtection(forceForFlaggedClip: true)
                    GGMessageDecorationHooks.redraw(messageIds: [msgId])
                }
            }
        }
    }

    private static func applyVerdict(_ verdict: GGMediaTokCoreLogic.AudioVerdict, to decoration: inout GGMessageDecoration) {
        switch verdict {
        case .clean:
            break
        case .loudScreamer:
            let prev = decoration.statusPrefix ?? ""
            if !prev.contains("⚠️") {
                decoration.statusPrefix = "⚠️ СКРИМЕР " + prev
            }
            if decoration.footnote == nil {
                decoration.footnote = GGMessageFootnote(
                    text: "🛡 MediaTok Фильтр: резкий/перегруженный звук (скример)! Громкие частоты приглушены (-12 dB).",
                    entities: [],
                    alpha: 0.92
                )
            }
        case .moanPrank:
            let prev = decoration.statusPrefix ?? ""
            if !prev.contains("⚠️") {
                decoration.statusPrefix = "⚠️ СТОНЫ/ПРАНК " + prev
            }
            if decoration.footnote == nil {
                decoration.footnote = GGMessageFootnote(
                    text: "🛡 MediaTok Фильтр: обнаружены громкие стоны / пранк-звук! Частоты голоса подавлены (-12 dB).",
                    entities: [],
                    alpha: 0.92
                )
            }
        }
    }

    // MARK: - Ogg Opus (Voice Messages) + AVAssetReader (Video Notes & Video)

    private static func analyzeAudioFile(at url: URL) -> GGMediaTokCoreLogic.AudioVerdict {
        let maxSamples16k = 16000 * 15 // inspect up to 15 seconds

        // 1) Try native Ogg Opus decoder first (covers 100% of Telegram voice notes)
        if let opusReader = OggOpusReader(path: url.path) {
            var pcm16k: [Int16] = []
            pcm16k.reserveCapacity(maxSamples16k)
            var buf = [Int16](repeating: 0, count: 4096)
            var stepCounter = 0
            while pcm16k.count < maxSamples16k {
                let readCount: Int32 = buf.withUnsafeMutableBytes { raw in
                    guard let base = raw.baseAddress else { return -1 }
                    return opusReader.read(base, bufSize: 4096)
                }
                if readCount <= 0 {
                    break
                }
                let safeCount = min(Int(readCount), buf.count)
                for idx in 0 ..< safeCount {
                    if stepCounter % 3 == 0 {
                        pcm16k.append(buf[idx])
                        if pcm16k.count >= maxSamples16k {
                            break
                        }
                    }
                    stepCounter += 1
                }
            }
            return GGMediaTokCoreLogic.analyzeAudioPcm16k(pcm16k)
        }

        // 2) Fallback to AVAssetReader for .mp4 round video notes and chat videos
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let tempLink = FileManager.default.temporaryDirectory.appendingPathComponent("mt_scan_\(UInt32.random(in: 0 ... UInt32.max)).mp4")
        defer { try? FileManager.default.removeItem(at: tempLink) }
        var didLinkOrCopy = false
        if (try? FileManager.default.linkItem(at: url, to: tempLink)) != nil {
            didLinkOrCopy = true
        } else if fileSize > 0 && fileSize <= 80 * 1024 * 1024 {
            if (try? FileManager.default.copyItem(at: url, to: tempLink)) != nil {
                didLinkOrCopy = true
            }
        }
        let targetUrl = didLinkOrCopy ? tempLink : url
        let asset = AVURLAsset(url: targetUrl)
        guard let track = asset.tracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else {
            return .clean
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return .clean }
        reader.add(output)
        guard reader.startReading() else { return .clean }

        var samples16k: [Int16] = []
        samples16k.reserveCapacity(maxSamples16k)
        while reader.status == .reading && samples16k.count < maxSamples16k {
            guard let sb = output.copyNextSampleBuffer(),
                  let block = CMSampleBufferGetDataBuffer(sb) else {
                break
            }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / 2
            guard count > 0 else { continue }
            var buf = [Int16](repeating: 0, count: count)
            let status = buf.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            let remaining = maxSamples16k - samples16k.count
            if count <= remaining {
                samples16k.append(contentsOf: buf)
            } else {
                samples16k.append(contentsOf: buf.prefix(remaining))
            }
        }
        reader.cancelReading()
        return GGMediaTokCoreLogic.analyzeAudioPcm16k(samples16k)
    }

    // MARK: - Settings UI

    static func presentSettings(context: GGMenuContext) {
        let cur = GGMediaTokAudioGuard.mode
        let sheet = UIAlertController(
            title: "🛡 Фильтр громких звуков, скримеров и стонов",
            message: "MediaTok сканирует ГС (Opus), кружки и видео на резкие перегрузы (ear-rape/скримеры) и характерные частоты пранк-стонов, предупреждает плашкой ⚠️ под сообщением и автоматически глушит резкие частоты (-12 dB).",
            preferredStyle: .actionSheet
        )
        let options: [(Int, String)] = [
            (1, "Авто-фильтр скримеров и стонов (Рекомендуется)" + (cur == 1 ? " ✓" : "")),
            (2, "Строгий: всегда глушить резкие частоты без наушников" + (cur == 2 ? " ✓" : "")),
            (0, "Выключено" + (cur == 0 ? " ✓" : ""))
        ]
        for (val, title) in options {
            sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
                GGMediaTokAudioGuard.mode = val
                context.presentToast("Фильтр звука: \(GGMediaTokAudioGuard.modeLabel)")
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        context.presentNative(sheet)
    }
}
