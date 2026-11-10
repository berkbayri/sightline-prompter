import XCTest
@testable import Aligner

/// Simulates a speaker reading a script aloud while the recognizer reports growing partial transcripts,
/// the way SpeechTranscriber and SFSpeechRecognizer do (digits for spoken numbers, capitals, punctuation,
/// the odd mistaken word). The cursor must follow word by word, with no lag.
final class LiveReadingTests: XCTestCase {
    static let turkishScript = """
    Merhaba sevgili izleyiciler. Bugün size teleprompter ile kamera karşısında nasıl daha rahat konuşabileceğinizi anlatacağım.

    Metni okurken gözleriniz sürekli kameraya yakın kalır. Böylece izleyiciyle göz teması kurduğunuz izlenimini verirsiniz. Okuduğunuz kelime, ön kameranın hemen altında durur.

    Konuşmaya başladığınızda uygulama sesinizi dinler ve metni sizin hızınıza göre kaydırır. Yavaş konuşursanız yavaşlar, hızlandığınızda size yetişir. Duraksadığınızda ise olduğu yerde bekler.

    Şimdi birkaç zor kelime deneyelim: çocukların güzel şarkıları, ığdır'dan gelen öğretmen, yağmurlu bir pazartesi sabahı. Ayrıca sayıları da okuyalım: bir, iki, üç, dört, beş, yirmi beş, yüz, bin.

    Videoyu bitirmeden önce izleyicilere teşekkür etmeyi unutmayın. İzlediğiniz için çok teşekkür ederim, bir sonraki videoda görüşmek üzere, hoşça kalın.
    """

    private let turkish = ScriptLanguage.named("tr-TR")

    /// What the recognizer writes for a spoken word.
    private static let asrDigits: [String: String] = [
        "bir,": "1,", "iki,": "2,", "üç,": "3,", "dört,": "4,", "beş,": "5,",
        "yüz,": "100,", "bin.": "1.000.",
    ]

    /// Speaks the script word by word. Returns how many words the cursor was behind after each word.
    private func lag(
        script: String,
        language: ScriptLanguage,
        heard: (ScriptToken, Int) -> [String],
        startAt: Int = 0
    ) -> (lags: [Int], finalCursor: Int, total: Int) {
        let aligner = ScriptAligner(script: script, language: language)
        aligner.reset(to: startAt)
        let tokens = aligner.tokens
        var transcript: [String] = []
        var lags: [Int] = []
        for index in startAt..<tokens.count {
            transcript.append(contentsOf: heard(tokens[index], index))
            _ = aligner.consume(transcript: transcript.joined(separator: " "))
            lags.append(max(0, index + 1 - aligner.cursor))
        }
        return (lags, aligner.cursor, tokens.count)
    }

    func testPerfectReadingNeverLags() {
        let result = lag(script: Self.turkishScript, language: turkish) { token, _ in [token.display] }
        XCTAssertEqual(result.finalCursor, result.total)
        XCTAssertLessThanOrEqual(result.lags.max() ?? 0, 1, "lags: \(result.lags)")
    }

    func testSpokenNumbersWrittenAsDigits() {
        // The recognizer writes "bir, iki, üç" as "1, 2, 3": the cursor must still cross the whole list.
        let yirmi = ScriptAligner(script: Self.turkishScript, language: turkish).tokens.firstIndex { $0.display == "yirmi" }
        let result = lag(script: Self.turkishScript, language: turkish) { token, index in
            if index == yirmi { return [] }
            if index == (yirmi ?? -2) + 1 { return ["25,"] }
            return [Self.asrDigits[token.display] ?? token.display]
        }
        XCTAssertEqual(result.finalCursor, result.total, "stopped at word \(result.finalCursor) of \(result.total)")
        XCTAssertLessThanOrEqual(result.lags.max() ?? 0, 3, "lags: \(result.lags)")
    }

    func testNumbersListOnItsOwn() {
        let script = "Sayıları da okuyalım: bir, iki, üç, dört, beş, yirmi beş, yüz, bin. Devam ediyoruz."
        let aligner = ScriptAligner(script: script, language: turkish)
        var cursors: [Int] = []
        for partial in ["Sayıları", "Sayıları da", "Sayıları da okuyalım", "Sayıları da okuyalım 1", "Sayıları da okuyalım 1 2",
                        "Sayıları da okuyalım 1 2 3", "Sayıları da okuyalım 1 2 3 4 5", "Sayıları da okuyalım 1 2 3 4 5 25",
                        "Sayıları da okuyalım 1 2 3 4 5 25 100", "Sayıları da okuyalım 1 2 3 4 5 25 100 1000"] {
            _ = aligner.consume(transcript: partial)
            cursors.append(aligner.cursor)
        }
        // "1000" is the 12th script word ("bin."), so the cursor ends right after it.
        XCTAssertEqual(aligner.cursor, 12, "cursors: \(cursors)")
    }

