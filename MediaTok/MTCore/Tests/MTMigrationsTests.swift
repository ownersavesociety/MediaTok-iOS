import Foundation
import XCTest

final class MTMigrationsTests: XCTestCase {
    private var directory: MTTestDirectory!
    private var suiteName: String!
    private var legacyStore: UserDefaults!

    override func setUp() {
        super.setUp()
        MTTestSettings.touchAll()
        self.directory = MTTestDirectory()
        MTSettingsStore.shared.resetForTesting(environment: self.directory.environment())
        MTMigrations.resetForTesting()
        self.suiteName = "MTCoreTests.legacy.\(UUID().uuidString)"
        self.legacyStore = UserDefaults(suiteName: self.suiteName)
    }

    override func tearDown() {
        MTMigrations.resetForTesting()
        self.legacyStore.removePersistentDomain(forName: self.suiteName)
        MTSettingsStore.shared.flushSynchronously()
        MTSettingsStore.shared.resetForTesting(environment: nil)
        self.directory.remove()
        super.tearDown()
    }

    private var legacy: MTLegacyDefaults {
        return MTLegacyDefaults(stores: [self.legacyStore])
    }

    func testGlobalMigrationRunsOnceAndIsRemembered() {
        self.legacyStore.set(true, forKey: "GhostMode.hideReadReceipts")
        var runs = 0
        MTMigrations.registerGlobal(id: "test.v1") { legacy in
            runs += 1
            if let value = legacy.bool("GhostMode.hideReadReceipts") {
                MTTestSettings.toggle.set(value)
                legacy.removeLegacyKey("GhostMode.hideReadReceipts")
            }
        }
        MTMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(MTTestSettings.toggle.value)
        XCTAssertNil(self.legacyStore.object(forKey: "GhostMode.hideReadReceipts"))

        MTMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(runs, 1)

        // The flag survives a relaunch.
        MTSettingsStore.shared.flushSynchronously()
        MTSettingsStore.shared.resetForTesting(environment: self.directory.environment())
        MTMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(MTMigrations.completedGlobal.value.contains("test.v1"))
    }

    func testMigrationsDoNotRunInExtensions() {
        MTSettingsStore.shared.resetForTesting(environment: self.directory.environment(process: .share))
        var runs = 0
        MTMigrations.registerGlobal(id: "test.extension") { _ in
            runs += 1
        }
        MTMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(runs, 0)
    }

    func testAccountMigrationRunsPerAccount() {
        let first = MTAccountID(rawValue: 11)
        let second = MTAccountID(rawValue: 12)
        MTSettingsStore.shared.registerAccount(first, basePath: self.directory.makeDirectory("a11"))
        var seen: [MTAccountID] = []
        MTMigrations.registerAccount(id: "test.account.v1") { _, account in
            seen.append(account)
            MTTestSettings.accountToggle.set(true, for: account)
        }
        MTMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(seen, [first])
        XCTAssertTrue(MTTestSettings.accountToggle.value(for: first))

        MTSettingsStore.shared.registerAccount(second, basePath: self.directory.makeDirectory("a12"))
        MTMigrations.runPendingAccountMigrations(for: second, legacy: self.legacy)
        XCTAssertEqual(seen, [first, second])

        MTMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(seen, [first, second])
    }

    func testAccountPeerMigrationRunsOnceThePeerIsKnown() {
        let account = MTAccountID(rawValue: 21)
        let peer = MTLegacyKeys.peerKey(fromLegacyInt64: 777000)
        MTSettingsStore.shared.registerAccount(account, basePath: self.directory.makeDirectory("a21"))
        var seen: [(MTAccountID, MTPeerKey)] = []
        MTMigrations.registerAccountPeer(id: "test.accountPeer.v1") { _, account, peer in
            seen.append((account, peer))
            MTTestSettings.accountToggle.set(true, for: account)
        }

        // The peer is not known yet: nothing runs and nothing is marked done.
        MTMigrations.runPending(legacy: self.legacy)
        XCTAssertTrue(seen.isEmpty)
        XCTAssertFalse(MTMigrations.completedAccount.value(for: account).contains("test.accountPeer.v1"))

        MTMigrations.accountPeerDidLoad(account, peer: peer)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.0, account)
        XCTAssertEqual(seen.first?.1, peer)
        XCTAssertTrue(MTTestSettings.accountToggle.value(for: account))

