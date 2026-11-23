import Foundation

/// One-time moves of the legacy MediaTok settings (same bundle id, so the old `UserDefaults` are
/// still there after an update). Each feature registers its own "old key → new setting" table in
/// its `register()`; MTCore only runs them.
///
///     MTMigrations.registerGlobal(id: "ghostMode.v1") { legacy in
///         if let value = legacy.bool("GhostMode.hideReadReceipts") {
///             GhostModeSettings.hideReadReceipts.set(value)
///             legacy.removeLegacyKey("GhostMode.hideReadReceipts")
///         }
///     }
///
/// A migration runs once: its id is stored in `global.json` (account migrations: in the account's
/// file) after the body returns. Ids are stable; to migrate again, register a new id. Bodies run
/// in the app process only, global ones on the launch thread, account ones on the thread that
/// creates the `Account`; they may only read `legacy` and write MediaTok settings.
public enum MTMigrations {
    private struct GlobalEntry {
        let id: String
        let body: (MTLegacyDefaults) -> Void
    }

    private struct AccountEntry {
        let id: String
        let body: (MTLegacyDefaults, MTAccountID) -> Void
    }

    private struct AccountPeerEntry {
        let id: String
        let body: (MTLegacyDefaults, MTAccountID, MTPeerKey) -> Void
    }

    private static let lock = MTUnfairLock()
    private static var globalEntries: [GlobalEntry] = []
    private static var accountEntries: [AccountEntry] = []
    private static var accountPeerEntries: [AccountPeerEntry] = []
    /// The account's own peer, once the TelegramCore bridge reported it in this process.
    private static var accountPeers: [MTAccountID: MTPeerKey] = [:]

    static let completedGlobal = MTSetting<[String]>("core.migrations.done", default: [], flags: [.noExport])
    static let completedAccount = MTAccountSetting<[String]>("core.migrations.accountDone", default: [], flags: [.noExport])

    /// `id` is unique and stable ("ghostMode.v1"). Runs once, the flag is stored in global.json.
    public static func registerGlobal(id: String, _ body: @escaping (MTLegacyDefaults) -> Void) {
        let isDuplicate = MTMigrations.lock.withLock { () -> Bool in
            if MTMigrations.globalEntries.contains(where: { $0.id == id }) {
                return true
            }
            MTMigrations.globalEntries.append(GlobalEntry(id: id, body: body))
            return false
        }
        assert(!isDuplicate, "Duplicate migration id \(id)")
    }

    /// Runs once per account, when the account registers (and for accounts registered before the
    /// migration was declared, from `MTCore.runGlobalMigrations()`).
    public static func registerAccount(id: String, _ body: @escaping (MTLegacyDefaults, MTAccountID) -> Void) {
        let isDuplicate = MTMigrations.lock.withLock { () -> Bool in
            if MTMigrations.isAccountIdTaken(id) {
                return true
            }
            MTMigrations.accountEntries.append(AccountEntry(id: id, body: body))
            return false
        }
        assert(!isDuplicate, "Duplicate migration id \(id)")
    }

    /// Like `registerAccount`, for old data keyed by the account's own peer id (legacy format used
    /// `PeerId.toInt64()` of the account: `MTLegacyKeys.legacyInt64(of: peer)`). The peer is known
    /// only once the account starts (`Account.init`), so the body runs then — after the account's
    /// settings are loaded and before the features' `MTAccountHooks.accountWillStart` handlers.
    /// Shares the "done" list (and the id space) with `registerAccount`.
    public static func registerAccountPeer(id: String, _ body: @escaping (MTLegacyDefaults, MTAccountID, MTPeerKey) -> Void) {
        let isDuplicate = MTMigrations.lock.withLock { () -> Bool in
            if MTMigrations.isAccountIdTaken(id) {
                return true
            }
            MTMigrations.accountPeerEntries.append(AccountPeerEntry(id: id, body: body))
            return false
        }
        assert(!isDuplicate, "Duplicate migration id \(id)")
    }

