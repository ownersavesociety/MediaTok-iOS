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
import UndoUI
import WebPBinding
import GGCore
import GGHooks
import GGSettingsUI

// MARK: - Persistent 10,000-Sticker Vault Store with Offline Apple Vision AI & Optional BYOK Gemini

final class GGStickerVaultStore {
    static let shared = GGStickerVaultStore()

    private static let geminiKeychainService = "org.mediatok.sticker_vault.gemini_key"
    private static let geminiKeychainAccount = "api_key"
    private static let maxStickerCount = 10_000

    private let lock = NSLock()
    private let aiQueue = DispatchQueue(label: "org.mediatok.sticker_vault.vision", qos: .utility)
    private let thumbCache = NSCache<NSString, UIImage>()
    private var loaded = false
    private var entries: [GGMediaTokCoreLogic.StickerEntry] = []

    private init() {
        self.thumbCache.countLimit = 400
    }

    private func rootDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ghostgram/mediatok/sticker_vault", isDirectory: true)
    }

    private func indexURL() -> URL {
        return self.rootDir().appendingPathComponent("index.json")
    }

    private func ensureLoadedLocked() {
        if self.loaded { return }
        self.loaded = true
        guard let data = try? Data(contentsOf: self.indexURL()),
              let decoded = try? JSONDecoder().decode([GGMediaTokCoreLogic.StickerEntry].self, from: data) else {
            return
        }
        self.entries = decoded
    }

    private func persistLocked() {
        let dir = self.rootDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        if let data = try? enc.encode(self.entries) {
            try? data.write(to: self.indexURL(), options: [.atomic])
        }
    }

    var count: Int {
        self.lock.lock()
        self.ensureLoadedLocked()
        let c = self.entries.count
        self.lock.unlock()
        return c
    }

    func allEntries() -> [GGMediaTokCoreLogic.StickerEntry] {
        self.lock.lock()
        self.ensureLoadedLocked()
        let snap = self.entries
        self.lock.unlock()
        return snap
    }

    func search(_ query: String, limit: Int = 120) -> [GGMediaTokCoreLogic.StickerEntry] {
        let snap = self.allEntries()
        return GGMediaTokCoreLogic.searchStickers(snap, query: query, limit: limit)
    }

    func fileURL(for entry: GGMediaTokCoreLogic.StickerEntry) -> URL {
        return self.rootDir().appendingPathComponent(entry.fileName)
    }

    func loadImage(for entry: GGMediaTokCoreLogic.StickerEntry) -> UIImage? {
        let key = entry.id as NSString
        if let cached = self.thumbCache.object(forKey: key) {
            return cached
        }
        let url = self.fileURL(for: entry)
        guard let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) ?? WebP.convert(fromWebP: data) else {
            return nil
        }
        self.thumbCache.setObject(img, forKey: key)
        return img
    }

    func addSticker(
        rawData: Data,
        suggestedName: String,
        initialTags: [String] = [],
        runGeminiIfConfigured: Bool = false,
        completion: ((GGMediaTokCoreLogic.StickerEntry?) -> Void)? = nil
    ) {
        self.aiQueue.async {
            guard !rawData.isEmpty, rawData.count <= 15 * 1024 * 1024,
                  let decoded = UIImage(data: rawData) ?? WebP.convert(fromWebP: rawData) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let webpData: Data
            let isAlreadySmallWebP = rawData.count <= 512 * 1024
                && suggestedName.lowercased().hasSuffix(".webp")
                && decoded.size.width <= 520.0
                && decoded.size.height <= 520.0
            if isAlreadySmallWebP {
                webpData = rawData
            } else {
                let normalized = GGStickerVaultStore.scaleToSticker512(decoded)
                guard let encoded = try? WebP.convert(toWebP: normalized, quality: 88.0), !encoded.isEmpty else {
                    DispatchQueue.main.async { completion?(nil) }
                    return
                }
                webpData = encoded
            }

            let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let cleanBase = GGMediaTokCoreLogic.sanitizeUploadFileName(suggestedName)
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

            var entry = GGMediaTokCoreLogic.StickerEntry(
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
            if self.entries.count >= GGStickerVaultStore.maxStickerCount {
                let removed = self.entries.removeFirst()
                try? FileManager.default.removeItem(at: self.fileURL(for: removed))
            }
            self.entries.append(entry)
            self.persistLocked()
            self.lock.unlock()

            DispatchQueue.main.async { completion?(entry) }

            // Background offline Apple Vision OCR + Scene Classification
            let indexingImage = UIImage(data: webpData) ?? WebP.convert(fromWebP: webpData) ?? decoded
            if let cgImage = indexingImage.cgImage {
                let visionMeta = GGStickerVaultStore.extractOfflineVisionMetadata(cgImage: cgImage)
                if !visionMeta.ocrText.isEmpty || !visionMeta.labels.isEmpty {
                    self.lock.lock()
                    if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                        self.entries[idx].ocrText = visionMeta.ocrText
                        self.entries[idx].visionLabels = visionMeta.labels
                        entry = self.entries[idx]
                        self.persistLocked()
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
            self.persistLocked()
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
            self.persistLocked()
        }
        self.lock.unlock()
    }

    func incrementUsage(id: String) {
        self.lock.lock()
        self.ensureLoadedLocked()
        if let idx = self.entries.firstIndex(where: { $0.id == id }) {
            self.entries[idx].usageCount += 1
            self.persistLocked()
        }
        self.lock.unlock()
    }

    func sendSticker(entry: GGMediaTokCoreLogic.StickerEntry, context: AccountContext, peerId: PeerId, replyTo: MessageId? = nil) {
        guard let webpData = try? Data(contentsOf: self.fileURL(for: entry)), !webpData.isEmpty else {
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
        let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [msg]).start()
        self.incrementUsage(id: entry.id)
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
                for tag in GGMediaTokCoreLogic.visionLabelToRussianTags(obs.identifier) {
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

    func geminiApiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: GGStickerVaultStore.geminiKeychainService,
            kSecAttrAccount as String: GGStickerVaultStore.geminiKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty else {
            return nil
        }
        return str
    }

    func setGeminiApiKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: GGStickerVaultStore.geminiKeychainService,
            kSecAttrAccount as String: GGStickerVaultStore.geminiKeychainAccount
        ]
        if trimmed.isEmpty {
            _ = SecItemDelete(baseQuery as CFDictionary)
            return
        }
        let data = Data(trimmed.utf8)
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            _ = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func autoTagWithGemini(entryId: String, image: UIImage, apiKey: String, completion: (([String]?) -> Void)?) {
        let scaled = GGStickerVaultStore.scaleToSticker512(image)
        guard let jpegData = scaled.jpegData(compressionQuality: 0.72),
              let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(encodedKey)") else {
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

        var req = URLRequest(url: url, timeoutInterval: 20.0)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let cands = obj["candidates"] as? [[String: Any]],
                  let content = cands.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
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
                self.persistLocked()
            }
            self.lock.unlock()

            DispatchQueue.main.async { completion?(merged) }
        }.resume()
    }
}

