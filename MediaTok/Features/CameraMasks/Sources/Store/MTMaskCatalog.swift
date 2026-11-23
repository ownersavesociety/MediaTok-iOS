import Foundation
import UIKit
import CryptoKit
import SwiftSignalKit
import MTCore

/// An entry of the server's mask catalog (`catalog.json`). The format is the old one plus optional
/// integrity fields: `version` (a newer one replaces the cached copy) and SHA-256 of the manifest
/// and of every asset, checked after download.
struct MTMaskCatalogEntry: Codable, Equatable {
    let id: String
    let name: [String: String]
    let category: String?
    let thumbnail: String
    let manifest: String
    let version: Int?
    let manifestSha256: String?
    let assetsSha256: [String: String]?

    func displayName(languageCode: String) -> String {
        if let value = self.name[languageCode], !value.isEmpty {
            return value
        }
        if let value = self.name["en"], !value.isEmpty {
            return value
        }
        return self.name.values.first(where: { !$0.isEmpty }) ?? self.id
    }
}

private struct MTMaskCatalogFile: Codable {
    let schemaVersion: Int?
    let catalogVersion: Int?
    let masks: [MTMaskCatalogEntry]
}

/// The catalog of masks on MediaTok's server and the cache of downloaded masks.
///
/// - Only `MTNetwork`: an ephemeral session, the user's SOCKS5 proxy, nothing about the user in the
///   request, nothing sent while an MTProxy / WEB proxy is on.
/// - The catalog is accepted only with a valid `X-MT-Signature` from `signingKeys`; manifests and
///   assets come only from the catalog's own host and are checked against the hashes it lists.
/// - Conditional GET (ETag), at most every 6 h, and only while masks are in use; the screens ask for
///   it, nothing polls.
/// - Everything lives in Caches (`mediatok/masks/`), never in UserDefaults or Documents, with a
///   size limit (least recently used masks go first).
/// - A mask that failed to download is not retried until it is picked again.
final class MTMaskCatalog {
    static let shared = MTMaskCatalog()

    static let catalogURL = URL(string: "about:blank")!
    /// P-256 public keys of the catalog signature (64-byte x‖y, X9.63 or DER). Provided by the
    /// owner of the server; while the list is empty the catalog is not fetched at all — unsigned
    /// data is never used (see the MediaTok report).
    static let signingKeys: [Data] = []

    static let refreshInterval: Double = 6.0 * 60.0 * 60.0
    static let minimumCacheLimitMB = 50

    private let queue = Queue(name: "org.mediatok.masks.catalog")
    private let entriesPromise = ValuePromise<[MTMaskCatalogEntry]>([], ignoreRepeated: true)
    private var entriesValue: [MTMaskCatalogEntry] = []
    private var didLoadCache = false
    private var isRefreshing = false
    private let refreshDisposable = MetaDisposable()
    private var preparing: [String: [(MTPreparedMask?) -> Void]] = [:]
    private let preparationDisposables = DisposableSet()

