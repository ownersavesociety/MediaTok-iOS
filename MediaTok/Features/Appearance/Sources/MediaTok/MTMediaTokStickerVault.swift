import Foundation
import UIKit
import Vision
import PhotosUI
import UniformTypeIdentifiers
import Network
import Darwin
import Security
import ImageIO
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import ItemListUI
import UndoUI
import WebPBinding
import MTCore
import MTHooks
import MTSettingsUI

// MARK: - Persistent 10,000-Sticker Vault Store with Offline Apple Vision AI & Optional BYOK Gemini

final class MTStickerVaultStore {
    static let shared = MTStickerVaultStore()

    private static let geminiKeychainService = "org.mediatok.sticker_vault.gemini_key"
    private static let geminiKeychainAccount = "api_key"
    private static let maxStickerCount = 10_000

    private let lock = NSLock()
    private let aiQueue = DispatchQueue(label: "org.mediatok.sticker_vault.vision", qos: .utility)
    private let ioQueue = DispatchQueue(label: "org.mediatok.sticker_vault.io", qos: .utility)
    private let thumbCache = NSCache<NSString, UIImage>()
    private var loaded = false
    private var entries: [MTMediaTokCoreLogic.StickerEntry] = []
    private var pendingPersistWorkItem: DispatchWorkItem?

    private init() {
        self.thumbCache.countLimit = 400
        self.thumbCache.totalCostLimit = 32 * 1024 * 1024
    }

