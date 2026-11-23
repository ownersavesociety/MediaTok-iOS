import Foundation
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import Security
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import Display
import UndoUI
import LegacyComponents
import OpusBinding
import UniversalMediaPlayer
import MTCore
import MTHooks
import MTSettingsUI
import MTFeaturesShared
import MTVoiceTranscription

// MARK: - Fish Audio Voice Model & Keychain Storage

public struct MTFishAudioVoiceItem: Codable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let isMine: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case isMine
    }

    public init(id: String, title: String, subtitle: String, isMine: Bool) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isMine = isMine
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.subtitle = (try? c.decode(String.self, forKey: .subtitle)) ?? ""
        self.isMine = (try? c.decode(Bool.self, forKey: .isMine)) ?? false
    }
}

public enum MTFishAudioError: LocalizedError {
    case missingApiKey
    case missingVoiceSelection
    case audioDecodeFailed
    case speechNotRecognized(String)
    case networkError(String)
    case opusEncodeFailed

    public var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Укажи API-ключ Fish Audio в настройках «Голос › AI Клон голоса (Fish Audio)»."
        case .missingVoiceSelection:
            return "Сначала выбери или клонируй голос персонажа в студии Fish Audio."
        case .audioDecodeFailed:
            return "Не удалось декодировать аудиофайл образца (.ogg / .wav / .mp3 / .mp4)."
        case let .speechNotRecognized(reason):
            return "Не удалось распознать речь для озвучки (\(reason))."
        case let .networkError(msg):
            return "Ошибка Fish Audio API: \(msg)"
        case .opusEncodeFailed:
            return "Не удалось закодировать ответ в голосовой формат Telegram Ogg/Opus."
        }
    }
}

public enum MTFishAudioClone {
    private static let keychainService = "org.mediatok.fishaudio.v1"
    private static let keychainAccount = "api_key"
    private static let savedVoicesDefaultsKey = "mediatok.fishaudio.saved_voices.v1"
    private static let activeTransformsLock = NSLock()
    private static var activeTransformDisposables: [UUID: Disposable] = [:]

    public static let availableModels: [(id: String, title: String)] = [
        ("s2-pro", "s2-pro"),
        ("speech-1.6", "speech-1.6"),
        ("speech-1.5", "speech-1.5")
    ]

    public static func register() {
        MTLifecycleHooks.openURL.register({ url, context, _ in
            guard url.scheme?.lowercased() == "mediatok",
                  url.host?.lowercased() == "fishaudio" else {
                return false
            }
            MTFishAudioClone.presentStudio(context: context)
            return true
        }, order: 120)

        MTVoiceRecordingHooks.transformRecordedVoice.register({ oggData, interfaceLanguage, completion in
            guard MTVoiceRecordingHooks.isFishAudioCloneActive else {
                return false
            }
            MTFishAudioClone.transformRecordedVoiceOgg(
                oggData: oggData,
                interfaceLanguage: interfaceLanguage,
                completion: completion
            )
            return true
        }, order: 100)
    }

    public static func presentStudio(context: AccountContext, from hostController: UIViewController? = nil) {
        let vc = MTFishAudioStudioController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if let hostController {
            MTModalPresenter.presentWhenReady(nav, from: hostController)
        } else {
            MTModalPresenter.presentOnTopmost(nav)
        }
    }

    // MARK: - Keychain API Key

