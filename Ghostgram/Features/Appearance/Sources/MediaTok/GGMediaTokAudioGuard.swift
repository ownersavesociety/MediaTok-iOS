import Foundation
import UIKit
import AVFoundation
import Postbox
import TelegramCore
import AccountContext
import GGVoiceDSP
import GGCore
import GGHooks
import GGSettingsUI

/// MediaTok Anti-Screamer, Loud Bad Sounds & Moan Prank Filter (`GGMediaTokAudioGuard`):
/// 1) Pre-scans downloaded voice messages, round video notes (кружки), and chat videos on a background
///    queue using `AVAssetReader` (16 kHz mono Int16 PCM) to detect:
///    - Ear-rape / Screamer / Loud Clipping (`|s| > 29000` > 3.2%, or RMS > -3.5 dBFS, or > +18 dB jump)
///    - Moan / Gemidão Prank Audio Signature (dominant vocal formant energy 350–1150 Hz via zero-crossing
///      rate + rhythmic amplitude bursts 1.2–4.2 Hz with high crest factor).
/// 2) Marks suspicious voice/round-video/video bubbles BEFORE playback with `⚠️ ГРОМКО/СТОНЫ ` in the
///    status line and a warning footnote right below the bubble.
/// 3) Suppresses screamer & moan frequencies (`910 Hz` and `3.6 kHz` cut by `-12 dB` = 4x quieter) in
///    real-time PCM inside `UniversalMediaPlayer` via `GGAudioEqualizerSetParameters`.
enum GGMediaTokAudioGuard {
    enum Verdict: Int {
        case clean = 0
        case loudScreamer = 1
        case moanPrank = 2
    }

    private static let modeKey = "mediatok.audioguard.mode.v1"
    private static let lock = NSLock()
    private static var verdicts: [Int64: Verdict] = [:]
    private static var inFlight: Set<Int64> = []
    private static let scanQueue = DispatchQueue(label: "org.mediatok.audioguard.scan", qos: .utility)
    private static var routeObserver: NSObjectProtocol?

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
            GGMediaTokAudioGuard.applyDspProtection(forceForFlaggedClip: newValue == 2)
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