    /// Called by the TelegramCore bridge when an account starts and its own peer is known: runs the
    /// account's pending `registerAccountPeer` migrations. App process only; other processes only
    /// remember the peer.
    public static func accountPeerDidLoad(_ account: MTAccountID, peer: MTPeerKey) {
        MTMigrations.lock.withLock {
            MTMigrations.accountPeers[account] = peer
        }
        MTMigrations.runPendingAccountPeerMigrations(for: account, peer: peer)
    }

    /// Lock held.
    private static func isAccountIdTaken(_ id: String) -> Bool {
        if MTMigrations.accountEntries.contains(where: { $0.id == id }) {
            return true
        }
        return MTMigrations.accountPeerEntries.contains(where: { $0.id == id })
    }

    /// `MTCore.runGlobalMigrations()`: every pending global migration, then the pending account
    /// migrations of the accounts already registered. App process only.
    static func runPending(legacy: MTLegacyDefaults? = nil) {
        guard MTSettingsStore.shared.processKind == .app else {
            return
        }
        let legacyDefaults = legacy ?? MTLegacyDefaults.current()
        let entries = MTMigrations.lock.withLock {
            return MTMigrations.globalEntries
        }
        var completed = MTMigrations.completedGlobal.value
        var didRun = false
        for entry in entries where !completed.contains(entry.id) {
            MTLog.info("migrations", "running \(entry.id)")
            entry.body(legacyDefaults)
            completed.append(entry.id)
            didRun = true
        }
        if didRun {
            MTMigrations.completedGlobal.set(completed)
        }
        for account in MTSettingsStore.shared.registeredAccounts {
            MTMigrations.runPendingAccountMigrations(for: account, legacy: legacyDefaults)
            let peer = MTMigrations.lock.withLock {
                return MTMigrations.accountPeers[account]
            }
            if let peer = peer {
                MTMigrations.runPendingAccountPeerMigrations(for: account, peer: peer, legacy: legacyDefaults)
            }
        }
        if didRun {
            MTSettingsStore.shared.flush()
        }
    }

    static func runPendingAccountMigrations(for account: MTAccountID, legacy: MTLegacyDefaults? = nil) {
        guard MTSettingsStore.shared.processKind == .app else {
            return
        }
        let entries = MTMigrations.lock.withLock {
            return MTMigrations.accountEntries
        }
        if entries.isEmpty {
            return
        }
        var legacyDefaults = legacy
        var completed = MTMigrations.completedAccount.value(for: account)
        var didRun = false
        for entry in entries where !completed.contains(entry.id) {
            if legacyDefaults == nil {
                legacyDefaults = MTLegacyDefaults.current()
            }
            guard let defaults = legacyDefaults else {
                continue
            }
            MTLog.info("migrations", "running \(entry.id) for an account")
            entry.body(defaults, account)
            completed.append(entry.id)
            didRun = true
        }
        if didRun {
            MTMigrations.completedAccount.set(completed, for: account)
        }
    }

    static func runPendingAccountPeerMigrations(for account: MTAccountID, peer: MTPeerKey, legacy: MTLegacyDefaults? = nil) {
        guard MTSettingsStore.shared.processKind == .app else {
            return
        }
        let entries = MTMigrations.lock.withLock {
            return MTMigrations.accountPeerEntries
        }
        if entries.isEmpty || !MTSettingsStore.shared.registeredAccounts.contains(account) {
            return
        }
        var legacyDefaults = legacy
        var completed = MTMigrations.completedAccount.value(for: account)
        var didRun = false
        for entry in entries where !completed.contains(entry.id) {
            if legacyDefaults == nil {
                legacyDefaults = MTLegacyDefaults.current()
            }
            guard let defaults = legacyDefaults else {
                continue
            }
            MTLog.info("migrations", "running \(entry.id) for an account")
            entry.body(defaults, account, peer)
            completed.append(entry.id)
            didRun = true
        }
        if didRun {
            MTMigrations.completedAccount.set(completed, for: account)
        }
    }

    /// Tests only.
    static func resetForTesting() {
        MTMigrations.lock.withLock {
            MTMigrations.globalEntries.removeAll()
            MTMigrations.accountEntries.removeAll()
            MTMigrations.accountPeerEntries.removeAll()
            MTMigrations.accountPeers.removeAll()
        }
    }
}