    private func rootDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("mediatok/mediatok/sticker_vault", isDirectory: true)
    }

    private func indexURL() -> URL {
        return self.rootDir().appendingPathComponent("index.json")
    }

    private func backupIndexURL() -> URL {
        return self.rootDir().appendingPathComponent("index.json.bak")
    }

    private func ensureLoadedLocked() {
        if self.loaded { return }
        self.loaded = true
        let dec = JSONDecoder()
        if let data = try? Data(contentsOf: self.indexURL()),
           let decoded = try? dec.decode([MTMediaTokCoreLogic.StickerEntry].self, from: data) {
            self.entries = decoded
            return
        }
        // Fallback 1: rolling backup index.json.bak
        if let data = try? Data(contentsOf: self.backupIndexURL()),
           let decoded = try? dec.decode([MTMediaTokCoreLogic.StickerEntry].self, from: data) {
            self.entries = decoded
            self.schedulePersistLocked(immediate: true)
            return
        }
        // Fallback 2: recover orphaned stk_*.webp files from disk so vault is never wiped on index corruption
        let dir = self.rootDir()
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            var recovered: [MTMediaTokCoreLogic.StickerEntry] = []
            for file in files.sorted() where file.hasPrefix("stk_") && file.hasSuffix(".webp") {
                let id = String(file.dropFirst(4).dropLast(5))
                guard !id.isEmpty else { continue }
                recovered.append(MTMediaTokCoreLogic.StickerEntry(
                    id: id,
                    fileName: file,
                    tags: [],
                    ocrText: "",
                    visionLabels: [],
                    addedAt: Int64(Date().timeIntervalSince1970),
                    usageCount: 0
                ))
            }
            if !recovered.isEmpty {
                self.entries = recovered
                self.schedulePersistLocked(immediate: true)
            }
        }
    }

    private func schedulePersistLocked(immediate: Bool = false) {
        self.pendingPersistWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let snapshot = self.entries
            self.lock.unlock()

            let dir = self.rootDir()
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let idxUrl = self.indexURL()
            let bakUrl = self.backupIndexURL()
            if fm.fileExists(atPath: idxUrl.path) {
                try? fm.removeItem(at: bakUrl)
                try? fm.copyItem(at: idxUrl, to: bakUrl)
            }
            let enc = JSONEncoder()
            if let data = try? enc.encode(snapshot) {
                try? data.write(to: idxUrl, options: [.atomic])
            }
        }
        self.pendingPersistWorkItem = work
        if immediate {
            self.ioQueue.async(execute: work)
        } else {
            self.ioQueue.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    var count: Int {
        self.lock.lock()
        self.ensureLoadedLocked()
        let c = self.entries.count
        self.lock.unlock()
        return c
    }

    func allEntries() -> [MTMediaTokCoreLogic.StickerEntry] {
        self.lock.lock()
        self.ensureLoadedLocked()
        let snap = self.entries
        self.lock.unlock()
        return snap
    }

    func search(_ query: String, limit: Int = 120) -> [MTMediaTokCoreLogic.StickerEntry] {
        let snap = self.allEntries()
        return MTMediaTokCoreLogic.searchStickers(snap, query: query, limit: limit)
    }

    func fileURL(for entry: MTMediaTokCoreLogic.StickerEntry) -> URL {
        return self.rootDir().appendingPathComponent(entry.fileName)
    }

    func cachedImage(for entry: MTMediaTokCoreLogic.StickerEntry) -> UIImage? {
        return self.thumbCache.object(forKey: entry.id as NSString)
    }

    func loadImage(for entry: MTMediaTokCoreLogic.StickerEntry) -> UIImage? {
        let key = entry.id as NSString
        if let cached = self.thumbCache.object(forKey: key) {
            return cached
        }
        let url = self.fileURL(for: entry)
        guard let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) ?? WebP.convert(fromWebP: data) else {
            return nil
        }
        let cost = max(1, Int(img.size.width * img.size.height * img.scale * img.scale * 4.0))
        self.thumbCache.setObject(img, forKey: key, cost: cost)
        return img
    }

    func loadImageAsync(for entry: MTMediaTokCoreLogic.StickerEntry, completion: @escaping (UIImage?) -> Void) {
        if let cached = self.cachedImage(for: entry) {
            completion(cached)
            return
        }
        self.ioQueue.async { [weak self] in
            let img = self?.loadImage(for: entry)
            DispatchQueue.main.async {
                completion(img)
            }
        }
    }

    private static func hasWebPMagicHeader(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        return data[data.startIndex] == 0x52     // 'R'
            && data[data.startIndex + 1] == 0x49 // 'I'
            && data[data.startIndex + 2] == 0x46 // 'F'
            && data[data.startIndex + 3] == 0x46 // 'F'
            && data[data.startIndex + 8] == 0x57 // 'W'
            && data[data.startIndex + 9] == 0x45 // 'E'
            && data[data.startIndex + 10] == 0x42 // 'B'
            && data[data.startIndex + 11] == 0x50 // 'P'
    }

    private static func isSafeImageDimension(_ data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return true // WebP may not be inspectable by older ImageIO codecs; let WebP decoder handle
        }
        if let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int {
            if w <= 0 || h <= 0 || w > 4096 || h > 4096 || (w * h) > 16_000_000 {
                return false
            }
        }
        return true
    }

    func addSticker(
        rawData: Data,
        suggestedName: String,
        initialTags: [String] = [],
        runGeminiIfConfigured: Bool = false,
        completion: ((MTMediaTokCoreLogic.StickerEntry?) -> Void)? = nil
    ) {
        self.aiQueue.async {
            guard !rawData.isEmpty, rawData.count <= 15 * 1024 * 1024,
                  MTStickerVaultStore.isSafeImageDimension(rawData),
                  let decoded = UIImage(data: rawData) ?? WebP.convert(fromWebP: rawData) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let pixelW = decoded.size.width * decoded.scale
            let pixelH = decoded.size.height * decoded.scale
            guard pixelW > 0 && pixelH > 0 && pixelW <= 4096.0 && pixelH <= 4096.0 && (pixelW * pixelH) <= 16_000_000.0 else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let webpData: Data
            let isAlreadySmallWebP = rawData.count <= 512 * 1024
                && MTStickerVaultStore.hasWebPMagicHeader(rawData)
                && pixelW <= 520.0
                && pixelH <= 520.0
            if isAlreadySmallWebP {
                webpData = rawData
            } else {
                let normalized = MTStickerVaultStore.scaleToSticker512(decoded)
                guard let encoded = try? WebP.convert(toWebP: normalized, quality: 88.0), !encoded.isEmpty else {
                    DispatchQueue.main.async { completion?(nil) }
                    return
                }
                webpData = encoded
            }

            let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let cleanBase = MTMediaTokCoreLogic.sanitizeUploadFileName(suggestedName)
            let stem = (cleanBase as NSString).deletingPathExtension
            let diskName = "stk_\(id).webp"
            let dir = self.rootDir()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            do {
                try webpData.write(to: dir.appendingPathComponent(diskName), options: [.atomic])
            } catch {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            var cleanTags = initialTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !stem.isEmpty && !stem.hasPrefix("stk_") && !cleanTags.contains(stem) {
                cleanTags.append(stem)
            }

            var entry = MTMediaTokCoreLogic.StickerEntry(
                id: id,
                fileName: diskName,
                tags: cleanTags,
                ocrText: "",
                visionLabels: [],
                addedAt: Int64(Date().timeIntervalSince1970),
                usageCount: 0
            )

            self.lock.lock()
            self.ensureLoadedLocked()
            if self.entries.count >= MTStickerVaultStore.maxStickerCount {
                let removed = self.entries.removeFirst()
                try? FileManager.default.removeItem(at: self.fileURL(for: removed))
            }
            self.entries.append(entry)
            self.schedulePersistLocked()
            self.lock.unlock()

            DispatchQueue.main.async { completion?(entry) }

            // Background offline Apple Vision OCR + Scene Classification
            let indexingImage = UIImage(data: webpData) ?? WebP.convert(fromWebP: webpData) ?? decoded
            if let cgImage = indexingImage.cgImage {
                let visionMeta = MTStickerVaultStore.extractOfflineVisionMetadata(cgImage: cgImage)
                if !visionMeta.ocrText.isEmpty || !visionMeta.labels.isEmpty {
                    self.lock.lock()
                    if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                        self.entries[idx].ocrText = visionMeta.ocrText
                        self.entries[idx].visionLabels = visionMeta.labels
                        entry = self.entries[idx]
                        self.schedulePersistLocked()
                    }
                    self.lock.unlock()
                }
            }

            if runGeminiIfConfigured, let key = self.geminiApiKey(), !key.isEmpty {
                self.autoTagWithGemini(entryId: id, image: indexingImage, apiKey: key, completion: nil)
            }
        }
    }

    func updateTags(id: String, tags: [String]) {
        let cleaned = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.lock.lock()
        self.ensureLoadedLocked()
        if let idx = self.entries.firstIndex(where: { $0.id == id }) {
            self.entries[idx].tags = cleaned
            self.schedulePersistLocked()
        }
        self.lock.unlock()
    }

    func deleteSticker(id: String) {
        self.lock.lock()
        self.ensureLoadedLocked()
        if let idx = self.entries.firstIndex(where: { $0.id == id }) {
            let removed = self.entries.remove(at: idx)
            try? FileManager.default.removeItem(at: self.fileURL(for: removed))
            self.thumbCache.removeObject(forKey: id as NSString)
            self.schedulePersistLocked()
        }
        self.lock.unlock()
    }

    func incrementUsage(id: String) {
        self.lock.lock()
        self.ensureLoadedLocked()
        if let idx = self.entries.firstIndex(where: { $0.id == id }) {
            self.entries[idx].usageCount += 1
            self.schedulePersistLocked()
        }
        self.lock.unlock()
    }

    func sendSticker(entry: MTMediaTokCoreLogic.StickerEntry, context: AccountContext, peerId: PeerId, replyTo: MessageId? = nil) {
        self.ioQueue.async { [weak self] in
            guard let self,
                  let webpData = try? Data(contentsOf: self.fileURL(for: entry)),
                  !webpData.isEmpty else {
                return
            }
            let img = self.loadImage(for: entry)
            let w = Int32(max(128.0, min(512.0, (img?.size.width ?? 512.0))))
            let h = Int32(max(128.0, min(512.0, (img?.size.height ?? 512.0))))

            let fileId = Int64.random(in: Int64.min ... Int64.max)
            let resource = LocalFileMediaResource(fileId: fileId)
            context.account.postbox.mediaBox.storeResourceData(resource.id, data: webpData, synchronous: true)

            let attrs: [TelegramMediaFileAttribute] = [
                .FileName(fileName: "mediatok_vault_\(entry.id.prefix(8)).webp"),
                .Sticker(displayText: "🎭", packReference: nil, maskData: nil),
                .ImageSize(size: PixelDimensions(width: w, height: h))
            ]
            let media = TelegramMediaFile(
                fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: fileId),
                partialReference: nil,
                resource: resource,
                previewRepresentations: [],
                videoThumbnails: [],
                immediateThumbnailData: nil,
                mimeType: "image/webp",
                size: Int64(webpData.count),
                attributes: attrs,
                alternativeRepresentations: []
            )
            let replySubj = replyTo.map { EngineMessageReplySubject(messageId: $0, quote: nil, innerSubject: nil) }
            let msg: EnqueueMessage = .message(
                text: "",
                attributes: [],
                inlineStickers: [:],
                mediaReference: .standalone(media: media),
                threadId: nil,
                replyToMessageId: replySubj,
                replyToStoryId: nil,
                localGroupingKey: nil,
                correlationId: nil,
                bubbleUpEmojiOrStickersets: []
            )
            DispatchQueue.main.async {
                let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [msg]).start()
            }
            self.incrementUsage(id: entry.id)
        }
    }

    // MARK: Offline Apple Vision OCR & Scene Classification

    private static func scaleToSticker512(_ image: UIImage) -> UIImage {
        let maxSide: CGFloat = 512.0
        let w = max(1.0, image.size.width)
        let h = max(1.0, image.size.height)
        let scale = min(1.0, maxSide / max(w, h))
        let targetSize = CGSize(width: max(64.0, floor(w * scale)), height: max(64.0, floor(h * scale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func extractOfflineVisionMetadata(cgImage: CGImage) -> (ocrText: String, labels: [String]) {
        var recognizedLines: [String] = []
        let textReq = VNRecognizeTextRequest { req, _ in
            guard let results = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in results {
                if let top = obs.topCandidates(1).first?.string, !top.isEmpty {
                    recognizedLines.append(top)
                }
            }
        }
        textReq.recognitionLevel = .fast
        textReq.usesLanguageCorrection = false
        textReq.recognitionLanguages = ["ru-RU", "en-US", "uk-UA"]

        var mappedTags: [String] = []
        let classifyReq = VNClassifyImageRequest { req, _ in
            guard let results = req.results as? [VNClassificationObservation] else { return }
            for obs in results.prefix(6) where obs.confidence >= 0.25 {
                for tag in MTMediaTokCoreLogic.visionLabelToRussianTags(obs.identifier) {
                    if !mappedTags.contains(tag) {
                        mappedTags.append(tag)
                    }
                }
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([textReq, classifyReq])
        let joinedOcr = String(recognizedLines.joined(separator: " ").prefix(280))
        return (joinedOcr, Array(mappedTags.prefix(16)))
    }

    // MARK: Optional BYOK Gemini Vision API Keychain & Tagging

    private static let geminiFallbackDefaultsKey = "mediatok.stickers.gemini_key.fb.v1"

    func geminiApiKey() -> String? {
        guard let data = MTMediaTokCoreLogic.resilientSecretLoad(
            service: MTStickerVaultStore.geminiKeychainService,
            account: MTStickerVaultStore.geminiKeychainAccount,
            fallbackKey: MTStickerVaultStore.geminiFallbackDefaultsKey
        ),
        let str = String(data: data, encoding: .utf8),
        !str.isEmpty else {
            return nil
        }
        return str
    }

    func setGeminiApiKey(_ key: String) {
        self.lock.lock()
        self.cachedGeminiModelId = nil
        self.cachedGeminiApiKey = nil
        self.lock.unlock()

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        MTMediaTokCoreLogic.resilientSecretSave(
            trimmed.isEmpty ? nil : Data(trimmed.utf8),
            service: MTStickerVaultStore.geminiKeychainService,
            account: MTStickerVaultStore.geminiKeychainAccount,
            fallbackKey: MTStickerVaultStore.geminiFallbackDefaultsKey
        )
    }

    private var cachedGeminiModelId: String?
    private var cachedGeminiApiKey: String?

    func resolveActiveGeminiFlashModel(apiKey: String, completion: @escaping (String) -> Void) {
        self.lock.lock()
        let cached: String?
        if self.cachedGeminiApiKey == apiKey {
            cached = self.cachedGeminiModelId
        } else {
            self.cachedGeminiModelId = nil
            self.cachedGeminiApiKey = apiKey
            cached = nil
        }
        self.lock.unlock()
        if let cached, !cached.isEmpty {
            completion(cached)
            return
        }
        guard let listUrl = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200") else {
            completion("gemini-flash-latest")
            return
        }
        var req = URLRequest(url: listUrl, timeoutInterval: 10.0)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: req) { [weak self] data, response, _ in
            defer { session.finishTasksAndInvalidate() }
            var chosen = "gemini-flash-latest"
            var resolved = false
            if let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
               let data,
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let models = obj["models"] as? [[String: Any]] {
                resolved = true
                var textModels: [String] = []
                for item in models {
                    guard let rawName = item["name"] as? String else { continue }
                    let methods = (item["supportedGenerationMethods"] as? [String]) ?? []
                    guard methods.contains("generateContent") else { continue }
                    let id = rawName.hasPrefix("models/") ? String(rawName.dropFirst(7)) : rawName
                    let low = id.lowercased()
                    if low.contains("tts") || low.contains("embedding") || low.contains("imagen") || low.contains("veo") || low.contains("aqa") || low.contains("native-audio") || low.contains("image-generation") {
                        continue
                    }
                    textModels.append(id)
                }
                let preferredOrder = [
                    "gemini-flash-latest",
                    "gemini-3-flash-preview",
                    "gemini-2.0-flash",
                    "gemini-2.0-flash-001",
                    "gemini-1.5-flash"
                ]
                if let exact = preferredOrder.first(where: { textModels.contains($0) }) {
                    chosen = exact
                } else if let anyFlash = textModels.first(where: { $0.lowercased().contains("flash") && !$0.lowercased().contains("lite") }) {
                    chosen = anyFlash
                } else if let anyFlashLite = textModels.first(where: { $0.lowercased().contains("flash") }) {
                    chosen = anyFlashLite
                } else if let firstGemini = textModels.first(where: { $0.lowercased().hasPrefix("gemini-") }) {
                    chosen = firstGemini
                }
            }
            if let self {
                self.lock.lock()
                if resolved && self.cachedGeminiApiKey == apiKey {
                    self.cachedGeminiModelId = chosen
                } else if !resolved && self.cachedGeminiApiKey == apiKey {
                    self.cachedGeminiModelId = nil
                }
                self.lock.unlock()
            }
            completion(chosen)
        }.resume()
    }

    struct MTGeminiTextError: Error {
        let message: String
    }

    func generateGeminiText(prompt: String, apiKey: String, completion: @escaping (Result<String, MTGeminiTextError>) -> Void) {
        self.resolveActiveGeminiFlashModel(apiKey: apiKey) { [weak self] modelId in
            let encodedModel = modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelId
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent") else {
                DispatchQueue.main.async { completion(.failure(MTGeminiTextError(message: "Некорректный URL модели Gemini"))) }
                return
            }
            let payload: [String: Any] = [
                "contents": [["parts": [["text": prompt]]]]
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
                DispatchQueue.main.async { completion(.failure(MTGeminiTextError(message: "Ошибка кодирования запроса"))) }
                return
            }
            var req = URLRequest(url: url, timeoutInterval: 22.0)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = body

            let session = URLSession(configuration: .ephemeral)
            session.dataTask(with: req) { [weak self] data, response, error in
                defer { session.finishTasksAndInvalidate() }
                if let error {
                    DispatchQueue.main.async { completion(.failure(MTGeminiTextError(message: error.localizedDescription))) }
                    return
                }
                if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode), let self {
                    self.lock.lock()
                    self.cachedGeminiModelId = nil
                    self.cachedGeminiApiKey = nil
                    self.lock.unlock()
                }
                guard let data,
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    DispatchQueue.main.async { completion(.failure(MTGeminiTextError(message: "Пустой ответ от Gemini API"))) }
                    return
                }
                if let errObj = obj["error"] as? [String: Any] {
                    let msg = (errObj["message"] as? String) ?? "Ошибка Gemini API"
                    if let self {
                        self.lock.lock()
                        self.cachedGeminiModelId = nil
                        self.cachedGeminiApiKey = nil
                        self.lock.unlock()
                    }
                    DispatchQueue.main.async { completion(.failure(MTGeminiTextError(message: msg))) }
                    return
                }
                if let cands = obj["candidates"] as? [[String: Any]],
                   let content = cands.first?["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let answer = parts.first?["text"] as? String,
                   !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DispatchQueue.main.async {
                        completion(.success(answer.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                } else {
                    DispatchQueue.main.async { completion(.failure(MTGeminiTextError(message: "Gemini не вернул текст"))) }
                }
            }.resume()
        }
    }

    func autoTagWithGemini(entryId: String, image: UIImage, apiKey: String, completion: (([String]?) -> Void)?) {
        let scaled = MTStickerVaultStore.scaleToSticker512(image)
        guard let jpegData = scaled.jpegData(compressionQuality: 0.72) else {
            DispatchQueue.main.async { completion?(nil) }
            return
        }

        let prompt = "Give 5 to 10 short search tags in Russian and English separated by commas for this Telegram sticker/meme (person/streamer/celebrity name if recognizable like Mellstroy, anime/character name, emotion, text/meme meaning). Output ONLY comma-separated tags."
        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg", "data": jpegData.base64EncodedString()]]
                ]
            ]]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            DispatchQueue.main.async { completion?(nil) }
            return
        }

        self.resolveActiveGeminiFlashModel(apiKey: apiKey) { [weak self] modelId in
            let encodedModel = modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelId
            guard let self,
                  let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent") else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            var req = URLRequest(url: url, timeoutInterval: 20.0)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = body

            let session = URLSession(configuration: .ephemeral)
            session.dataTask(with: req) { data, response, _ in
                defer { session.finishTasksAndInvalidate() }
                let httpStatus = (response as? HTTPURLResponse)?.statusCode
                let parsedObj = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
                guard let status = httpStatus,
                      (200 ... 299).contains(status),
                      let obj = parsedObj,
                      obj["error"] == nil,
                      let cands = obj["candidates"] as? [[String: Any]],
                      let content = cands.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let text = parts.first?["text"] as? String else {
                    let isHttpError = httpStatus.map { !(200 ... 299).contains($0) } ?? false
                    if isHttpError || parsedObj?["error"] != nil {
                        self.lock.lock()
                        self.cachedGeminiModelId = nil
                        self.cachedGeminiApiKey = nil
                        self.lock.unlock()
                    }
                    DispatchQueue.main.async { completion?(nil) }
                    return
                }

                let parsedTags = text
                    .components(separatedBy: CharacterSet(charactersIn: ",\n;"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.count <= 40 }

                guard !parsedTags.isEmpty else {
                    DispatchQueue.main.async { completion?(nil) }
                    return
                }

                self.lock.lock()
                self.ensureLoadedLocked()
                var merged: [String] = []
                if let idx = self.entries.firstIndex(where: { $0.id == entryId }) {
                    merged = self.entries[idx].tags
                    for t in parsedTags where !merged.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                        merged.append(t)
                    }
                    self.entries[idx].tags = Array(merged.prefix(30))
                    self.schedulePersistLocked()
                }
                self.lock.unlock()

                DispatchQueue.main.async { completion?(merged) }
            }.resume()
        }
    }
}