    public static var apiKey: String {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: self.keychainService,
                kSecAttrAccount as String: self.keychainAccount,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess,
                  let data = item as? Data,
                  let str = String(data: data, encoding: .utf8) else {
                return ""
            }
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: self.keychainService,
                kSecAttrAccount as String: self.keychainAccount
            ]
            let _ = SecItemDelete(baseQuery as CFDictionary)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
                return
            }
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let _ = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    // MARK: - Saved Voices

    public static var savedVoices: [MTFishAudioVoiceItem] {
        get {
            guard let data = UserDefaults.standard.data(forKey: self.savedVoicesDefaultsKey),
                  let decoded = try? JSONDecoder().decode([MTFishAudioVoiceItem].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: self.savedVoicesDefaultsKey)
            }
        }
    }

    public static func upsertSavedVoice(_ item: MTFishAudioVoiceItem) {
        var list = self.savedVoices
        list.removeAll { $0.id == item.id }
        list.insert(item, at: 0)
        self.savedVoices = list
    }

    public static func removeSavedVoice(id: String) {
        var list = self.savedVoices
        list.removeAll { $0.id == id }
        self.savedVoices = list
        if MTVoiceSettings.fishAudioReferenceId.value == id {
            MTVoiceSettings.fishAudioReferenceId.set("")
            MTVoiceSettings.fishAudioReferenceTitle.set("")
            MTVoiceSettings.fishAudioAutoReplace.set(false)
        }
    }

    public static func selectVoice(_ item: MTFishAudioVoiceItem) {
        MTVoiceSettings.fishAudioReferenceId.set(item.id)
        MTVoiceSettings.fishAudioReferenceTitle.set(item.title)
        self.upsertSavedVoice(item)
    }

    // MARK: - Audio Conversion (.ogg / .opus / .mp4 / .mp3 / .m4a -> 24 kHz 16-bit RIFF WAV)

    public static func decodeAnyMediaFileToWav(url: URL, maxSeconds: Double = 45.0) throws -> Data {
        // Primary path: FFmpeg SoftwareAudioSource handles Telegram .ogg/.opus/.oga + .mp4/.mov/.mp3/.m4a/.wav cleanly at 48 kHz mono Int16.
        let source = SoftwareAudioSource(path: url.path)
        if source.hasStream {
            let maxSamples48k = Int(maxSeconds * 48000.0)
            var samples24k: [Int16] = []
            samples24k.reserveCapacity(min(maxSamples48k / 2, 24000 * 30))
            var totalRead48k = 0
            while totalRead48k < maxSamples48k, let frame = source.readFrame() {
                let count = frame.count / 2
                if count <= 0 { continue }
                frame.withUnsafeBytes { raw in
                    guard let ptr = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
                    let limit = min(count, maxSamples48k - totalRead48k)
                    var idx = 0
                    while idx + 1 < limit {
                        let avg = (Int32(ptr[idx]) + Int32(ptr[idx + 1])) / 2
                        samples24k.append(Int16(clamping: avg))
                        idx += 2
                    }
                }
                totalRead48k += count
            }
            if samples24k.count >= 2400 {
                return Self.buildRiffWavData(samples: samples24k, sampleRate: 24000)
            }
        }

        // Secondary fallback: AVAudioFile
        guard let audioFile = try? AVAudioFile(forReading: url), audioFile.length > 0 else {
            throw MTFishAudioError.audioDecodeFailed
        }
        let srcFmt = audioFile.processingFormat
        let maxFrames = AVAudioFrameCount(min(Double(audioFile.length), maxSeconds * srcFmt.sampleRate))
        guard maxFrames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: maxFrames),
              (try? audioFile.read(into: buf, frameCount: maxFrames)) != nil,
              let chData = buf.floatChannelData else {
            throw MTFishAudioError.audioDecodeFailed
        }
        let nFrames = Int(buf.frameLength)
        let nCh = Int(srcFmt.channelCount)
        guard nFrames > 0, nCh > 0 else {
            throw MTFishAudioError.audioDecodeFailed
        }
        let targetRate: Double = 24000.0
        let outCount = max(1, Int((Double(nFrames) * targetRate / max(1.0, srcFmt.sampleRate)).rounded()))
        var pcm = [Int16](repeating: 0, count: outCount)
        let step = Double(nFrames - 1) / Double(max(1, outCount - 1))
        for i in 0 ..< outCount {
            let pos = Double(i) * step
            let i0 = min(nFrames - 1, max(0, Int(pos)))
            let i1 = min(nFrames - 1, i0 + 1)
            let frac = Float(pos - Double(i0))
            var s0: Float = 0
            var s1: Float = 0
            for c in 0 ..< nCh {
                s0 += chData[c][i0]
                s1 += chData[c][i1]
            }
            let invCh = 1.0 / Float(nCh)
            let sample = (s0 * (1.0 - frac) + s1 * frac) * invCh
            let clamped = max(-1.0, min(1.0, sample))
            pcm[i] = Int16(clamped * 32767.0)
        }
        return Self.buildRiffWavData(samples: pcm, sampleRate: 24000)
    }

    public static func buildRiffWavData(samples: [Int16], sampleRate: UInt32) -> Data {
        let dataBytes = UInt32(samples.count * 2)
        let riffChunkSize = 36 + dataBytes
        let byteRate = sampleRate * 2
        let blockAlign: UInt16 = 2
        let bitsPerSample: UInt16 = 16

        var out = Data(capacity: Int(44 + dataBytes))
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }

        out.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendU32(riffChunkSize)
        out.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        out.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendU32(16)
        appendU16(1) // PCM
        appendU16(1) // Mono
        appendU32(sampleRate)
        appendU32(byteRate)
        appendU16(blockAlign)
        appendU16(bitsPerSample)
        out.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendU32(dataBytes)

        samples.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                out.append(UnsafeBufferPointer(start: UnsafeRawPointer(base).assumingMemoryBound(to: UInt8.self), count: samples.count * 2))
            }
        }
        return out
    }

    // MARK: - Encode Synthesized WAV -> 48 kHz Telegram Ogg/Opus + 5-bit Waveform

    public static func encodeWavDataToTelegramOgg(wavData: Data) throws -> MTVoiceRecordingHooks.FishAudioVoiceResult {
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("mt_fish_tts_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempUrl) }
        try wavData.write(to: tempUrl, options: .atomic)

        var mono48k: [Int16] = []
        let source = SoftwareAudioSource(path: tempUrl.path)
        if source.hasStream {
            while let frame = source.readFrame() {
                let count = frame.count / 2
                if count <= 0 { continue }
                frame.withUnsafeBytes { raw in
                    guard let ptr = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
                    mono48k.append(contentsOf: UnsafeBufferPointer(start: ptr, count: count))
                }
            }
        }

        if mono48k.isEmpty {
            guard let audioFile = try? AVAudioFile(forReading: tempUrl), audioFile.length > 0 else {
                throw MTFishAudioError.opusEncodeFailed
            }
            let srcFmt = audioFile.processingFormat
            guard let buf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: AVAudioFrameCount(audioFile.length)),
                  (try? audioFile.read(into: buf)) != nil,
                  let chData = buf.floatChannelData else {
                throw MTFishAudioError.opusEncodeFailed
            }
            let nFrames = Int(buf.frameLength)
            let nCh = Int(srcFmt.channelCount)
            guard nFrames > 0, nCh > 0 else {
                throw MTFishAudioError.opusEncodeFailed
            }
            let outCount = max(960, Int((Double(nFrames) * 48000.0 / max(1.0, srcFmt.sampleRate)).rounded()))
            mono48k = [Int16](repeating: 0, count: outCount)
            let step = Double(max(0, nFrames - 1)) / Double(max(1, outCount - 1))
            let invCh = 1.0 / Float(nCh)
            for i in 0 ..< outCount {
                let pos = Double(i) * step
                let i0 = min(nFrames - 1, max(0, Int(pos)))
                let i1 = min(nFrames - 1, i0 + 1)
                let frac = Float(pos - Double(i0))
                var s0: Float = 0
                var s1: Float = 0
                for c in 0 ..< nCh {
                    s0 += chData[c][i0]
                    s1 += chData[c][i1]
                }
                let val = max(-1.0, min(1.0, (s0 * (1.0 - frac) + s1 * frac) * invCh))
                mono48k[i] = Int16(val * 32767.0)
            }
        }

        guard !mono48k.isEmpty else {
            throw MTFishAudioError.opusEncodeFailed
        }

        let dataItem = TGDataItem()
        let writer = TGOggOpusWriter()
        guard writer.begin(with: dataItem) else {
            throw MTFishAudioError.opusEncodeFailed
        }

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
            if !ok {
                throw MTFishAudioError.opusEncodeFailed
            }
            offset += take
        }
        let _ = writer.writeFrame(nil, frameByteCount: 0)
        guard let oggData = dataItem.data(), !oggData.isEmpty else {
            throw MTFishAudioError.opusEncodeFailed
        }

        let duration = max(1.0, Double(mono48k.count) / 48000.0)
        let waveform = Self.makeTelegram5BitWaveform(samples: mono48k)
        return MTVoiceRecordingHooks.FishAudioVoiceResult(oggData: oggData, duration: duration, waveform: waveform)
    }

    public static func makeTelegram5BitWaveform(samples: [Int16], bucketCount: Int = 100) -> Data {
        let count = max(1, bucketCount)
        var peaks = [Int32](repeating: 0, count: count)
        if !samples.isEmpty {
            for i in 0 ..< count {
                let start = (i * samples.count) / count
                let end = max(start + 1, min(samples.count, ((i + 1) * samples.count) / count))
                var localPeak: Int32 = 0
                for sIdx in start ..< end {
                    let v = abs(Int32(samples[sIdx]))
                    if v > localPeak { localPeak = v }
                }
                peaks[i] = localPeak
            }
        }
        let globalPeak = max(1, peaks.max() ?? 1)
        let totalBits = count * 5
        let byteLen = (totalBits + 7) / 8
        var bitstream = [UInt8](repeating: 0, count: byteLen + 2)
        for i in 0 ..< count {
            let scaled = UInt32(min(31, (peaks[i] * 31) / globalPeak))
            let bitOffset = i * 5
            let byteIdx = bitOffset / 8
            let shift = bitOffset % 8
            bitstream[byteIdx] |= UInt8((scaled << shift) & 0xFF)
            if shift > 3 {
                bitstream[byteIdx + 1] |= UInt8((scaled >> (8 - shift)) & 0xFF)
            }
        }
        return Data(bitstream.prefix(byteLen))
    }

    // MARK: - Fish Audio REST API (`https://api.fish.audio`)

    private static func extractApiErrorMessage(data: Data?, statusCode: Int) -> String {
        if let data,
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let msg = json["message"] as? String, !msg.isEmpty {
                return "\(msg) (HTTP \(statusCode))"
            }
            if let detail = json["detail"] as? String, !detail.isEmpty {
                return "\(detail) (HTTP \(statusCode))"
            }
        }
        if statusCode == 401 || statusCode == 402 {
            return statusCode == 401 ? "Неверный API-ключ (HTTP 401)" : "Недостаточно баланса Fish Audio (HTTP 402)"
        }
        return "HTTP \(statusCode)"
    }

    public static func createVoiceClone(
        title: String,
        descriptionText: String,
        wavData: Data,
        completion: @escaping (Result<MTFishAudioVoiceItem, Error>) -> Void
    ) {
        let key = self.apiKey
        guard !key.isEmpty else {
            DispatchQueue.main.async { completion(.failure(MTFishAudioError.missingApiKey)) }
            return
        }
        guard let url = URL(string: "https://api.fish.audio/model") else {
            DispatchQueue.main.async { completion(.failure(MTFishAudioError.networkError("Некорректный URL"))) }
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "MediaTok Voice Clone" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        addField("type", "tts")
        addField("title", cleanTitle)
        addField("train_mode", "fast")
        addField("visibility", "private")
        if !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addField("description", descriptionText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"voices\"; filename=\"sample.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wavData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url, timeoutInterval: 45.0)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(MTFishAudioError.networkError(error.localizedDescription)))
                }
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ... 299).contains(code),
                  let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                let errMsg = Self.extractApiErrorMessage(data: data, statusCode: code)
                DispatchQueue.main.async {
                    completion(.failure(MTFishAudioError.networkError(errMsg)))
                }
                return
            }
            let modelId = (json["_id"] as? String) ?? (json["id"] as? String) ?? ""
            guard !modelId.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(MTFishAudioError.networkError("Сервер не вернул _id модели")))
                }
                return
            }
            let returnedTitle = (json["title"] as? String) ?? cleanTitle
            let item = MTFishAudioVoiceItem(
                id: modelId,
                title: returnedTitle,
                subtitle: "Личный клон • ID \(modelId.prefix(8))",
                isMine: true
            )
            DispatchQueue.main.async {
                Self.selectVoice(item)
                completion(.success(item))
            }
        }.resume()
    }

    public static func searchVoices(
        query: String,
        onlyMine: Bool = false,
        completion: @escaping (Result<[MTFishAudioVoiceItem], Error>) -> Void
    ) {
        let key = self.apiKey
        guard !key.isEmpty else {
            DispatchQueue.main.async { completion(.failure(MTFishAudioError.missingApiKey)) }
            return
        }
        var comps = URLComponents(string: "https://api.fish.audio/model")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "page_number", value: "1")
        ]
        if onlyMine {
            items.append(URLQueryItem(name: "self", value: "true"))
        } else {
            items.append(URLQueryItem(name: "sort_by", value: "task_count"))
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            items.append(URLQueryItem(name: "title", value: q))
        }
        comps?.queryItems = items
        guard let url = comps?.url else {
            DispatchQueue.main.async { completion(.failure(MTFishAudioError.networkError("Некорректный URL запроса"))) }
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 20.0)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(MTFishAudioError.networkError(error.localizedDescription)))
                }
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ... 299).contains(code),
                  let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                let errMsg = Self.extractApiErrorMessage(data: data, statusCode: code)
                DispatchQueue.main.async {
                    completion(.failure(MTFishAudioError.networkError(errMsg)))
                }
                return
            }
            let rawList = (json["items"] as? [[String: Any]]) ?? []
            var parsed: [MTFishAudioVoiceItem] = []
            for entry in rawList {
                let id = (entry["_id"] as? String) ?? (entry["id"] as? String) ?? ""
                let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if id.isEmpty || title.isEmpty { continue }
                let author = ((entry["author"] as? [String: Any])?["nickname"] as? String) ?? ""
                let langs = (entry["languages"] as? [String])?.joined(separator: "/") ?? ""
                let tasks = (entry["task_count"] as? Int) ?? 0
                var parts: [String] = []
                if !author.isEmpty { parts.append("@\(author)") }
                if !langs.isEmpty { parts.append(langs.uppercased()) }
                if tasks > 0 { parts.append("\(tasks) ген.") }
                parsed.append(MTFishAudioVoiceItem(
                    id: id,
                    title: title,
                    subtitle: parts.isEmpty ? "ID \(id.prefix(10))" : parts.joined(separator: " • "),
                    isMine: onlyMine
                ))
            }
            DispatchQueue.main.async {
                completion(.success(parsed))
            }
        }.resume()
    }

    public static func synthesizeWav(
        text: String,
        referenceId: String,
        model: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let key = self.apiKey
        guard !key.isEmpty else {
            DispatchQueue.main.async { completion(.failure(MTFishAudioError.missingApiKey)) }
            return
        }
        let refId = referenceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refId.isEmpty else {
            DispatchQueue.main.async { completion(.failure(MTFishAudioError.missingVoiceSelection)) }
            return
        }
        guard let url = URL(string: "https://api.fish.audio/v1/tts") else {
            DispatchQueue.main.async { completion(.failure(MTFishAudioError.networkError("Некорректный URL"))) }
            return
        }

        let chosenModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "s2-pro" : model
        let payload: [String: Any] = [
            "text": text,
            "reference_id": refId,
            "format": "wav",
            "normalize": true,
            "latency": "normal"
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            DispatchQueue.main.async { completion(.failure(MTFishAudioError.networkError("Не удалось сформировать JSON-запрос"))) }
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 45.0)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(chosenModel, forHTTPHeaderField: "model")
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(MTFishAudioError.networkError(error.localizedDescription)))
                }
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ... 299).contains(code), let data, data.count > 128 else {
                let errMsg = Self.extractApiErrorMessage(data: data, statusCode: code)
                DispatchQueue.main.async {
                    completion(.failure(MTFishAudioError.networkError(errMsg)))
                }
                return
            }
            DispatchQueue.main.async {
                completion(.success(data))
            }
        }.resume()
    }

    // MARK: - Recorded Voice -> Speech-to-Text -> Fish Audio Cloned Ogg/Opus

    private static func transformRecordedVoiceOgg(
        oggData: Data,
        interfaceLanguage: String,
        completion: @escaping (Result<MTVoiceRecordingHooks.FishAudioVoiceResult, Error>) -> Void
    ) {
        let key = self.apiKey
        guard !key.isEmpty else {
            DispatchQueue.main.async { completion(.failure(MTFishAudioError.missingApiKey)) }
            return
        }
        let refId = MTVoiceSettings.fishAudioReferenceId.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refId.isEmpty else {
            DispatchQueue.main.async { completion(.failure(MTFishAudioError.missingVoiceSelection)) }
            return
        }
        let model = MTVoiceSettings.fishAudioModel.value

        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("mt_rec_in_\(UUID().uuidString).ogg")
        do {
            try oggData.write(to: tempUrl, options: .atomic)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        let signal = MTSpeechRecognition.authorize()
        |> castError(MTSpeechError.self)
        |> mapToSignal { authorized -> Signal<MTSpeechTranscript, MTSpeechError> in
            if !authorized {
                return .fail(.notAuthorized)
            }
            return MTSpeechRecognition.recognize(path: tempUrl.path, interfaceLanguage: interfaceLanguage)
        }
        |> deliverOnMainQueue

        let requestId = UUID()
        let completedFlag = Atomic<Bool>(value: false)
        let finishTransform: () -> Void = {
            let _ = completedFlag.swap(true)
            Self.activeTransformsLock.lock()
            Self.activeTransformDisposables.removeValue(forKey: requestId)
            Self.activeTransformsLock.unlock()
        }

        let disp = signal.startStandalone(next: { transcript in
            finishTransform()
            try? FileManager.default.removeItem(at: tempUrl)
            let spoken = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spoken.isEmpty else {
                completion(.failure(MTFishAudioError.speechNotRecognized("пустой текст")))
                return
            }
            Self.synthesizeWav(text: spoken, referenceId: refId, model: model) { ttsResult in
                switch ttsResult {
                case let .failure(err):
                    completion(.failure(err))
                case let .success(wavData):
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let encoded = try Self.encodeWavDataToTelegramOgg(wavData: wavData)
                            DispatchQueue.main.async {
                                completion(.success(encoded))
                            }
                        } catch {
                            DispatchQueue.main.async {
                                completion(.failure(error))
                            }
                        }
                    }
                }
            }
        }, error: { speechErr in
            finishTransform()
            try? FileManager.default.removeItem(at: tempUrl)
            let reason: String
            switch speechErr {
            case .notAuthorized:
                reason = "нет доступа к Распознаванию речи в Настройках iOS"
            case .noSpeech:
                reason = "речь не обнаружена"
            case .unavailable:
                reason = "распознавание речи недоступно"
            case .failed:
                reason = "сбой распознавания"
            }
            completion(.failure(MTFishAudioError.speechNotRecognized(reason)))
        })
        Self.activeTransformsLock.lock()
        if !completedFlag.with({ $0 }) {
            Self.activeTransformDisposables[requestId] = disp
        }
        Self.activeTransformsLock.unlock()
    }
}

