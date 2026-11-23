import Foundation
import XCTest

// Host tests of «Без перехода к следующему каналу и теме» as one switch (2026-10-27), compiled together
// with Sources/Messages/MTScrollToNextMerge.swift (target MTFeaturesSharedTests).
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/Shared:MTFeaturesSharedTests

final class MTScrollToNextMergeTests: XCTestCase {
    func testEitherOldSwitchTurnsTheOneOn() {
        XCTAssertNil(MTScrollToNextMerge.merged(channel: nil, topic: nil))
        XCTAssertEqual(MTScrollToNextMerge.merged(channel: true, topic: nil), true)
        XCTAssertEqual(MTScrollToNextMerge.merged(channel: nil, topic: true), true)
        XCTAssertEqual(MTScrollToNextMerge.merged(channel: true, topic: false), true)
        XCTAssertEqual(MTScrollToNextMerge.merged(channel: false, topic: true), true)
        XCTAssertEqual(MTScrollToNextMerge.merged(channel: true, topic: true), true)
    }

    func testBothStoredOffStaysOff() {
        XCTAssertEqual(MTScrollToNextMerge.merged(channel: false, topic: false), false)
        XCTAssertEqual(MTScrollToNextMerge.merged(channel: false, topic: nil), false)
        XCTAssertEqual(MTScrollToNextMerge.merged(channel: nil, topic: false), false)
    }
}
