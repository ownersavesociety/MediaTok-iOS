import Foundation
import XCTest

// Host tests of the choices that replaced switch pairs and the nine screen-edge rows (2026-10-27),
// compiled together with Settings/Sources/MTAppearanceChoices.swift only.
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/Appearance:MTAppearanceChoicesTests

final class MTAppearanceChoicesTests: XCTestCase {
    // MARK: Hidden reactions and formatting

    func testHiddenReactionsFromTwoSwitches() {
        XCTAssertNil(MTHiddenReactions.merged(inChats: nil, inChannels: nil))
        XCTAssertNil(MTHiddenReactions.merged(inChats: false, inChannels: false))
        XCTAssertEqual(MTHiddenReactions.merged(inChats: true, inChannels: nil), .chats)
        XCTAssertEqual(MTHiddenReactions.merged(inChats: false, inChannels: true), .channels)
        XCTAssertEqual(MTHiddenReactions.merged(inChats: true, inChannels: true), .all)
    }

    func testHiddenReactionsPlaces() {
        for value in MTHiddenReactions.allCases {
            XCTAssertEqual(MTHiddenReactions(inChats: value.inChats, inChannels: value.inChannels), value)
        }
        XCTAssertFalse(MTHiddenReactions.off.inChats || MTHiddenReactions.off.inChannels)
        XCTAssertTrue(MTHiddenReactions.chats.inChats && !MTHiddenReactions.chats.inChannels)
        XCTAssertTrue(!MTHiddenReactions.channels.inChats && MTHiddenReactions.channels.inChannels)
        XCTAssertTrue(MTHiddenReactions.all.inChats && MTHiddenReactions.all.inChannels)
    }

    func testHiddenFormattingFromTwoSwitches() {
        XCTAssertNil(MTHiddenFormatting.merged(inIncoming: nil, inOutgoing: false))
        XCTAssertEqual(MTHiddenFormatting.merged(inIncoming: true, inOutgoing: nil), .incoming)
        XCTAssertEqual(MTHiddenFormatting.merged(inIncoming: nil, inOutgoing: true), .outgoing)
        XCTAssertEqual(MTHiddenFormatting.merged(inIncoming: true, inOutgoing: true), .all)
        for value in MTHiddenFormatting.allCases {
            XCTAssertEqual(MTHiddenFormatting(inIncoming: value.inIncoming, inOutgoing: value.inOutgoing), value)
        }
    }

    func testRawValuesAreStable() {
        // Stored in the settings file: never rename.
        XCTAssertEqual(MTHiddenReactions.allCases.map { $0.rawValue }, ["off", "chats", "channels", "all"])
        XCTAssertEqual(MTHiddenFormatting.allCases.map { $0.rawValue }, ["off", "incoming", "outgoing", "all"])
        XCTAssertEqual(MTEdgeStyle.allCases.map { $0.rawValue }, ["off", "blur", "gradient"])
    }

    // MARK: Screen edges

    func testNothingStoredWritesNothing() {
        XCTAssertNil(MTEdgeMerge.merged(MTEdgeMerge.Old()))
        XCTAssertNil(MTEdgeMerge.merged(MTEdgeMerge.Old(blur: false, blurColor: "", gradient: false)))
    }

    func testBlurKeepsItsValues() {
        let merge = MTEdgeMerge.merged(MTEdgeMerge.Old(blur: true, blurColor: "112233", blurSize: 120.0, blurIntensity: 60.0, gradientColor: "445566", gradientSize: 30.0))
        XCTAssertEqual(merge, MTEdgeMerge(style: .blur, color: "112233", size: 120.0, intensity: 60.0))
    }

    func testBlurWithDefaultsKeepsTheOldBlurHeight() {
        XCTAssertEqual(MTEdgeMerge.merged(MTEdgeMerge.Old(blur: true)), MTEdgeMerge(style: .blur, size: 80.0))
    }

    func testGradientKeepsItsOldDefaultHeight() {
        // The gradient was 40 pt by default; the group's default is 80, so 40 is written.
        let merge = MTEdgeMerge.merged(MTEdgeMerge.Old(blurSize: 100.0, gradient: true, gradientHideInChatList: true))
        XCTAssertEqual(merge, MTEdgeMerge(style: .gradient, size: 40.0, hideInChatList: true))
    }

    func testBothOnPicksTheBlur() {
        let merge = MTEdgeMerge.merged(MTEdgeMerge.Old(blur: true, blurIntensity: 70.0, gradient: true, gradientColor: "AABBCC", gradientSize: 20.0, gradientIntensity: 30.0))
        XCTAssertEqual(merge?.style, .blur)
        XCTAssertNil(merge?.color)
        XCTAssertEqual(merge?.size, 80.0)
        XCTAssertEqual(merge?.intensity, 70.0)
    }

    func testBothOffKeepsTunedValuesBlurFirst() {
        let merge = MTEdgeMerge.merged(MTEdgeMerge.Old(blur: false, blurSize: 64.0, gradient: false, gradientColor: "AABBCC", gradientSize: 20.0, gradientIntensity: 30.0))
        XCTAssertEqual(merge, MTEdgeMerge(style: .off, color: "AABBCC", size: 64.0, intensity: 30.0))
    }

    func testValuesAreClamped() {
        let merge = MTEdgeMerge.merged(MTEdgeMerge.Old(blur: true, blurSize: 500.0, blurIntensity: -5.0))
        XCTAssertEqual(merge?.size, MTEdgeStyle.sizeRange.upperBound)
        XCTAssertEqual(merge?.intensity, 0.0)
        XCTAssertEqual(MTEdgeMerge.merged(MTEdgeMerge.Old(gradient: true, gradientSize: 1.0))?.size, MTEdgeStyle.sizeRange.lowerBound)
    }
}