// MARK: - Fish Audio Voice Cloning Studio UI

private final class MTFishAudioStudioController: UIViewController, UITextFieldDelegate, UIDocumentPickerDelegate {
    private let context: AccountContext

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let activeVoiceTitleLabel = UILabel()
    private let activeVoiceSubLabel = UILabel()
    private let autoReplaceSwitch = UISwitch()
    private let apiKeyField = UITextField()
    private let modelSegment = UISegmentedControl(items: MTFishAudioClone.availableModels.map { $0.title })
    private let cloneBtn = UIButton(type: .system)
    private let recordSampleBtn = UIButton(type: .system)
    private let statusLabel = UILabel()

    private let sourceTabSegment = UISegmentedControl(items: ["Сохраненные клоны", "Поиск Fish Audio"])
    private let searchField = UITextField()
    private let voicesListStack = UIStackView()

    private let ttsTextField = UITextField()
    private let previewPlayBtn = UIButton(type: .system)
    private let sendSavedBtn = UIButton(type: .system)

    private var catalogResults: [MTFishAudioVoiceItem] = []
    private var audioPlayer: AVAudioPlayer?
    private var sampleRecorder: AVAudioRecorder?
    private var sampleRecordUrl: URL?
    private var activeDecodeCount: Int = 0
    private var didActivateAudioSession: Bool = false

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func removeSampleFileIfTemporary(_ url: URL?) {
        guard let url else { return }
        if url.lastPathComponent.hasPrefix("mt_fish_sample_") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func deactivateAudioSessionIfNeeded() {
        guard self.didActivateAudioSession else { return }
        self.didActivateAudioSession = false
        let session = AVAudioSession.sharedInstance()
        if !session.isOtherAudioPlaying && session.mode != .voiceChat {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        self.sampleRecorder?.stop()
        self.sampleRecorder = nil
        self.audioPlayer?.stop()
        self.audioPlayer = nil
        if self.activeDecodeCount == 0 {
            Self.removeSampleFileIfTemporary(self.sampleRecordUrl)
        }
        self.deactivateAudioSessionIfNeeded()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [self.scrollView]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.isBeingPresented || self.navigationController?.isBeingPresented == true {
            self.view.endEditing(true)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.view.endEditing(true)
        self.sampleRecorder?.stop()
        self.sampleRecorder = nil
        self.audioPlayer?.stop()
        self.audioPlayer = nil
        if self.isBeingDismissed || self.isMovingFromParent || self.navigationController?.isBeingDismissed == true {
            if self.activeDecodeCount == 0 {
                Self.removeSampleFileIfTemporary(self.sampleRecordUrl)
                self.sampleRecordUrl = nil
            }
            self.deactivateAudioSessionIfNeeded()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = .dark
        self.title = "Fish Audio — Клон голоса"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.closeTapped))

        let bgTap = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboard))
        bgTap.cancelsTouchesInView = false
        self.view.addGestureRecognizer(bgTap)

        NotificationCenter.default.addObserver(self, selector: #selector(self.handleKeyboardFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleKeyboardHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        self.scrollView.keyboardDismissMode = .interactive
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.scrollView)

        self.stackView.axis = .vertical
        self.stackView.spacing = 12
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stackView)

        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.stackView.topAnchor.constraint(equalTo: self.scrollView.topAnchor, constant: 14),
            self.stackView.leadingAnchor.constraint(equalTo: self.scrollView.leadingAnchor, constant: 16),
            self.stackView.trailingAnchor.constraint(equalTo: self.scrollView.trailingAnchor, constant: -16),
            self.stackView.bottomAnchor.constraint(equalTo: self.scrollView.bottomAnchor, constant: -28),
            self.stackView.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor, constant: -32)
        ])

        self.buildSections()
        self.refreshHeaderState()
        self.rebuildVoicesList()
    }

    private func makeCard() -> UIStackView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 10
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1.0
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        return card
    }

    private func makeSectionTitle(_ text: String, symbol: String, tint: UIColor) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let iv = UIImageView(image: UIImage(systemName: symbol, withConfiguration: cfg)?.withTintColor(tint, renderingMode: .alwaysOriginal))
        iv.setContentHuggingPriority(.required, for: .horizontal)
        let lbl = UILabel()
        lbl.text = text
        lbl.font = .systemFont(ofSize: 13, weight: .bold)
        lbl.textColor = UIColor(white: 0.78, alpha: 1.0)
        row.addArrangedSubview(iv)
        row.addArrangedSubview(lbl)
        return row
    }

    private func configureField(_ tf: UITextField, placeholder: String, returnType: UIReturnKeyType = .done) {
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(white: 0.46, alpha: 1.0)]
        )
        tf.textColor = .white
        tf.font = .systemFont(ofSize: 14, weight: .regular)
        tf.backgroundColor = UIColor(white: 0.08, alpha: 1.0)
        tf.layer.cornerRadius = 11
        tf.layer.borderWidth = 1.0
        tf.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        tf.leftViewMode = .always
        tf.clearButtonMode = .whileEditing
        tf.returnKeyType = returnType
        tf.delegate = self
        tf.heightAnchor.constraint(equalToConstant: 42).isActive = true
    }

    private func configureActionButton(_ b: UIButton, symbol: String, title: String, bg: UIColor, action: Selector) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        b.setImage(UIImage(systemName: symbol, withConfiguration: cfg)?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        b.setTitle("  " + title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.backgroundColor = bg
        b.layer.cornerRadius = 12
        b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        b.addTarget(self, action: action, for: .touchUpInside)
    }

    private func buildSections() {
        // 1. Active voice + Auto-replace switch + API Key
        let card1 = self.makeCard()
        card1.addArrangedSubview(self.makeSectionTitle("АКТИВНЫЙ ГОЛОС И КЛЮЧ FISH AUDIO", symbol: "waveform.badge.person.crop", tint: .systemPink))

        self.activeVoiceTitleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        self.activeVoiceTitleLabel.textColor = .white
        self.activeVoiceSubLabel.font = .systemFont(ofSize: 12, weight: .medium)
        self.activeVoiceSubLabel.textColor = UIColor(white: 0.65, alpha: 1.0)
        self.activeVoiceSubLabel.numberOfLines = 2
        card1.addArrangedSubview(self.activeVoiceTitleLabel)
        card1.addArrangedSubview(self.activeVoiceSubLabel)

        let autoRow = UIStackView()
        autoRow.axis = .horizontal
        autoRow.spacing = 10
        autoRow.alignment = .center
        let autoLbl = UILabel()
        autoLbl.text = "Озвучивать мои ГС в чатах этим голосом"
        autoLbl.font = .systemFont(ofSize: 14, weight: .medium)
        autoLbl.textColor = .white
        autoLbl.numberOfLines = 2
        self.autoReplaceSwitch.onTintColor = .systemPink
        self.autoReplaceSwitch.isOn = MTVoiceSettings.fishAudioAutoReplace.value
        self.autoReplaceSwitch.addTarget(self, action: #selector(self.autoSwitchChanged), for: .valueChanged)
        autoRow.addArrangedSubview(autoLbl)
        autoRow.addArrangedSubview(self.autoReplaceSwitch)
        card1.addArrangedSubview(autoRow)

        self.configureField(self.apiKeyField, placeholder: "API-ключ Fish Audio (fish.audio/app/api-keys)...")
        self.apiKeyField.isSecureTextEntry = true
        self.apiKeyField.autocapitalizationType = .none
        self.apiKeyField.autocorrectionType = .no
        self.apiKeyField.text = MTFishAudioClone.apiKey
        self.apiKeyField.addTarget(self, action: #selector(self.apiKeyEditingChanged), for: .editingChanged)
        card1.addArrangedSubview(self.apiKeyField)

        let curModel = MTVoiceSettings.fishAudioModel.value
        let mIdx = MTFishAudioClone.availableModels.firstIndex(where: { $0.id == curModel }) ?? 0
        self.modelSegment.selectedSegmentIndex = mIdx
        self.modelSegment.addTarget(self, action: #selector(self.modelChanged), for: .valueChanged)
        card1.addArrangedSubview(self.modelSegment)
        self.stackView.addArrangedSubview(card1)

        // 2. Clone from sample (.ogg / .mp3 / .wav / .mp4 voiceline or live mic)
        let card2 = self.makeCard()
        card2.addArrangedSubview(self.makeSectionTitle("КЛОНИРОВАТЬ ГОЛОС ПО ГС ИЛИ ВОЙСЛАЙНУ", symbol: "doc.badge.plus", tint: .systemIndigo))

        let hint = UILabel()
        hint.text = "Загрузи любое голосовое (.ogg), аудио или видео-войслайн аниме-персонажа (5–45 сек чистой речи без музыки) — Fish Audio создаст точный клон голоса."
        hint.font = .systemFont(ofSize: 12, weight: .regular)
        hint.textColor = UIColor(white: 0.68, alpha: 1.0)
        hint.numberOfLines = 0
        card2.addArrangedSubview(hint)

        self.configureActionButton(self.cloneBtn, symbol: "folder.fill.badge.plus", title: "Загрузить ГС / войслайн из Файлов", bg: .systemIndigo, action: #selector(self.pickVoiceSampleTapped))
        self.configureActionButton(self.recordSampleBtn, symbol: "mic.fill", title: "Записать образец с микрофона", bg: UIColor(white: 0.20, alpha: 1.0), action: #selector(self.recordSampleTapped))
        card2.addArrangedSubview(self.cloneBtn)
        card2.addArrangedSubview(self.recordSampleBtn)

        self.statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        self.statusLabel.textColor = .systemCyan
        self.statusLabel.numberOfLines = 0
        self.statusLabel.isHidden = true
        card2.addArrangedSubview(self.statusLabel)
        self.stackView.addArrangedSubview(card2)

        // 3. Saved clones + Public anime/character search
        let card3 = self.makeCard()
        card3.addArrangedSubview(self.makeSectionTitle("МОИ КЛОНЫ И ПОИСК АНИМЕ-ГОЛОСОВ", symbol: "magnifyingglass", tint: .systemCyan))

        self.sourceTabSegment.selectedSegmentIndex = 0
        self.sourceTabSegment.addTarget(self, action: #selector(self.sourceTabChanged), for: .valueChanged)
        card3.addArrangedSubview(self.sourceTabSegment)

        let searchRow = UIStackView()
        searchRow.axis = .horizontal
        searchRow.spacing = 8
        self.configureField(self.searchField, placeholder: "Поиск: Gojo, Makima, Sukuna, Raiden, Dio...", returnType: .search)
        self.searchField.autocorrectionType = .no
        let findBtn = UIButton(type: .system)
        let fCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        findBtn.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: fCfg)?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        findBtn.backgroundColor = .systemBlue
        findBtn.layer.cornerRadius = 11
        findBtn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        findBtn.heightAnchor.constraint(equalToConstant: 42).isActive = true
        findBtn.addTarget(self, action: #selector(self.runSearchTapped), for: .touchUpInside)
        searchRow.addArrangedSubview(self.searchField)
        searchRow.addArrangedSubview(findBtn)
        card3.addArrangedSubview(searchRow)

        self.voicesListStack.axis = .vertical
        self.voicesListStack.spacing = 6
        card3.addArrangedSubview(self.voicesListStack)
        self.stackView.addArrangedSubview(card3)

        // 4. Test TTS & Send Voice Message
        let card4 = self.makeCard()
        card4.addArrangedSubview(self.makeSectionTitle("ПРОВЕРИТЬ И ОЗВУЧИТЬ ТЕКСТ В ГС", symbol: "waveform", tint: .systemGreen))
        self.configureField(self.ttsTextField, placeholder: "Введи текст для озвучки выбранным голосом...")

        let btnRow = UIStackView()
        btnRow.axis = .horizontal
        btnRow.spacing = 8
        btnRow.distribution = .fillEqually
        self.configureActionButton(self.previewPlayBtn, symbol: "play.fill", title: "Прослушать", bg: UIColor(red: 0.18, green: 0.52, blue: 0.96, alpha: 1.0), action: #selector(self.previewTtsTapped))
        self.configureActionButton(self.sendSavedBtn, symbol: "paperplane.fill", title: "В Избранное", bg: UIColor(red: 0.14, green: 0.62, blue: 0.36, alpha: 1.0), action: #selector(self.sendTtsToSavedTapped))
        btnRow.addArrangedSubview(self.previewPlayBtn)
        btnRow.addArrangedSubview(self.sendSavedBtn)
        card4.addArrangedSubview(self.ttsTextField)
        card4.addArrangedSubview(btnRow)
        self.stackView.addArrangedSubview(card4)
    }

    private func setStatus(_ text: String, isError: Bool = false) {
        self.statusLabel.isHidden = text.isEmpty
        self.statusLabel.text = text
        self.statusLabel.textColor = isError ? .systemRed : .systemCyan
    }

    private func refreshHeaderState() {
        let refId = MTVoiceSettings.fishAudioReferenceId.value
        let refTitle = MTVoiceSettings.fishAudioReferenceTitle.value
        if refId.isEmpty {
            self.activeVoiceTitleLabel.text = "Голос не выбран"
            self.activeVoiceSubLabel.text = "Загрузи образец войслайна ниже или найди готового персонажа в каталоге Fish Audio."
        } else {
            self.activeVoiceTitleLabel.text = refTitle.isEmpty ? "Клон \(refId.prefix(8))" : refTitle
            let stateText = MTVoiceSettings.fishAudioAutoReplace.value
                ? "Активен • твои записываемые ГС в чатах озвучиваются этим голосом"
                : "Выбран • включи тумблер ниже для авто-замены ГС в чатах"
            self.activeVoiceSubLabel.text = "\(stateText) (ID: \(refId.prefix(10)))"
        }
        self.autoReplaceSwitch.isOn = MTVoiceSettings.fishAudioAutoReplace.value
    }

    private func rebuildVoicesList() {
        for sub in self.voicesListStack.arrangedSubviews {
            self.voicesListStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        let activeId = MTVoiceSettings.fishAudioReferenceId.value
        let items = self.sourceTabSegment.selectedSegmentIndex == 0 ? MTFishAudioClone.savedVoices : self.catalogResults

        if items.isEmpty {
            let empty = UILabel()
            empty.text = self.sourceTabSegment.selectedSegmentIndex == 0
                ? "Пока нет сохранённых голосов. Клонируй голос по файлу выше или переключись на «Поиск Fish Audio»."
                : "Введи имя персонажа (например Gojo, Makima, Sukuna, Raiden) и нажми поиск."
            empty.font = .systemFont(ofSize: 12, weight: .regular)
            empty.textColor = UIColor(white: 0.55, alpha: 1.0)
            empty.numberOfLines = 0
            self.voicesListStack.addArrangedSubview(empty)
            return
        }

        for (idx, item) in items.prefix(25).enumerated() {
            let isSelected = (item.id == activeId)
            let row = UIView()
            row.backgroundColor = isSelected
                ? UIColor.systemPink.withAlphaComponent(0.18)
                : UIColor(white: 0.08, alpha: 1.0)
            row.layer.cornerRadius = 11
            row.layer.borderWidth = 1.0
            row.layer.borderColor = isSelected
                ? UIColor.systemPink.withAlphaComponent(0.55).cgColor
                : UIColor.white.withAlphaComponent(0.06).cgColor

            let selectBtn = UIButton(type: .system)
            selectBtn.tag = idx
            selectBtn.addTarget(self, action: #selector(self.voiceItemTapped(_:)), for: .touchUpInside)
            selectBtn.translatesAutoresizingMaskIntoConstraints = false

            let titleLbl = UILabel()
            titleLbl.text = item.title
            titleLbl.font = .systemFont(ofSize: 14, weight: .semibold)
            titleLbl.textColor = .white

            let subLbl = UILabel()
            subLbl.text = item.subtitle
            subLbl.font = .systemFont(ofSize: 11, weight: .regular)
            subLbl.textColor = UIColor(white: 0.62, alpha: 1.0)

            let vStack = UIStackView(arrangedSubviews: [titleLbl, subLbl])
            vStack.axis = .vertical
            vStack.spacing = 2
            vStack.isUserInteractionEnabled = false
            vStack.translatesAutoresizingMaskIntoConstraints = false

            let checkCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            let rightIcon = UIImageView(
                image: UIImage(
                    systemName: isSelected ? "checkmark.circle.fill" : "circle",
                    withConfiguration: checkCfg
                )?.withTintColor(isSelected ? .systemPink : UIColor(white: 0.45, alpha: 1.0), renderingMode: .alwaysOriginal)
            )
            rightIcon.translatesAutoresizingMaskIntoConstraints = false

            row.addSubview(vStack)
            row.addSubview(rightIcon)
            row.addSubview(selectBtn)

            var trailingTarget = rightIcon.leadingAnchor
            if self.sourceTabSegment.selectedSegmentIndex == 0 {
                let delBtn = UIButton(type: .system)
                delBtn.tag = idx
                let dCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                delBtn.setImage(UIImage(systemName: "trash", withConfiguration: dCfg)?.withTintColor(.systemRed, renderingMode: .alwaysOriginal), for: .normal)
                delBtn.addTarget(self, action: #selector(self.deleteSavedVoiceTapped(_:)), for: .touchUpInside)
                delBtn.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(delBtn)
                NSLayoutConstraint.activate([
                    delBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                    delBtn.trailingAnchor.constraint(equalTo: rightIcon.leadingAnchor, constant: -8),
                    delBtn.widthAnchor.constraint(equalToConstant: 30),
                    delBtn.heightAnchor.constraint(equalToConstant: 30)
                ])
                trailingTarget = delBtn.leadingAnchor
            }

            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
                vStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
                vStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingTarget, constant: -8),
                vStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
                vStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
                rightIcon.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
                rightIcon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                rightIcon.widthAnchor.constraint(equalToConstant: 20),
                selectBtn.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                selectBtn.topAnchor.constraint(equalTo: row.topAnchor),
                selectBtn.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                selectBtn.trailingAnchor.constraint(equalTo: trailingTarget)
            ])
            self.voicesListStack.addArrangedSubview(row)
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        self.view.endEditing(true)
        self.dismiss(animated: true)
    }

    @objc private func dismissKeyboard() {
        self.view.endEditing(true)
    }

    @objc private func handleKeyboardFrame(_ note: Notification) {
        guard let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let local = self.view.convert(endFrame, from: nil)
        let overlap = max(0, self.view.bounds.maxY - local.minY)
        self.scrollView.contentInset.bottom = overlap + 16
        self.scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    @objc private func handleKeyboardHide(_ note: Notification) {
        let _ = note
        self.scrollView.contentInset.bottom = 0
        self.scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if textField === self.searchField {
            self.runSearchTapped()
        }
        return true
    }

    @objc private func apiKeyEditingChanged() {
        MTFishAudioClone.apiKey = self.apiKeyField.text ?? ""
    }

    @objc private func autoSwitchChanged() {
        if self.autoReplaceSwitch.isOn && MTVoiceSettings.fishAudioReferenceId.value.isEmpty {
            self.autoReplaceSwitch.setOn(false, animated: true)
            self.setStatus("Сначала выбери или клонируй голос персонажа.", isError: true)
            return
        }
        MTVoiceSettings.fishAudioAutoReplace.set(self.autoReplaceSwitch.isOn)
        self.refreshHeaderState()
    }

    @objc private func modelChanged() {
        let idx = self.modelSegment.selectedSegmentIndex
        guard MTFishAudioClone.availableModels.indices.contains(idx) else { return }
        MTVoiceSettings.fishAudioModel.set(MTFishAudioClone.availableModels[idx].id)
    }

    @objc private func sourceTabChanged() {
        if self.sourceTabSegment.selectedSegmentIndex == 1 && self.catalogResults.isEmpty && !MTFishAudioClone.apiKey.isEmpty {
            self.runSearchTapped()
        } else {
            self.rebuildVoicesList()
        }
    }

    @objc private func runSearchTapped() {
        self.view.endEditing(true)
        self.sourceTabSegment.selectedSegmentIndex = 1
        let q = self.searchField.text ?? ""
        self.setStatus("Ищу голоса в Fish Audio...")
        MTFishAudioClone.searchVoices(query: q, onlyMine: false) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(items):
                self.catalogResults = items
                self.setStatus(items.isEmpty ? "Ничего не найдено по запросу." : "Найдено голосов: \(items.count)")
                self.rebuildVoicesList()
            case let .failure(err):
                self.setStatus(err.localizedDescription, isError: true)
            }
        }
    }

    @objc private func voiceItemTapped(_ sender: UIButton) {
        let list = self.sourceTabSegment.selectedSegmentIndex == 0 ? MTFishAudioClone.savedVoices : self.catalogResults
        guard list.indices.contains(sender.tag) else { return }
        let chosen = list[sender.tag]
        MTFishAudioClone.selectVoice(chosen)
        self.refreshHeaderState()
        self.rebuildVoicesList()
        self.setStatus("Выбран голос «\(chosen.title)»")
    }

    @objc private func deleteSavedVoiceTapped(_ sender: UIButton) {
        let list = MTFishAudioClone.savedVoices
        guard list.indices.contains(sender.tag) else { return }
        let target = list[sender.tag]
        MTFishAudioClone.removeSavedVoice(id: target.id)
        self.refreshHeaderState()
        self.rebuildVoicesList()
    }

    @objc private func pickVoiceSampleTapped() {
        self.view.endEditing(true)
        guard !MTFishAudioClone.apiKey.isEmpty else {
            self.setStatus("Сначала вставь API-ключ Fish Audio в верхнем блоке.", isError: true)
            return
        }
        var types: [UTType] = [.audio, .movie, .mpeg4Movie, .mp3, .wav]
        for ext in ["ogg", "oga", "opus", "flac", "m4a"] {
            if let t = UTType(filenameExtension: ext) {
                types.append(t)
            }
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        self.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let pickedUrl = urls.first else { return }
        let defaultName = pickedUrl.deletingPathExtension().lastPathComponent
        self.promptCloneTitleAndUpload(audioUrl: pickedUrl, suggestedTitle: defaultName)
    }

    @objc private func recordSampleTapped() {
        self.view.endEditing(true)
        if let rec = self.sampleRecorder, rec.isRecording {
            rec.stop()
            self.sampleRecorder = nil
            self.configureActionButton(self.recordSampleBtn, symbol: "mic.fill", title: "Записать образец с микрофона", bg: UIColor(white: 0.20, alpha: 1.0), action: #selector(self.recordSampleTapped))
            if let url = self.sampleRecordUrl {
                self.promptCloneTitleAndUpload(audioUrl: url, suggestedTitle: "Мой клон голоса")
            }
            return
        }
        guard !MTFishAudioClone.apiKey.isEmpty else {
            self.setStatus("Сначала вставь API-ключ Fish Audio в верхнем блоке.", isError: true)
            return
        }
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.setStatus("Нет доступа к микрофону в Настройках iOS.", isError: true)
                    return
                }
                Self.removeSampleFileIfTemporary(self.sampleRecordUrl)
                self.sampleRecordUrl = nil
                let outUrl = FileManager.default.temporaryDirectory.appendingPathComponent("mt_fish_sample_\(UUID().uuidString).wav")
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 24000.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try AVAudioSession.sharedInstance().setActive(true)
                    self.didActivateAudioSession = true
                    let rec = try AVAudioRecorder(url: outUrl, settings: settings)
                    let _ = rec.record(forDuration: 40.0)
                    self.sampleRecordUrl = outUrl
                    self.sampleRecorder = rec
                    self.configureActionButton(self.recordSampleBtn, symbol: "stop.fill", title: "Остановить запись и клонировать", bg: .systemRed, action: #selector(self.recordSampleTapped))
                    self.setStatus("Запись образца (говори чётко 10–30 сек, затем нажми Стоп)...")
                } catch {
                    Self.removeSampleFileIfTemporary(outUrl)
                    self.setStatus("Не удалось начать запись: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    private func promptCloneTitleAndUpload(audioUrl: URL, suggestedTitle: String) {
        let startUpload: (String) -> Void = { [weak self] rawName in
            guard let self else {
                Self.removeSampleFileIfTemporary(audioUrl)
                return
            }
            let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? suggestedTitle : trimmed
            self.setStatus("Декодирую аудио и создаю клон в Fish Audio...")
            self.cloneBtn.isEnabled = false
            self.activeDecodeCount += 1
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                defer {
                    Self.removeSampleFileIfTemporary(audioUrl)
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.activeDecodeCount = max(0, self.activeDecodeCount - 1)
                        if self.sampleRecordUrl == audioUrl {
                            self.sampleRecordUrl = nil
                        }
                    }
                }
                do {
                    let wavData = try MTFishAudioClone.decodeAnyMediaFileToWav(url: audioUrl)
                    MTFishAudioClone.createVoiceClone(title: name, descriptionText: "MediaTok iOS Voice Clone", wavData: wavData) { [weak self] result in
                        guard let self else { return }
                        self.cloneBtn.isEnabled = true
                        switch result {
                        case let .success(voice):
                            self.sourceTabSegment.selectedSegmentIndex = 0
                            self.refreshHeaderState()
                            self.rebuildVoicesList()
                            self.setStatus("Клон «\(voice.title)» готов и выбран!")
                        case let .failure(err):
                            self.setStatus(err.localizedDescription, isError: true)
                        }
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.cloneBtn.isEnabled = true
                        self?.setStatus(error.localizedDescription, isError: true)
                    }
                }
            }
        }
        mtPresentMenuPrompt(
            context: self.context,
            title: "Название клона голоса",
            subtitle: "Например: Gojo Satoru, Makima, Мой голос",
            value: suggestedTitle,
            placeholder: "Имя персонажа / голоса",
            characterLimit: 80,
            onCancel: { [weak self] in
                Self.removeSampleFileIfTemporary(audioUrl)
                if self?.sampleRecordUrl == audioUrl {
                    self?.sampleRecordUrl = nil
                }
            },
            apply: { name in
                startUpload(name)
            }
        )
    }

    @objc private func previewTtsTapped() {
        self.view.endEditing(true)
        let text = (self.ttsTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            self.setStatus("Введи фразу для тестовой озвучки.", isError: true)
            return
        }
        let refId = MTVoiceSettings.fishAudioReferenceId.value
        let model = MTVoiceSettings.fishAudioModel.value
        self.previewPlayBtn.isEnabled = false
        self.setStatus("Синтезирую речь через Fish Audio (\(model))...")
        MTFishAudioClone.synthesizeWav(text: text, referenceId: refId, model: model) { [weak self] result in
            guard let self else { return }
            self.previewPlayBtn.isEnabled = true
            switch result {
            case let .success(wavData):
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                    try AVAudioSession.sharedInstance().setActive(true)
                    self.didActivateAudioSession = true
                    let player = try AVAudioPlayer(data: wavData)
                    let _ = player.prepareToPlay()
                    let _ = player.play()
                    self.audioPlayer = player
                    self.setStatus("Воспроизведение озвучки...")
                } catch {
                    self.setStatus("Ошибка плеера: \(error.localizedDescription)", isError: true)
                }
            case let .failure(err):
                self.setStatus(err.localizedDescription, isError: true)
            }
        }
    }

    @objc private func sendTtsToSavedTapped() {
        self.view.endEditing(true)
        let text = (self.ttsTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            self.setStatus("Введи текст для отправки голосовым сообщением.", isError: true)
            return
        }
        let refId = MTVoiceSettings.fishAudioReferenceId.value
        let model = MTVoiceSettings.fishAudioModel.value
        self.sendSavedBtn.isEnabled = false
        self.setStatus("Генерирую голосовое сообщение Ogg/Opus...")

        let finishWithWav: (Data) -> Void = { [weak self] wavData in
            guard let self else { return }
            let ctx = self.context
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    let opus = try MTFishAudioClone.encodeWavDataToTelegramOgg(wavData: wavData)
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.sendSavedBtn.isEnabled = true
                        let fileId = Int64.random(in: Int64.min ... Int64.max)
                        let resource = LocalFileMediaResource(fileId: fileId, size: Int64(opus.oggData.count), isSecretRelated: false)
                        ctx.account.postbox.mediaBox.storeResourceData(resource.id, data: opus.oggData, synchronous: true)
                        let media = TelegramMediaFile(
                            fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: fileId),
                            partialReference: nil,
                            resource: resource,
                            previewRepresentations: [],
                            videoThumbnails: [],
                            immediateThumbnailData: nil,
                            mimeType: "audio/ogg",
                            size: Int64(opus.oggData.count),
                            attributes: [
                                .Audio(isVoice: true, duration: max(1, Int(opus.duration.rounded())), title: nil, performer: nil, waveform: opus.waveform)
                            ],
                            alternativeRepresentations: []
                        )
                        let _ = enqueueMessages(account: ctx.account, peerId: ctx.account.peerId, messages: [
                            .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                        ]).startStandalone()
                        self.setStatus("Голосовое отправлено в Избранное!")
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.sendSavedBtn.isEnabled = true
                        self?.setStatus(error.localizedDescription, isError: true)
                    }
                }
            }
        }

        MTFishAudioClone.synthesizeWav(text: text, referenceId: refId, model: model) { [weak self] result in
            switch result {
            case let .success(wavData):
                finishWithWav(wavData)
            case let .failure(err):
                self?.sendSavedBtn.isEnabled = true
                self?.setStatus(err.localizedDescription, isError: true)
            }
        }
    }
}
