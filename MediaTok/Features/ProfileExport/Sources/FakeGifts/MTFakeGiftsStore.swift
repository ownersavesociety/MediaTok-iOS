import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import MTCore

// Fake gifts: local copies of any gift, shown only on the user's own profile and only on this
// device. Nothing goes to the server.
//
// Storage is per account: `<account>/mediatok/fake-gifts.json` (versioned Codable), next to the
// account's own data, so it leaves with the account. The file is read on this class's queue, and
// only while the feature is on. What the profile shows is kept in memory already resolved (sender
// peers looked up once per change), so a gift list push only concatenates.

enum MTFakeGiftsSettings {
    static let isEnabled = MTSetting<Bool>("fakeGifts.isEnabled", default: false)
    /// Explicit opt-in for global ntfy.sh fake-gift sync (off by default to keep fake gifts local-only).
    static let globalSyncEnabled = MTSetting<Bool>("fakeGifts.globalSync", default: false)
    /// Fake gifts moved from legacy format, waiting for the store to merge them into the account's
    /// file (a migration only writes settings). Service state, never exported.
    static let legacyImport = MTAccountSetting<Data>("fakeGifts.legacyImport", default: Data(), flags: [.noExport])

    static func declare() {
        let _ = MTFakeGiftsSettings.isEnabled
        let _ = MTFakeGiftsSettings.globalSyncEnabled
        let _ = MTFakeGiftsSettings.legacyImport
    }
}

struct MTFakeGiftBatchInput {
    let gift: StarGift
    let fromPeer: PeerId?
    let nameHidden: Bool
    let date: Int32
    let text: String?
    let entities: [MessageTextEntity]?
    let number: Int32?
}

/// One fake gift as stored. The gift itself is kept as it was copied; what the profile shows
/// (owner = you, the original-info line of a collectible) is derived when it is resolved.
struct MTFakeGiftRecord: Codable, Equatable {
    var localId: Int64
    var gift: StarGift
    var fromPeer: MTPeerKey?
    var nameHidden: Bool
    var date: Int32
    var text: String?
    var entities: [MessageTextEntity]?
    var savedToProfile: Bool
    var pinnedToTop: Bool
    var number: Int32?
    /// When the gift's media was last refreshed from the server (file references expire).
    var refreshedAt: Int32
    /// Whose profile shows the gift: nil = your own, otherwise another person's (visual only, on this device).
    var targetPeer: MTPeerKey? = nil
}

private struct MTFakeGiftsFile: Codable {
    var version: Int
    var nextLocalId: Int64
    var items: [MTFakeGiftRecord]
}

final class MTFakeGiftsStore {
    static let shared = MTFakeGiftsStore()

    private static let refreshInterval: Int32 = 24 * 60 * 60

    private final class AccountEntry {
        let id: AccountRecordId
        let peerId: PeerId
        let fileURL: URL
        weak var postbox: Postbox?
        var records: [MTFakeGiftRecord]?
        var nextLocalId: Int64 = -1
        var refreshStarted = false
        let resolveDisposable = MetaDisposable()

        init(id: AccountRecordId, peerId: PeerId, basePath: String, postbox: Postbox) {
            self.id = id
            self.peerId = peerId
            self.fileURL = URL(fileURLWithPath: basePath).appendingPathComponent("mediatok", isDirectory: true).appendingPathComponent("fake-gifts.json")
            self.postbox = postbox
        }
    }

    private let queue = Queue(name: "org.mediatok.fakeGifts", qos: .utility)
    /// Queue only.
    private var entries: [PeerId: AccountEntry] = [:]

    private let lock = MTProfileExportLock()
    /// What the profile shows, per account peer. Read on the main thread on every gift list push.
    private var resolved: [PeerId: [ProfileGiftsContext.State.StarGift]] = [:]
    private var recordSnapshots: [PeerId: [MTFakeGiftRecord]] = [:]
    /// Synced fake gifts from other MediaTok users, keyed by target peerId.
    private var remoteResolved: [PeerId: [ProfileGiftsContext.State.StarGift]] = [:]
    private var remoteLastChecked: [PeerId: TimeInterval] = [:]

    private let changesPipe = ValuePipe<PeerId>()

    private init() {
    }

    // MARK: - Reading (any thread)

    func resolvedGifts(accountPeerId: PeerId) -> [ProfileGiftsContext.State.StarGift] {
        return self.lock.withLock {
            return self.resolved[accountPeerId] ?? []
        }
    }

    /// The account's fake gifts shown on the profile of `peerId` (yours or another person's).
    func resolvedGifts(accountPeerId: PeerId, forPeer peerId: PeerId) -> [ProfileGiftsContext.State.StarGift] {
        return self.resolvedGifts(accountPeerId: accountPeerId).filter { gift in
            if let reference = gift.reference, case let .peer(owner, _) = reference {
                return owner == peerId
            }
            return false
        }
    }

    /// Synced fake gifts received from another MediaTok user's global channel.
    func remoteGifts(forPeer peerId: PeerId) -> [ProfileGiftsContext.State.StarGift] {
        return self.lock.withLock {
            return self.remoteResolved[peerId] ?? []
        }
    }

    func records(accountPeerId: PeerId) -> [MTFakeGiftRecord] {
        return self.lock.withLock {
            return self.recordSnapshots[accountPeerId] ?? []
        }
    }

