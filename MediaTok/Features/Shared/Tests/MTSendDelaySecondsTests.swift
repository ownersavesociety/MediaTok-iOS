import Foundation
import XCTest

// Host tests of the one send delay (since 2026-10-27), compiled together with
// Sources/GhostMode/MTSendDelaySeconds.swift (target MTFeaturesSharedTests).
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/Shared:MTFeaturesSharedTests

final class MTSendDelaySecondsTests: XCTestCase {
    func testDefaultIsTheLargerOldDefault() {
        XCTAssertEqual(MTSendDelaySeconds.defaultValue, 20.0)
        XCTAssertTrue(MTSendDelaySeconds.range.contains(MTSendDelaySeconds.defaultValue))
    }

    func testMergeTakesTheLargerOfTheTwo() {
        // Nothing stored: the default already is max(12, 20).
        XCTAssertNil(MTSendDelaySeconds.merged(text: nil, media: nil))
        XCTAssertEqual(MTSendDelaySeconds.merged(text: 30.0, media: nil), 30.0)
        XCTAssertEqual(MTSendDelaySeconds.merged(text: 15.0, media: nil), 20.0)
        XCTAssertEqual(MTSendDelaySeconds.merged(text: nil, media: 90.0), 90.0)
        XCTAssertEqual(MTSendDelaySeconds.merged(text: 45.0, media: 25.0), 45.0)
        XCTAssertEqual(MTSendDelaySeconds.merged(text: 12.0, media: 180.0), 180.0)
    }

    func testValuesStayInTheRange() {
        XCTAssertEqual(MTSendDelaySeconds.merged(text: 500.0, media: nil), 180.0)
        XCTAssertEqual(MTSendDelaySeconds.clamped(3.0), 12.0)
        XCTAssertEqual(MTSendDelaySeconds.clamped(.nan), MTSendDelaySeconds.defaultValue)
        XCTAssertEqual(MTSendDelaySeconds.clamped(61.0), 61.0)
    }
}
