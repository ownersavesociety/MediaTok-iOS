import Foundation
import XCTest

// Host tests of «Скругление углов» (one setting since 2026-10-27), compiled together with
// Sources/Settings/MTAvatarCorners.swift only.
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/Interface:MTAvatarCornersTests

final class MTAvatarCornersTests: XCTestCase {
    func testShape() {
        XCTAssertFalse(MTAvatarCorners.isSquare(MTAvatarCorners.round))
        XCTAssertEqual(MTAvatarCorners.squareness("0"), 0.0)
        XCTAssertEqual(MTAvatarCorners.squareness("50"), 0.5)
        XCTAssertEqual(MTAvatarCorners.squareness("100"), 1.0)
        XCTAssertTrue(MTAvatarCorners.isSquare("25"))
        // Garbage and out-of-range values never break the shape.
        XCTAssertEqual(MTAvatarCorners.squareness("square"), 0.0)
        XCTAssertEqual(MTAvatarCorners.squareness("250"), 1.0)
        XCTAssertEqual(MTAvatarCorners.squareness("-5"), 0.0)
    }

    func testOptionsStartWithTheCircleAndEndWithTheSquare() {
        XCTAssertEqual(MTAvatarCorners.options.first, MTAvatarCorners.round)
        XCTAssertEqual(MTAvatarCorners.options.last, "100")
    }

    func testMergeOfBuild185() {
        // Off or never touched: the circle (the default), nothing to write.
        XCTAssertNil(MTAvatarCorners.merged(square: nil, squareness: nil))
        XCTAssertNil(MTAvatarCorners.merged(square: false, squareness: "50"))
        XCTAssertNil(MTAvatarCorners.merged(square: nil, squareness: "25"))
        // On: the level, absent = the old default 100.
        XCTAssertEqual(MTAvatarCorners.merged(square: true, squareness: nil), "100")
        XCTAssertEqual(MTAvatarCorners.merged(square: true, squareness: "50"), "50")
        XCTAssertEqual(MTAvatarCorners.merged(square: true, squareness: "75"), "75")
        // An odd stored value goes to the nearest level, never to the circle.
        XCTAssertEqual(MTAvatarCorners.merged(square: true, squareness: "0"), "25")
        XCTAssertEqual(MTAvatarCorners.merged(square: true, squareness: "x"), "100")
    }

    func testOldMediaTok() {
        XCTAssertNil(MTAvatarCorners.fromLegacy(square: nil, level: 50))
        XCTAssertNil(MTAvatarCorners.fromLegacy(square: false, level: 100))
        XCTAssertEqual(MTAvatarCorners.fromLegacy(square: true, level: nil), "100")
        XCTAssertEqual(MTAvatarCorners.fromLegacy(square: true, level: 40), "50")
        XCTAssertEqual(MTAvatarCorners.fromLegacy(square: true, level: 10), "25")
        XCTAssertEqual(MTAvatarCorners.fromLegacy(square: true, level: 90), "100")
    }
}
