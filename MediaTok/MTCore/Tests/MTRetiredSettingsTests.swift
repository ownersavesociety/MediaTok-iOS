import Foundation
import XCTest

/// Values of keys no setting declares any more (removed features, merged rows): read once by a
/// migration, then dropped from the files.
final class MTRetiredSettingsTests: XCTestCase {
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

    func testRetiredValuesAreReadFromGlobalThenSharedFile() {
        self.directory.writeFile(self.directory.globalFilePath, "{\"version\":1,\"values\":{\"old.flag\":true,\"old.size\":40.5,\"old.both\":\"global\",\"test.counter\":3}}")
        self.directory.writeFile(self.directory.sharedFilePath, "{\"version\":1,\"values\":{\"old.shared\":\"x\",\"old.both\":\"shared\"}}")
        self.reload()

        XCTAssertEqual(MTRetiredSettings.value("old.flag", as: Bool.self), true)
        XCTAssertEqual(MTRetiredSettings.value("old.size", as: Double.self), 40.5)
        XCTAssertEqual(MTRetiredSettings.value("old.shared", as: String.self), "x")
        XCTAssertEqual(MTRetiredSettings.value("old.both", as: String.self), "global")
        // Absent: the old default, which the caller knows.
        XCTAssertNil(MTRetiredSettings.value("old.missing", as: Bool.self))
        // Another type than stored.
        XCTAssertNil(MTRetiredSettings.value("old.flag", as: String.self))
        // A declared key is not retired: its value is the setting's.
        XCTAssertNil(MTRetiredSettings.value("test.counter", as: Int.self))
        XCTAssertEqual(MTTestSettings.counter.value, 3)
    }

    func testRemoveDropsOnlyRetiredKeysAndRewritesTheFile() {
        self.directory.writeFile(self.directory.globalFilePath, "{\"version\":1,\"values\":{\"feed.videos\":false,\"feed.peers.extra\":[1],\"other.drop\":1,\"other.keep\":2,\"test.counter\":3}}")
        self.directory.writeFile(self.directory.sharedFilePath, "{\"version\":1,\"values\":{\"feed.shared\":true,\"test.sharedFlag\":true}}")
        self.reload()

        // A prefix never reaches a declared key.
        MTRetiredSettings.remove(keys: ["other.drop"], prefixes: ["feed.", "test."])
        XCTAssertNil(MTRetiredSettings.value("feed.videos", as: Bool.self))
        XCTAssertNil(MTRetiredSettings.value("other.drop", as: Int.self))
        XCTAssertEqual(MTRetiredSettings.value("other.keep", as: Int.self), 2)

        MTSettingsStore.shared.flushSynchronously()
        let global = self.directory.storedValues(self.directory.globalFilePath)
        XCTAssertNil(global?["feed.videos"])
        XCTAssertNil(global?["feed.peers.extra"])
        XCTAssertNil(global?["other.drop"])
        XCTAssertEqual(global?["other.keep"] as? Int, 2)
        XCTAssertEqual(global?["test.counter"] as? Int, 3)
        let shared = self.directory.storedValues(self.directory.sharedFilePath)
        XCTAssertNil(shared?["feed.shared"])
        XCTAssertEqual(shared?["test.sharedFlag"] as? Bool, true)

        self.reload()
        XCTAssertEqual(MTTestSettings.counter.value, 3)
        XCTAssertTrue(MTTestSettings.shared.value)
    }

    func testAccountKeysAndFiles() {
        let account = MTAccountID(rawValue: 77)
        let basePath = self.directory.makeDirectory("telegram-data", "account-77")
        let settingsPath = MTSettingsStore.accountFilePath(basePath: basePath)
        self.directory.writeFile(settingsPath, "{\"version\":1,\"values\":{\"feed.peers\":[\"0:1\"],\"old.seconds\":30,\"test.accountToggle\":true}}")
        let historyPath = self.directory.subpath("telegram-data", "account-77", "mediatok", "feed-history.json")
        self.directory.writeFile(historyPath, "[]")
        let outsidePath = self.directory.subpath("telegram-data", "account-77", "keep.json")
        self.directory.writeFile(outsidePath, "{}")
        MTSettingsStore.shared.registerAccount(account, basePath: basePath)

        XCTAssertEqual(MTRetiredSettings.value("old.seconds", as: Double.self, account: account), 30.0)
        XCTAssertNil(MTRetiredSettings.value("old.seconds", as: Double.self))
        XCTAssertEqual(MTRetiredSettings.value("feed.peers", as: [String].self, account: account), ["0:1"])

        MTRetiredSettings.remove(keys: ["old.seconds"], prefixes: ["feed."], account: account)
        MTSettingsStore.shared.flushSynchronously()
        let stored = self.directory.storedValues(settingsPath)
        XCTAssertNil(stored?["feed.peers"])
        XCTAssertNil(stored?["old.seconds"])
        XCTAssertEqual(stored?["test.accountToggle"] as? Bool, true)

        // Plain names only: «../keep.json» does not leave the account's mediatok directory.
        MTRetiredSettings.removeAccountFiles(["feed-history.json", "../keep.json", ""], account: account)
        let removed = self.expectation(description: "history file removed")
        func poll(_ attempt: Int) {
            if !FileManager.default.fileExists(atPath: historyPath) || attempt > 50 {
                removed.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                poll(attempt + 1)
            }
        }
        poll(0)
        self.wait(for: [removed], timeout: 5.0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsidePath))
    }

    func testExtensionsDropNothing() {
        self.directory.writeFile(self.directory.sharedFilePath, "{\"version\":1,\"values\":{\"old.shared\":true}}")
        self.reload(process: .notificationService)
        XCTAssertEqual(MTRetiredSettings.value("old.shared", as: Bool.self), true)
        MTRetiredSettings.remove(keys: ["old.shared"])
        XCTAssertEqual(MTRetiredSettings.value("old.shared", as: Bool.self), true)
        MTSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.sharedFilePath)?["old.shared"] as? Bool, true)
    }
}
