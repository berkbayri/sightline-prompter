import Aligner
import XCTest
@testable import SightlineCore

final class PrompterTextTests: XCTestCase {
    private let english = ScriptLanguage.named("en-US")

    private func build(_ script: String, cursor: Int = 0) -> PrompterText.Result {
        PrompterText.build(script: script, language: english, fontSize: 20, cursor: cursor) { _ in PrompterColor.white }
    }

    func testWordRangesPointAtTheWords() {
        let built = build("Hello [[smile]] there.\n\n[[beat]]\n\nBye [[end]]")
        let text = built.attributed.string as NSString
        XCTAssertEqual(built.words.map { text.substring(with: $0.range) }, ["Hello", "there.", "Bye"])
    }

    func testCuesAreSeparateRunsAndDoNotCountAsWords() {
        let built = build("Hello [[smile]] there.\n\n[[beat]]\n\nBye")
        let text = built.attributed.string as NSString
        XCTAssertEqual(built.cues.map { text.substring(with: $0.range).trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\u{00A0}"))) },
                       ["smile", "beat"])
        XCTAssertEqual(built.cues.map(\.wordsBefore), [1, 2])
        XCTAssertEqual(built.cues.map(\.standalone), [false, true])
        XCTAssertEqual(built.paragraphStarts, [0, 2])
    }

    func testStandaloneCueGetsItsOwnLine() {
        let built = build("One two.\n[[pause]]\nThree four.")
        let lines = built.attributed.string.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "One two.")
        XCTAssertTrue(lines[1].contains("pause"))
        XCTAssertEqual(lines[2], "Three four.")
    }

    func testCueAtTheStartAndEnd() {
        let built = build("[[intro]]\nHello world\n[[outro]]")
        let lines = built.attributed.string.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(built.words.count, 2)
        XCTAssertEqual(built.cues.map(\.wordsBefore), [0, 2])
        XCTAssertEqual(built.paragraphStarts, [0])
    }

    func testInlineCueAtParagraphStartStaysWithItsParagraph() {
        let built = build("One two.\n\n[[smile]] Three four.")
        let lines = built.attributed.string.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("smile"))
        XCTAssertTrue(lines[1].hasSuffix("Three four."))
    }

    func testCuesChangeColorOnceRead() {
        let ahead = PrompterText.cueColor(wordsBefore: 5, cursor: 2)
        let behind = PrompterText.cueColor(wordsBefore: 1, cursor: 2)
        XCTAssertGreaterThan(ahead.alphaComponent, behind.alphaComponent)
    }

    func testScriptWithoutCuesBuildsLikeBefore() {
        let built = build("One two.\n\nThree four.")
        XCTAssertEqual(built.attributed.string, "One two.\nThree four.")
        XCTAssertTrue(built.cues.isEmpty)
        XCTAssertEqual(built.paragraphStarts, [0, 2])
    }
}