    /// Current records first, then every change of this account's list.
    func recordsSignal(accountPeerId: PeerId) -> Signal<[MTFakeGiftRecord], NoError> {
        return .single(self.records(accountPeerId: accountPeerId))
        |> then(self.changesPipe.signal()
        |> filter { $0 == accountPeerId }
        |> map { [weak self] _ -> [MTFakeGiftRecord] in
            return self?.records(accountPeerId: accountPeerId) ?? []
        })
    }

    /// The local id when `reference` points at one of this account's fake gifts.
    static func localId(of reference: StarGiftReference?, accountPeerId: PeerId) -> Int64? {
        guard let reference = reference, case let .peer(_, id) = reference, id < 0 else {
            return nil
        }
        return id
    }

    // MARK: - Accounts

    /// `MTAccountHooks.accountWillStart` (the thread that creates the account).
    func accountWillStart(_ start: MTAccountStartContext) {
        if start.isSupplementary || MTCore.environment?.process.isApp != true {
            return
        }
        let entry = AccountEntry(id: start.id, peerId: start.peerId, basePath: start.basePath, postbox: start.postbox)
        self.queue.async {
            self.entries[start.peerId] = entry
            if MTFakeGiftsSettings.isEnabled.value {
                self.load(entry)
            } else {
                MTFakeGiftsStore.reconcileWornGift(accountPeerId: start.peerId, records: [], enabled: false)
            }
        }
    }

    func accountWillBeRemoved(_ id: AccountRecordId) {
        self.queue.async {
            guard let (peerId, entry) = self.entries.first(where: { $0.value.id == id }) else {
                return
            }
            entry.resolveDisposable.dispose()
            self.entries.removeValue(forKey: peerId)
            self.lock.withLock {
                self.resolved.removeValue(forKey: peerId)
                self.recordSnapshots.removeValue(forKey: peerId)
            }
        }
    }

    /// The feature was turned on or off. Off: nothing is read or kept in memory (the files stay —
    /// "Delete all" deletes them).
    func setEnabled(_ enabled: Bool) {
        self.queue.async {
            for (_, entry) in self.entries {
                if enabled {
                    self.load(entry)
                } else {
                    entry.resolveDisposable.set(nil)
                    entry.records = nil
                }
            }
            if !enabled {
                let peerIds = Array(self.entries.keys)
                self.lock.withLock {
                    self.resolved.removeAll()
                    self.recordSnapshots.removeAll()
                }
                for peerId in peerIds {
                    MTFakeGiftsStore.reconcileWornGift(accountPeerId: peerId, records: [], enabled: false)
                    self.changesPipe.putNext(peerId)
                }
                Queue.mainQueue().async {
                    MTFakeGiftsPendingPoints.storeDidChange()
                }
            }
        }
    }

    // MARK: - Changes

    /// Ensures an account entry exists even if `accountWillStart` ran before login completed.
    func ensureAccount(_ account: Account) {
        let entry = AccountEntry(id: account.id, peerId: account.peerId, basePath: account.basePath, postbox: account.postbox)
        self.queue.async {
            if self.entries[account.peerId] == nil {
                self.entries[account.peerId] = entry
                if MTFakeGiftsSettings.isEnabled.value {
                    self.load(entry)
                }
            }
        }
    }

    /// Adds a copy of a gift to the account's profile. `completion` on the main thread.
    func add(accountPeerId: PeerId, gift: StarGift, fromPeer: PeerId?, nameHidden: Bool, date: Int32, text: String?, entities: [MessageTextEntity]?, number: Int32?, targetPeer: PeerId? = nil, completion: @escaping (Int64?) -> Void) {
        self.queue.async {
            guard let entry = self.entries[accountPeerId] else {
                Queue.mainQueue().async {
                    completion(nil)
                }
                return
            }
            if entry.records == nil {
                self.readFile(entry)
            }
            var records = entry.records ?? []
            let localId = entry.nextLocalId
            entry.nextLocalId = min(localId - 1, -1)
            let record = MTFakeGiftRecord(localId: localId, gift: gift, fromPeer: fromPeer?.mtKey, nameHidden: nameHidden, date: date, text: text, entities: entities, savedToProfile: true, pinnedToTop: false, number: number, refreshedAt: Int32(Date().timeIntervalSince1970), targetPeer: targetPeer?.mtKey)
            records.insert(record, at: 0)
            self.commit(entry, records: records)
            if let targetPeer {
                self.publishGlobalFakeGifts(forTargetPeerId: targetPeer, records: [record], mode: "add")
            }
            Queue.mainQueue().async {
                completion(localId)
            }
        }
    }

