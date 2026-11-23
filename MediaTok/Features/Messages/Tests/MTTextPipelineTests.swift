import Foundation
import XCTest

// Host tests of the outgoing text pipeline core (compiled together with Sources/Pipeline/Core).
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/Messages:MTMessagesTests

final class MTTextPipelineTests: XCTestCase {
    private let plain = MTTextPipelineContext(isBot: false, isSavedMessages: false, isVerbatim: false)

    private func entity(_ range: Range<Int>, protected: Bool = false, overlay: Bool = false, tag: Int = 0) -> MTPipelineEntity {
        return MTPipelineEntity(range: range, isProtected: protected, excludesOverlay: overlay, tag: tag)
    }

    private func utf16Range(of needle: String, in text: String) -> Range<Int> {
        let range = (text as NSString).range(of: needle)
        return range.location ..< (range.location + range.length)
    }

    // MARK: Order

    func testOrderIsFixed() {
        XCTAssertEqual(MTTextPipeline.order, [.wordReplacement, .antiCaps, .hyperlink])
        let configuration = MTTextPipelineConfiguration(replacementRules: [MTTextReplacementRule(source: "a", replacement: "b")], antiCaps: true, hyperlink: true)
        XCTAssertEqual(MTTextPipeline.enabledStages(configuration: configuration, context: self.plain, text: "text"), MTTextPipeline.order)
    }

    func testOrderIsDeterministic() {
        let configuration = MTTextPipelineConfiguration(replacementRules: [MTTextReplacementRule(source: "ПРИВЕТ", replacement: "ЗДРАВСТВУЙТЕ")], antiCaps: true, hyperlink: false)
        let input = MTPipelineText(text: "ПРИВЕТ ДРУЗЬЯ КАК ДЕЛА", entities: [])
        let first = MTTextPipeline.run(input, configuration: configuration, context: self.plain)
        for _ in 0 ..< 5 {
            XCTAssertEqual(MTTextPipeline.run(input, configuration: configuration, context: self.plain), first)
        }
        // Replacement first (sees the typed caps), then anti-caps.
        XCTAssertEqual(first.text, "Здравствуйте друзья как дела")
    }

    func testBotsAndCopiesAreNeverTransformed() {
        let configuration = MTTextPipelineConfiguration(antiCaps: true, hyperlink: true)
        let input = MTPipelineText(text: "ПРИВЕТ БОТ", entities: [])
        XCTAssertEqual(MTTextPipeline.run(input, configuration: configuration, context: MTTextPipelineContext(isBot: true, isSavedMessages: false, isVerbatim: false)), input)
        XCTAssertEqual(MTTextPipeline.run(input, configuration: configuration, context: MTTextPipelineContext(isBot: false, isSavedMessages: false, isVerbatim: true)), input)
    }

    func testCommandsSkipTheCaseAndOverlayStages() {
        let configuration = MTTextPipelineConfiguration(antiCaps: true, hyperlink: true)
        XCTAssertEqual(MTTextPipeline.enabledStages(configuration: configuration, context: self.plain, text: "/START NOW"), [])
    }

    func testSavedMessagesGetNoMentionOverlay() {
        let configuration = MTTextPipelineConfiguration(antiCaps: true, hyperlink: true)
        let savedMessages = MTTextPipelineContext(isBot: false, isSavedMessages: true, isVerbatim: false)
        XCTAssertEqual(MTTextPipeline.enabledStages(configuration: configuration, context: savedMessages, text: "ПРИВЕТ ВСЕМ"), [.antiCaps])
    }

    // MARK: Entities survive

    func testEntityMovesWithReplacement() {
        let text = "да давай завтра"
        let bold = self.entity(self.utf16Range(of: "завтра", in: text), tag: 1)
        let input = MTPipelineText(text: text, entities: [bold])
        let rules = [MTTextReplacementRule(source: "да", replacement: "нет")]
        let output = MTTextPipeline.run(input, configuration: MTTextPipelineConfiguration(replacementRules: rules), context: self.plain)
        XCTAssertEqual(output.text, "нет давай завтра")
        XCTAssertEqual(output.entities.count, 1)
        XCTAssertEqual(output.substring(output.entities[0].range), "завтра")
        XCTAssertEqual(output.entities[0].tag, 1)
    }

    func testEntityCoveringChangedWordGrowsWithIt() {
        let text = "Привет мир"
        let italic = self.entity(self.utf16Range(of: "Привет", in: text), tag: 2)
        let input = MTPipelineText(text: text, entities: [italic])
        let rules = [MTTextReplacementRule(source: "привет", replacement: "здравствуйте")]
        let output = MTTextPipeline.run(input, configuration: MTTextPipelineConfiguration(replacementRules: rules), context: self.plain)
        XCTAssertEqual(output.text, "Здравствуйте мир")
        XCTAssertEqual(output.substring(output.entities[0].range), "Здравствуйте")
    }