    var root: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("mediatok/masks", isDirectory: true)
    }

    private var catalogFile: URL {
        return self.root.appendingPathComponent("catalog.json")
    }

    func directory(id: String) -> URL {
        return self.root.appendingPathComponent("remote", isDirectory: true).appendingPathComponent(MTMaskStore.safeComponent(id), isDirectory: true)
    }

    static var isAvailable: Bool {
        return !MTMaskCatalog.signingKeys.isEmpty
    }

    // MARK: Entries

    var entries: Signal<[MTMaskCatalogEntry], NoError> {
        self.queue.async {
            self.loadCacheIfNeeded()
        }
        return self.entriesPromise.get()
    }

    private let snapshotLock = NSLock()
    private var snapshot: [MTMaskCatalogEntry] = []

    /// Any thread: the last loaded catalog (empty until the first screen asked for it).
    func entry(id: String) -> MTMaskCatalogEntry? {
        self.snapshotLock.lock()
        defer {
            self.snapshotLock.unlock()
        }
        return self.snapshot.first(where: { $0.id == id })
    }

    private func setEntries(_ entries: [MTMaskCatalogEntry]) {
        self.entriesValue = entries
        self.snapshotLock.lock()
        self.snapshot = entries
        self.snapshotLock.unlock()
        self.entriesPromise.set(entries)
    }

    private func loadCacheIfNeeded() {
        if self.didLoadCache {
            return
        }
        self.didLoadCache = true
        if let data = try? Data(contentsOf: self.catalogFile), let file = try? JSONDecoder().decode(MTMaskCatalogFile.self, from: data) {
            self.setEntries(file.masks)
        }
    }

    /// Fetches the catalog when it is older than 6 h (or `force`). Masks must be in use.
    func refreshIfNeeded(force: Bool = false) {
        guard MTMaskCatalog.isAvailable else {
            MTLog.info("masks", "catalog: no signing key configured, not fetched")
            return
        }
        let fetchedAt = MTMaskSettings.catalogFetchedAt.value
        let now = Date().timeIntervalSince1970
        if !force && now - fetchedAt < MTMaskCatalog.refreshInterval {
            return
        }
        self.queue.async { [self] in
            self.loadCacheIfNeeded()
            if self.isRefreshing {
                return
            }
            self.isRefreshing = true
            let etag = MTMaskSettings.catalogETag.value
            let request = MTNetworkRequest(url: MTMaskCatalog.catalogURL, etag: etag.isEmpty || self.entriesValue.isEmpty ? nil : etag, signingKeys: MTMaskCatalog.signingKeys, maxBytes: 2 * 1024 * 1024)
            self.refreshDisposable.set((MTNetwork.shared.fetch(request) |> deliverOn(self.queue)).start(next: { [weak self] response in
                guard let self else {
                    return
                }
                self.isRefreshing = false
                MTMaskSettings.catalogFetchedAt.set(Date().timeIntervalSince1970)
                if response.notModified {
                    return
                }
                guard let data = response.data, let file = try? JSONDecoder().decode(MTMaskCatalogFile.self, from: data) else {
                    MTLog.warning("masks", "catalog: unreadable response kept the previous catalog")
                    return
                }
                try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
                try? data.write(to: self.catalogFile, options: [.atomic])
                MTMaskSettings.catalogETag.set(response.etag ?? "")
                self.setEntries(file.masks)
            }, error: { [weak self] error in
                guard let self else {
                    return
                }
                self.queue.async {
                    self.isRefreshing = false
                }
                MTLog.info("masks", "catalog fetch failed: \(error)")
            }))
        }
    }

    // MARK: Masks

    /// A catalog mask ready to render: from the cache, else downloaded (manifest, then assets).
    /// Called when the mask is picked, never per frame.
    func prepare(id: String, completion: @escaping (MTPreparedMask?) -> Void) {
        self.queue.async { [self] in
            self.loadCacheIfNeeded()
            if var waiting = self.preparing[id] {
                waiting.append(completion)
                self.preparing[id] = waiting
                return
            }
            let entry = self.entriesValue.first(where: { $0.id == id })
            let directory = self.directory(id: id)
            if let cached = self.cachedMask(id: id, entry: entry, directory: directory) {
                self.touch(directory)
                completion(cached)
                return
            }
            guard let entry, MTMaskCatalog.isAvailable, let manifestUrl = self.trustedURL(entry.manifest) else {
                completion(nil)
                return
            }
            self.preparing[id] = [completion]
            self.preparationDisposables.add((MTNetwork.shared.fetch(MTNetworkRequest(url: manifestUrl, maxBytes: 1024 * 1024)) |> deliverOn(self.queue)).start(next: { [weak self] response in
                guard let self else {
                    return
                }
                guard let data = response.data, MTMaskCatalog.matches(data, sha256: entry.manifestSha256), let manifest = try? JSONDecoder().decode(MTMaskManifest.self, from: data) else {
                    self.finishPreparation(id: id, result: nil)
                    return
                }
                self.downloadAssets(entry: entry, manifest: manifest, manifestData: data, baseUrl: manifestUrl.deletingLastPathComponent(), directory: directory)
            }, error: { [weak self] _ in
                self?.finishPreparation(id: id, result: nil)
            }))
        }
    }

    private func cachedMask(id: String, entry: MTMaskCatalogEntry?, directory: URL) -> MTPreparedMask? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")), let manifest = try? JSONDecoder().decode(MTMaskManifest.self, from: data) else {
            return nil
        }
        // A newer version in the catalog replaces the cached copy.
        if let version = entry?.version {
            let cachedVersion = (try? String(contentsOf: directory.appendingPathComponent("version"), encoding: .utf8)).flatMap { Int($0) } ?? 0
            if cachedVersion < version {
                return nil
            }
        }
        return MTPreparedMask(selection: .catalog(id), manifest: manifest, assets: MTMaskAssets(directory: directory.appendingPathComponent("assets", isDirectory: true)))
    }

    private func downloadAssets(entry: MTMaskCatalogEntry, manifest: MTMaskManifest, manifestData: Data, baseUrl: URL, directory: URL) {
        let names = Array(manifest.referencedAssets)
        var downloaded: [String: Data] = [:]
        func next(_ index: Int) {
            if index >= names.count {
                let fileManager = FileManager.default
                try? fileManager.removeItem(at: directory)
                let assets = directory.appendingPathComponent("assets", isDirectory: true)
                try? fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
                for (name, data) in downloaded {
                    try? data.write(to: assets.appendingPathComponent(MTMaskStore.safeComponent(name)), options: [.atomic])
                }
                try? manifestData.write(to: directory.appendingPathComponent("manifest.json"), options: [.atomic])
                try? String(entry.version ?? 0).write(to: directory.appendingPathComponent("version"), atomically: true, encoding: .utf8)
                self.enforceLimit()
                self.finishPreparation(id: entry.id, result: MTPreparedMask(selection: .catalog(entry.id), manifest: manifest, assets: MTMaskAssets(directory: assets)))
                return
            }
            let name = names[index]
            guard let url = self.trustedURL(baseUrl.appendingPathComponent("assets").appendingPathComponent(MTMaskStore.safeComponent(name)).absoluteString) else {
                self.finishPreparation(id: entry.id, result: nil)
                return
            }
            self.preparationDisposables.add((MTNetwork.shared.fetch(MTNetworkRequest(url: url, maxBytes: 8 * 1024 * 1024)) |> deliverOn(self.queue)).start(next: { [weak self] response in
                guard let self else {
                    return
                }
                guard let data = response.data, MTMaskCatalog.matches(data, sha256: entry.assetsSha256?[name]) else {
                    self.finishPreparation(id: entry.id, result: nil)
                    return
                }
                downloaded[name] = data
                next(index + 1)
            }, error: { [weak self] _ in
                self?.finishPreparation(id: entry.id, result: nil)
            }))
        }
        next(0)
    }

    private func finishPreparation(id: String, result: MTPreparedMask?) {
        let completions = self.preparing.removeValue(forKey: id) ?? []
        for completion in completions {
            completion(result)
        }
    }

    /// Only https URLs on the catalog's own host.
    private func trustedURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme?.lowercased() == "https", url.host?.lowercased() == MTMaskCatalog.catalogURL.host?.lowercased() else {
            return nil
        }
        return url
    }

    private static func matches(_ data: Data, sha256: String?) -> Bool {
        guard let sha256, !sha256.isEmpty else {
            return true
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == sha256.lowercased()
    }

    // MARK: Thumbnails

    func thumbnail(entry: MTMaskCatalogEntry) -> Signal<UIImage?, NoError> {
        let file = self.directory(id: entry.id).appendingPathComponent("thumbnail")
        return Signal { subscriber in
            if let image = UIImage(contentsOfFile: file.path) {
                subscriber.putNext(image)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            guard MTMaskCatalog.isAvailable, let url = self.trustedURL(entry.thumbnail) else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            return (MTNetwork.shared.fetch(MTNetworkRequest(url: url, maxBytes: 512 * 1024)) |> deliverOn(self.queue)).start(next: { response in
                var image: UIImage?
                if let data = response.data, let decoded = UIImage(data: data) {
                    image = MTMaskStore.downscaled(decoded, maxSide: 160.0)
                    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if let jpeg = image?.jpegData(compressionQuality: 0.8) {
                        try? jpeg.write(to: file, options: [.atomic])
                    }
                }
                subscriber.putNext(image)
                subscriber.putCompletion()
            }, error: { _ in
                subscriber.putNext(nil)
                subscriber.putCompletion()
            })
        }
    }

    // MARK: Cache

    private func touch(_ directory: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: directory.path)
    }

    /// Least recently used masks go first until the cache fits the limit.
    private func enforceLimit() {
        let limit = Int64(max(MTMaskCatalog.minimumCacheLimitMB, Int(MTMaskSettings.cacheLimit.value) ?? 200)) * 1024 * 1024
        let remote = self.root.appendingPathComponent("remote", isDirectory: true)
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(at: remote, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return
        }
        var items = urls.map { url -> (URL, Date, Int64) in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date(timeIntervalSince1970: 0.0)
            return (url, date, MTMaskStore.directorySize(url))
        }
        var total = items.reduce(Int64(0)) { $0 + $1.2 }
        items.sort(by: { $0.1 < $1.1 })
        for item in items where total > limit {
            try? fileManager.removeItem(at: item.0)
            total -= item.2
        }
    }

    func cacheSize(completion: @escaping (Int64) -> Void) {
        self.queue.async {
            let size = MTMaskStore.directorySize(self.root.appendingPathComponent("remote", isDirectory: true))
            DispatchQueue.main.async {
                completion(size)
            }
        }
    }

    func clearCache(completion: (() -> Void)? = nil) {
        self.queue.async {
            try? FileManager.default.removeItem(at: self.root.appendingPathComponent("remote", isDirectory: true))
            if let completion {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
}
