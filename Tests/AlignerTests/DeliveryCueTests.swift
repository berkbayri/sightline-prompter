import XCTest
@testable import Aligner

/// `[[...]]` blocks are delivery directions: shown, never spoken, never counted as words.
final class DeliveryCueTests: XCTestCase {
    private let english = ScriptLanguage.named("en-US")

    private func words(_ text: String, _ language: ScriptLanguage? = nil) -> [String] {
        ScriptTokenizer.tokenize(text, language: language ?? english).map(\.display)
    }

    private func cues(_ text: String) -> [ScriptCue] {
        ScriptTokenizer.parse(text, language: english).elements.compactMap {
            if case .cue(let cue) = $0 { return cue }
            return nil
        }
    }

    func testCueIsNotAWord() {
        XCTAssertEqual(words("Hello [[smile, pause two seconds]] there"), ["Hello", "there"])
    }

    func testCueOnItsOwnLineIsStandalone() {
        let found = cues("Hello there.\n\n[[ look at the camera ]]\n\nNext part.")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].text, "look at the camera")
        XCTAssertTrue(found[0].standalone)
    }

    func testCueBetweenWordsIsInline() {
        let found = cues("Hello [[smile]] there")
        XCTAssertEqual(found.map(\.text), ["smile"])
        XCTAssertFalse(found[0].standalone)
    }

    func testCueSpanningLinesIsOneCue() {
        let found = cues("Hello [[slow\ndown   here]] there")
        XCTAssertEqual(found.map(\.text), ["slow down here"])
        XCTAssertEqual(words("Hello [[slow\ndown   here]] there"), ["Hello", "there"])
    }

    func testEmptyAndUnclosedBlocks() {
        XCTAssertEqual(cues("a [[]] b [[   ]] c").count, 0)
        XCTAssertEqual(words("a [[]] b"), ["a", "b"])
        // An unclosed block is plain text.
        XCTAssertEqual(words("a [[ b c"), ["a", "[[", "b", "c"])
        XCTAssertEqual(cues("a [[ b c").count, 0)
    }

    func testSingleBracketsStayText() {
        XCTAssertEqual(words("see [1] and [note]"), ["see", "[1]", "and", "[note]"])
    }

    func testCueDoesNotChangeWordIndicesOrParagraphs() {
        let plain = ScriptTokenizer.tokenize("One two.\n\nThree four.", language: english)
        let withCues = ScriptTokenizer.tokenize(
            "[[start]]\nOne [[a]] two.\n\n[[beat]]\n\nThree four. [[end]]", language: english
        )
        XCTAssertEqual(withCues, plain)
    }

    func testStandaloneCueBetweenLinesSplitsTheParagraph() {
        let tokens = ScriptTokenizer.tokenize("One two.\n[[pause]]\nThree four.", language: english)
        XCTAssertEqual(tokens.map(\.paragraph), [0, 0, 1, 1])
    }

    func testCueAtParagraphStartBelongsToThatParagraph() {
        let parsed = ScriptTokenizer.parse("One two.\n\n[[smile]] Three four.", language: english)
        let cue = parsed.elements.compactMap { element -> ScriptCue? in
            if case .cue(let cue) = element { return cue }
            return nil
        }.first
        XCTAssertEqual(cue?.paragraph, 1)
        XCTAssertEqual(cue?.standalone, false)
    }

    func testAlignerSkipsCues() {
        let aligner = ScriptAligner(script: "Hello [[smile]] there my friend", language: english)
        XCTAssertEqual(aligner.tokens.count, 4)
        XCTAssertEqual(aligner.consume(transcript: "hello there"), 2)
    }

    func testReservedCharactersInTheTextAreHarmless() {
        XCTAssertEqual(words("a \u{E000}0\u{E001} b [[x]] c"), ["a", "0", "b", "c"])
    }

    func testChineseCues() {
        let chinese = ScriptLanguage.named("zh-CN")
        XCTAssertEqual(words("你好[[微笑]]世界", chinese).joined(), "你好世界")
        XCTAssertEqual(ScriptTokenizer.parse("你好[[微笑]]世界", language: chinese).elements.contains {
            if case .cue = $0 { return true }
            return false
        }, true)
    }
}
