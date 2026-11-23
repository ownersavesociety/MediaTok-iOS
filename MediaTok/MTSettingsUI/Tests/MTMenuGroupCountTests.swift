import Foundation
import XCTest

// Host tests of the summary on an expandable row without a master switch (2026-10-27), compiled
// together with Sources/Model/MTMenuGroupCount.swift only.
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/MTSettingsUI:MTSettingsUIModelTests

final class MTMenuGroupCountTests: XCTestCase {
    private func hidden(_ count: MTMenuGroupCount) -> String {
        return "скрыто: \(count.selected) из \(count.total)"
    }

    func testCountsTheVisibleChildren() {
        XCTAssertEqual(MTMenuGroupCount(values: [true, false, true, false]), MTMenuGroupCount(selected: 2, total: 4))
        XCTAssertEqual(MTMenuGroupCount(values: [false, false, false, false]), MTMenuGroupCount(selected: 0, total: 4))
        XCTAssertEqual(MTMenuGroupCount(values: [true, true, true, true]), MTMenuGroupCount(selected: 4, total: 4))
        XCTAssertEqual(MTMenuGroupCount(values: []), MTMenuGroupCount(selected: 0, total: 0))
    }

    func testNothingOnShowsNothing() {
        var calls = 0
        let summary = MTMenuGroupCount(values: [false, false, false, false]).summary { count in
            calls += 1
            return self.hidden(count)
        }
        XCTAssertNil(summary)
        // The feature's text is not even built.
        XCTAssertEqual(calls, 0)
        XCTAssertNil(MTMenuGroupCount(values: []).summary(self.hidden))
    }

    func testSummaryOfWhatIsOn() {
        XCTAssertEqual(MTMenuGroupCount(values: [true, false, true, false]).summary(self.hidden), "скрыто: 2 из 4")
        XCTAssertEqual(MTMenuGroupCount(values: [false, false, false, true]).summary(self.hidden), "скрыто: 1 из 4")
        XCTAssertEqual(MTMenuGroupCount(values: [true, true, true, true]).summary(self.hidden), "скрыто: 4 из 4")
    }
}