// MARK: - Hooks & Entry Point

enum GGMediaTokStickerVault {
    static func register() {
        // 1. Slash command interceptor: `/stickers`, `/stickers <q>`, `/s <q>`, `/s! <q>`
        GGChatScreenHooks.willSendText.register({ request, _ in
            return GGMediaTokStickerVault.interceptCommand(request)
        }, order: 18)

        // 2. Message Context Menu: "📥 Сохранить в /stickers" on photos and static stickers
        GGMessageMenuHooks.items.register({ menuContext in
            return GGMediaTokStickerVault.messageMenuItems(menuContext)
        }, order: 82)

        // 3. Send button long-press menu shortcut
        GGChatScreenHooks.sendMenuItems.register({ sendContext in
            let count = GGStickerVaultStore.shared.count
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
                    GGMediaTokStickerVault.presentPicker(context: context, targetPeerId: peerId, initialQuery: "")
                }
            ))]
        }, order: 75)
    }

    private static func interceptCommand(_ request: GGComposedTextRequest) -> Bool {
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
            GGMediaTokStickerVault.presentPicker(context: request.context, targetPeerId: peerId, initialQuery: query)
            return true
        }

        if lower.hasPrefix("/s! ") {
            guard let peerId = request.chatLocation.peerId else { return false }
            request.replace(ChatTextInputState())
            let query = String(raw.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let best = GGStickerVaultStore.shared.search(query, limit: 1).first {
                GGStickerVaultStore.shared.sendSticker(entry: best, context: request.context, peerId: peerId)
            } else {
                GGMediaTokStickerVault.showToast(context: request.context, text: "Стикер по запросу «\(query)» не найден. Добавьте через /stickers")
            }
            return true
        }
        return false
    }

    private static func messageMenuItems(_ menuContext: GGMessageMenuContext) -> [GGMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        let fallbackName = (message.author?.debugDisplayTitle ?? "sticker") + "_" + "\(message.id.id)"

        if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile,
           file.isSticker, !file.isAnimatedSticker,
           file.mimeType.lowercased().contains("webp") || file.mimeType.lowercased().contains("png") {
            let resource = file.resource
            let name = file.fileName ?? "\(fallbackName).webp"
            return [GGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Сохранить в /stickers",
                icon: { theme in
                    return UIImage(systemName: "square.and.arrow.down")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    GGMediaTokStickerVault.stealResourceToVault(context: context, resource: resource, fileName: name)
                }
            )))]
        }

        if let imageMedia = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage,
           let largest = largestImageRepresentation(imageMedia.representations) {
            let resource = largest.resource
            return [GGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Сохранить фото в /stickers",
                icon: { theme in
                    return UIImage(systemName: "face.smiling")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    GGMediaTokStickerVault.stealResourceToVault(context: context, resource: resource, fileName: "\(fallbackName).png")
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
                GGMediaTokStickerVault.showToast(context: context, text: "Не удалось прочитать файл стикера")
                return
            }
            GGStickerVaultStore.shared.addSticker(rawData: rawData, suggestedName: fileName, runGeminiIfConfigured: true) { entry in
                if entry != nil {
                    GGMediaTokStickerVault.showToast(context: context, text: "✅ Добавлено в /stickers (всего: \(GGStickerVaultStore.shared.count))")
                } else {
                    GGMediaTokStickerVault.showToast(context: context, text: "Не удалось добавить стикер")
                }
            }
        })
    }

    static func presentManagerFromMenu(context: GGMenuContext) {
        GGDiscordProfileStore.shared.activeAccountPeerId = context.context.account.peerId
        let vc = GGStickerVaultPickerViewController(accountContext: context.context, targetPeerId: nil, initialQuery: "")
        vc.overrideUserInterfaceStyle = .dark
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        nav.modalPresentationStyle = .pageSheet
        context.presentNative(nav)
    }

    static func presentPicker(context: AccountContext, targetPeerId: PeerId?, initialQuery: String) {
        GGDiscordProfileStore.shared.activeAccountPeerId = context.account.peerId
        DispatchQueue.main.async {
            let vc = GGStickerVaultPickerViewController(accountContext: context, targetPeerId: targetPeerId, initialQuery: initialQuery)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            GGModalPresenter.presentOnTopmost(nav)
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

private final class GGStickerVaultCell: UICollectionViewCell {
    static let reuseId = "GGStickerVaultCell"

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

    func configure(entry: GGMediaTokCoreLogic.StickerEntry, image: UIImage?) {
        self.imageView.image = image
        let labelText = entry.tags.first ?? (entry.ocrText.isEmpty ? (entry.visionLabels.first ?? "стикер") : entry.ocrText)
        self.badgeLabel.text = " " + labelText + " "
    }
}

// MARK: - /stickers Search & Browser UI

private final class GGStickerVaultPickerViewController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
    UISearchBarDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {

    private let accountContext: AccountContext
    private let targetPeerId: PeerId?
    private var currentQuery: String
    private var items: [GGMediaTokCoreLogic.StickerEntry] = []

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
        self.overrideUserInterfaceStyle = .dark
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closeTapped))

        let lanBtn = UIBarButtonItem(image: UIImage(systemName: "wifi"), style: .plain, target: self, action: #selector(self.openLanUploaderTapped))
        let aiBtn = UIBarButtonItem(image: UIImage(systemName: "wand.and.stars"), style: .plain, target: self, action: #selector(self.aiSettingsTapped))
        let addBtn = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.addMenuTapped))
        self.navigationItem.rightBarButtonItems = [addBtn, lanBtn, aiBtn]

        self.searchBar.delegate = self
        self.searchBar.placeholder = "Поиск (/s меллстрой, наруто, кот, текст...)"
        self.searchBar.text = self.currentQuery
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.searchBar)

        self.collectionView.backgroundColor = .clear
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.keyboardDismissMode = .onDrag
        self.collectionView.register(GGStickerVaultCell.self, forCellWithReuseIdentifier: GGStickerVaultCell.reuseId)
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
        let total = GGStickerVaultStore.shared.count
        self.title = "/stickers (\(total)/10к)"
        self.items = GGStickerVaultStore.shared.search(self.currentQuery, limit: 160)
        self.collectionView.reloadData()
        if self.items.isEmpty {
            self.emptyLabel.isHidden = false
            self.emptyLabel.text = total == 0
                ? "Хранилище на 10 000 стикеров пусто!\n\nНажмите «+» чтобы загрузить фото/WebP с iPhone, значок Wi-Fi 🌐 чтобы залить папку стикеров прямо с ПК в браузере, или зажмите любой стикер в чате → «Сохранить в /stickers»."
                : "По запросу «\(self.currentQuery)» ничего не найдено.\nПопробуйте транслит, слово с картинки или добавьте тег."
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
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GGStickerVaultCell.reuseId, for: indexPath) as! GGStickerVaultCell
        let entry = self.items[indexPath.item]
        cell.configure(entry: entry, image: GGStickerVaultStore.shared.loadImage(for: entry))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = max(60.0, floor((collectionView.bounds.width - 24.0 - 24.0) / 4.0))
        return CGSize(width: width, height: width + 12.0)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let entry = self.items[indexPath.item]
        if let peerId = self.targetPeerId {
            GGStickerVaultStore.shared.sendSticker(entry: entry, context: self.accountContext, peerId: peerId)
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

    private func presentEntryActions(_ entry: GGMediaTokCoreLogic.StickerEntry) {
        let sheet = UIAlertController(
            title: "🎭 Стикер",
            message: "Теги: \(entry.tags.joined(separator: ", "))\nOCR текст: \(entry.ocrText.isEmpty ? "—" : entry.ocrText)\nVision AI: \(entry.visionLabels.prefix(5).joined(separator: ", "))",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "🏷 Изменить теги", style: .default, handler: { [weak self] _ in
            self?.presentTagEditor(entry: entry)
        }))
        sheet.addAction(UIAlertAction(title: "🤖 Определить теги (Gemini ИИ)", style: .default, handler: { [weak self] _ in
            guard let strongSelf = self else { return }
            guard let key = GGStickerVaultStore.shared.geminiApiKey(), !key.isEmpty else {
                strongSelf.aiSettingsTapped()
                return
            }
            guard let img = GGStickerVaultStore.shared.loadImage(for: entry) else { return }
            GGStickerVaultStore.shared.autoTagWithGemini(entryId: entry.id, image: img, apiKey: key) { tags in
                if let tags {
                    strongSelf.reloadResults()
                    let info = UIAlertController(title: "✅ ИИ добавил теги", message: tags.joined(separator: ", "), preferredStyle: .alert)
                    info.addAction(UIAlertAction(title: "OK", style: .default))
                    GGModalPresenter.presentWhenReady(info, from: strongSelf)
                }
            }
        }))
        sheet.addAction(UIAlertAction(title: "📋 Скопировать изображение", style: .default, handler: { _ in
            if let img = GGStickerVaultStore.shared.loadImage(for: entry) {
                UIPasteboard.general.image = img
            }
        }))
        sheet.addAction(UIAlertAction(title: "🗑 Удалить стикер", style: .destructive, handler: { [weak self] _ in
            GGStickerVaultStore.shared.deleteSticker(id: entry.id)
            self?.reloadResults()
        }))
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGModalPresenter.presentWhenReady(sheet, from: self)
    }

    private func presentTagEditor(entry: GGMediaTokCoreLogic.StickerEntry) {
        let alert = UIAlertController(
            title: "🏷 Теги для поиска (/s <слово>)",
            message: "Укажите слова через запятую (например: меллстрой, угар, донат, аниме)",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = entry.tags.joined(separator: ", ")
            tf.placeholder = "тег1, тег2, персонаж..."
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak self, weak alert] _ in
            let raw = alert?.textFields?.first?.text ?? ""
            let tags = raw.components(separatedBy: CharacterSet(charactersIn: ",;"))
            GGStickerVaultStore.shared.updateTags(id: entry.id, tags: tags)
            self?.reloadResults()
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGModalPresenter.presentWhenReady(alert, from: self)
    }

    @objc private func addMenuTapped() {
        let sheet = UIAlertController(title: "Добавить стикеры в /stickers", message: "Можно выбрать сразу десятки или сотни файлов", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "🖼 Из Фото / Галереи", style: .default, handler: { [weak self] _ in
            guard let strongSelf = self else { return }
            var config = PHPickerConfiguration()
            config.selectionLimit = 0
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = strongSelf
            GGModalPresenter.presentWhenReady(picker, from: strongSelf)
        }))
        sheet.addAction(UIAlertAction(title: "📁 Из Файлов (.webp / .png / .jpg)", style: .default, handler: { [weak self] _ in
            guard let strongSelf = self else { return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .webP, .png, .jpeg], asCopy: true)
            picker.allowsMultipleSelection = true
            picker.delegate = strongSelf
            GGModalPresenter.presentWhenReady(picker, from: strongSelf)
        }))
        sheet.addAction(UIAlertAction(title: "🌐 Залить 10 000 шт с ПК (Wi-Fi)", style: .default, handler: { [weak self] _ in
            self?.openLanUploaderTapped()
        }))
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGModalPresenter.presentWhenReady(
            sheet,
            from: self,
            sourceView: self.view,
            sourceRect: CGRect(x: self.view.bounds.maxX - 44.0, y: 56.0, width: 1.0, height: 1.0)
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
                    GGStickerVaultStore.shared.addSticker(rawData: data, suggestedName: suggested, runGeminiIfConfigured: true) { _ in
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
                    GGStickerVaultStore.shared.addSticker(rawData: data, suggestedName: name, runGeminiIfConfigured: true) { _ in
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
        let vc = GGMediaTokLanUploaderViewController()
        self.navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func aiSettingsTapped() {
        let existing = GGStickerVaultStore.shared.geminiApiKey() ?? ""
        let alert = UIAlertController(
            title: "🤖 ИИ-поиск по стикерам",
            message: "Офлайн Apple Vision OCR + распознавание объектов работают всегда без интернета.\n\nПо желанию вставьте бесплатный Gemini API ключ (хранится в Keychain) — тогда ИИ будет знать мемы, стримеров (Меллстрой и др.) и аниме-персонажей!",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "AIza... (опционально, оставить пустым для откл.)"
            tf.text = existing
            tf.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak alert] _ in
            let key = alert?.textFields?.first?.text ?? ""
            GGStickerVaultStore.shared.setGeminiApiKey(key)
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGModalPresenter.presentWhenReady(alert, from: self)
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}

// MARK: - Local Wi-Fi PC Drag-and-Drop Web Uploader (Stickers + Music + Fonts)

private final class GGMediaTokLanUploader {
    private let queue = DispatchQueue(label: "org.mediatok.lan_uploader")
    private var listener: NWListener?
    private(set) var pin: String = ""
    private var failedPinAttempts: Int = 0
    private var pinLockedUntil: Date = .distantPast
    private(set) var port: UInt16 = 0
    var onLog: ((String) -> Void)?

    func start(completion: @escaping (String?) -> Void) {
        self.stop()
        let code = String(format: "%04d", Int.random(in: 1000 ... 9999))
        self.pin = code

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

        self.listener = listenerObj
        listenerObj.stateUpdateHandler = { [weak self] state in
            guard let strongSelf = self else { return }
            switch state {
            case .ready:
                let actualPort = strongSelf.listener?.port?.rawValue ?? 8787
                strongSelf.port = actualPort
                let ip = GGMediaTokLanUploader.localWiFiIPv4() ?? "127.0.0.1"
                DispatchQueue.main.async {
                    completion("http://\(ip):\(actualPort)")
                }
            case .failed:
                DispatchQueue.main.async { completion(nil) }
            default:
                break
            }
        }
        listenerObj.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listenerObj.start(queue: self.queue)
    }

    func stop() {
        self.listener?.cancel()
        self.listener = nil
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: self.queue)
        var buffer = Data()
        var expectedBodyLength: Int?
        var headerEndOffset: Int?

        func receiveChunk() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
                guard let strongSelf = self else {
                    conn.cancel()
                    return
                }
                if let data, !data.isEmpty {
                    if buffer.count + data.count > 26 * 1024 * 1024 {
                        strongSelf.sendJson(conn, status: "413 Payload Too Large", body: "{\"ok\":false,\"error\":\"File too large (>25MB)\"}")
                        return
                    }
                    buffer.append(data)
                }

                if headerEndOffset == nil, let sepRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    headerEndOffset = sepRange.upperBound
                    let headerData = buffer.subdata(in: 0 ..< sepRange.lowerBound)
                    if let headerStr = String(data: headerData, encoding: .utf8) {
                        for line in headerStr.components(separatedBy: "\r\n") {
                            let lower = line.lowercased()
                            if lower.hasPrefix("content-length:") {
                                let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                                expectedBodyLength = Int(val) ?? 0
                            }
                        }
                    }
                    if expectedBodyLength == nil {
                        expectedBodyLength = 0
                    }
                }

                if let hEnd = headerEndOffset, let expLen = expectedBodyLength {
                    if buffer.count - hEnd >= expLen || isComplete {
                        strongSelf.dispatchHttpRequest(conn: conn, buffer: buffer, headerEnd: hEnd, bodyLength: min(expLen, max(0, buffer.count - hEnd)))
                        return
                    }
                }

                if isComplete || error != nil {
                    conn.cancel()
                    return
                }
                receiveChunk()
            }
        }
        receiveChunk()
    }

    private func dispatchHttpRequest(conn: NWConnection, buffer: Data, headerEnd: Int, bodyLength: Int) {
        let headerRaw = String(data: buffer.subdata(in: 0 ..< max(0, headerEnd - 4)), encoding: .utf8) ?? ""
        let lines = headerRaw.components(separatedBy: "\r\n")
        let reqLine = (lines.first ?? "").components(separatedBy: " ")
        let method = reqLine.first?.uppercased() ?? "GET"
        let fullTarget = reqLine.count > 1 ? reqLine[1] : "/"

        let comps = URLComponents(string: "http://localhost\(fullTarget)")
        let path = comps?.path ?? "/"
        var queryMap: [String: String] = [:]
        for item in comps?.queryItems ?? [] {
            queryMap[item.name] = item.value ?? ""
        }

        if method == "GET" && (path == "/" || path == "/index.html") {
            self.sendHtml(conn, html: GGMediaTokLanUploader.webUploaderHtml)
            return
        }

        if Date() < self.pinLockedUntil {
            self.sendJson(conn, status: "429 Too Many Requests", body: "{\"ok\":false,\"error\":\"Слишком много неверных PIN. Подождите 60 сек.\"}")
            return
        }

        let headerPin = lines.first(where: { $0.lowercased().hasPrefix("x-pin:") })?
            .dropFirst("x-pin:".count).trimmingCharacters(in: .whitespaces) ?? ""
        let suppliedPin = !headerPin.isEmpty ? headerPin : (queryMap["pin"] ?? "")
        guard GGMediaTokCoreLogic.constantTimeEquals(suppliedPin, self.pin) else {
            self.failedPinAttempts += 1
            if self.failedPinAttempts >= 5 {
                self.pinLockedUntil = Date().addingTimeInterval(60.0)
                self.failedPinAttempts = 0
                self.emitLog("🔒 Блокировка на 60 сек после 5 неверных PIN")
            }
            self.sendJson(conn, status: "403 Forbidden", body: "{\"ok\":false,\"error\":\"Неверный PIN-код\"}")
            return
        }
        self.failedPinAttempts = 0

        let body = bodyLength > 0 ? buffer.subdata(in: headerEnd ..< (headerEnd + bodyLength)) : Data()
        guard !body.isEmpty else {
            self.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Empty body\"}")
            return
        }

        let cleanName = GGMediaTokCoreLogic.sanitizeUploadFileName(queryMap["name"] ?? "upload")

        if method == "POST" && path == "/api/upload/sticker" {
            let rawTags = (queryMap["tags"] ?? "").components(separatedBy: CharacterSet(charactersIn: ",;"))
            GGStickerVaultStore.shared.addSticker(rawData: body, suggestedName: cleanName, initialTags: rawTags, runGeminiIfConfigured: true) { entry in
                if entry != nil {
                    self.emitLog("🎭 Стикер: \(cleanName)")
                    self.sendJson(conn, status: "200 OK", body: "{\"ok\":true}")
                } else {
                    self.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Unsupported image\"}")
                }
            }
            return
        }

        if method == "POST" && path == "/api/upload/music" {
            let ext = (cleanName as NSString).pathExtension
            let title = (cleanName as NSString).deletingPathExtension
            let ok = GGDiscordProfileStore.shared.addUploadedTrackToOwnProfile(data: body, ext: ext, title: title)
            if ok {
                self.emitLog("🎵 Трек в профиль: \(title)")
                self.sendJson(conn, status: "200 OK", body: "{\"ok\":true}")
            } else {
                self.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Откройте сначала профиль в MediaTok\"}")
            }
            return
        }

        if method == "POST" && path == "/api/upload/font" {
            let ext = (cleanName as NSString).pathExtension.lowercased()
            let safeExt = ["ttf", "otf", "ttc"].contains(ext) ? ext : "ttf"
            let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("lan_\(UUID().uuidString).\(safeExt)")
            do {
                try body.write(to: tempUrl, options: [.atomic])
                GGCustomFonts.importFont(at: tempUrl) { res in
                    try? FileManager.default.removeItem(at: tempUrl)
                    switch res {
                    case let .added(font):
                        self.emitLog("🔤 Шрифт: \(font.familyName)")
                        self.sendJson(conn, status: "200 OK", body: "{\"ok\":true}")
                    default:
                        self.sendJson(conn, status: "400 Bad Request", body: "{\"ok\":false,\"error\":\"Invalid font or limit reached\"}")
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
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let addrPtr = interface.ifa_addr else { continue }
            let addrFamily = addrPtr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addrPtr, socklen_t(addrPtr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if !ip.isEmpty { return ip }
                    }
                }
            }
        }
        return nil
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

private final class GGMediaTokLanUploaderViewController: UIViewController {
    private let uploader = GGMediaTokLanUploader()
    private let urlLabel = UILabel()
    private let pinLabel = UILabel()
    private let logView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = .dark
        self.title = "Wi-Fi Загрузка с ПК"
        self.view.backgroundColor = .systemGroupedBackground

        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14.0
        card.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(card)

        self.urlLabel.font = UIFont.monospacedSystemFont(ofSize: 18.0, weight: .bold)
        self.urlLabel.textColor = .systemCyan
        self.urlLabel.textAlignment = .center
        self.urlLabel.numberOfLines = 0
        self.urlLabel.text = "Запуск локального сервера..."
        self.urlLabel.translatesAutoresizingMaskIntoConstraints = false

        self.pinLabel.font = UIFont.monospacedSystemFont(ofSize: 28.0, weight: .heavy)
        self.pinLabel.textAlignment = .center
        self.pinLabel.translatesAutoresizingMaskIntoConstraints = false

        let hint = UILabel()
        hint.font = UIFont.systemFont(ofSize: 13.0)
        hint.textColor = .secondaryLabel
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.text = "Откройте адрес выше в браузере на ПК (в одной Wi-Fi сети), введите PIN и перетащите папку со стикерами, треками (.mp3) или шрифтами (.ttf)."
        hint.translatesAutoresizingMaskIntoConstraints = false

        self.logView.isEditable = false
        self.logView.backgroundColor = .secondarySystemGroupedBackground
        self.logView.layer.cornerRadius = 12.0
        self.logView.font = UIFont.monospacedSystemFont(ofSize: 12.0, weight: .regular)
        self.logView.text = "Лог загрузок:\n"
        self.logView.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(self.urlLabel)
        card.addSubview(self.pinLabel)
        card.addSubview(hint)
        self.view.addSubview(self.logView)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 16.0),
            card.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            card.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),
            self.urlLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16.0),
            self.urlLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12.0),
            self.urlLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12.0),
            self.pinLabel.topAnchor.constraint(equalTo: self.urlLabel.bottomAnchor, constant: 8.0),
            self.pinLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12.0),
            self.pinLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12.0),
            hint.topAnchor.constraint(equalTo: self.pinLabel.bottomAnchor, constant: 8.0),
            hint.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12.0),
            hint.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12.0),
            hint.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16.0),
            self.logView.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 14.0),
            self.logView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            self.logView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),
            self.logView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -16.0)
        ])

        self.uploader.onLog = { [weak self] entry in
            guard let strongSelf = self else { return }
            strongSelf.logView.text += "\(entry)\n"
        }
        self.uploader.start { [weak self] url in
            guard let strongSelf = self else { return }
            if let url {
                strongSelf.urlLabel.text = url
                strongSelf.pinLabel.text = "PIN: \(strongSelf.uploader.pin)"
            } else {
                strongSelf.urlLabel.text = "Ошибка запуска сервера (проверьте Wi-Fi)"
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.uploader.stop()
    }

    deinit {
        self.uploader.stop()
    }
}
