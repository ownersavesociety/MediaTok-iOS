import Foundation
import SwiftSignalKit
import XCTest

/// Settings used only by these tests. Declared once: a second declaration of a key asserts.
enum MTTestSettings {
    static let toggle = MTSetting<Bool>("test.toggle", default: false)
    static let counter = MTSetting<Int>("test.counter", default: 7)
    static let title = MTSetting<String>("test.title", default: "")
    static let optionalText = MTSetting<String?>("test.optionalText", default: nil)
    static let list = MTSetting<[String]>("test.list", default: [])
    static let peers = MTSetting<Set<MTPeerKey>>("test.peers", default: [])
    static let shared = MTSetting<Bool>("test.sharedFlag", default: false, scope: .appGroup, flags: [.extensions])
    static let secret = MTSetting<String>("test.secret", default: "", flags: [.noExport])
    static let restart = MTSetting<Bool>("test.restart", default: false, flags: [.requiresRestart])
    static let exceptions = MTAccountSetting<[String]>("test.exceptions", default: [])
    static let accountToggle = MTAccountSetting<Bool>("test.accountToggle", default: false)
    static let accountSecret = MTAccountSetting<String>("test.accountSecret", default: "", flags: [.noExport])

    static func touchAll() {
        let _ = MTTestSettings.toggle
        let _ = MTTestSettings.counter
        let _ = MTTestSettings.title
        let _ = MTTestSettings.optionalText
        let _ = MTTestSettings.list
        let _ = MTTestSettings.peers
        let _ = MTTestSettings.shared
        let _ = MTTestSettings.secret
        let _ = MTTestSettings.restart
        let _ = MTTestSettings.exceptions
        let _ = MTTestSettings.accountToggle
        let _ = MTTestSettings.accountSecret
    }
}

final class MTSettingsStoreTests: XCTestCase {
    private var directory: MTTestDirectory!

    override func setUp() {
        super.setUp()
        MTTestSettings.touchAll()
        self.directory = MTTestDirectory()
        MTSettingsStore.shared.resetForTesting(environment: self.directory.environment())
    }

    override func tearDown() {
        MTSettingsStore.shared.flushSynchronously()
        MTSettingsStore.shared.resetForTesting(environment: nil)
        self.directory.remove()
        self.directory = nil
        super.tearDown()
    }

    private func reload(process: MTProcessKind = .app) {
        MTSettingsStore.shared.flushSynchronously()
        MTSettingsStore.shared.resetForTesting(environment: self.directory.environment(process: process))
    }

    // MARK: - Values and signals

    func testDefaultSetResetAndIsDefault() {
        XCTAssertEqual(MTTestSettings.counter.value, 7)
        XCTAssertTrue(MTTestSettings.counter.isDefault)

        MTTestSettings.counter.set(42)
        XCTAssertEqual(MTTestSettings.counter.value, 42)
        XCTAssertFalse(MTTestSettings.counter.isDefault)

        MTTestSettings.counter.reset()
        XCTAssertEqual(MTTestSettings.counter.value, 7)
        XCTAssertTrue(MTTestSettings.counter.isDefault)
    }

    func testOptionalAndCollectionValues() {
        MTTestSettings.optionalText.set("a")
        MTTestSettings.list.set(["x", "y"])
        let peer = MTPeerKey(namespace: 2, id: 1234567890)!
        MTTestSettings.peers.set([peer])
        self.reload()
        XCTAssertEqual(MTTestSettings.optionalText.value, "a")
        XCTAssertEqual(MTTestSettings.list.value, ["x", "y"])
        XCTAssertEqual(MTTestSettings.peers.value, [peer])

        MTTestSettings.optionalText.set(nil)
        self.reload()
        XCTAssertNil(MTTestSettings.optionalText.value)
    }

    func testSignalDeliversCurrentValueThenDistinctChanges() {
        MTTestSettings.counter.set(1)
        let recorder = MTSignalRecorder(MTTestSettings.counter.signal)
        MTTestSettings.counter.set(2)
        MTTestSettings.counter.set(2)
        MTTestSettings.counter.set(3)
        MTTestSettings.counter.set(1)
        XCTAssertEqual(recorder.values, [1, 2, 3, 1])
        recorder.dispose()
        MTTestSettings.counter.set(9)
        XCTAssertEqual(recorder.values, [1, 2, 3, 1])
    }