        // Once per account: neither a restart of the account nor the global pass run it again.
        MTMigrations.accountPeerDidLoad(account, peer: peer)
        MTMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(seen.count, 1)
        XCTAssertTrue(MTMigrations.completedAccount.value(for: account).contains("test.accountPeer.v1"))
    }

    func testAccountPeerMigrationOfAKnownPeerRunsFromTheGlobalPass() {
        let account = MTAccountID(rawValue: 22)
        let peer = MTLegacyKeys.peerKey(fromLegacyInt64: 777001)
        MTSettingsStore.shared.registerAccount(account, basePath: self.directory.makeDirectory("a22"))
        MTMigrations.accountPeerDidLoad(account, peer: peer)
        var runs = 0
        MTMigrations.registerAccountPeer(id: "test.accountPeer.late") { _, _, _ in
            runs += 1
        }
        MTMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(runs, 1)
    }

    func testLegacyDefaultsTypedReaders() {
        self.legacyStore.set(true, forKey: "b")
        self.legacyStore.set("1", forKey: "bs")
        self.legacyStore.set(42, forKey: "i")
        self.legacyStore.set("43", forKey: "is")
        self.legacyStore.set(1.5, forKey: "d")
        self.legacyStore.set("text", forKey: "s")
        self.legacyStore.set(Data([1, 2]), forKey: "data")
        self.legacyStore.set(["a", "b"], forKey: "sa")
        self.legacyStore.set(["a", 1] as [Any], forKey: "mixed")

        let legacy = self.legacy
        XCTAssertEqual(legacy.bool("b"), true)
        XCTAssertEqual(legacy.bool("bs"), true)
        XCTAssertEqual(legacy.int("i"), 42)
        XCTAssertEqual(legacy.int("is"), 43)
        XCTAssertEqual(legacy.double("d"), 1.5)
        XCTAssertEqual(legacy.string("s"), "text")
        XCTAssertNil(legacy.string("i"))
        XCTAssertEqual(legacy.data("data"), Data([1, 2]))
        XCTAssertEqual(legacy.stringArray("sa"), ["a", "b"])
        XCTAssertNil(legacy.stringArray("mixed"))
        XCTAssertNil(legacy.bool("absent"))
    }

    func testLegacyAccountProfileKey() {
        XCTAssertEqual(MTLegacyDefaults.sanitizedAccountText(MTAccountID(rawValue: 123)), "AccountRecordId_rawValue__123_")
        XCTAssertEqual(MTLegacyDefaults.sanitizedAccountText(MTAccountID(rawValue: -5)), "AccountRecordId_rawValue___5_")

        let profile: [String: Any] = ["GhostMode.isEnabled": true]
        self.legacyStore.set(profile, forKey: "GG.accountConfigs.snapshots.mediatok.AccountRecordId_rawValue__123_")
        let loaded = self.legacy.legacyAccountProfile(for: MTAccountID(rawValue: 123))
        XCTAssertEqual(loaded?["GhostMode.isEnabled"] as? Bool, true)
        XCTAssertNil(self.legacy.legacyAccountProfile(for: MTAccountID(rawValue: 124)))
    }

    /// With the old profiles on, the shared keys belong to the active account only.
    func testLegacyAccountValue() {
        let active = MTAccountID(rawValue: 123)
        let other = MTAccountID(rawValue: 124)
        let otherWithProfile = MTAccountID(rawValue: 125)
        self.legacyStore.set("777", forKey: "GG.hyperlinkSpoof.targetId")
        self.legacyStore.set(["GG.hyperlinkSpoof.targetId": "555"], forKey: "GG.accountConfigs.snapshots.mediatok.AccountRecordId_rawValue__123_")
        self.legacyStore.set(["GhostMode.isEnabled": true], forKey: "GG.accountConfigs.snapshots.mediatok.AccountRecordId_rawValue__125_")

        // Profiles off: everybody has the shared value.
        XCTAssertEqual(self.legacy.legacyAccountValue("GG.hyperlinkSpoof.targetId", for: active) as? String, "777")
        XCTAssertEqual(self.legacy.legacyAccountValue("GG.hyperlinkSpoof.targetId", for: other) as? String, "777")

        self.legacyStore.set(true, forKey: "GG.accountConfigs.enabled.mediatok")
        self.legacyStore.set("AccountRecordId_rawValue__123_", forKey: "GG.accountConfigs.activeAccountId.mediatok")
        // The active account: the live shared value, not its older profile.
        XCTAssertEqual(self.legacy.legacyAccountValue("GG.hyperlinkSpoof.targetId", for: active) as? String, "777")
        // Others: their profile only.
        XCTAssertNil(self.legacy.legacyAccountValue("GG.hyperlinkSpoof.targetId", for: other))
        XCTAssertNil(self.legacy.legacyAccountValue("GG.hyperlinkSpoof.targetId", for: otherWithProfile))
        XCTAssertEqual(self.legacy.legacyAccountValue("GhostMode.isEnabled", for: otherWithProfile) as? Bool, true)
    }
}