// MARK: - Hooks & Entry Point

enum MTMediaTokStickerVault {
    static func register() {
        // 1. Slash command interceptor: `/stickers`, `/stickers <q>`, `/s <q>`, `/s! <q>`
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokStickerVault.interceptCommand(request)
        }, order: 18)

        // 2. Message Context Menu: "📥 Сохранить в /stickers" on photos and static stickers
        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokStickerVault.messageMenuItems(menuContext)
        }, order: 82)

        // 3. Send button long-press menu shortcut
        MTChatScreenHooks.sendMenuItems.register({ sendContext in
            let count = MTStickerVaultStore.shared.count
            let context = sendContext.context
            let peerId = sendContext.peerId
            let dismiss = sendContext.dismiss
            return [.action(ContextMenuActionItem(
                text: "Мои /stickers (\(count))",
                icon: { theme in
                    return UIImage(systemName: "face.smiling")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { contextController, _ in
                    contextController?.dismiss(completion: nil)
                    dismiss()
                    MTMediaTokStickerVault.presentPicker(context: context, targetPeerId: peerId, initialQuery: "")
                }
            ))]
        }, order: 8)
    }

    private static func interceptCommand(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()

        if lower == "/stickers" || lower == "/s" || lower.hasPrefix("/stickers ") || lower.hasPrefix("/s ") {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            let query: String
            if lower.hasPrefix("/stickers ") {
                query = String(raw.dropFirst("/stickers ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lower.hasPrefix("/s ") {
                query = String(raw.dropFirst("/s ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                query = ""
            }
            MTMediaTokStickerVault.presentPicker(context: request.context, targetPeerId: peerId, initialQuery: query)
            return true
        }

        if lower.hasPrefix("/s! ") {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            let query = String(raw.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let best = MTStickerVaultStore.shared.search(query, limit: 1).first {
                MTStickerVaultStore.shared.sendSticker(entry: best, context: request.context, peerId: peerId)
            } else {
                MTMediaTokStickerVault.showToast(context: request.context, text: "Стикер по запросу «\(query)» не найден. Добавьте через /stickers")
            }
            return true
        }
        return false
    }

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        let fallbackName = (message.author?.debugDisplayTitle ?? "sticker") + "_" + "\(message.id.id)"

        if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile,
           file.isSticker, !file.isAnimatedSticker,
           file.mimeType.lowercased().contains("webp") || file.mimeType.lowercased().contains("png") {
            let resource = file.resource
            let name = file.fileName ?? "\(fallbackName).webp"
            return [MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Сохранить в /stickers",
                icon: { theme in
                    return UIImage(systemName: "square.and.arrow.down")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokStickerVault.stealResourceToVault(context: context, resource: resource, fileName: name)
                }
            )))]
        }

        return []
    }

    private static func stealResourceToVault(context: AccountContext, resource: MediaResource, fileName: String) {
        let _ = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { data in
            guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: data.path)), !rawData.isEmpty else {
                MTMediaTokStickerVault.showToast(context: context, text: "Не удалось прочитать файл стикера")
                return
            }
            MTStickerVaultStore.shared.addSticker(rawData: rawData, suggestedName: fileName, runGeminiIfConfigured: true) { entry in
                if entry != nil {
                    MTMediaTokStickerVault.showToast(context: context, text: "Добавлено в сейф стикеров (всего: \(MTStickerVaultStore.shared.count))")
                } else {
                    MTMediaTokStickerVault.showToast(context: context, text: "Не удалось добавить стикер")
                }
            }
        })
    }

    static func presentManagerFromMenu(context: MTMenuContext) {
        MTDiscordProfileStore.shared.activeAccountPeerId = context.context.account.peerId
        let isDark = context.context.sharedContext.currentPresentationData.with { $0.theme.overallDarkAppearance }
        let vc = MTStickerVaultPickerViewController(accountContext: context.context, targetPeerId: nil, initialQuery: "")
        vc.overrideUserInterfaceStyle = isDark ? .dark : .light
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = isDark ? .dark : .light
        nav.modalPresentationStyle = .pageSheet
        context.presentNative(nav)
    }

    static func presentPicker(context: AccountContext, targetPeerId: PeerId?, initialQuery: String) {
        MTDiscordProfileStore.shared.activeAccountPeerId = context.account.peerId
        DispatchQueue.main.async {
            let isDark = context.sharedContext.currentPresentationData.with { $0.theme.overallDarkAppearance }
            let vc = MTStickerVaultPickerViewController(accountContext: context, targetPeerId: targetPeerId, initialQuery: initialQuery)
            vc.overrideUserInterfaceStyle = isDark ? .dark : .light
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = isDark ? .dark : .light
            nav.modalPresentationStyle = .pageSheet
            MTModalPresenter.presentOnTopmost(nav)
        }
    }

    private static func showToast(context: AccountContext, text: String) {
        DispatchQueue.main.async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let overlay = UndoOverlayController(
                presentationData: presentationData,
                content: .info(title: nil, text: text, timeout: nil, customUndoText: nil),
                elevatedLayout: false,
                action: { _ in return false }
            )
            context.sharedContext.mainWindow?.present(overlay, on: .root)
        }
    }
}

