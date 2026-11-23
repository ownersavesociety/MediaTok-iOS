import Foundation
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import Display
import ContextUI
import OpusBinding
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

// ============================================================================
// MediaTok Wave 16 — Video & Audio Studio Power Tools:
//   #132 / .cinema        — Night Cinema Mode (OLED dim + reduced white point overlay)
//   #134 / .vbm           — Video Timestamp Bookmarks with notes
//   #355 / .waveform      — Server-visible Waveform Art editor (draw custom voice waveform & send!)
//   #354 / .audiotovoice  — Send any .mp3/.m4a/.wav file from Files as a real Telegram Voice Message
//   #363 / .soundboard    — Built-in PCM-synthesized Soundboard (play live or send as Voice Message)
// ============================================================================

public struct MTVideoBookmarkItem: Codable, Equatable {
    public let id: String
    public let title: String
    public let timecode: String
    public let note: String
    public let createdAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case id, title, timecode, note, createdAt
    }
}

public enum MTMediaTokWave16Tools {
    private static let bookmarksKey = "mediatok.wave16.video_bookmarks.v1"
    private static var nightCinemaWindow: UIWindow?
    private static var activePlayer: AVAudioPlayer?
    private static var activePlaybackDelegate: MTLocalAudioPlaybackDelegate?