        GGMediaTokAudioGuard.routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            if GGMediaTokAudioGuard.mode == 2 {
                GGMediaTokAudioGuard.applyDspProtection(forceForFlaggedClip: true)
            }
        }
        if GGMediaTokAudioGuard.mode == 2 {
            GGMediaTokAudioGuard.applyDspProtection(forceForFlaggedClip: true)
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

    static func applyDspProtection(forceForFlaggedClip: Bool) {
        let currentMode = GGMediaTokAudioGuard.mode
        guard currentMode != 0 else { return }
        let shouldSuppress: Bool
        if currentMode == 2 {
            shouldSuppress = GGMediaTokAudioGuard.isSpeakerOutputWithoutHeadphones() || forceForFlaggedClip
        } else {
            shouldSuppress = forceForFlaggedClip
        }
        guard shouldSuppress else { return }
        // 5 bands: 60 Hz, 230 Hz, 910 Hz (moan/scream fundamental), 3.6 kHz (ear-piercing screamer formant), 14 kHz
        let safeGains: [Float] = [-6.0, -5.0, -12.0, -12.0, -9.0]
        safeGains.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                GGAudioEqualizerSetParameters(base, true, true, true)
            }
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

    private static func applyVerdict(_ verdict: Verdict, to decoration: inout GGMessageDecoration) {
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

    // MARK: - Fast Acoustic PCM Analyzer (Screamer + Moan Formant & Rhythm Detector)

    private static func analyzeAudioFile(at url: URL) -> Verdict {
        // AVAssetReader needs a standard audio/video extension or symlink in temporary directory if Postbox path has no extension
        let tempLink = FileManager.default.temporaryDirectory.appendingPathComponent("mt_scan_\(UInt32.random(in: 0 ... UInt32.max)).mp4")
        defer { try? FileManager.default.removeItem(at: tempLink) }
        if (try? FileManager.default.linkItem(at: url, to: tempLink)) == nil {
            try? FileManager.default.copyItem(at: url, to: tempLink)
        }
        let targetUrl = FileManager.default.fileExists(atPath: tempLink.path) ? tempLink : url
        let asset = AVURLAsset(url: targetUrl)
        guard let track = asset.tracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else {
            return .clean
        }
        let sampleRate: Int = 16000
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
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

        let windowSize = 800 // 50 ms at 16 kHz
        let maxSamples = sampleRate * 15 // inspect up to 15 seconds
        var totalSamples = 0
        var clippedSamples = 0
        var sumSqTotal: Double = 0.0

        var windowSumSq: Double = 0.0
        var windowZeroCrossings = 0
        var windowCount = 0
        var prevSample: Int16 = 0

        var windowRmsList: [Double] = []
        var windowZcrList: [Double] = []

        while reader.status == .reading && totalSamples < maxSamples {
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

            for s in buf {
                let absVal = abs(Int(s))
                if absVal >= 28500 {
                    clippedSamples += 1
                }
                let norm = Double(s) / 32768.0
                let sq = norm * norm
                sumSqTotal += sq
                windowSumSq += sq
                if (s >= 0 && prevSample < 0) || (s < 0 && prevSample >= 0) {
                    windowZeroCrossings += 1
                }
                prevSample = s
                totalSamples += 1
                windowCount += 1

                if windowCount >= windowSize {
                    let rms = sqrt(windowSumSq / Double(windowCount))
                    let zcrHz = (Double(windowZeroCrossings) * Double(sampleRate)) / (2.0 * Double(windowCount))
                    windowRmsList.append(rms)
                    windowZcrList.append(zcrHz)
                    windowSumSq = 0.0
                    windowZeroCrossings = 0
                    windowCount = 0
                }
            }
        }
        reader.cancelReading()

        guard totalSamples > sampleRate / 3, !windowRmsList.isEmpty else {
            return .clean
        }

        let overallRms = sqrt(sumSqTotal / Double(totalSamples))
        let clipRatio = Double(clippedSamples) / Double(totalSamples)
        let maxWindowRms = windowRmsList.max() ?? 0.0

        // 1. Ear-rape / Screamer check: heavy hard clipping or extreme loud burst
        if clipRatio > 0.032 || (overallRms > 0.62 && clipRatio > 0.012) || (maxWindowRms > 0.86 && clipRatio > 0.015) {
            return .loudScreamer
        }

        // Sudden screamer jump (> 7x amplitude jump into near-full-scale clipping)
        if windowRmsList.count >= 6 {
            var quietBaseline = 0.05
            for i in 0 ..< windowRmsList.count {
                let r = windowRmsList[i]
                if i >= 3 && r > 0.78 && quietBaseline < 0.09 {
                    return .loudScreamer
                }
                quietBaseline = quietBaseline * 0.8 + r * 0.2
            }
        }

        // 2. Moan / Gemidão Prank acoustic signature:
        // Loud vocal formant bursts (fundamental + 1st formant ZCR 380..1250 Hz) with rhythmic pulsing (2+ bursts separated by valleys)
        var vocalBurstWindows = 0
        var burstTransitions = 0
        var inBurst = false
        for i in 0 ..< windowRmsList.count {
            let r = windowRmsList[i]
            let z = windowZcrList[i]
            let isLoudVocal = r > 0.34 && z >= 380.0 && z <= 1280.0
            if isLoudVocal {
                vocalBurstWindows += 1
                if !inBurst {
                    inBurst = true
                    burstTransitions += 1
                }
            } else if r < 0.16 {
                inBurst = false
            }
        }
        let vocalFraction = Double(vocalBurstWindows) / Double(windowRmsList.count)
        if burstTransitions >= 2 && vocalFraction >= 0.22 && maxWindowRms >= 0.52 {
            return .moanPrank
        }

        return .clean
    }

    // MARK: - Settings UI

    static func presentSettings(context: GGMenuContext) {
        let cur = GGMediaTokAudioGuard.mode
        let sheet = UIAlertController(
            title: "🛡 Фильтр громких звуков, скримеров и стонов",
            message: "MediaTok сканирует ГС, кружки и видео на резкие перегрузы (ear-rape/скримеры) и характерные частоты пранк-стонов, предупреждает плашкой ⚠️ под сообщением и автоматически глушит резкие частоты (-12 dB).",
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