// MARK: - Sticker Vault Grid Cell

private final class MTStickerVaultCell: UICollectionViewCell {
    static let reuseId = "MTStickerVaultCell"

    var representedEntryId: String?
    private let imageView = UIImageView()
    private let badgeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.backgroundColor = .secondarySystemGroupedBackground
        self.contentView.layer.cornerRadius = 10.0
        self.contentView.clipsToBounds = true

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.imageView)

        self.badgeLabel.font = UIFont.systemFont(ofSize: 9.0, weight: .medium)
        self.badgeLabel.textColor = .white
        self.badgeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        self.badgeLabel.textAlignment = .center
        self.badgeLabel.lineBreakMode = .byTruncatingTail
        self.badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.badgeLabel)

        NSLayoutConstraint.activate([
            self.imageView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 4.0),
            self.imageView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.imageView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0),
            self.imageView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -16.0),
            self.badgeLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            self.badgeLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
            self.badgeLabel.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            self.badgeLabel.heightAnchor.constraint(equalToConstant: 15.0)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.representedEntryId = nil
        self.imageView.image = nil
    }

    func configure(entry: MTMediaTokCoreLogic.StickerEntry, image: UIImage?) {
        self.representedEntryId = entry.id
        self.imageView.image = image
        let labelText = entry.tags.first ?? (entry.ocrText.isEmpty ? (entry.visionLabels.first ?? "стикер") : entry.ocrText)
        self.badgeLabel.text = " " + labelText + " "
    }

    func setLoadedImage(_ image: UIImage?, forId id: String) {
        guard self.representedEntryId == id else { return }
        self.imageView.image = image
    }
}

// MARK: - /stickers Search & Browser UI