    public static func register() {
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave16Tools.interceptCommands(request)
        }, order: 38)
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - Slash Commands

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix(".") else { return false }
        let lower = raw.lowercased()
        let peerId = request.chatLocation.peerId

        if lower == ".cinema" || lower == ".night" || lower == ".dim" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { toggleNightCinemaMode(context: request.context) }
            return true
        }
        if lower == ".vbm" || lower == ".videobookmarks" || lower == ".timecodes" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentVideoBookmarks(context: request.context) }
            return true
        }
        if lower == ".waveform" || lower == ".waveart" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentWaveformArtEditor(context: request.context, peerId: peerId) }
            return true
        }
        if lower == ".audiotovoice" || lower == ".atv" || lower == ".mp3voice" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentAudioToVoicePicker(context: request.context, peerId: peerId) }
            return true
        }
        if lower == ".soundboard" || lower == ".sb" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentSoundboard(context: request.context, peerId: peerId) }
            return true
        }
        return false
    }

    // MARK: - #132 Night Cinema Mode

    public static func toggleNightCinemaMode(context: AccountContext) {
        if let existing = nightCinemaWindow {
            existing.isHidden = true
            nightCinemaWindow = nil
            MTMediaTokWave5Tools.showToast(context: context, text: "Режим «Ночной кинотеатр» выключен")
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }
        let overlay = UIWindow(windowScene: scene)
        overlay.frame = scene.coordinateSpace.bounds
        overlay.windowLevel = .statusBar + 100
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear
        rootVC.view.isUserInteractionEnabled = false
        overlay.rootViewController = rootVC
        overlay.isHidden = false
        nightCinemaWindow = overlay
        MTMediaTokWave5Tools.showToast(context: context, text: "Ночной кинотеатр ВКЛ (снижена точка белого). Выкл: .cinema")
    }

    // MARK: - #134 Video Timestamp Bookmarks

    public static func loadVideoBookmarks() -> [MTVideoBookmarkItem] {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let arr = try? JSONDecoder().decode([MTVideoBookmarkItem].self, from: data) else {
            return []
        }
        return arr
    }

    public static func saveVideoBookmarks(_ items: [MTVideoBookmarkItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }

    public static func presentVideoBookmarks(context: AccountContext) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            MTMediaTokWave5Tools.showToast(context: context, text: "Паник-режим активен: закладки видео скрыты")
            return
        }
        guard let top = topViewController() else { return }
        let vc = MTVideoBookmarksController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #355 Waveform Art Editor

    public static func presentWaveformArtEditor(context: AccountContext, peerId: PeerId?) {
        guard let top = topViewController() else { return }
        let vc = MTWaveformArtController(context: context, peerId: peerId)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #354 Audio File -> Telegram Voice Message

    public static func presentAudioToVoicePicker(context: AccountContext, peerId: PeerId?) {
        guard let top = topViewController() else { return }
        let vc = MTAudioToVoiceController(context: context, peerId: peerId)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #363 Soundboard

    public static func presentSoundboard(context: AccountContext, peerId: PeerId?) {
        guard let top = topViewController() else { return }
        let vc = MTSoundboardController(context: context, peerId: peerId)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - Shared Opus Voice Encoding & Sending Helpers

    public static func pack5BitWaveform(_ levels0To31: [UInt8]) -> Data {
        let count = levels0To31.count
        let totalBits = count * 5
        let byteCount = (totalBits + 7) / 8
        var out = Data(repeating: 0, count: byteCount)
        for i in 0 ..< count {
            let val = UInt32(min(31, levels0To31[i]))
            let bitPos = i * 5
            let byteIdx = bitPos / 8
            let bitOff = bitPos % 8
            out[byteIdx] |= UInt8((val << bitOff) & 0xFF)
            if bitOff > 3 && byteIdx + 1 < byteCount {
                out[byteIdx + 1] |= UInt8((val >> (8 - bitOff)) & 0xFF)
            }
        }
        return out
    }

    public static func compute5BitWaveform(from pcm: [Int16], bars: Int = 100) -> Data {
        guard !pcm.isEmpty else { return pack5BitWaveform([UInt8](repeating: 4, count: bars)) }
        var peaks = [Int32](repeating: 0, count: bars)
        var maxPeak: Int32 = 1
        for i in 0 ..< bars {
            let start = (i * pcm.count) / bars
            let end = max(start + 1, min(pcm.count, ((i + 1) * pcm.count) / bars))
            var local: Int32 = 0
            for j in start ..< end {
                let a = abs(Int32(pcm[j]))
                if a > local { local = a }
            }
            peaks[i] = local
            if local > maxPeak { maxPeak = local }
        }
        let scaled: [UInt8] = peaks.map { p in
            UInt8(min(31, max(1, Int((Double(p) / Double(maxPeak)) * 31.0))))
        }
        return pack5BitWaveform(scaled)
    }

    public static func encodePcm48kToOggOpus(_ mono48k: [Int16]) -> Data? {
        guard !mono48k.isEmpty else { return nil }
        let dataItem = TGDataItem()
        let writer = TGOggOpusWriter()
        guard writer.begin(with: dataItem) else { return nil }

        let frameSize = 960 // 20 ms @ 48 kHz
        var offset = 0
        while offset < mono48k.count {
            let take = min(frameSize, mono48k.count - offset)
            var packet = [Int16](repeating: 0, count: frameSize)
            for i in 0 ..< take {
                packet[i] = mono48k[offset + i]
            }
            let ok = packet.withUnsafeMutableBytes { rawBuf -> Bool in
                guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
                return writer.writeFrame(ptr, frameByteCount: UInt(frameSize * 2))
            }
            if !ok { return nil }
            offset += take
        }
        let _ = writer.writeFrame(nil, frameByteCount: 0)
        guard let ogg = dataItem.data(), !ogg.isEmpty else { return nil }
        return ogg
    }

    public static func sendVoiceMessage(context: AccountContext, peerId: PeerId, oggData: Data, durationSec: Int, waveform: Data) {
        let fileId = Int64.random(in: Int64.min ... Int64.max)
        let resource = LocalFileMediaResource(fileId: fileId, size: Int64(oggData.count), isSecretRelated: false)
        context.account.postbox.mediaBox.storeResourceData(resource.id, data: oggData, synchronous: true)
        let media = TelegramMediaFile(
            fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: fileId),
            partialReference: nil,
            resource: resource,
            previewRepresentations: [],
            videoThumbnails: [],
            immediateThumbnailData: nil,
            mimeType: "audio/ogg",
            size: Int64(oggData.count),
            attributes: [
                .Audio(isVoice: true, duration: max(1, durationSec), title: nil, performer: nil, waveform: waveform)
            ],
            alternativeRepresentations: []
        )
        let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [
            .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        ]).startStandalone()
    }

    public static func playPcm48kLocally(_ mono48k: [Int16]) {
        let wav = makeWavData(from: mono48k, sampleRate: 48000)
        let session = AVAudioSession.sharedInstance()
        let prevCategory = session.category
        let prevMode = session.mode
        let prevOptions = session.categoryOptions
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: wav)
            let delegate = MTLocalAudioPlaybackDelegate(
                previousCategory: prevCategory,
                previousMode: prevMode,
                previousOptions: prevOptions
            ) { finishedPlayer in
                if activePlayer === finishedPlayer {
                    activePlayer = nil
                    activePlaybackDelegate = nil
                }
            }
            player.delegate = delegate
            let _ = player.prepareToPlay()
            let _ = player.play()
            activePlaybackDelegate = delegate
            activePlayer = player
        } catch {
            try? session.setCategory(prevCategory, mode: prevMode, options: prevOptions)
        }
    }

    private static func makeWavData(from pcm: [Int16], sampleRate: UInt32) -> Data {
        let dataSize = UInt32(pcm.count * 2)
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        var chunkSize = (36 + dataSize).littleEndian
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append(contentsOf: "WAVEfmt ".utf8)
        var subchunk1: UInt32 = UInt32(16).littleEndian
        header.append(Data(bytes: &subchunk1, count: 4))
        var audioFmt: UInt16 = UInt16(1).littleEndian
        header.append(Data(bytes: &audioFmt, count: 2))
        var channels: UInt16 = UInt16(1).littleEndian
        header.append(Data(bytes: &channels, count: 2))
        var sr = sampleRate.littleEndian
        header.append(Data(bytes: &sr, count: 4))
        var byteRate = (sampleRate * 2).littleEndian
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign: UInt16 = UInt16(2).littleEndian
        header.append(Data(bytes: &blockAlign, count: 2))
        var bits: UInt16 = UInt16(16).littleEndian
        header.append(Data(bytes: &bits, count: 2))
        header.append(contentsOf: "data".utf8)
        var subchunk2 = dataSize.littleEndian
        header.append(Data(bytes: &subchunk2, count: 4))
        pcm.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                header.append(base.assumingMemoryBound(to: UInt8.self), count: raw.count)
            }
        }
        return header
    }

    public static func synthesizeSoundEffect(id: String) -> [Int16] {
        let sr = 48000.0
        switch id {
        case "vine_boom":
            let count = Int(sr * 1.1)
            return (0 ..< count).map { i in
                let t = Double(i) / sr
                let freq = 95.0 * exp(-t * 3.8) + 32.0
                let env = exp(-t * 2.6)
                let s = tanh(sin(2.0 * .pi * freq * t) * 2.5) * env
                return Int16(max(-1.0, min(1.0, s)) * 30000.0)
            }
        case "airhorn":
            let count = Int(sr * 1.2)
            return (0 ..< count).map { i in
                let t = Double(i) / sr
                let env = min(1.0, t * 25.0) * (t > 0.9 ? max(0.0, (1.2 - t) / 0.3) : 1.0)
                let s = (sin(2.0 * .pi * 440.0 * t) + 0.7 * sin(2.0 * .pi * 554.37 * t) + 0.5 * sin(2.0 * .pi * 659.25 * t) + 0.3 * sin(2.0 * .pi * 880.0 * t)) * 0.35 * env
                return Int16(max(-1.0, min(1.0, s)) * 28000.0)
            }
        case "sad_trombone":
            let notes: [(Double, Double)] = [(293.66, 0.35), (277.18, 0.35), (261.63, 0.35), (246.94, 0.75)]
            var out: [Int16] = []
            for (idx, (f, dur)) in notes.enumerated() {
                let n = Int(sr * dur)
                for i in 0 ..< n {
                    let t = Double(i) / sr
                    let vibrato = (idx == 3) ? (1.0 + 0.025 * sin(2.0 * .pi * 6.0 * t)) : 1.0
                    let env = min(1.0, t * 20.0) * exp(-t * 1.2)
                    let s = (sin(2.0 * .pi * f * vibrato * t) + 0.4 * sin(4.0 * .pi * f * vibrato * t)) * 0.45 * env
                    out.append(Int16(max(-1.0, min(1.0, s)) * 26000.0))
                }
            }
            return out
        case "laser":
            let count = Int(sr * 0.6)
            return (0 ..< count).map { i in
                let t = Double(i) / sr
                let freq = 1800.0 * exp(-t * 6.5) + 120.0
                let env = exp(-t * 4.0)
                let s = sin(2.0 * .pi * freq * t) * env
                return Int16(max(-1.0, min(1.0, s)) * 26000.0)
            }
        case "beep_censor":
            let count = Int(sr * 0.8)
            return (0 ..< count).map { i in
                let t = Double(i) / sr
                let s = sin(2.0 * .pi * 1000.0 * t) * 0.7
                return Int16(max(-1.0, min(1.0, s)) * 26000.0)
            }
        case "icq_uhoh":
            // Classic two-tone "Uh-oh!" synth
            let notes: [(Double, Double)] = [(587.33, 0.16), (0.0, 0.04), (783.99, 0.24)]
            var out: [Int16] = []
            for (f, dur) in notes {
                let n = Int(sr * dur)
                for i in 0 ..< n {
                    if f <= 0.0 {
                        out.append(0)
                    } else {
                        let t = Double(i) / sr
                        let env = min(1.0, t * 40.0) * exp(-t * 6.0)
                        let s = (sin(2.0 * .pi * f * t) + 0.3 * sin(4.0 * .pi * f * t)) * 0.5 * env
                        out.append(Int16(max(-1.0, min(1.0, s)) * 26000.0))
                    }
                }
            }
            return out
        default: // chime
            let count = Int(sr * 0.9)
            return (0 ..< count).map { i in
                let t = Double(i) / sr
                let env = exp(-t * 4.5)
                let s = (sin(2.0 * .pi * 523.25 * t) + 0.6 * sin(2.0 * .pi * 783.99 * t) + 0.4 * sin(2.0 * .pi * 1046.5 * t)) * 0.4 * env
                return Int16(max(-1.0, min(1.0, s)) * 26000.0)
            }
        }
    }
}

