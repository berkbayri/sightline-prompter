import XCTest
@testable import Aligner

final class AlignerTests: XCTestCase {
    // Word indices: 0 Merhaba, 2 bugün, 3 notch, 4 teleprompter, 5 uygulamasını, 6 anlatacağım,
    // 12 Sonra, 13 çalışıyoruz, 14 ve, 15 ses, 18 Bu, 19 yıl, 20 2024, 21 yılında,
    // 22 yeni, 23 sürüm, 24 çıkacak, 25 Geliyorum, 26 dedi, 27 ve, 28 kapıdan
    private let script = """
    Merhaba arkadaşlar, bugün notch teleprompter uygulamasını anlatacağım. Önce kısaca neler yapabildiğini göstereceğim.
    Sonra çalışıyoruz ve ses takibini deneyeceğiz. Bu yıl 2024 yılında yeni sürüm çıkacak. Geliyorum dedi ve kapıdan girdi.
    """

    func testExactSequentialSpeechAdvancesCursor() {
        let a = ScriptAligner(script: script)
        XCTAssertEqual(a.consume(transcript: "Merhaba arkadaşlar bugün"), 3)
        XCTAssertEqual(a.consume(transcript: "Merhaba arkadaşlar bugün notch teleprompter"), 5)
        XCTAssertEqual(a.consume(transcript: "Merhaba arkadaşlar bugün notch teleprompter uygulamasını anlatacağım"), 7)
        XCTAssertEqual(a.cursor, 7)
    }

    func testSkippedWordStillAdvances() {
        let a = ScriptAligner(script: script)
        // "teleprompter" was not said.
        XCTAssertEqual(a.consume(transcript: "bugün notch uygulamasını"), 6)
    }

    func testMisheardWordStillAdvances() {
        let a = ScriptAligner(script: script)
        a.reset(to: 25)
        // "geliyoruz" for "geliyorum" (fuzzy 0.6) plus exact "dedi".
        XCTAssertEqual(a.consume(transcript: "geliyoruz dedi"), 27)
    }

    func testTurkishDiacriticsMatchAsciiTranscript() {
        let a = ScriptAligner(script: script)
        a.reset(to: 12)
        XCTAssertEqual(a.consume(transcript: "calisiyoruz ve ses"), 16)
    }

    func testRereadingBackwardMovesCursorBack() {
        let a = ScriptAligner(script: script)
        a.reset(to: 6)
        XCTAssertEqual(a.consume(transcript: "bugün notch teleprompter"), 5)
        XCTAssertEqual(a.cursor, 5)
    }

    func testTwoWordBackwardMatchIsIgnored() {
        let a = ScriptAligner(script: script)
        a.reset(to: 6)
        XCTAssertNil(a.consume(transcript: "bugün notch"))
        XCTAssertEqual(a.cursor, 6)
    }

    func testRandomUnrelatedWordDoesNotMoveCursor() {
        let a = ScriptAligner(script: script)
        a.reset(to: 10)
        XCTAssertNil(a.consume(transcript: "zebra"))
        XCTAssertEqual(a.cursor, 10)
    }

    func testRandomLongWordAtStartDoesNotMoveCursor() {
        let a = ScriptAligner(script: script)
        XCTAssertNil(a.consume(transcript: "istanbul"))
        XCTAssertEqual(a.cursor, 0)
    }

    func testSingleLongExactWordAllowsShortJump() {
        let a = ScriptAligner(script: script)
        XCTAssertEqual(a.consume(transcript: "uygulamasını"), 6)
    }

    func testNumberSpokenAsWordsDoesNotCrashAndStaysNearby() {
        let a = ScriptAligner(script: script)
        a.reset(to: 19)
        _ = a.consume(transcript: "bu yıl iki bin yirmi dört")
        // Script "2024" is a weak wildcard for number words; cursor must stay in the local area.
        XCTAssertTrue((19...25).contains(a.cursor), "cursor \(a.cursor)")
    }

    func testMatchesOutsideAllowedRangeAreIgnored() {
        let a = ScriptAligner(script: script)
        // Only words 0...6 are on screen: the phrase "yeni sürüm çıkacak" (21...24) must not pull the cursor.
        a.allowedRange = 0...6
        a.reset(to: 0)
        XCTAssertNil(a.consume(transcript: "yeni sürüm çıkacak"))
        XCTAssertEqual(a.cursor, 0)
    }

    func testAllowedRangeStillAdvancesInsideVisibleWords() {
        let a = ScriptAligner(script: script)
        a.allowedRange = 0...6
        XCTAssertEqual(a.consume(transcript: "Merhaba arkadaşlar bugün notch"), 4)
    }

    func testCumulativePartialsDoNotDoubleCount() {
        let a = ScriptAligner(script: script)
        XCTAssertEqual(a.consume(transcript: "Merhaba arkadaşlar bugün"), 3)
        XCTAssertEqual(a.consume(transcript: "Merhaba arkadaşlar bugün notch"), 4)
        XCTAssertNil(a.consume(transcript: "Merhaba arkadaşlar bugün notch"))
        XCTAssertEqual(a.consume(transcript: "Merhaba arkadaşlar bugün notch teleprompter"), 5)
        XCTAssertEqual(a.cursor, 5)
    }

    func testResetClampsToScriptLength() {
        let a = ScriptAligner(script: script)
        a.reset(to: 1000)
        XCTAssertEqual(a.cursor, a.tokens.count)
        a.reset(to: -5)
        XCTAssertEqual(a.cursor, 0)
    }

    func testNormalizerTurkishLowercaseAndFolding() {
        XCTAssertEqual(Normalizer.normalize("Çalışıyoruz,"), "calisiyoruz")
        XCTAssertEqual(Normalizer.normalize("İstanbul"), "istanbul")
        XCTAssertEqual(Normalizer.normalize("ISIK"), "isik")
        XCTAssertEqual(Normalizer.normalize("Ankara'da"), "ankarada")
        XCTAssertEqual(Normalizer.normalize("2024."), "2024")
        XCTAssertEqual(Normalizer.normalize("—"), "")
    }

    func testTokenizeKeepsWordIndicesAndMarksParagraphs() {
        let tokens = Normalizer.tokenize("bir iki\n\n\nüç  dört\n")
        XCTAssertEqual(tokens.map(\.display), ["bir", "iki", "üç", "dört"])
        XCTAssertEqual(tokens.map(\.paragraph), [0, 0, 1, 1])
    }
}
