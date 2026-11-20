import Aligner
import XCTest
@testable import SightlineCore

final class ScriptEditingTests: XCTestCase {
    private let en = ScriptLanguage.named("en-US")
    private let old = "one two [[smile]] three four five"

    private func offset(_ word: String, in text: String) -> Int {
        (text as NSString).range(of: word).location
    }

    func testStartOffsetOfWordSkipsCues() {
        XCTAssertEqual(ScriptEditing.startOffset(ofWord: 0, in: old, language: en), 0)
        XCTAssertEqual(ScriptEditing.startOffset(ofWord: 2, in: old, language: en), offset("three", in: old))
        XCTAssertEqual(ScriptEditing.startOffset(ofWord: 4, in: old, language: en), offset("five", in: old))
        XCTAssertEqual(ScriptEditing.startOffset(ofWord: 99, in: old, language: en), (old as NSString).length)
    }

    func testWordIndexAtOffset() {
        XCTAssertEqual(ScriptEditing.wordIndex(atOffset: offset("three", in: old), in: old, language: en), 2)
        // Inside or at the end of a word it is that word; at the start of a word it is that word.
        XCTAssertEqual(ScriptEditing.wordIndex(atOffset: offset("three", in: old) + 2, in: old, language: en), 2)
        XCTAssertEqual(ScriptEditing.wordIndex(atOffset: offset("four", in: old) - 1, in: old, language: en), 2)
        XCTAssertEqual(ScriptEditing.wordIndex(atOffset: offset("four", in: old), in: old, language: en), 3)
        // Inside a cue the next spoken word counts.
        XCTAssertEqual(ScriptEditing.wordIndex(atOffset: offset("smile", in: old), in: old, language: en), 2)
    }

    private func remap(_ word: Int, to new: String) -> Int {
        ScriptEditing.remap(word: word, old: old, new: new, language: en)
    }

    func testEditAfterCurrentWordKeepsIndex() {
        XCTAssertEqual(remap(2, to: old + " six"), 2)
        XCTAssertEqual(remap(2, to: old.replacingOccurrences(of: "five", with: "5")), 2)
        XCTAssertEqual(remap(2, to: old.replacingOccurrences(of: "four five", with: "")), 2)
    }

    func testInsertBeforeShiftsIndex() {
        XCTAssertEqual(remap(2, to: "zero " + old), 3)
        XCTAssertEqual(remap(2, to: old.replacingOccurrences(of: "one two", with: "one extra words two")), 4)
    }

    func testDeleteBeforeShiftsIndexBack() {
        XCTAssertEqual(remap(2, to: old.replacingOccurrences(of: "one ", with: "")), 1)
        XCTAssertEqual(remap(3, to: old.replacingOccurrences(of: "one two ", with: "")), 1)
    }

    func testCueEditBeforeDoesNotMoveWords() {
        XCTAssertEqual(remap(2, to: old.replacingOccurrences(of: "[[smile]]", with: "[[long pause here]]")), 2)
        XCTAssertEqual(remap(2, to: old.replacingOccurrences(of: "[[smile]] ", with: "")), 2)
        XCTAssertEqual(remap(2, to: old.replacingOccurrences(of: "[[smile]]", with: "[[smile]] [[beat]]")), 2)
    }

    func testReplacingTheCurrentWordKeepsItsPlace() {
        XCTAssertEqual(remap(2, to: old.replacingOccurrences(of: "three", with: "3")), 2)
        XCTAssertEqual(remap(2, to: old.replacingOccurrences(of: "three", with: "a b")), 2)
    }

    func testRemovingTheCurrentWordResumesAtTheNextOne() {
        // "three" is gone; "four" slides into its index.
        XCTAssertEqual(remap(2, to: old.replacingOccurrences(of: "three ", with: "")), 2)
        // The last word removed: clamps to the new last word.
        XCTAssertEqual(remap(4, to: old.replacingOccurrences(of: " five", with: "")), 3)
    }

    func testIdenticalAndEmptyTexts() {
        XCTAssertEqual(remap(3, to: old), 3)
        XCTAssertEqual(remap(3, to: ""), 0)
    }

    func testUnclosedCueIsPlainText() {
        let text = "a b [[c d"
        XCTAssertEqual(ScriptEditing.startOffset(ofWord: 2, in: text, language: en), offset("[[c", in: text))
    }
}
