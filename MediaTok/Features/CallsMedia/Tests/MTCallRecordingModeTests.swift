import Foundation
import XCTest

// Host tests of «Записывать звонки» as one choice (2026-10-27), compiled together with
// Sources/Settings/MTCallRecordingMode.swift only.
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/CallsMedia:MTCallRecordingModeTests

final class MTCallRecordingModeTests: XCTestCase {
    func testMergeOfTheTwoOldSwitches() {
        // Nothing stored: keep the default.
        XCTAssertNil(MTCallRecordingMode.merged(audio: nil, video: nil))
        // Video on wins, also without audio (a video-only setting is not a choice any more).
        XCTAssertEqual(MTCallRecordingMode.merged(audio: true, video: true), .audioAndVideo)
        XCTAssertEqual(MTCallRecordingMode.merged(audio: false, video: true), .audioAndVideo)
        XCTAssertEqual(MTCallRecordingMode.merged(audio: nil, video: true), .audioAndVideo)
        // Audio only.
        XCTAssertEqual(MTCallRecordingMode.merged(audio: true, video: false), .audio)
        XCTAssertEqual(MTCallRecordingMode.merged(audio: true, video: nil), .audio)
        // Both stored off, or one stored off and the other never written.
        XCTAssertEqual(MTCallRecordingMode.merged(audio: false, video: false), .off)
        XCTAssertEqual(MTCallRecordingMode.merged(audio: false, video: nil), .off)
        XCTAssertEqual(MTCallRecordingMode.merged(audio: nil, video: false), .off)
    }

    func testWhatEachChoiceRecords() {
        XCTAssertFalse(MTCallRecordingMode.off.isOn)
        XCTAssertFalse(MTCallRecordingMode.off.recordsVideo)
        XCTAssertTrue(MTCallRecordingMode.audio.isOn)
        XCTAssertFalse(MTCallRecordingMode.audio.recordsVideo)
        XCTAssertTrue(MTCallRecordingMode.audioAndVideo.isOn)
        XCTAssertTrue(MTCallRecordingMode.audioAndVideo.recordsVideo)
    }

    func testStoredValues() {
        // The raw values are what `calls.record` stores: they must not change.
        XCTAssertEqual(MTCallRecordingMode.allCases.map(\.rawValue), ["off", "audio", "audioAndVideo"])
        for mode in MTCallRecordingMode.allCases {
            XCTAssertEqual(MTCallRecordingMode.resolved(mode.rawValue), mode)
        }
        XCTAssertEqual(MTCallRecordingMode.resolved(""), .off)
        XCTAssertEqual(MTCallRecordingMode.resolved("video"), .off)
    }
}