    /// Adds multiple fake gifts in a single atomic write + single resolve pass (and at most one
    /// sync batch if global sync is explicitly enabled). `completion` runs on the main thread.
    func addBatch(accountPeerId: PeerId, items: [MTFakeGiftBatchInput], targetPeer: PeerId? = nil, completion: @escaping (Int) -> Void) {
        guard !items.isEmpty else {
            Queue.mainQueue().async {
                completion(0)
            }
            return
        }
        self.queue.async {
            guard let entry = self.entries[accountPeerId] else {
                Queue.mainQueue().async {
                    completion(0)
                }
                return
            }
            if entry.records == nil {
                self.readFile(entry)
            }
            var records = entry.records ?? []
            let now = Int32(Date().timeIntervalSince1970)
            var newRecords: [MTFakeGiftRecord] = []
            newRecords.reserveCapacity(items.count)
            for item in items {
                let localId = entry.nextLocalId
                entry.nextLocalId = min(localId - 1, -1)
                let record = MTFakeGiftRecord(
                    localId: localId,
                    gift: item.gift,
                    fromPeer: item.fromPeer?.mtKey,
                    nameHidden: item.nameHidden,
                    date: item.date,
                    text: item.text,
                    entities: item.entities,
                    savedToProfile: true,
                    pinnedToTop: false,
                    number: item.number,
                    refreshedAt: now,
                    targetPeer: targetPeer?.mtKey
                )
                newRecords.append(record)
            }
            records.insert(contentsOf: newRecords, at: 0)
            self.commit(entry, records: records)
            if let targetPeer {
                self.publishGlobalFakeGifts(forTargetPeerId: targetPeer, records: newRecords, mode: "add")
            }
            let added = newRecords.count
            Queue.mainQueue().async {
                completion(added)
            }
        }
    }

    /// Hide / pin from the profile: the shown list changes at once (the profile pushes
    /// its state right after the action), the file follows on the queue.
    func updateFlags(accountPeerId: PeerId, localId: Int64, savedToProfile: Bool?, pinnedToTop: Bool?) {
        self.lock.withLock {
            if var gifts = self.resolved[accountPeerId], let index = gifts.firstIndex(where: { MTFakeGiftsStore.localId(of: $0.reference, accountPeerId: accountPeerId) == localId }) {
                var gift = gifts[index]
                if let savedToProfile = savedToProfile {
                    gift = gift.withSavedToProfile(savedToProfile)
                }
                if let pinnedToTop = pinnedToTop {
                    gift = gift.withPinnedToTop(pinnedToTop)
                }
                gifts[index] = gift
                self.resolved[accountPeerId] = gifts
            }
        }
        self.update(accountPeerId: accountPeerId, localId: localId, { record in
            if let savedToProfile = savedToProfile {
                record.savedToProfile = savedToProfile
            }
            if let pinnedToTop = pinnedToTop {
                record.pinnedToTop = pinnedToTop
            }
        })
    }

    func update(accountPeerId: PeerId, localId: Int64, _ transform: @escaping (inout MTFakeGiftRecord) -> Void) {
        self.queue.async {
            guard let entry = self.entries[accountPeerId], var records = entry.records, let index = records.firstIndex(where: { $0.localId == localId }) else {
                return
            }
            transform(&records[index])
            records[index].localId = localId
            self.commit(entry, records: records)
        }
    }

    func remove(accountPeerId: PeerId, localId: Int64) {
        self.queue.async {
            guard let entry = self.entries[accountPeerId] else {
                return
            }
            if entry.records == nil {
                self.readFile(entry)
            }
            guard var records = entry.records else {
                return
            }
            let removed = records.filter { $0.localId == localId }
            records.removeAll(where: { $0.localId == localId })
            for item in removed {
                if case let .unique(u) = item.gift {
                    let ownerKey = item.targetPeer ?? accountPeerId.mtKey
                    if let worn = MTVisualProfileStore.shared.wornStarGift(for: ownerKey),
                       (worn.id == u.id || (!u.slug.isEmpty && worn.slug == u.slug)) {
                        MTVisualProfileStore.shared.setWornStarGift(nil, for: ownerKey)
                    }
                }
                if let targetKey = item.targetPeer {
                    let targetPeerId = PeerId(mtKey: targetKey)
                    let remainingForTarget = records.filter { $0.targetPeer == targetKey && $0.savedToProfile }
                    self.publishGlobalFakeGifts(forTargetPeerId: targetPeerId, records: remainingForTarget, mode: "replace")
                }
            }
            self.commit(entry, records: records)
        }
    }