private final class MTStickerVaultPickerViewController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
    UISearchBarDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {

    private let accountContext: AccountContext
    private let targetPeerId: PeerId?
    private var currentQuery: String
    private var items: [MTMediaTokCoreLogic.StickerEntry] = []

    private let searchBar = UISearchBar()
    private let emptyLabel = UILabel()
    private let collectionView: UICollectionView

    init(accountContext: AccountContext, targetPeerId: PeerId?, initialQuery: String) {
        self.accountContext = accountContext
        self.targetPeerId = targetPeerId
        self.currentQuery = initialQuery
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8.0
        layout.minimumLineSpacing = 8.0
        layout.sectionInset = UIEdgeInsets(top: 10.0, left: 12.0, bottom: 16.0, right: 12.0)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let isDark = self.accountContext.sharedContext.currentPresentationData.with { $0.theme.overallDarkAppearance }
        self.overrideUserInterfaceStyle = isDark ? .dark : .light
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closeTapped))

        let lanBtn = UIBarButtonItem(image: UIImage(systemName: "wifi"), style: .plain, target: self, action: #selector(self.openLanUploaderTapped))
        let aiBtn = UIBarButtonItem(image: UIImage(systemName: "wand.and.stars"), style: .plain, target: self, action: #selector(self.aiSettingsTapped))
        let addBtn = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.addMenuTapped))
        self.navigationItem.rightBarButtonItems = [addBtn, lanBtn, aiBtn]

        self.searchBar.delegate = self
        self.searchBar.placeholder = "Поиск по тегам или тексту (/s кот, мем...)"
        self.searchBar.text = self.currentQuery
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.searchBar)

        self.collectionView.backgroundColor = .clear
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.keyboardDismissMode = .onDrag
        self.collectionView.register(MTStickerVaultCell.self, forCellWithReuseIdentifier: MTStickerVaultCell.reuseId)
        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.collectionView)

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(self.handleLongPress(_:)))
        self.collectionView.addGestureRecognizer(lp)

        self.emptyLabel.numberOfLines = 0
        self.emptyLabel.textAlignment = .center
        self.emptyLabel.font = UIFont.systemFont(ofSize: 14.0)
        self.emptyLabel.textColor = .secondaryLabel
        self.emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.emptyLabel)

        NSLayoutConstraint.activate([
            self.searchBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 4.0),
            self.searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -4.0),
            self.collectionView.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.emptyLabel.centerXAnchor.constraint(equalTo: self.collectionView.centerXAnchor),
            self.emptyLabel.centerYAnchor.constraint(equalTo: self.collectionView.centerYAnchor),
            self.emptyLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 28.0),
            self.emptyLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -28.0)
        ])

        self.reloadResults()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.reloadResults()
    }

    private func reloadResults() {
        let total = MTStickerVaultStore.shared.count
        self.title = "Сейф стикеров (\(total))"
        self.items = MTStickerVaultStore.shared.search(self.currentQuery, limit: 160)
        self.collectionView.reloadData()
        if self.items.isEmpty {
            self.emptyLabel.isHidden = false
            self.emptyLabel.text = total == 0
                ? "Сейф стикеров пока пуст.\n\nНажмите «+» для загрузки с iPhone, значок Wi-Fi для загрузки папок с ПК, или зажмите любой стикер в чате → «Сохранить в /stickers»."
                : "По запросу «\(self.currentQuery)» ничего не найдено."
        } else {
            self.emptyLabel.isHidden = true
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.currentQuery = searchText
        self.reloadResults()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MTStickerVaultCell.reuseId, for: indexPath) as! MTStickerVaultCell
        let entry = self.items[indexPath.item]
        if let cached = MTStickerVaultStore.shared.cachedImage(for: entry) {
            cell.configure(entry: entry, image: cached)
        } else {
            cell.configure(entry: entry, image: nil)
            MTStickerVaultStore.shared.loadImageAsync(for: entry) { [weak cell] img in
                cell?.setLoadedImage(img, forId: entry.id)
            }
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = max(60.0, floor((collectionView.bounds.width - 24.0 - 24.0) / 4.0))
        return CGSize(width: width, height: width + 12.0)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let entry = self.items[indexPath.item]
        if let peerId = self.targetPeerId {
            MTStickerVaultStore.shared.sendSticker(entry: entry, context: self.accountContext, peerId: peerId)
            self.dismiss(animated: true)
        } else {
            self.presentEntryActions(entry)
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let pt = recognizer.location(in: self.collectionView)
        guard let idxPath = self.collectionView.indexPathForItem(at: pt), idxPath.item < self.items.count else { return }
        self.presentEntryActions(self.items[idxPath.item])
    }

    private func presentEntryActions(_ entry: MTMediaTokCoreLogic.StickerEntry) {
        let tagDesc = entry.tags.isEmpty ? "нет тегов" : entry.tags.joined(separator: ", ")
        mtPresentNativeActionSheet(
            context: self.accountContext,
            title: "Стикер • \(tagDesc)",
            buttons: [
                (title: "Изменить теги", isDestructive: false, action: { [weak self] in
                    self?.presentTagEditor(entry: entry)
                }),
                (title: "Определить теги через Gemini ИИ", isDestructive: false, action: { [weak self] in
                    guard let strongSelf = self else { return }
                    guard let key = MTStickerVaultStore.shared.geminiApiKey(), !key.isEmpty else {
                        strongSelf.aiSettingsTapped()
                        return
                    }
                    guard let img = MTStickerVaultStore.shared.loadImage(for: entry) else { return }
                    MTStickerVaultStore.shared.autoTagWithGemini(entryId: entry.id, image: img, apiKey: key) { tags in
                        if let tags {
                            strongSelf.reloadResults()
                            mtPresentNativeToast(context: strongSelf.accountContext, text: "Теги добавлены: \(tags.joined(separator: ", "))")
                        }
                    }
                }),
                (title: "Скопировать изображение", isDestructive: false, action: { [weak self] in
                    if let img = MTStickerVaultStore.shared.loadImage(for: entry) {
                        UIPasteboard.general.image = img
                        if let strongSelf = self {
                            mtPresentNativeToast(context: strongSelf.accountContext, text: "Изображение скопировано")
                        }
                    }
                }),
                (title: "Удалить стикер", isDestructive: true, action: { [weak self] in
                    MTStickerVaultStore.shared.deleteSticker(id: entry.id)
                    self?.reloadResults()
                })
            ]
        )
    }

    private func presentTagEditor(entry: MTMediaTokCoreLogic.StickerEntry) {
        mtPresentNativePrompt(
            context: self.accountContext,
            title: "Теги стикера",
            subtitle: "Укажите ключевые слова через запятую для поиска через /s:",
            value: entry.tags.joined(separator: ", "),
            placeholder: "кот, мем, реакция...",
            apply: { [weak self] raw in
                let tags = raw.components(separatedBy: CharacterSet(charactersIn: ",;"))
                MTStickerVaultStore.shared.updateTags(id: entry.id, tags: tags)
                self?.reloadResults()
            }
        )
    }

    @objc private func addMenuTapped() {
        mtPresentNativeActionSheet(
            context: self.accountContext,
            title: "Добавить стикеры",
            buttons: [
                (title: "Из Фото / Галереи", isDestructive: false, action: { [weak self] in
                    guard let strongSelf = self else { return }
                    var config = PHPickerConfiguration()
                    config.selectionLimit = 0
                    config.filter = .images
                    let picker = PHPickerViewController(configuration: config)
                    picker.delegate = strongSelf
                    MTModalPresenter.presentWhenReady(picker, from: strongSelf)
                }),
                (title: "Из Файлов (.webp / .png / .jpg)", isDestructive: false, action: { [weak self] in
                    guard let strongSelf = self else { return }
                    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .webP, .png, .jpeg], asCopy: true)
                    picker.allowsMultipleSelection = true
                    picker.delegate = strongSelf
                    MTModalPresenter.presentWhenReady(picker, from: strongSelf)
                }),
                (title: "Загрузить с ПК по Wi-Fi", isDestructive: false, action: { [weak self] in
                    self?.openLanUploaderTapped()
                })
            ]
        )
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        let group = DispatchGroup()
        for res in results where res.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            group.enter()
            let suggested = res.itemProvider.suggestedName ?? "photo"
            res.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data {
                    MTStickerVaultStore.shared.addSticker(rawData: data, suggestedName: suggested, runGeminiIfConfigured: true) { _ in
                        group.leave()
                    }
                } else {
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.reloadResults()
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        let group = DispatchGroup()
        for url in urls {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = try? Data(contentsOf: url)
                let name = url.lastPathComponent
                try? FileManager.default.removeItem(at: url)
                if let data {
                    MTStickerVaultStore.shared.addSticker(rawData: data, suggestedName: name, runGeminiIfConfigured: true) { _ in
                        group.leave()
                    }
                } else {
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.reloadResults()
        }
    }

    @objc private func openLanUploaderTapped() {
        let ctx = self.accountContext
        self.dismiss(animated: true) {
            let lanCtrl = mtMakeNativeLanUploaderController(context: ctx)
            mtPushNativeController(lanCtrl, context: ctx)
        }
    }

    @objc private func aiSettingsTapped() {
        let existing = MTStickerVaultStore.shared.geminiApiKey() ?? ""
        mtPresentNativePrompt(
            context: self.accountContext,
            title: "Gemini API для стикеров",
            subtitle: "Офлайн OCR Apple Vision работает всегда. По желанию укажите ключ Gemini API (хранится в Keychain) для распознавания мемов и персонажей:",
            value: existing,
            placeholder: "AIza... (пусто для отключения)",
            apply: { [weak self] key in
                MTStickerVaultStore.shared.setGeminiApiKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
                if let strongSelf = self {
                    mtPresentNativeToast(context: strongSelf.accountContext, text: key.isEmpty ? "Ключ Gemini удалён" : "Ключ Gemini сохранён в Keychain")
                }
            }
        )
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}

// MARK: - Local Wi-Fi PC Drag-and-Drop Web Uploader (Stickers + Music + Fonts)

private final class MTMediaTokLanUploader {
    private let queue = DispatchQueue(label: "org.mediatok.lan_uploader")
    private let maxConcurrentConnections = 4
    private let maxHeaderBytes = 16 * 1024
    private let maxBodyBytes = 25 * 1024 * 1024
    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    private var pinStorage: String = ""
    private let pinLock = NSLock()
    var pin: String {
        self.pinLock.lock()
        defer { self.pinLock.unlock() }
        return self.pinStorage
    }
    private var failedPinAttempts: Int = 0
    private var pinLockedUntil: Date = .distantPast
    private(set) var port: UInt16 = 0
    var onLog: ((String) -> Void)?

    func start(completion: @escaping (String?) -> Void) {
        let code = String(format: "%04d", Int.random(in: 1000 ... 9999))
        self.pinLock.lock()
        self.pinStorage = code
        self.pinLock.unlock()

        self.queue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.stopLocked()

            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listenerObj: NWListener
            if let preferred = NWEndpoint.Port(rawValue: 8787), let l = try? NWListener(using: params, on: preferred) {
                listenerObj = l
            } else if let l = try? NWListener(using: params) {
                listenerObj = l
            } else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            strongSelf.listener = listenerObj
            var didNotify = false
            listenerObj.stateUpdateHandler = { [weak self] state in
                guard let s = self, !didNotify else { return }
                switch state {
                case .ready:
                    didNotify = true
                    let actualPort = s.listener?.port?.rawValue ?? 8787
                    s.port = actualPort
                    let ip = MTMediaTokLanUploader.localWiFiIPv4() ?? "127.0.0.1"
                    DispatchQueue.main.async {
                        completion("http://\(ip):\(actualPort)")
                    }
                case .failed:
                    didNotify = true
                    DispatchQueue.main.async { completion(nil) }
                default:
                    break
                }
            }
            listenerObj.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            listenerObj.start(queue: strongSelf.queue)
        }
    }

    private func stopLocked() {
        self.listener?.cancel()
        self.listener = nil
        for conn in self.activeConnections.values {
            conn.cancel()
        }
        self.activeConnections.removeAll()
    }

    func stop() {
        self.queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    private func closeConnection(_ conn: NWConnection) {
        let key = ObjectIdentifier(conn)
        self.activeConnections.removeValue(forKey: key)
        conn.cancel()
    }

    private func handleConnection(_ conn: NWConnection) {
        if self.activeConnections.count >= self.maxConcurrentConnections {
            conn.cancel()
            return
        }
        let connKey = ObjectIdentifier(conn)
        self.activeConnections[connKey] = conn
        conn.start(queue: self.queue)

        let timeoutWork = DispatchWorkItem { [weak self, weak conn] in
            guard let self, let conn else { return }
            self.closeConnection(conn)
        }
        self.queue.asyncAfter(deadline: .now() + 30.0, execute: timeoutWork)

        var buffer = Data()
        var expectedBodyLength: Int?
        var headerEndOffset: Int?

        func receiveChunk() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
                guard let strongSelf = self else {
                    timeoutWork.cancel()
                    conn.cancel()
                    return
                }
                if error != nil {
                    timeoutWork.cancel()
                    strongSelf.closeConnection(conn)
                    return
                }
                if let data, !data.isEmpty {
                    if headerEndOffset == nil && buffer.count + data.count > strongSelf.maxHeaderBytes + 4096 {
                        if buffer.range(of: Data("\r\n\r\n".utf8)) == nil {
                            timeoutWork.cancel()
                            strongSelf.sendJson(conn, status: "431 Request Header Fields Too Large", body: "{\"ok\":false,\"error\":\"Headers too large\"}")
                            strongSelf.activeConnections.removeValue(forKey: connKey)
                            return
                        }
                    }
                    if buffer.count + data.count > strongSelf.maxBodyBytes + strongSelf.maxHeaderBytes {
                        timeoutWork.cancel()
                        strongSelf.sendJson(conn, status: "413 Payload Too Large", body: "{\"ok\":false,\"error\":\"File too large (>25MB)\"}")
                        strongSelf.activeConnections.removeValue(forKey: connKey)
                        return
                    }
                    buffer.append(data)
                }

                if headerEndOffset == nil, let sepRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    guard sepRange.lowerBound <= strongSelf.maxHeaderBytes else {
                        timeoutWork.cancel()
                        strongSelf.sendJson(conn, status: "431 Request Header Fields Too Large", body: "{\"ok\":false,\"error\":\"Headers too large\"}")
                        strongSelf.activeConnections.removeValue(forKey: connKey)
                        return
                    }
                    headerEndOffset = sepRange.upperBound
                    let headerData = buffer.subdata(in: 0 ..< sepRange.lowerBound)
                    guard let headerStr = String(data: headerData, encoding: .isoLatin1) else {
                        timeoutWork.cancel()
                        strongSelf.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Invalid headers\"}")
                        strongSelf.activeConnections.removeValue(forKey: connKey)
                        return
                    }
                    let lines = headerStr.components(separatedBy: "\r\n")
                    let reqLine = (lines.first ?? "").components(separatedBy: " ")
                    let method = reqLine.first?.uppercased() ?? "GET"
                    var seenContentLength = false
                    var parsedLength = 0
                    var headerPin = ""
                    for line in lines.dropFirst() {
                        let lower = line.lowercased()
                        if lower.hasPrefix("transfer-encoding:") && lower.contains("chunked") {
                            timeoutWork.cancel()
                            strongSelf.sendJson(conn, status: "411 Length Required", body: "{\"ok\":false,\"error\":\"Chunked encoding not supported\"}")
                            strongSelf.activeConnections.removeValue(forKey: connKey)
                            return
                        }
                        if lower.hasPrefix("content-length:") {
                            let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                            guard !seenContentLength, let n = Int(val), n >= 0 else {
                                timeoutWork.cancel()
                                strongSelf.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Invalid Content-Length\"}")
                                strongSelf.activeConnections.removeValue(forKey: connKey)
                                return
                            }
                            seenContentLength = true
                            parsedLength = n
                        } else if lower.hasPrefix("x-pin:") {
                            headerPin = line.dropFirst("x-pin:".count).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    if parsedLength > strongSelf.maxBodyBytes {
                        timeoutWork.cancel()
                        strongSelf.sendJson(conn, status: "413 Payload Too Large", body: "{\"ok\":false,\"error\":\"File too large (>25MB)\"}")
                        strongSelf.activeConnections.removeValue(forKey: connKey)
                        return
                    }
                    // Authenticate POST immediately on headers BEFORE buffering 25MB body (C1/C9 DoS fix)
                    if method == "POST" {
                        if Date() < strongSelf.pinLockedUntil {
                            timeoutWork.cancel()
                            strongSelf.sendJson(conn, status: "429 Too Many Requests", body: "{\"ok\":false,\"error\":\"Слишком много неверных PIN. Подождите 60 сек.\"}")
                            strongSelf.activeConnections.removeValue(forKey: connKey)
                            return
                        }
                        if !MTMediaTokCoreLogic.constantTimeEquals(headerPin, strongSelf.pin) {
                            strongSelf.failedPinAttempts += 1
                            if strongSelf.failedPinAttempts >= 5 {
                                strongSelf.pinLockedUntil = Date().addingTimeInterval(60.0)
                                strongSelf.failedPinAttempts = 0
                                strongSelf.emitLog("🔒 Блокировка на 60 сек после 5 неверных PIN")
                            }
                            timeoutWork.cancel()
                            strongSelf.sendJson(conn, status: "403 Forbidden", body: "{\"ok\":false,\"error\":\"Неверный PIN-код\"}")
                            strongSelf.activeConnections.removeValue(forKey: connKey)
                            return
                        }
                        strongSelf.failedPinAttempts = 0
                    }
                    expectedBodyLength = parsedLength
                }

                if let hEnd = headerEndOffset, let expLen = expectedBodyLength {
                    if buffer.count - hEnd >= expLen {
                        timeoutWork.cancel()
                        strongSelf.activeConnections.removeValue(forKey: connKey)
                        strongSelf.dispatchHttpRequest(conn: conn, buffer: buffer, headerEnd: hEnd, bodyLength: expLen)
                        return
                    }
                    if isComplete {
                        // Truncated upload — reject instead of saving corrupted file (H25)
                        timeoutWork.cancel()
                        strongSelf.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Truncated upload\"}")
                        strongSelf.activeConnections.removeValue(forKey: connKey)
                        return
                    }
                }

                if isComplete {
                    timeoutWork.cancel()
                    strongSelf.closeConnection(conn)
                    return
                }
                receiveChunk()
            }
        }
        receiveChunk()
    }

    private func dispatchHttpRequest(conn: NWConnection, buffer: Data, headerEnd: Int, bodyLength: Int) {
        let headerRaw = String(data: buffer.subdata(in: 0 ..< max(0, headerEnd - 4)), encoding: .isoLatin1) ?? ""
        let lines = headerRaw.components(separatedBy: "\r\n")
        let reqLine = (lines.first ?? "").components(separatedBy: " ")
        let method = reqLine.first?.uppercased() ?? "GET"
        let fullTarget = reqLine.count > 1 ? reqLine[1] : "/"

        let normalizedTarget = fullTarget.hasPrefix("/") ? fullTarget : "/\(fullTarget)"
        let comps = URLComponents(string: "http://localhost\(normalizedTarget)")
        let path = comps?.path ?? "/"
        var queryMap: [String: String] = [:]
        for item in comps?.queryItems ?? [] {
            queryMap[item.name] = item.value ?? ""
        }

        if method == "GET" && (path == "/" || path == "/index.html") {
            self.sendHtml(conn, html: MTMediaTokLanUploader.webUploaderHtml)
            return
        }

        if Date() < self.pinLockedUntil {
            self.sendJson(conn, status: "429 Too Many Requests", body: "{\"ok\":false,\"error\":\"Слишком много неверных PIN. Подождите 60 сек.\"}")
            return
        }

        // Strict X-Pin header only (no query-string ?pin= CSRF bypass)
        let headerPin = lines.first(where: { $0.lowercased().hasPrefix("x-pin:") })?
            .dropFirst("x-pin:".count).trimmingCharacters(in: .whitespaces) ?? ""
        guard MTMediaTokCoreLogic.constantTimeEquals(headerPin, self.pin) else {
            self.sendJson(conn, status: "403 Forbidden", body: "{\"ok\":false,\"error\":\"Неверный PIN-код\"}")
            return
        }

        let body = bodyLength > 0 ? buffer.subdata(in: headerEnd ..< (headerEnd + bodyLength)) : Data()
        guard !body.isEmpty else {
            self.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Empty body\"}")
            return
        }

        let cleanName = MTMediaTokCoreLogic.sanitizeUploadFileName(queryMap["name"] ?? "upload")

        if method == "POST" && path == "/api/upload/sticker" {
            let rawTags = (queryMap["tags"] ?? "").components(separatedBy: CharacterSet(charactersIn: ",;"))
            MTStickerVaultStore.shared.addSticker(rawData: body, suggestedName: cleanName, initialTags: rawTags, runGeminiIfConfigured: true) { [weak self] entry in
                guard let self else { conn.cancel(); return }
                self.queue.async {
                    if entry != nil {
                        self.emitLog("🎭 Стикер: \(cleanName)")
                        self.sendJson(conn, status: "200 OK", body: "{\"ok\":true}")
                    } else {
                        self.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Unsupported image\"}")
                    }
                }
            }
            return
        }

        if method == "POST" && path == "/api/upload/music" {
            let ext = (cleanName as NSString).pathExtension
            let title = (cleanName as NSString).deletingPathExtension
            DispatchQueue.main.async { [weak self] in
                let ok = MTDiscordProfileStore.shared.addUploadedTrackToOwnProfile(data: body, ext: ext, title: title)
                guard let self else { conn.cancel(); return }
                self.queue.async {
                    if ok {
                        self.emitLog("🎵 Трек в профиль: \(title)")
                        self.sendJson(conn, status: "200 OK", body: "{\"ok\":true}")
                    } else {
                        self.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Откройте сначала профиль в MediaTok\"}")
                    }
                }
            }
            return
        }

        if method == "POST" && path == "/api/upload/font" {
            let ext = (cleanName as NSString).pathExtension.lowercased()
            let safeExt = ["ttf", "otf", "ttc"].contains(ext) ? ext : "ttf"
            let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("lan_\(UUID().uuidString).\(safeExt)")
            do {
                try body.write(to: tempUrl, options: [.atomic])
                DispatchQueue.main.async { [weak self] in
                    MTCustomFonts.importFont(at: tempUrl) { res in
                        try? FileManager.default.removeItem(at: tempUrl)
                        guard let self else { conn.cancel(); return }
                        self.queue.async {
                            switch res {
                            case let .added(font):
                                self.emitLog("🔤 Шрифт: \(font.familyName)")
                                self.sendJson(conn, status: "200 OK", body: "{\"ok\":true}")
                            default:
                                self.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Invalid font or limit reached\"}")
                            }
                        }
                    }
                }
            } catch {
                self.sendJson(conn, status: "500 Internal Server Error", body: "{\"ok\":false,\"error\":\"Write error\"}")
            }
            return
        }

        self.sendJson(conn, status: "404 Not Found", body: "{\"ok\":false,\"error\":\"Not found\"}")
    }

    private func emitLog(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onLog?(text)
        }
    }

    private func sendHtml(_ conn: NWConnection, html: String) {
        let bodyData = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var resp = Data(header.utf8)
        resp.append(bodyData)
        conn.send(content: resp, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private func sendJson(_ conn: NWConnection, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var resp = Data(header.utf8)
        resp.append(bodyData)
        conn.send(content: resp, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static func localWiFiIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var fallbackEn: String?
        var fallbackBridge: String?
        var fallbackOther: String?
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addrPtr = interface.ifa_addr, addrPtr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addrPtr, socklen_t(addrPtr.pointee.sa_len),
                              &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let ip = String(cString: hostname)
            guard !ip.isEmpty, !ip.hasPrefix("169.254.") else { continue }
            let name = String(cString: interface.ifa_name)
            if name == "en0" {
                return ip
            } else if name.hasPrefix("en") {
                if fallbackEn == nil { fallbackEn = ip }
            } else if name.hasPrefix("bridge") {
                if fallbackBridge == nil { fallbackBridge = ip }
            } else if !name.hasPrefix("pdp_ip") && !name.hasPrefix("utun") {
                if fallbackOther == nil { fallbackOther = ip }
            }
        }
        return fallbackEn ?? fallbackBridge ?? fallbackOther
    }

    private static let webUploaderHtml = """
    <!DOCTYPE html>
    <html lang="ru">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>MediaTok iOS — Wi-Fi Uploader</title>
    <style>
    body{font-family:-apple-system,Segoe UI,sans-serif;background:#0b0f17;color:#eef2ff;margin:0;padding:24px}
    .card{max-width:640px;margin:0 auto;background:#131a29;border:1px solid #26314a;border-radius:18px;padding:24px;box-shadow:0 20px 50px rgba(0,0,0,.45)}
    h1{margin:0 0 8px;font-size:22px;color:#00f5ff}
    p{color:#9aa8c7;font-size:14px;line-height:1.45}
    .row{display:flex;gap:10px;margin:14px 0;flex-wrap:wrap}
    input,select{background:#0b0f17;color:#fff;border:1px solid #303d5e;border-radius:10px;padding:10px 12px;font-size:15px}
    .drop{border:2px dashed #00f5ff;border-radius:14px;padding:28px;text-align:center;margin:16px 0;background:rgba(0,245,255,.04)}
    .btn{background:#00f5ff;color:#041019;font-weight:700;border:none;border-radius:10px;padding:11px 16px;cursor:pointer;font-size:14px}
    #prog{font-size:14px;margin-top:10px;color:#7ef9a9;white-space:pre-line}
    </style>
    </head>
    <body>
    <div class="card">
      <h1>⚡ MediaTok iOS — Загрузка с ПК по Wi-Fi</h1>
      <p>Введите 4-значный PIN с экрана iPhone и перетащите файлы или целую папку стикеров (/stickers до 10 000 шт), треки профиля (.mp3/.m4a) или шрифты (.ttf/.otf).</p>
      <div class="row">
        <input id="pin" placeholder="PIN с iPhone" maxlength="4" style="width:130px">
        <select id="kind">
          <option value="sticker">🎭 В /stickers (WebP/PNG/JPG)</option>
          <option value="music">🎵 В плейлист профиля (MP3/M4A)</option>
          <option value="font">🔤 Шрифт интерфейса (TTF/OTF)</option>
        </select>
      </div>
      <div class="row">
        <input id="tags" placeholder="Теги для стикеров через запятую (опционально)" style="flex:1">
      </div>
      <div class="drop" id="drop">
        Перетащите файлы сюда<br><br>
        <input id="files" type="file" multiple style="display:none">
        <input id="folder" type="file" webkitdirectory directory multiple style="display:none">
        <button class="btn" onclick="document.getElementById('files').click()">Выбрать файлы</button>
        <button class="btn" onclick="document.getElementById('folder').click()">Выбрать папку</button>
      </div>
      <div id="prog">Ожидание файлов...</div>
    </div>
    <script>
    const prog=document.getElementById('prog');
    async function uploadList(fileList){
      const pin=document.getElementById('pin').value.trim();
      const kind=document.getElementById('kind').value;
      const tags=encodeURIComponent(document.getElementById('tags').value.trim());
      if(pin.length!==4){alert('Введите 4-значный PIN с экрана iPhone');return;}
      let ok=0,fail=0;
      const arr=Array.from(fileList);
      for(let i=0;i<arr.length;i++){
        const f=arr[i];
        prog.textContent=`Загрузка ${i+1} / ${arr.length}: ${f.name} (OK: ${ok}, Ошибки: ${fail})`;
        try{
          const url=`/api/upload/${kind}?name=${encodeURIComponent(f.name)}&tags=${tags}`;
          const r=await fetch(url,{method:'POST',headers:{'X-Pin':pin},body:f});
          if(r.ok) ok++; else fail++;
        }catch(e){fail++;}
      }
      prog.textContent=`Готово! Успешно загружено: ${ok}, ошибок: ${fail}`;
    }
    document.getElementById('files').onchange=e=>uploadList(e.target.files);
    document.getElementById('folder').onchange=e=>uploadList(e.target.files);
    const d=document.getElementById('drop');
    d.ondragover=e=>{e.preventDefault();};
    d.ondrop=e=>{e.preventDefault();uploadList(e.dataTransfer.files);};
    </script>
    </body>
    </html>
    """
}

private func mtMakeNativeLanUploaderController(context: AccountContext) -> ItemListController {
    final class LanStateBox {
        let uploader = MTMediaTokLanUploader()
        var urlText: String = "Запуск сервера..."
        var pinText: String = "—"
        var logs: [String] = []
        deinit {
            self.uploader.stop()
        }
    }

    let stateAtomic = Atomic<LanStateBox>(value: LanStateBox())
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revCount = 0
    let bump: () -> Void = {
        revCount += 1
        revision.set(revCount)
    }

    weak var weakController: ItemListController?

    let box = stateAtomic.with { $0 }
    box.uploader.onLog = { entry in
        let _ = stateAtomic.modify { st in
            st.logs.insert(entry, at: 0)
            if st.logs.count > 40 {
                st.logs.removeLast()
            }
            return st
        }
        bump()
    }
    box.uploader.start { url in
        let _ = stateAtomic.modify { st in
            if let url {
                st.urlText = url
                st.pinText = st.uploader.pin
            } else {
                st.urlText = "Ошибка запуска (проверьте Wi-Fi)"
                st.pinText = "—"
            }
            return st
        }
        bump()
    }

    let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let snap = stateAtomic.with { ($0.urlText, $0.pinText, $0.logs) }
        var screen = MTNativeScreenModel(title: "Загрузка с ПК по Wi-Fi")

        screen.sections.append([
            MTNativeRow(id: "lan.h", kind: .header("Параметры подключения")),
            MTNativeRow(id: "lan.url", kind: .disclosure(title: "Адрес в браузере на ПК", label: snap.0, icon: .system("wifi"), enabled: true)),
            MTNativeRow(id: "lan.pin", kind: .disclosure(title: "PIN-код доступа", label: snap.1, icon: .system("lock"), enabled: true)),
            MTNativeRow(id: "lan.f", kind: .footer("Откройте указанный адрес в браузере на компьютере (в одной Wi-Fi сети), введите 4-значный PIN и перетащите файлы или папку со стикерами, треками (.mp3) или шрифтами (.ttf). Нажмите на строку, чтобы скопировать."))
        ])

        screen.tap["lan.url"] = {
            if snap.0.hasPrefix("http") {
                UIPasteboard.general.string = snap.0
                mtPresentNativeToast(context: context, from: weakController, text: "Адрес скопирован")
            }
        }
        screen.tap["lan.pin"] = {
            if snap.1 != "—" {
                UIPasteboard.general.string = snap.1
                mtPresentNativeToast(context: context, from: weakController, text: "PIN скопирован")
            }
        }

        var logRows: [MTNativeRow] = [
            MTNativeRow(id: "log.h", kind: .header("Журнал загрузок (\(snap.2.count))"))
        ]
        if snap.2.isEmpty {
            logRows.append(MTNativeRow(id: "log.empty", kind: .info("Ожидание файлов...")))
        } else {
            for (idx, line) in snap.2.enumerated() {
                logRows.append(MTNativeRow(id: "log.\(idx)", kind: .info("#\(snap.2.count - idx) • \(line)")))
            }
        }
        screen.sections.append(logRows)

        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}