    func testCustomEmojiIsNeverTouched() {
        let text = "ОЧЕНЬ ХОРОШО 😀 ДА"
        let emoji = self.entity(self.utf16Range(of: "😀", in: text), protected: true, tag: 3)
        let input = MTPipelineText(text: text, entities: [emoji])
        let output = MTTextPipeline.run(input, configuration: MTTextPipelineConfiguration(antiCaps: true), context: self.plain)
        XCTAssertEqual(output.entities.count, 1)
        XCTAssertEqual(output.substring(output.entities[0].range), "😀")
    }

    // MARK: Word replacement

    func testWholeWordOnly() {
        let rules = [MTTextReplacementRule(source: "да", replacement: "нет")]
        let output = MTTextPipeline.run(MTPipelineText(text: "давай да", entities: []), configuration: MTTextPipelineConfiguration(replacementRules: rules), context: self.plain)
        XCTAssertEqual(output.text, "давай нет")
    }

    func testRulesDoNotChain() {
        let rules = [MTTextReplacementRule(source: "a", replacement: "b"), MTTextReplacementRule(source: "b", replacement: "c")]
        let output = MTTextPipeline.run(MTPipelineText(text: "a b", entities: []), configuration: MTTextPipelineConfiguration(replacementRules: rules), context: self.plain)
        XCTAssertEqual(output.text, "b c")
    }

    func testReplacementKeepsCase() {
        let rules = [MTTextReplacementRule(source: "привет", replacement: "здравствуй")]
        let output = MTTextPipeline.run(MTPipelineText(text: "Привет и ПРИВЕТ", entities: []), configuration: MTTextPipelineConfiguration(replacementRules: rules), context: self.plain)
        XCTAssertEqual(output.text, "Здравствуй и ЗДРАВСТВУЙ")
    }

    func testReplacementSkipsLinks() {
        let rules = [MTTextReplacementRule(source: "example", replacement: "x")]
        let output = MTTextPipeline.run(MTPipelineText(text: "see example.com example", entities: []), configuration: MTTextPipelineConfiguration(replacementRules: rules), context: self.plain)
        XCTAssertEqual(output.text, "see example.com x")
    }

    // MARK: Anti-caps

    func testAntiCaps() {
        let output = MTTextPipeline.run(MTPipelineText(text: "ПРИВЕТ ВСЕМ. КАК ДЕЛА", entities: []), configuration: MTTextPipelineConfiguration(antiCaps: true), context: self.plain)
        XCTAssertEqual(output.text, "Привет всем. Как дела")
    }

    func testAntiCapsKeepsCodesLinksAndMentions() {
        let text = "СМОТРИ HTTPS://EXAMPLE.COM/ABC @USERNAME КОД"
        let code = self.entity(self.utf16Range(of: "КОД", in: text), protected: true, overlay: true, tag: 4)
        let output = MTTextPipeline.run(MTPipelineText(text: text, entities: [code]), configuration: MTTextPipelineConfiguration(antiCaps: true), context: self.plain)
        XCTAssertTrue(output.text.hasPrefix("Смотри "))
        XCTAssertTrue(output.text.contains("HTTPS://EXAMPLE.COM/ABC"))
        XCTAssertTrue(output.text.contains("@USERNAME"))
        XCTAssertTrue(output.text.hasSuffix("КОД"))
    }

    func testAntiCapsLeavesNormalText() {
        let input = MTPipelineText(text: "Привет, это NASA", entities: [])
        XCTAssertEqual(MTTextPipeline.run(input, configuration: MTTextPipelineConfiguration(antiCaps: true), context: self.plain), input)
    }

    // MARK: Hyperlink

    func testHyperlinkKeepsFormattingAndSkipsLinks() {
        let text = "hello https://t.me/x world"
        let bold = self.entity(self.utf16Range(of: "hello", in: text), tag: 5)
        let url = self.entity(self.utf16Range(of: "https://t.me/x", in: text), protected: true, overlay: true, tag: 6)
        let output = MTTextPipeline.run(MTPipelineText(text: text, entities: [bold, url]), configuration: MTTextPipelineConfiguration(hyperlink: true), context: self.plain)
        XCTAssertEqual(output.text, text)
        let added = output.entities.filter { $0.tag == MTPipelineEntity.addedOverlay }
        XCTAssertEqual(added.map { output.substring($0.range) }, ["hello", "world"])
        XCTAssertEqual(output.entities.filter { $0.tag == 5 }.count, 1)
        XCTAssertEqual(output.entities.filter { $0.tag == 6 }.count, 1)
    }

    // MARK: Remap

    func testRemapInsideEdit() {
        let text = MTPipelineText(text: "abcdef", entities: [self.entity(2 ..< 4, tag: 7)])
        let output = text.applying([MTTextEdit(range: 1 ..< 5, replacement: "XY")])
        XCTAssertEqual(output.text, "aXYf")
        XCTAssertEqual(output.entities[0].range, 1 ..< 3)
    }

    func testRemapAfterEdit() {
        let text = MTPipelineText(text: "ab cd", entities: [self.entity(3 ..< 5, tag: 8)])
        let output = text.applying([MTTextEdit(range: 0 ..< 2, replacement: "abcd")])
        XCTAssertEqual(output.substring(output.entities[0].range), "cd")
    }
}