    /// Deletes the account's fake gifts and their file.
    func removeAll(accountPeerId: PeerId) {
        self.queue.async {
            MTVisualProfileStore.shared.setWornStarGift(nil, for: accountPeerId.mtKey)
            guard let entry = self.entries[accountPeerId] else {
                return
            }
            let targetPeers = Set((entry.records ?? []).compactMap { $0.targetPeer })
            for targetKey in targetPeers {
                MTVisualProfileStore.shared.setWornStarGift(nil, for: targetKey)
                self.publishGlobalFakeGifts(forTargetPeerId: PeerId(mtKey: targetKey), records: [], mode: "replace")
            }
            entry.records = []
            try? FileManager.default.removeItem(at: entry.fileURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: entry.fileURL.path + ".bak"))
            self.publish(entry, records: [], gifts: [])
            self.publishGlobalFakeGifts(forTargetPeerId: entry.peerId, records: [], mode: "replace")
        }
    }

    /// Ensures any orphaned worn StarGift in the nickname/header is automatically cleared if its
    /// corresponding visual NFT was deleted, hidden, or Fake Gifts were disabled.
    private static func reconcileWornGift(accountPeerId: PeerId, records: [MTFakeGiftRecord], enabled: Bool) {
        let peerKey = accountPeerId.mtKey
        guard let worn = MTVisualProfileStore.shared.wornStarGift(for: peerKey) else {
            return
        }
        guard enabled else {
            MTVisualProfileStore.shared.setWornStarGift(nil, for: peerKey)
            return
        }
        let stillValid = records.contains { rec in
            guard rec.targetPeer == nil && rec.savedToProfile else { return false }
            if case let .unique(u) = rec.gift {
                return u.id == worn.id || (!u.slug.isEmpty && u.slug == worn.slug)
            }
            return false
        }
        if !stillValid {
            MTVisualProfileStore.shared.setWornStarGift(nil, for: peerKey)
        }
    }

    // MARK: - Media refresh

    /// File references in a stored gift expire. Once per session per account (while the own
    /// profile's gifts are shown), plain gifts older than a day get fresh media from the gift catalog
    /// cached on the device. Nothing is asked from the server: «nothing is sent» is the feature's
    /// promise, and a request by slug told the server which collectibles the user hangs on himself.
    /// A collectible keeps the media it was copied with (already downloaded files stay in the cache).
    func refreshIfNeeded(account: Account) {
        let accountPeerId = account.peerId
        self.queue.async { [self] in
            guard let entry = self.entries[accountPeerId], !entry.refreshStarted, let records = entry.records, !records.isEmpty else {
                return
            }
            entry.refreshStarted = true
            let now = Int32(Date().timeIntervalSince1970)
            let hasStaleGeneric = records.contains { record in
                if case .generic = record.gift {
                    return now - record.refreshedAt > MTFakeGiftsStore.refreshInterval
                }
                return false
            }
            if !hasStaleGeneric {
                return
            }
            let engine = TelegramEngine(account: account)
            let _ = (engine.payments.cachedStarGifts()
            |> take(1)
            |> deliverOn(self.queue)).start(next: { [weak self] catalog in
                guard let self = self, let entry = self.entries[accountPeerId], var records = entry.records else {
                    return
                }
                var catalogById: [Int64: StarGift] = [:]
                for gift in catalog ?? [] {
                    if case let .generic(generic) = gift {
                        catalogById[generic.id] = gift
                    }
                }
                var changed = false
                for index in records.indices where now - records[index].refreshedAt > MTFakeGiftsStore.refreshInterval {
                    if case let .generic(generic) = records[index].gift, let fresh = catalogById[generic.id] {
                        records[index].gift = fresh
                        records[index].refreshedAt = now
                        changed = true
                    }
                }
                if changed {
                    self.commit(entry, records: records)
                }
            })
        }
    }

    // MARK: - Private (queue)

    private func load(_ entry: AccountEntry) {
        if entry.records == nil {
            self.readFile(entry)
        }
        MTFakeGiftsStore.reconcileWornGift(accountPeerId: entry.peerId, records: entry.records ?? [], enabled: MTFakeGiftsSettings.isEnabled.value)
        self.resolve(entry)
    }

    private func readFile(_ entry: AccountEntry) {
        var records: [MTFakeGiftRecord] = []
        let backupURL = entry.fileURL.appendingPathExtension("bak")
        if let data = try? Data(contentsOf: entry.fileURL), let file = try? JSONDecoder().decode(MTFakeGiftsFile.self, from: data), file.version == 1 {
            records = file.items
            entry.nextLocalId = min(file.nextLocalId, (records.map { $0.localId }.min() ?? 0) - 1, -1)
        } else if let bakData = try? Data(contentsOf: backupURL), let file = try? JSONDecoder().decode(MTFakeGiftsFile.self, from: bakData), file.version == 1 {
            // Auto-restore from backup if primary JSON was corrupted (#424).
            records = file.items
            entry.nextLocalId = min(file.nextLocalId, (records.map { $0.localId }.min() ?? 0) - 1, -1)
            try? bakData.write(to: entry.fileURL, options: .atomic)
        }
        entry.records = records
        // Gifts moved from legacy format by the migration.
        let accountId = entry.id.mt
        let legacy = MTFakeGiftsSettings.legacyImport.value(for: accountId)
        if !legacy.isEmpty {
            let imported = MTFakeGiftsLegacy.records(from: legacy, accountPeerId: entry.peerId, firstLocalId: entry.nextLocalId)
            if !imported.isEmpty {
                entry.records = imported + records
                entry.nextLocalId = min(entry.nextLocalId, (imported.map { $0.localId }.min() ?? 0) - 1)
                self.writeFile(entry)
            }
            Queue.mainQueue().async {
                MTFakeGiftsSettings.legacyImport.reset(for: accountId)
            }
        }
    }

    private func writeFile(_ entry: AccountEntry) {
        let file = MTFakeGiftsFile(version: 1, nextLocalId: entry.nextLocalId, items: entry.records ?? [])
        guard let data = try? JSONEncoder().encode(file) else {
            return
        }
        try? FileManager.default.createDirectory(at: entry.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        // Snapshot previous valid file to .bak before atomic overwrite (#424).
        if let previous = try? Data(contentsOf: entry.fileURL), !previous.isEmpty {
            let backupURL = entry.fileURL.appendingPathExtension("bak")
            try? previous.write(to: backupURL, options: .atomic)
        }
        try? data.write(to: entry.fileURL, options: .atomic)
    }

    private func commit(_ entry: AccountEntry, records: [MTFakeGiftRecord]) {
        entry.records = records
        self.writeFile(entry)
        MTFakeGiftsStore.reconcileWornGift(accountPeerId: entry.peerId, records: records, enabled: MTFakeGiftsSettings.isEnabled.value)
        self.resolve(entry)
        let ownSaved = records.filter { $0.targetPeer == nil && $0.savedToProfile }
        self.publishGlobalFakeGifts(forTargetPeerId: entry.peerId, records: ownSaved, mode: "replace")
    }

    // MARK: - Global MediaTok Fake Gifts Sync

    private static func dialogId(for peerId: PeerId) -> Int64? {
        guard peerId.namespace == Namespaces.Peer.CloudUser else {
            return nil
        }
        let raw = peerId.id._internalGetInt64Value()
        return raw > 0 ? raw : nil
    }

    private static func unwrapNtfyGiftLine(_ line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
              let data = trimmed.data(using: .utf8),
              let outer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        if let msgStr = outer["message"] as? String,
           msgStr.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
           let innerData = msgStr.data(using: .utf8),
           let inner = (try? JSONSerialization.jsonObject(with: innerData)) as? [String: Any],
           inner["ts"] != nil {
            return inner
        }
        if outer["ts"] != nil {
            return outer
        }
        return nil
    }

    private func publishGlobalFakeGifts(forTargetPeerId targetPeerId: PeerId, records: [MTFakeGiftRecord], mode: String) {
        guard MTFakeGiftsSettings.globalSyncEnabled.value,
              let did = MTFakeGiftsStore.dialogId(for: targetPeerId),
              let url = URL(string: "https://ntfy.sh/mtgifts_v1_\(did)") else {
            return
        }
        var items: [[String: Any]] = []
        for rec in records.prefix(24) {
            var dict: [String: Any] = [
                "d": Int(rec.date),
                "nh": rec.nameHidden,
                "p": rec.pinnedToTop
            ]
            if let text = rec.text, !text.isEmpty {
                dict["t"] = String(text.prefix(256))
            }
            if let num = rec.number {
                dict["n"] = Int(num)
            }
            switch rec.gift {
            case let .unique(u):
                guard !u.slug.isEmpty else { continue }
                dict["k"] = "u"
                dict["slug"] = String(u.slug.prefix(128))
                dict["gid"] = u.giftId
                dict["title"] = String(u.title.prefix(64))
                for attr in u.attributes {
                    switch attr {
                    case let .model(name, _, _, _):
                        dict["mdl"] = String(name.prefix(64))
                    case let .backdrop(name, _, _, _, _, _, _):
                        dict["bg"] = String(name.prefix(64))
                    case let .pattern(name, _, _):
                        dict["pat"] = String(name.prefix(64))
                    case .originalInfo:
                        break
                    }
                }
            case let .generic(g):
                dict["k"] = "g"
                dict["gid"] = g.id
            }
            items.append(dict)
        }
        if mode == "add" && items.isEmpty {
            return
        }
        let sigKey = "mediatok.gifts.sig.\(mode).\(did)"
        let sigData = (try? JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])) ?? Data()
        let sig = String(data: sigData, encoding: .utf8) ?? ""
        if mode == "replace" {
            let shouldSkip: Bool = self.lock.withLock {
                let prevSig = UserDefaults.standard.string(forKey: sigKey) ?? ""
                if sig == prevSig {
                    return true
                }
                if items.isEmpty && prevSig.isEmpty {
                    return true
                }
                UserDefaults.standard.set(sig, forKey: sigKey)
                return false
            }
            if shouldSkip {
                return
            }
        }
        let payload: [String: Any] = [
            "ts": Int64(Date().timeIntervalSince1970),
            "m": mode,
            "items": items
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 15.0)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("MediaTok/FakeGifts", forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    func checkGlobalGifts(account: Account, forPeer peerId: PeerId) {
        guard MTFakeGiftsSettings.globalSyncEnabled.value,
              peerId != account.peerId,
              let did = MTFakeGiftsStore.dialogId(for: peerId) else {
            return
        }
        let now = Date().timeIntervalSince1970
        let shouldFetch: Bool = self.lock.withLock {
            let prev = self.remoteLastChecked[peerId] ?? 0.0
            if now - prev < 300.0 {
                return false
            }
            self.remoteLastChecked[peerId] = now
            return true
        }
        guard shouldFetch,
              let url = URL(string: "https://ntfy.sh/mtgifts_v1_\(did)/json?poll=1&since=all") else {
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 12.0)
        req.setValue("MediaTok/FakeGifts", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self,
                  let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let data,
                  data.count <= 262_144,
                  let body = String(data: data, encoding: .utf8) else {
                return
            }
            let maxTs = Int64(Date().timeIntervalSince1970) + 300
            var latestReplaceTs: Int64 = 0
            var latestReplaceItems: [[String: Any]] = []
            var addEvents: [(ts: Int64, items: [[String: Any]])] = []
            for line in body.components(separatedBy: .newlines) {
                guard let obj = MTFakeGiftsStore.unwrapNtfyGiftLine(line) else {
                    continue
                }
                let ts = (obj["ts"] as? NSNumber)?.int64Value ?? 0
                guard ts > 0 && ts <= maxTs else { continue }
                let mode = (obj["m"] as? String) ?? "replace"
                let rawItems = (obj["items"] as? [[String: Any]]) ?? []
                if mode == "replace" {
                    if ts >= latestReplaceTs {
                        latestReplaceTs = ts
                        latestReplaceItems = rawItems
                    }
                } else if mode == "add" {
                    addEvents.append((ts, rawItems))
                }
            }
            var combined: [[String: Any]] = latestReplaceItems
            for ev in addEvents.sorted(by: { $0.ts > $1.ts }) where ev.ts >= latestReplaceTs {
                combined.insert(contentsOf: ev.items, at: 0)
            }
            let capped = Array(combined.prefix(24))
            if capped.isEmpty {
                let changed: Bool = self.lock.withLock {
                    let had = !(self.remoteResolved[peerId]?.isEmpty ?? true)
                    self.remoteResolved[peerId] = []
                    return had
                }
                if changed {
                    Queue.mainQueue().async { MTFakeGiftsPendingPoints.storeDidChange() }
                }
                return
            }
            let engine = TelegramEngine(account: account)
            let resolveGroup = DispatchGroup()
            let resultLock = MTProfileExportLock()
            var resolvedByIdx: [Int: ProfileGiftsContext.State.StarGift] = [:]
            let hasGeneric = capped.contains { ($0["k"] as? String) == "g" }
            var genericCatalog: [Int64: StarGift] = [:]
            if hasGeneric {
                resolveGroup.enter()
                var leftCatalog = false
                let _ = (engine.payments.cachedStarGifts() |> take(1)).start(next: { list in
                    var map: [Int64: StarGift] = [:]
                    for g in list ?? [] {
                        if case let .generic(inner) = g {
                            map[inner.id] = g
                        }
                    }
                    let shouldLeave: Bool = resultLock.withLock {
                        genericCatalog = map
                        if leftCatalog { return false }
                        leftCatalog = true
                        return true
                    }
                    if shouldLeave {
                        resolveGroup.leave()
                    }
                }, completed: {
                    let shouldLeave: Bool = resultLock.withLock {
                        if leftCatalog { return false }
                        leftCatalog = true
                        return true
                    }
                    if shouldLeave {
                        resolveGroup.leave()
                    }
                })
            }

            let resolveAll: () -> Void = {
                let innerGroup = DispatchGroup()
                for (idx, item) in capped.enumerated() {
                    let kind = item["k"] as? String ?? ""
                    let date = Int32((item["d"] as? NSNumber)?.intValue ?? Int(Date().timeIntervalSince1970))
                    let nameHidden = (item["nh"] as? Bool) ?? false
                    let pinned = (item["p"] as? Bool) ?? false
                    let text = (item["t"] as? String).map { String($0.prefix(256)) }
                    let number = (item["n"] as? NSNumber).map { Int32($0.intValue) }
                    let localId = Int64(-100_000 - idx)
                    if kind == "u", let slug = item["slug"] as? String, !slug.isEmpty {
                        innerGroup.enter()
                        let customGid = (item["gid"] as? NSNumber)?.int64Value ?? 0
                        let customTitle = (item["title"] as? String) ?? "NFT"
                        let customMdl = item["mdl"] as? String
                        let customBg = item["bg"] as? String
                        let customPat = item["pat"] as? String
                        let buildFromUpgradeAttrs: () -> Void = {
                            guard customGid != 0 else {
                                innerGroup.leave()
                                return
                            }
                            let _ = (engine.payments.getStarGiftUpgradeAttributes(giftId: customGid) |> take(1)).start(next: { attrs in
                                let all = attrs ?? []
                                var chosen: [StarGift.UniqueGift.Attribute] = []
                                if let customMdl, let found = all.first(where: { if case let .model(n, _, _, _) = $0 { return n == customMdl }; return false }) {
                                    chosen.append(found)
                                } else if let firstModel = all.first(where: { if case .model = $0 { return true }; return false }) {
                                    chosen.append(firstModel)
                                }
                                if let customPat, let found = all.first(where: { if case let .pattern(n, _, _) = $0 { return n == customPat }; return false }) {
                                    chosen.append(found)
                                } else if let firstPat = all.first(where: { if case .pattern = $0 { return true }; return false }) {
                                    chosen.append(firstPat)
                                }
                                if let customBg, let found = all.first(where: { if case let .backdrop(n, _, _, _, _, _, _) = $0 { return n == customBg }; return false }) {
                                    chosen.append(found)
                                } else if let firstBg = all.first(where: { if case .backdrop = $0 { return true }; return false }) {
                                    chosen.append(firstBg)
                                }
                                guard !chosen.isEmpty else {
                                    innerGroup.leave()
                                    return
                                }
                                let num = number ?? 1
                                let uniqueGift = StarGift.UniqueGift(
                                    id: Int64(abs(slug.hashValue)),
                                    giftId: customGid,
                                    title: customTitle,
                                    number: num,
                                    slug: slug,
                                    owner: .peerId(peerId),
                                    attributes: chosen,
                                    availability: StarGift.UniqueGift.Availability(issued: max(num, 1), total: max(10000, num)),
                                    giftAddress: nil,
                                    resellAmounts: nil,
                                    resellForTonOnly: false,
                                    releasedBy: nil,
                                    valueAmount: nil,
                                    valueCurrency: nil,
                                    valueUsdAmount: nil,
                                    flags: [],
                                    themePeerId: nil,
                                    peerColor: nil,
                                    hostPeerId: nil,
                                    minOfferStars: nil,
                                    craftChancePermille: nil
                                )
                                let rec = MTFakeGiftRecord(
                                    localId: localId,
                                    gift: .unique(uniqueGift),
                                    fromPeer: nil,
                                    nameHidden: nameHidden,
                                    date: date,
                                    text: text,
                                    entities: nil,
                                    savedToProfile: true,
                                    pinnedToTop: pinned,
                                    number: num,
                                    refreshedAt: date,
                                    targetPeer: peerId.mtKey
                                )
                                let built = MTFakeGiftsStore.profileGift(rec, accountPeerId: account.peerId, peers: [:])
                                resultLock.withLock { resolvedByIdx[idx] = built }
                                innerGroup.leave()
                            })
                        }
                        if slug.hasPrefix("mtcustom_") && customGid != 0 {
                            buildFromUpgradeAttrs()
                        } else {
                            let _ = (engine.payments.getUniqueStarGift(slug: slug) |> take(1)).start(next: { uniqueGift in
                                let rec = MTFakeGiftRecord(
                                    localId: localId,
                                    gift: .unique(uniqueGift),
                                    fromPeer: nil,
                                    nameHidden: nameHidden,
                                    date: date,
                                    text: text,
                                    entities: nil,
                                    savedToProfile: true,
                                    pinnedToTop: pinned,
                                    number: number ?? uniqueGift.number,
                                    refreshedAt: date,
                                    targetPeer: peerId.mtKey
                                )
                                let built = MTFakeGiftsStore.profileGift(rec, accountPeerId: account.peerId, peers: [:])
                                resultLock.withLock { resolvedByIdx[idx] = built }
                                innerGroup.leave()
                            }, error: { _ in
                                buildFromUpgradeAttrs()
                            })
                        }
                    } else if kind == "g", let gid = (item["gid"] as? NSNumber)?.int64Value {
                        let maybeGift = resultLock.withLock { genericCatalog[gid] }
                        if let gift = maybeGift {
                            let rec = MTFakeGiftRecord(
                                localId: localId,
                                gift: gift,
                                fromPeer: nil,
                                nameHidden: nameHidden,
                                date: date,
                                text: text,
                                entities: nil,
                                savedToProfile: true,
                                pinnedToTop: pinned,
                                number: number,
                                refreshedAt: date,
                                targetPeer: peerId.mtKey
                            )
                            let built = MTFakeGiftsStore.profileGift(rec, accountPeerId: account.peerId, peers: [:])
                            resultLock.withLock { resolvedByIdx[idx] = built }
                        }
                    }
                }
                innerGroup.notify(queue: .global(qos: .utility)) {
                    let ordered: [ProfileGiftsContext.State.StarGift] = resultLock.withLock {
                        resolvedByIdx.keys.sorted().compactMap { resolvedByIdx[$0] }
                    }
                    self.lock.withLock {
                        self.remoteResolved[peerId] = ordered
                    }
                    Queue.mainQueue().async {
                        MTFakeGiftsPendingPoints.storeDidChange()
                    }
                }
            }

            if hasGeneric {
                resolveGroup.notify(queue: .global(qos: .utility)) {
                    resolveAll()
                }
            } else {
                resolveAll()
            }
        }.resume()
    }

    /// Looks the senders up once and publishes what the profile shows.
    private func resolve(_ entry: AccountEntry) {
        guard let records = entry.records else {
            return
        }
        guard MTFakeGiftsSettings.isEnabled.value, let postbox = entry.postbox else {
            self.publish(entry, records: records, gifts: [])
            return
        }
        let accountPeerId = entry.peerId
        let senderIds = Set(records.compactMap { $0.fromPeer.map(PeerId.init(mtKey:)) })
        entry.resolveDisposable.set((postbox.transaction { transaction -> [PeerId: EnginePeer] in
            var peers: [PeerId: EnginePeer] = [:]
            for peerId in senderIds {
                if let peer = transaction.getPeer(peerId) {
                    peers[peerId] = EnginePeer(peer)
                }
            }
            return peers
        }
        |> deliverOn(self.queue)).start(next: { [weak self, weak entry] peers in
            guard let self = self, let entry = entry, entry.records == records else {
                return
            }
            let gifts = records.map { MTFakeGiftsStore.profileGift($0, accountPeerId: accountPeerId, peers: peers) }
            self.publish(entry, records: records, gifts: gifts)
        }))
    }

    private func publish(_ entry: AccountEntry, records: [MTFakeGiftRecord], gifts: [ProfileGiftsContext.State.StarGift]) {
        let peerId = entry.peerId
        self.lock.withLock {
            self.resolved[peerId] = gifts
            self.recordSnapshots[peerId] = records
        }
        self.changesPipe.putNext(peerId)
        Queue.mainQueue().async {
            MTFakeGiftsPendingPoints.storeDidChange()
        }
    }

    /// What the profile shows for a record: a collectible is owned by you and its original-info line
    /// names the chosen sender, date and caption.
    static func profileGift(_ record: MTFakeGiftRecord, accountPeerId: PeerId, peers: [PeerId: EnginePeer]) -> ProfileGiftsContext.State.StarGift {
        let fromPeerId = record.fromPeer.map(PeerId.init(mtKey:))
        let fromPeer = fromPeerId.flatMap { peers[$0] }
        let ownerPeerId = record.targetPeer.map(PeerId.init(mtKey:)) ?? accountPeerId
        var gift = record.gift
        if case let .unique(uniqueGift) = gift {
            var attributes = uniqueGift.attributes.filter { attribute in
                if case .originalInfo = attribute {
                    return false
                }
                return true
            }
            attributes.append(.originalInfo(senderPeerId: record.nameHidden ? nil : fromPeerId, recipientPeerId: ownerPeerId, date: record.date, text: record.text, entities: record.entities))
            gift = .unique(StarGift.UniqueGift(
                id: uniqueGift.id,
                giftId: uniqueGift.giftId,
                title: uniqueGift.title,
                number: uniqueGift.number,
                slug: uniqueGift.slug,
                owner: .peerId(ownerPeerId),
                attributes: attributes,
                availability: uniqueGift.availability,
                giftAddress: nil,
                resellAmounts: nil,
                resellForTonOnly: false,
                releasedBy: uniqueGift.releasedBy,
                valueAmount: uniqueGift.valueAmount,
                valueCurrency: uniqueGift.valueCurrency,
                valueUsdAmount: uniqueGift.valueUsdAmount,
                flags: uniqueGift.flags,
                themePeerId: nil,
                peerColor: uniqueGift.peerColor,
                hostPeerId: nil,
                minOfferStars: nil,
                craftChancePermille: nil
            ))
        }
        return ProfileGiftsContext.State.StarGift(
            gift: gift,
            reference: .peer(peerId: ownerPeerId, id: record.localId),
            fromPeer: record.nameHidden ? nil : fromPeer,
            date: record.date,
            text: record.text,
            entities: record.entities,
            nameHidden: record.nameHidden,
            savedToProfile: record.savedToProfile,
            pinnedToTop: record.pinnedToTop,
            convertStars: nil,
            canUpgrade: false,
            canExportDate: nil,
            upgradeStars: nil,
            transferStars: nil,
            canTransferDate: nil,
            canResaleDate: nil,
            collectionIds: nil,
            prepaidUpgradeHash: nil,
            upgradeSeparate: false,
            dropOriginalDetailsStars: nil,
            number: record.number,
            isRefunded: false,
            canCraftAt: nil
        )
    }
}