private final class MTLocalAudioPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let previousCategory: AVAudioSession.Category
    private let previousMode: AVAudioSession.Mode
    private let previousOptions: AVAudioSession.CategoryOptions
    private let onFinish: (AVAudioPlayer) -> Void

    init(
        previousCategory: AVAudioSession.Category,
        previousMode: AVAudioSession.Mode,
        previousOptions: AVAudioSession.CategoryOptions,
        onFinish: @escaping (AVAudioPlayer) -> Void
    ) {
        self.previousCategory = previousCategory
        self.previousMode = previousMode
        self.previousOptions = previousOptions
        self.onFinish = onFinish
    }

    private func restoreSession(_ player: AVAudioPlayer) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(self.previousCategory, mode: self.previousMode, options: self.previousOptions)
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        self.onFinish(player)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.restoreSession(player)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        self.restoreSession(player)
    }
}

// MARK: - #134 Video Timestamp Bookmarks Controller

private final class MTVideoBookmarksController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private var items: [MTVideoBookmarkItem] = MTMediaTokWave16Tools.loadVideoBookmarks()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Таймкоды-закладки видео"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.frame = self.view.bounds
        self.tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(self.tableView)
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }

    @objc private func addTapped() {
        let alert = UIAlertController(title: "Новый таймкод", message: "Сохраните момент видео с заметкой", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Название видео / канала" }
        alert.addTextField { $0.placeholder = "Таймкод (например 14:25)" }
        alert.addTextField { $0.placeholder = "Заметка к моменту" }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak self] _ in
            guard let self else { return }
            let title = (alert.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let tc = (alert.textFields?[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (alert.textFields?[2].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tc.isEmpty else { return }
            let item = MTVideoBookmarkItem(
                id: UUID().uuidString,
                title: title.isEmpty ? "Видео" : title,
                timecode: tc,
                note: note.isEmpty ? "Закладка" : note,
                createdAt: Date().timeIntervalSince1970
            )
            self.items.insert(item, at: 0)
            MTMediaTokWave16Tools.saveVideoBookmarks(self.items)
            self.tableView.reloadData()
        })
        self.present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "vbmCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "vbmCell")
        let item = self.items[indexPath.row]
        cell.textLabel?.text = "\(item.timecode) · \(item.title)"
        cell.detailTextLabel?.text = item.note
        cell.imageView?.image = UIImage(systemName: "bookmark.fill")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = self.items[indexPath.row]
        UIPasteboard.general.string = "\(item.timecode) — \(item.title): \(item.note)"
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Таймкод \(item.timecode) скопирован")
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            self.items.remove(at: indexPath.row)
            MTMediaTokWave16Tools.saveVideoBookmarks(self.items)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
}

// MARK: - #355 Waveform Art Editor Controller

private final class MTWaveformCanvasView: UIView {
    var bars: [UInt8] = (0 ..< 64).map { i in
        UInt8(max(2, min(31, Int(16.0 + 14.0 * sin(Double(i) * 0.25)))))
    } {
        didSet { self.setNeedsDisplay() }
    }
    private var lastTouchBarIndex: Int?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), !self.bars.isEmpty else { return }
        ctx.setFillColor(UIColor.secondarySystemGroupedBackground.cgColor)
        ctx.fill(rect)

        let step = rect.width / CGFloat(self.bars.count)
        let barW = max(2.0, step * 0.65)
        for (i, level) in self.bars.enumerated() {
            let norm = CGFloat(level) / 31.0
            let h = max(4.0, norm * (rect.height - 20.0))
            let x = CGFloat(i) * step + (step - barW) * 0.5
            let y = (rect.height - h) * 0.5
            let path = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: barW, height: h), cornerRadius: barW * 0.5)
            UIColor.systemBlue.setFill()
            path.fill()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.lastTouchBarIndex = nil
        self.updateTouch(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.updateTouch(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.lastTouchBarIndex = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.lastTouchBarIndex = nil
    }

    private func updateTouch(_ touches: Set<UITouch>) {
        guard let pt = touches.first?.location(in: self), self.bounds.width > 0, self.bounds.height > 0 else { return }
        let idx = max(0, min(self.bars.count - 1, Int((pt.x / self.bounds.width) * CGFloat(self.bars.count))))
        let distFromMid = abs(pt.y - self.bounds.height * 0.5) / (self.bounds.height * 0.5)
        let val = UInt8(max(1, min(31, Int(distFromMid * 31.0))))
        if let prevIdx = self.lastTouchBarIndex, prevIdx != idx {
            let prevVal = self.bars[prevIdx]
            let steps = abs(idx - prevIdx)
            let dir = idx > prevIdx ? 1 : -1
            for s in 1 ... steps {
                let k = prevIdx + s * dir
                let frac = Double(s) / Double(steps)
                let interp = Double(prevVal) * (1.0 - frac) + Double(val) * frac
                self.bars[k] = UInt8(max(1, min(31, Int(interp.rounded()))))
            }
        } else {
            self.bars[idx] = val
        }
        self.lastTouchBarIndex = idx
    }
}

private final class MTWaveformArtController: UIViewController {
    private let context: AccountContext
    private let peerId: PeerId?
    private let canvas = MTWaveformCanvasView()
    private let presetSegment = UISegmentedControl(items: ["Синус", "Пила", "Сердце", "Горы", "Флэт"])
    private let sendButton = UIButton(type: .system)

    init(context: AccountContext, peerId: PeerId?) {
        self.context = context
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Waveform Art (Волна ГС)"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        let hint = UILabel()
        hint.text = self.peerId == nil
            ? "Рисуйте форму волны пальцем — перед отправкой подтвердите сохранение в «Избранное»."
            : "Рисуйте пальцем форму волны прямо по графику — она будет видна всем в Telegram!"
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0
        hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false

        self.canvas.layer.cornerRadius = 16
        self.canvas.clipsToBounds = true
        self.canvas.translatesAutoresizingMaskIntoConstraints = false

        self.presetSegment.selectedSegmentIndex = 0
        self.presetSegment.addTarget(self, action: #selector(presetChanged), for: .valueChanged)
        self.presetSegment.translatesAutoresizingMaskIntoConstraints = false

        var cfg = UIButton.Configuration.filled()
        cfg.title = self.peerId == nil ? "Сохранить в Избранное (как ГС)" : "Отправить голосовое с этой волной"
        cfg.image = UIImage(systemName: "waveform.path")
        cfg.imagePadding = 8
        cfg.cornerStyle = .large
        self.sendButton.configuration = cfg
        self.sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        self.sendButton.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(hint)
        self.view.addSubview(self.canvas)
        self.view.addSubview(self.presetSegment)
        self.view.addSubview(self.sendButton)

        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 14),
            hint.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.canvas.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 16),
            self.canvas.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.canvas.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.canvas.heightAnchor.constraint(equalToConstant: 200),

            self.presetSegment.topAnchor.constraint(equalTo: self.canvas.bottomAnchor, constant: 16),
            self.presetSegment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.presetSegment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.sendButton.topAnchor.constraint(equalTo: self.presetSegment.bottomAnchor, constant: 20),
            self.sendButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.sendButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.sendButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func presetChanged() {
        let n = 64
        switch self.presetSegment.selectedSegmentIndex {
        case 1: // Sawtooth
            self.canvas.bars = (0 ..< n).map { UInt8(max(2, ($0 % 16) * 2)) }
        case 2: // Heart pulse
            self.canvas.bars = (0 ..< n).map { i in
                let x = Double(i) / Double(n - 1)
                if abs(x - 0.35) < 0.05 || abs(x - 0.65) < 0.05 { return 31 }
                if abs(x - 0.5) < 0.06 { return 18 }
                return 6
            }
        case 3: // Mountains
            self.canvas.bars = (0 ..< n).map { i in
                let half = n / 2
                let d = abs(i - half)
                return UInt8(max(2, 31 - d))
            }
        case 4: // Flat line
            self.canvas.bars = [UInt8](repeating: 15, count: n)
        default: // Sine
            self.canvas.bars = (0 ..< n).map { i in
                UInt8(max(2, min(31, Int(16.0 + 14.0 * sin(Double(i) * 0.25)))))
            }
        }
    }

    @objc private func sendTapped() {
        let customWave = MTMediaTokWave16Tools.pack5BitWaveform(self.canvas.bars)
        let pcm = MTMediaTokWave16Tools.synthesizeSoundEffect(id: "chime")
        guard let ogg = MTMediaTokWave16Tools.encodePcm48kToOggOpus(pcm) else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Ошибка кодирования Ogg/Opus")
            return
        }
        let durationSec = max(1, Int((Double(pcm.count) / 48000.0).rounded()))
        if let targetPeer = self.peerId {
            MTMediaTokWave16Tools.sendVoiceMessage(context: self.context, peerId: targetPeer, oggData: ogg, durationSec: durationSec, waveform: customWave)
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Голосовое с кастомной волной отправлено!")
            self.dismiss(animated: true)
        } else {
            let confirm = UIAlertController(
                title: "Сохранить в Избранное?",
                message: "Редактор открыт из Палитры команд (вне чата). Отправить голосовое с кастомной волной в «Избранное»?",
                preferredStyle: .alert
            )
            confirm.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            confirm.addAction(UIAlertAction(title: "Сохранить в Избранное", style: .default) { [weak self] _ in
                guard let self else { return }
                MTMediaTokWave16Tools.sendVoiceMessage(context: self.context, peerId: self.context.account.peerId, oggData: ogg, durationSec: durationSec, waveform: customWave)
                MTMediaTokWave5Tools.showToast(context: self.context, text: "Голосовое сохранено в Избранное!")
                self.dismiss(animated: true)
            })
            self.present(confirm, animated: true)
        }
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #354 Audio File -> Telegram Voice Message Controller

private final class MTAudioToVoiceController: UIViewController, UIDocumentPickerDelegate {
    private let context: AccountContext
    private let peerId: PeerId?
    private let statusLabel = UILabel()
    private let pickButton = UIButton(type: .system)

    init(context: AccountContext, peerId: PeerId?) {
        self.context = context
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Аудио → Голосовое (Оgg)"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.statusLabel.text = self.peerId == nil
            ? "Режим без чата: выберите .mp3 / .m4a / .wav — после подтверждения голосовое будет сохранено в «Избранное»."
            : "Выберите любой .mp3 / .m4a / .wav файл — он будет перекодирован в 48 кГц Ogg/Opus с реальной волной и отправлен как голосовое."
        self.statusLabel.font = .systemFont(ofSize: 14)
        self.statusLabel.textColor = .secondaryLabel
        self.statusLabel.numberOfLines = 0
        self.statusLabel.textAlignment = .center
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        var cfg = UIButton.Configuration.filled()
        cfg.title = "Выбрать аудиофайл из Файлов"
        cfg.image = UIImage(systemName: "doc.badge.plus")
        cfg.imagePadding = 8
        cfg.cornerStyle = .large
        self.pickButton.configuration = cfg
        self.pickButton.addTarget(self, action: #selector(pickTapped), for: .touchUpInside)
        self.pickButton.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.statusLabel)
        self.view.addSubview(self.pickButton)

        NSLayoutConstraint.activate([
            self.statusLabel.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: -40),
            self.statusLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
            self.statusLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24),

            self.pickButton.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 24),
            self.pickButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
            self.pickButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24),
            self.pickButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    @objc private func pickTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.audio])
        picker.delegate = self
        self.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        self.pickButton.isEnabled = false
        self.statusLabel.text = "Кодирую \(url.lastPathComponent) в Telegram Ogg/Opus..."
        let ctx = self.context
        let targetPeer = self.peerId

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let file = try AVAudioFile(forReading: url)
                let srcFormat = file.processingFormat
                let srcSampleRate = srcFormat.sampleRate
                let nCh = Int(srcFormat.channelCount)
                guard srcSampleRate > 0, nCh > 0 else {
                    throw NSError(domain: "MediaTok", code: 2, userInfo: [NSLocalizedDescriptionKey: "Неподдерживаемый формат аудио"])
                }
                let maxSrcFrames = Int64(srcSampleRate * 300.0)
                let targetMaxFrames = file.length > 0 ? min(file.length, maxSrcFrames) : maxSrcFrames
                guard targetMaxFrames > 0 else {
                    throw NSError(domain: "MediaTok", code: 4, userInfo: [NSLocalizedDescriptionKey: "Аудиофайл пуст"])
                }

                let chunkCapacity: AVAudioFrameCount = 4096
                guard let buf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: chunkCapacity) else {
                    throw NSError(domain: "MediaTok", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось выделить аудио буфер"])
                }

                var mono48k: [Int16] = []
                if file.length > 0 {
                    let estOut = Int(Double(targetMaxFrames) * (48000.0 / srcSampleRate)) + 16
                    mono48k.reserveCapacity(min(estOut, 48000 * 300))
                }

                let step = srcSampleRate / 48000.0
                let invCh = 1.0 / Float(nCh)
                var totalRead: Int64 = 0
                var srcPos: Double = 0.0
                var prevSample: Float = 0.0
                var hasPrev = false
                var chunkMono = [Float](repeating: 0.0, count: Int(chunkCapacity))

                while totalRead < targetMaxFrames {
                    let remaining = targetMaxFrames - totalRead
                    let framesToRead = AVAudioFrameCount(min(Int64(chunkCapacity), remaining))
                    buf.frameLength = 0
                    try file.read(into: buf, frameCount: framesToRead)
                    let nFrames = Int(buf.frameLength)
                    if nFrames <= 0 { break }
                    guard let chData = buf.floatChannelData else {
                        throw NSError(domain: "MediaTok", code: 2, userInfo: [NSLocalizedDescriptionKey: "Неподдерживаемый формат аудио"])
                    }
                    for f in 0 ..< nFrames {
                        var sum: Float = 0.0
                        for c in 0 ..< nCh {
                            sum += chData[c][f]
                        }
                        chunkMono[f] = sum * invCh
                    }
                    let limit = Double(nFrames - 1)
                    while srcPos < limit {
                        let sample: Float
                        if srcPos < 0.0 {
                            let frac = Float(srcPos + 1.0)
                            sample = prevSample * (1.0 - frac) + chunkMono[0] * frac
                        } else {
                            let i0 = Int(srcPos)
                            let i1 = i0 + 1
                            let frac = Float(srcPos - Double(i0))
                            sample = chunkMono[i0] * (1.0 - frac) + chunkMono[i1] * frac
                        }
                        let clamped = max(-1.0, min(1.0, sample))
                        mono48k.append(Int16(clamped * 32767.0))
                        srcPos += step
                    }
                    prevSample = chunkMono[nFrames - 1]
                    hasPrev = true
                    srcPos -= Double(nFrames)
                    totalRead += Int64(nFrames)
                }

                if hasPrev && srcPos < 0.0 {
                    let clamped = max(-1.0, min(1.0, prevSample))
                    mono48k.append(Int16(clamped * 32767.0))
                }

                guard !mono48k.isEmpty else {
                    throw NSError(domain: "MediaTok", code: 4, userInfo: [NSLocalizedDescriptionKey: "Аудиофайл не содержит аудиосэмплов"])
                }
                guard let ogg = MTMediaTokWave16Tools.encodePcm48kToOggOpus(mono48k) else {
                    throw NSError(domain: "MediaTok", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ошибка кодирования Ogg/Opus"])
                }
                let wave = MTMediaTokWave16Tools.compute5BitWaveform(from: mono48k)
                let dur = max(1, Int((Double(mono48k.count) / 48000.0).rounded()))
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if let targetPeer {
                        MTMediaTokWave16Tools.sendVoiceMessage(context: ctx, peerId: targetPeer, oggData: ogg, durationSec: dur, waveform: wave)
                        MTMediaTokWave5Tools.showToast(context: ctx, text: "Аудио отправлено как голосовое (\(dur) сек)!")
                        self.dismiss(animated: true)
                    } else {
                        self.pickButton.isEnabled = true
                        self.statusLabel.text = "Готово (\(dur) сек). Подтвердите отправку в «Избранное»."
                        let confirm = UIAlertController(
                            title: "Сохранить в Избранное?",
                            message: "Файл перекодирован в ГС (\(dur) сек). Сохранить в «Избранное»?",
                            preferredStyle: .alert
                        )
                        confirm.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                        confirm.addAction(UIAlertAction(title: "Сохранить в Избранное", style: .default) { [weak self] _ in
                            MTMediaTokWave16Tools.sendVoiceMessage(context: ctx, peerId: ctx.account.peerId, oggData: ogg, durationSec: dur, waveform: wave)
                            MTMediaTokWave5Tools.showToast(context: ctx, text: "Голосовое сохранено в Избранное (\(dur) сек)!")
                            self?.dismiss(animated: true)
                        })
                        self.present(confirm, animated: true)
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.pickButton.isEnabled = true
                    self?.statusLabel.text = "Ошибка: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #363 Soundboard Controller

private final class MTSoundboardController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private struct PadItem {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
    }

    private let context: AccountContext
    private let peerId: PeerId?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let pads: [PadItem] = [
        PadItem(id: "vine_boom", title: "Vine Boom (Бас-удар)", subtitle: "Мощный кинематографический бум", icon: "speaker.wave.3.fill"),
        PadItem(id: "airhorn", title: "Airhorn (Мемный гудок)", subtitle: "Классический MLG сигнал", icon: "megaphone.fill"),
        PadItem(id: "sad_trombone", title: "Sad Trombone (Грустный тромбон)", subtitle: "Ва-ва-ва-ваааа", icon: "music.note"),
        PadItem(id: "laser", title: "Sci-Fi Laser (Лазер)", subtitle: "Футуристический выстрел", icon: "bolt.fill"),
        PadItem(id: "beep_censor", title: "Цензура (Бип 1 кГц)", subtitle: "Телевизионный писк", icon: "exclamationmark.triangle.fill"),
        PadItem(id: "chime", title: "Приятный звонок", subtitle: "Чистый аккорд уведомления", icon: "bell.fill")
    ]

    init(context: AccountContext, peerId: PeerId?) {
        self.context = context
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Саундпад (Soundboard)"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.frame = self.view.bounds
        self.tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(self.tableView)
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.pads.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "sbCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "sbCell")
        let pad = self.pads[indexPath.row]
        cell.textLabel?.text = pad.title
        cell.detailTextLabel?.text = pad.subtitle
        cell.imageView?.image = UIImage(systemName: pad.icon)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let pad = self.pads[indexPath.row]
        let pcm = MTMediaTokWave16Tools.synthesizeSoundEffect(id: pad.id)
        MTMediaTokWave16Tools.playPcm48kLocally(pcm)

        let isFallbackSaved = (self.peerId == nil)
        let alert = UIAlertController(
            title: pad.title,
            message: isFallbackSaved ? "Воспроизведено! Сохранить этот звук в «Избранное» как голосовое?" : "Воспроизведено! Отправить этот звук голосовым в чат?",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: isFallbackSaved ? "Сохранить в Избранное (как ГС)" : "Отправить как голосовое в чат", style: .default) { [weak self] _ in
            guard let self else { return }
            guard let ogg = MTMediaTokWave16Tools.encodePcm48kToOggOpus(pcm) else { return }
            let wave = MTMediaTokWave16Tools.compute5BitWaveform(from: pcm)
            let target = self.peerId ?? self.context.account.peerId
            let durationSec = max(1, Int((Double(pcm.count) / 48000.0).rounded()))
            MTMediaTokWave16Tools.sendVoiceMessage(context: self.context, peerId: target, oggData: ogg, durationSec: durationSec, waveform: wave)
            MTMediaTokWave5Tools.showToast(
                context: self.context,
                text: isFallbackSaved ? "Звук «\(pad.title)» сохранён в Избранное!" : "Звук «\(pad.title)» отправлен голосовым!"
            )
        })
        alert.addAction(UIAlertAction(title: "Проиграть ещё раз", style: .default) { _ in
            MTMediaTokWave16Tools.playPcm48kLocally(pcm)
        })
        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        if let pop = alert.popoverPresentationController, let cell = tableView.cellForRow(at: indexPath) {
            pop.sourceView = cell
            pop.sourceRect = cell.bounds
        }
        self.present(alert, animated: true)
    }
}