    func testFirstWordOfAnUtteranceMovesTheCursor() {
        // A short first word ("ve", "bir") must not wait for a second word before the cursor reacts.
        let script = "Bu bir deneme. Ve sonra devam eder, çünkü zaman azdır."
        let aligner = ScriptAligner(script: script, language: turkish)
        XCTAssertEqual(aligner.consume(transcript: "Bu"), 1)
        XCTAssertEqual(aligner.consume(transcript: "Bu bir"), 2)
    }

    func testRecognitionMistakesDoNotStallTheCursor() {
        // Every fifth word is misheard as something unrelated; the cursor still gets through the script.
        let result = lag(script: Self.turkishScript, language: turkish) { token, index in
            index % 5 == 4 ? ["xyz"] : [token.display]
        }
        XCTAssertEqual(result.finalCursor, result.total, "stopped at \(result.finalCursor) of \(result.total)")
        XCTAssertLessThanOrEqual(result.lags.max() ?? 0, 6, "lags: \(result.lags)")
    }

    func testInflectionAndSpellingVariantsAreAccepted() {
        // Recognizers drop apostrophes and change suffixes: "ığdır'dan" -> "ığdırdan", "konuşursanız" -> "konuşursan".
        let script = "Ayrıca ığdır'dan gelen öğretmen yağmurlu bir pazartesi sabahı konuşursanız yavaşlar."
        let heard = "Ayrıca ığdırdan gelen öğretmen yağmurlu bir pazartesi sabahı konuşursan yavaşlar"
        let aligner = ScriptAligner(script: script, language: turkish)
        var words: [String] = []
        for word in heard.split(separator: " ") {
            words.append(String(word))
            _ = aligner.consume(transcript: words.joined(separator: " "))
        }
        XCTAssertEqual(aligner.cursor, aligner.tokens.count)
    }

    func testLongTranscriptStaysFast() {
        // After a long recording the cumulative transcript holds thousands of words; each partial must stay cheap.
        let aligner = ScriptAligner(script: Self.turkishScript, language: turkish)
        let history = String(repeating: "alakasız kelimeler söyleniyor burada ", count: 3000)
        measure {
            for _ in 0..<20 {
                _ = aligner.consume(transcript: history + "Merhaba sevgili")
            }
        }
    }

    func testEnglishNumbersAlsoWork() {
        let script = "Count with me: one, two, three, four, five, twenty five, one hundred, and finish."
        let aligner = ScriptAligner(script: script, language: .named("en-US"))
        _ = aligner.consume(transcript: "Count with me 1 2 3 4 5 25 100 and finish")
        XCTAssertEqual(aligner.cursor, aligner.tokens.count)
    }

    // MARK: - Scrolling away

    func testSpeechOnScreenIsFoundAfterScrollingToTheTop() {
        // The cursor is deep in the script; the reader scrolls to the top and starts over.
        let aligner = ScriptAligner(script: Self.turkishScript, language: turkish)
        aligner.reset(to: 70)
        aligner.allowedRange = 0...25   // the words now on screen
        XCTAssertNotNil(aligner.consume(transcript: "Merhaba sevgili izleyiciler"))
        XCTAssertEqual(aligner.cursor, 3)
        _ = aligner.consume(transcript: "Merhaba sevgili izleyiciler Bugün size teleprompter")
        XCTAssertEqual(aligner.cursor, 6)
    }

    func testSpeechOnScreenIsFoundWhenScrolledBackwards() {
        let aligner = ScriptAligner(script: Self.turkishScript, language: turkish)
        aligner.reset(to: 60)
        aligner.allowedRange = 20...45
        _ = aligner.consume(transcript: "Okuduğunuz kelime ön kameranın hemen")
        let tokens = aligner.tokens
        let spoken = tokens.firstIndex { $0.display == "hemen" }!
        XCTAssertEqual(aligner.cursor, spoken + 1)
    }

    func testOffScreenWordsAreNotMatchedWhenScrolledAway() {
        let aligner = ScriptAligner(script: Self.turkishScript, language: turkish)
        aligner.reset(to: 70)
        aligner.allowedRange = 0...25
        // Words from near the old cursor are not on screen, so they must not pull the cursor back there.
        XCTAssertNil(aligner.consume(transcript: "teşekkür ederim hoşça kalın"))
        XCTAssertEqual(aligner.cursor, 70)
    }

    func testNoiseDoesNotRelocateTheCursor() {
        let aligner = ScriptAligner(script: Self.turkishScript, language: turkish)
        aligner.reset(to: 70)
        aligner.allowedRange = 0...25
        XCTAssertNil(aligner.consume(transcript: "ev araba kalem"))
        XCTAssertEqual(aligner.cursor, 70)
    }
}