    func testRevisionGrowsOnEveryChange() {
        let recorder = MTSignalRecorder(MTSettingsStore.shared.revision)
        XCTAssertEqual(recorder.values.count, 1)
        MTTestSettings.toggle.set(true)
        MTTestSettings.toggle.set(true)
        MTTestSettings.title.set("x")
        let values = recorder.values
        XCTAssertEqual(values.count, 3)
        XCTAssertTrue(values[1] > values[0] && values[2] > values[1])
        recorder.dispose()
    }

    // MARK: - Files

    func testGlobalValueIsWrittenAndReloaded() {
        MTTestSettings.title.set("hello")
        MTSettingsStore.shared.flushSynchronously()
        let stored = self.directory.storedValues(self.directory.globalFilePath)
        XCTAssertEqual(stored?["test.title"] as? String, "hello")

        MTSettingsStore.shared.resetForTesting(environment: nil)
        XCTAssertEqual(MTTestSettings.title.value, "")
        MTSettingsStore.shared.resetForTesting(environment: self.directory.environment())
        XCTAssertEqual(MTTestSettings.title.value, "hello")
    }

    func testDefaultValuesAreNotWritten() {
        MTTestSettings.toggle.set(true)
        MTSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.globalFilePath)?["test.toggle"] as? Bool, true)

        MTTestSettings.toggle.set(false)
        MTSettingsStore.shared.flushSynchronously()
        let stored = self.directory.storedValues(self.directory.globalFilePath)
        XCTAssertNotNil(stored)
        XCTAssertNil(stored?["test.toggle"])
    }

    func testUnknownKeysSurviveRewrite() {
        self.directory.writeFile(self.directory.globalFilePath, "{\"version\":1,\"values\":{\"future.feature\":{\"a\":[1,2]},\"test.counter\":11}}")
        self.reload()
        XCTAssertEqual(MTTestSettings.counter.value, 11)

        MTTestSettings.counter.set(12)
        MTSettingsStore.shared.flushSynchronously()
        let stored = self.directory.storedValues(self.directory.globalFilePath)
        XCTAssertEqual(stored?["test.counter"] as? Int, 12)
        let future = stored?["future.feature"] as? [String: Any]
        XCTAssertEqual(future?["a"] as? [Int], [1, 2])
    }

    func testWritesAreCoalesced() {
        for value in 0 ..< 50 {
            MTTestSettings.counter.set(100 + value)
        }
        // Nothing is on disk before the coalescing delay.
        XCTAssertNil(self.directory.storedValues(self.directory.globalFilePath))

        let written = self.expectation(description: "coalesced write")
        DispatchQueue.main.asyncAfter(deadline: .now() + MTSettingsStore.coalescingDelay + 0.5) {
            written.fulfill()
        }
        self.wait(for: [written], timeout: 5.0)
        MTSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.globalFilePath)?["test.counter"] as? Int, 149)
    }

    func testFlushWritesWithoutWaitingForTheDelay() {
        MTTestSettings.counter.set(5)
        MTSettingsStore.shared.flush()
        MTSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.globalFilePath)?["test.counter"] as? Int, 5)
    }

    func testAppGroupScopeGoesToSharedFile() {
        MTTestSettings.shared.set(true)
        MTSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.sharedFilePath)?["test.sharedFlag"] as? Bool, true)
        XCTAssertNil(self.directory.storedValues(self.directory.globalFilePath)?["test.sharedFlag"])
    }

    func testExtensionReadsOnlyTheSharedFile() {
        MTTestSettings.shared.set(true)
        MTTestSettings.title.set("app only")
        self.reload(process: .notificationService)
        XCTAssertTrue(MTTestSettings.shared.value)
        XCTAssertEqual(MTTestSettings.title.value, "")
    }

    /// iOS keeps the notification service's process between pushes while the app changes the files:
    /// the extension reads them again on the next push (shared.json and the push account's file).
    func testExtensionReadsChangedFilesAgain() {
        let account = MTAccountID(rawValue: 303)
        let basePath = self.directory.makeDirectory("telegram-data", "account-303")
        let accountFile = MTSettingsStore.accountFilePath(basePath: basePath)
        MTSettingsStore.shared.registerAccount(account, basePath: basePath)
        MTTestSettings.shared.set(true)
        MTTestSettings.accountToggle.set(true, for: account)
        self.reload(process: .notificationService)
        MTSettingsStore.shared.registerAccount(account, basePath: basePath)
        XCTAssertTrue(MTTestSettings.shared.value)
        XCTAssertTrue(MTTestSettings.accountToggle.value(for: account))

        let recorder = MTSignalRecorder(MTTestSettings.shared.signal)
        self.directory.writeFile(self.directory.sharedFilePath, "{\"version\":1,\"values\":{}}")
        self.directory.writeFile(accountFile, "{\"version\":1,\"values\":{}}")
        MTSettingsStore.shared.reloadFromDisk()
        XCTAssertFalse(MTTestSettings.shared.value)
        XCTAssertFalse(MTTestSettings.accountToggle.value(for: account))
        XCTAssertEqual(recorder.values, [true, false])
        recorder.dispose()

        // The next push registers the account again: its file is read again too.
        self.directory.writeFile(accountFile, "{\"version\":1,\"values\":{\"test.accountToggle\":true}}")
        MTSettingsStore.shared.registerAccount(account, basePath: basePath)
        XCTAssertTrue(MTTestSettings.accountToggle.value(for: account))
        // Extensions still never write.
        XCTAssertEqual(self.directory.storedValues(accountFile)?["test.accountToggle"] as? Bool, true)
    }

    /// In the app memory is the truth (it may hold changes not written yet): no reload.
    func testAppDoesNotReloadFromDisk() {
        MTTestSettings.shared.set(true)
        self.directory.writeFile(self.directory.sharedFilePath, "{\"version\":1,\"values\":{}}")
        MTSettingsStore.shared.reloadFromDisk()
        XCTAssertTrue(MTTestSettings.shared.value)
    }

    func testDamagedFileIsMovedAsideAndDefaultsAreUsed() {
        self.directory.writeFile(self.directory.globalFilePath, "{not json")
        self.reload()
        XCTAssertEqual(MTTestSettings.counter.value, 7)
        XCTAssertTrue(FileManager.default.fileExists(atPath: self.directory.globalFilePath + ".damaged"))

        MTTestSettings.counter.set(8)
        MTSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.globalFilePath)?["test.counter"] as? Int, 8)
    }

    func testNewerFileFormatIsNeverOverwritten() {
        let text = "{\"version\":2,\"values\":{\"test.counter\":21}}"
        self.directory.writeFile(self.directory.globalFilePath, text)
        self.reload()
        XCTAssertEqual(MTTestSettings.counter.value, 21)
        MTTestSettings.counter.set(22)
        MTSettingsStore.shared.flushSynchronously()
        let data = FileManager.default.contents(atPath: self.directory.globalFilePath)
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, text)
    }

    func testStoredValueOfAnotherTypeReadsTheDefault() {
        self.directory.writeFile(self.directory.globalFilePath, "{\"version\":1,\"values\":{\"test.counter\":\"seven\"}}")
        self.reload()
        XCTAssertEqual(MTTestSettings.counter.value, 7)
    }

    // MARK: - Accounts

    func testAccountValuesAreSeparateAndLiveInTheAccountDirectory() {
        let first = MTAccountID(rawValue: 101)
        let second = MTAccountID(rawValue: -202)
        let firstPath = self.directory.makeDirectory("telegram-data", "account-101")
        let secondPath = self.directory.makeDirectory("telegram-data", "account-202")
        MTSettingsStore.shared.registerAccount(first, basePath: firstPath)
        MTSettingsStore.shared.registerAccount(second, basePath: secondPath)
        XCTAssertEqual(MTSettingsStore.shared.registeredAccounts, [second, first])

        MTTestSettings.exceptions.set(["0:1"], for: first)
        XCTAssertEqual(MTTestSettings.exceptions.value(for: first), ["0:1"])
        XCTAssertEqual(MTTestSettings.exceptions.value(for: second), [])
        XCTAssertTrue(MTTestSettings.exceptions.isDefault(for: second))

        MTSettingsStore.shared.flushSynchronously()
        let firstFile = MTSettingsStore.accountFilePath(basePath: firstPath)
        XCTAssertEqual(self.directory.storedValues(firstFile)?["test.exceptions"] as? [String], ["0:1"])
        XCTAssertNil(self.directory.storedValues(MTSettingsStore.accountFilePath(basePath: secondPath)))
        XCTAssertNil(self.directory.storedValues(self.directory.globalFilePath)?["test.exceptions"])

        MTSettingsStore.shared.unregisterAccount(first)
        XCTAssertEqual(MTTestSettings.exceptions.value(for: first), [])
        MTSettingsStore.shared.registerAccount(first, basePath: firstPath)
        XCTAssertEqual(MTTestSettings.exceptions.value(for: first), ["0:1"])
    }

    func testAccountSignalIsPerAccount() {
        let first = MTAccountID(rawValue: 1)
        let second = MTAccountID(rawValue: 2)
        MTSettingsStore.shared.registerAccount(first, basePath: self.directory.makeDirectory("a1"))
        MTSettingsStore.shared.registerAccount(second, basePath: self.directory.makeDirectory("a2"))
        let recorder = MTSignalRecorder(MTTestSettings.accountToggle.signal(for: first))
        MTTestSettings.accountToggle.set(true, for: second)
        MTTestSettings.accountToggle.set(true, for: first)
        MTTestSettings.accountToggle.set(false, for: first)
        XCTAssertEqual(recorder.values, [false, true, false])
        recorder.dispose()
    }

    func testWriteForUnregisteredAccountIsIgnored() {
        let account = MTAccountID(rawValue: 77)
        MTTestSettings.accountToggle.set(true, for: account)
        XCTAssertFalse(MTTestSettings.accountToggle.value(for: account))
    }

    func testRemovedAccountDirectoryIsNotRecreated() {
        let account = MTAccountID(rawValue: 5)
        let basePath = self.directory.makeDirectory("telegram-data", "account-5")
        MTSettingsStore.shared.registerAccount(account, basePath: basePath)
        MTTestSettings.accountToggle.set(true, for: account)
        try? FileManager.default.removeItem(atPath: basePath)
        MTSettingsStore.shared.unregisterAccount(account)
        MTSettingsStore.shared.flushSynchronously()
        XCTAssertFalse(FileManager.default.fileExists(atPath: basePath))
    }

    // MARK: - Export / import / reset

    func testExportSkipsSecretsAndImportRestores() {
        let account = MTAccountID(rawValue: 9)
        MTSettingsStore.shared.registerAccount(account, basePath: self.directory.makeDirectory("acc9"))
        MTTestSettings.counter.set(33)
        MTTestSettings.title.set("exported")
        MTTestSettings.secret.set("hash")
        MTTestSettings.exceptions.set(["2:5"], for: account)
        MTTestSettings.accountSecret.set("token", for: account)

        let data = MTSettingsStore.shared.exportData(accounts: [account])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("test.secret"))
        XCTAssertFalse(text.contains("test.accountSecret"))
        XCTAssertTrue(text.contains("test.counter"))

        MTSettingsStore.shared.resetAll(accounts: [account])
        XCTAssertEqual(MTTestSettings.counter.value, 7)
        XCTAssertEqual(MTTestSettings.exceptions.value(for: account), [])
        // Secrets survive "reset all".
        XCTAssertEqual(MTTestSettings.secret.value, "hash")
        XCTAssertEqual(MTTestSettings.accountSecret.value(for: account), "token")

        let diff: MTSettingsImportDiff
        do {
            diff = try MTSettingsStore.shared.importPreview(data)
        } catch {
            XCTFail("import preview failed: \(error)")
            return
        }
        let counterChange = diff.changes.first(where: { $0.key == "test.counter" })
        XCTAssertEqual(counterChange?.oldValue, "7")
        XCTAssertEqual(counterChange?.newValue, "33")
        XCTAssertEqual(counterChange?.scope, .global)
        let accountChange = diff.changes.first(where: { $0.key == "test.exceptions" })
        XCTAssertEqual(accountChange?.account, account)
        XCTAssertEqual(accountChange?.scope, .account)
        XCTAssertNil(diff.changes.first(where: { $0.key == "test.toggle" }), "unchanged values are not in the diff")

        MTSettingsStore.shared.applyImport(diff)
        XCTAssertEqual(MTTestSettings.counter.value, 33)
        XCTAssertEqual(MTTestSettings.title.value, "exported")
        XCTAssertEqual(MTTestSettings.exceptions.value(for: account), ["2:5"])
    }

    func testImportBumpsRevisionOnce() {
        MTTestSettings.counter.set(1)
        MTTestSettings.title.set("a")
        let data = MTSettingsStore.shared.exportData(accounts: [])
        MTSettingsStore.shared.resetAll(accounts: [])
        let diff = try? MTSettingsStore.shared.importPreview(data)
        XCTAssertEqual(diff?.changes.count, 2)
        let recorder = MTSignalRecorder(MTSettingsStore.shared.revision)
        if let diff = diff {
            MTSettingsStore.shared.applyImport(diff)
        }
        XCTAssertEqual(recorder.values.count, 2)
        recorder.dispose()
    }

    func testImportRejectsForeignAndNewerFiles() {
        XCTAssertThrowsError(try MTSettingsStore.shared.importPreview(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? MTSettingsImportError, .invalidFormat)
        }
        XCTAssertThrowsError(try MTSettingsStore.shared.importPreview(Data("{\"format\":\"other\",\"version\":1}".utf8))) { error in
            XCTAssertEqual(error as? MTSettingsImportError, .invalidFormat)
        }
        XCTAssertThrowsError(try MTSettingsStore.shared.importPreview(Data("{\"format\":\"mediatok.settings\",\"version\":2}".utf8))) { error in
            XCTAssertEqual(error as? MTSettingsImportError, .unsupportedVersion(2))
        }
    }

    func testImportSortsOutUnknownSecretAndMistypedKeys() {
        let text = """
        {"format":"mediatok.settings","version":1,
         "global":{"test.counter":"many","test.secret":"stolen","nobody.knows":1,"test.toggle":true},
         "appGroup":{},"accounts":{}}
        """
        guard let diff = try? MTSettingsStore.shared.importPreview(Data(text.utf8)) else {
            XCTFail("import preview failed")
            return
        }
        XCTAssertEqual(diff.unknownKeys, ["nobody.knows"])
        XCTAssertEqual(diff.skippedKeys, ["test.counter", "test.secret"])
        XCTAssertEqual(diff.changes.map { $0.key }, ["test.toggle"])
        MTSettingsStore.shared.applyImport(diff)
        XCTAssertEqual(MTTestSettings.secret.value, "")
        XCTAssertTrue(MTTestSettings.toggle.value)
    }

    func testImportMapsTheOnlyAccountSection() {
        let here = MTAccountID(rawValue: 1000)
        MTSettingsStore.shared.registerAccount(here, basePath: self.directory.makeDirectory("acc1000"))
        let text = """
        {"format":"mediatok.settings","version":1,"global":{},"appGroup":{},
         "accounts":{"555":{"test.accountToggle":true}}}
        """
        guard let diff = try? MTSettingsStore.shared.importPreview(Data(text.utf8)) else {
            XCTFail("import preview failed")
            return
        }
        XCTAssertEqual(diff.unmatchedAccounts, [])
        XCTAssertEqual(diff.changes.first?.account, here)

        let other = MTAccountID(rawValue: 2000)
        MTSettingsStore.shared.registerAccount(other, basePath: self.directory.makeDirectory("acc2000"))
        guard let ambiguous = try? MTSettingsStore.shared.importPreview(Data(text.utf8)) else {
            XCTFail("import preview failed")
            return
        }
        XCTAssertEqual(ambiguous.unmatchedAccounts, [MTAccountID(rawValue: 555)])
        guard let mapped = try? MTSettingsStore.shared.importPreview(Data(text.utf8), accountMapping: [MTAccountID(rawValue: 555): other]) else {
            XCTFail("import preview failed")
            return
        }
        XCTAssertEqual(mapped.changes.first?.account, other)
    }

    // MARK: - Registry

    func testRegistryKnowsDeclaredSettings() {
        let _ = MTLocalization.languageOverride
        let keys = MTSettingsStore.shared.registeredKeys
        XCTAssertTrue(keys.contains("test.toggle"))
        XCTAssertTrue(keys.contains("test.exceptions"))
        XCTAssertTrue(keys.contains("core.language"))
        XCTAssertTrue(MTTestSettings.restart.flags.contains(.requiresRestart))
        XCTAssertEqual(MTTestSettings.shared.scope, .appGroup)
    }

    #if DEBUG
    func testUnreadSettingsAreReported() {
        let _ = MTTestSettings.toggle.value
        let unread = MTSettingsStore.shared.debugUnreadKeys()
        XCTAssertFalse(unread.contains("test.toggle"))
        XCTAssertTrue(unread.contains("test.restart"), "declared, shown in a menu, never read: a dead toggle")
    }
    #endif

    func testKeyValidation() {
        XCTAssertTrue(MTSettingsStore.isValidKey("ghostMode.hideReadReceipts"))
        XCTAssertTrue(MTSettingsStore.isValidKey("a.b.c2"))
        XCTAssertFalse(MTSettingsStore.isValidKey("ghostMode"))
        XCTAssertFalse(MTSettingsStore.isValidKey("GhostMode.x"))
        XCTAssertFalse(MTSettingsStore.isValidKey("ghost-mode.x"))
        XCTAssertFalse(MTSettingsStore.isValidKey("ghostMode..x"))
        XCTAssertFalse(MTSettingsStore.isValidKey("ghostMode.x "))
    }

    func testReadIsCheap() {
        MTTestSettings.toggle.set(true)
        let iterations = 1_000_000
        var count = 0
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0 ..< iterations {
            if MTTestSettings.toggle.value {
                count += 1
            }
        }
        let perRead = (CFAbsoluteTimeGetCurrent() - start) / Double(iterations)
        XCTAssertEqual(count, iterations)
        // Generous bound for unoptimized test builds; the target in release is tens of nanoseconds.
        XCTAssertLessThan(perRead, 2.0e-6)
    }
}