/// Read access to the settings of the legacy MediaTok: `UserDefaults.standard` and the old App
/// Group suite. Typed getters return nil when the key is absent or holds another type.
public struct MTLegacyDefaults {
    private let stores: [UserDefaults]

    init(stores: [UserDefaults]) {
        self.stores = stores
    }

    /// `UserDefaults.standard` plus `group.<main bundle id>` (or the environment's legacy group).
    static func current() -> MTLegacyDefaults {
        var stores: [UserDefaults] = [UserDefaults.standard]
        var groupIdentifier = MTCore.environment?.legacyAppGroupIdentifier
        if groupIdentifier == nil, let bundleIdentifier = Bundle.main.bundleIdentifier {
            groupIdentifier = "group.\(bundleIdentifier)"
        }
        if let groupIdentifier = groupIdentifier, let group = UserDefaults(suiteName: groupIdentifier) {
            stores.append(group)
        }
        return MTLegacyDefaults(stores: stores)
    }

    public func object(_ key: String) -> Any? {
        for store in self.stores {
            if let value = store.object(forKey: key) {
                return value
            }
        }
        return nil
    }

    public func bool(_ key: String) -> Bool? {
        guard let value = self.object(key) else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    public func int(_ key: String) -> Int? {
        guard let value = self.object(key) else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    public func double(_ key: String) -> Double? {
        guard let value = self.object(key) else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    public func string(_ key: String) -> String? {
        return self.object(key) as? String
    }

    public func data(_ key: String) -> Data? {
        return self.object(key) as? Data
    }

    public func stringArray(_ key: String) -> [String]? {
        guard let array = self.object(key) as? [Any] else {
            return nil
        }
        var result: [String] = []
        for item in array {
            guard let string = item as? String else {
                return nil
            }
            result.append(string)
        }
        return result
    }

    /// Removes the key from every store, after its value has been moved.
    public func removeLegacyKey(_ key: String) {
        for store in self.stores {
            store.removeObject(forKey: key)
        }
    }

    /// The per-account profile of the old `MTAccountConfigManager` (`GG.accountConfigs.snapshots.
    /// <client>.<sanitized account>`): the old account-scoped `GhostMode.*` / `MiscSettings.*` /
    /// `DeviceSpoof.*` values of that account, or nil when profiles were never saved for it.
    /// The old code keyed it by the sanitized `"\(AccountRecordId)"` text, which loses the sign of
    /// the id; a profile of the negated id would also match (practically never, ids are random).
    public func legacyAccountProfile(for account: MTAccountID) -> [String: Any]? {
        let sanitized = MTLegacyDefaults.sanitizedAccountText(account)
        for client in ["mediatok"] {
            if let profile = self.object("GG.accountConfigs.snapshots.\(client).\(sanitized)") as? [String: Any] {
                return profile
            }
        }
        return nil
    }

    /// Whether the old per-account profiles were switched on (`GG.accountConfigs.enabled.mediatok`).
    public var legacyAccountProfilesEnabled: Bool {
        return self.bool("GG.accountConfigs.enabled.mediatok") ?? false
    }

    /// The value an old account-scoped key had for `account`. Profiles off: the one shared value.
    /// Profiles on: the shared keys hold the live values of the account that was active
    /// (`GG.accountConfigs.activeAccountId.mediatok`; its profile was saved only when switching
    /// away and may be stale); any other account has its profile only — a key missing there was
    /// unset for that account, never the active account's value.
    public func legacyAccountValue(_ key: String, for account: MTAccountID) -> Any? {
        if !self.legacyAccountProfilesEnabled {
            return self.object(key)
        }
        if self.string("GG.accountConfigs.activeAccountId.mediatok") == MTLegacyDefaults.sanitizedAccountText(account) {
            return self.object(key)
        }
        return self.legacyAccountProfile(for: account)?[key]
    }

    static func sanitizedAccountText(_ account: MTAccountID) -> String {
        let text = "AccountRecordId(rawValue: \(account.rawValue))"
        var result = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("_")
            }
        }
        return result
    }
}