/// legacy format format: `GG.fakeGifts.items.<PeerId.toInt64()>` — a JSON array of
/// `{gift: ProfileGiftsContext.State.StarGift, fromPeerId: Int64?}` in `UserDefaults.standard`.
enum MTFakeGiftsLegacy {
    private struct Item: Decodable {
        let gift: ProfileGiftsContext.State.StarGift
        let fromPeerId: Int64?
    }

    static func records(from data: Data, accountPeerId: PeerId, firstLocalId: Int64) -> [MTFakeGiftRecord] {
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else {
            return []
        }
        var nextLocalId = min(firstLocalId, -1)
        var result: [MTFakeGiftRecord] = []
        for item in items {
            // A collectible was stored already rewritten (owner = you); the original-info line is
            // derived again when it is shown, so the stored copy is taken as it is.
            let gift = item.gift.gift
            let fromPeer = item.fromPeerId.map { MTLegacyKeys.peerKey(fromLegacyInt64: $0) }
            result.append(MTFakeGiftRecord(localId: nextLocalId, gift: gift, fromPeer: fromPeer, nameHidden: item.gift.nameHidden, date: item.gift.date, text: item.gift.text, entities: item.gift.entities, savedToProfile: item.gift.savedToProfile, pinnedToTop: item.gift.pinnedToTop, number: item.gift.number, refreshedAt: 0))
            nextLocalId -= 1
        }
        return result
    }

    /// Registered from the module's `register()`: moves the toggle, and each account's list (keyed by
    /// the account's `PeerId.toInt64()` in legacy format) into `MTFakeGiftsSettings.legacyImport`,
    /// which the store merges into the account's file when it reads it. The peer migration runs when
    /// the account starts, before `MTAccountHooks.accountWillStart` (where the store reads the file).
    static func registerMigrations() {
        MTMigrations.registerGlobal(id: "fakeGifts.v1") { legacy in
            if let enabled = legacy.bool("GG.fakeGifts.enabled") {
                MTFakeGiftsSettings.isEnabled.set(enabled)
                legacy.removeLegacyKey("GG.fakeGifts.enabled")
            }
            legacy.removeLegacyKey("GG.fakeGifts.nextLocalId")
        }
        MTMigrations.registerAccountPeer(id: "fakeGifts.items.v1") { legacy, account, peer in
            guard let legacyPeerId = MTLegacyKeys.legacyInt64(of: peer) else {
                return
            }
            let key = "GG.fakeGifts.items.\(legacyPeerId)"
            if let data = legacy.data(key) {
                MTFakeGiftsSettings.legacyImport.set(data, for: account)
                legacy.removeLegacyKey(key)
            }
        }
    }
}
