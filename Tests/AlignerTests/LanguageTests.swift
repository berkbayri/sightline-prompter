import XCTest
@testable import Aligner

final class LanguageTests: XCTestCase {
    private let turkish = ScriptLanguage.named("tr-TR")
    private let english = ScriptLanguage.named("en-US")
    private let russian = ScriptLanguage.named("ru-RU")
    private let arabic = ScriptLanguage.named("ar-SA")
    private let chinese = ScriptLanguage.named("zh-CN")
    private let japanese = ScriptLanguage.named("ja-JP")
    private let hindi = ScriptLanguage.named("hi-IN")

    /// Feeds cumulative transcripts of `spoken` and checks the cursor follows the reader word by word.
    private func assertSequentialReading(script: String, language: ScriptLanguage, spoken: [String],
                                         file: StaticString = #filePath, line: UInt = #line) {
        let aligner = ScriptAligner(script: script, language: language)
        XCTAssertEqual(aligner.tokens.count, spoken.count, "script and spoken word counts differ", file: file, line: line)
        var k = 3
        while k <= spoken.count {
            _ = aligner.consume(transcript: spoken[0..<k].joined(separator: " "))
            XCTAssertEqual(aligner.cursor, k, "after \(k) words", file: file, line: line)
            k += 3
        }
    }

    func testTurkishSequentialReadingAdvances() {
        assertSequentialReading(
            script: "Bugün sahnede yeni bir konuşma yapacağım. Önce kısa bir giriş yapacak, sonra ses takibini deneyeceğim. Ekranda kelimeler sırayla ilerleyecek.",
            language: turkish,
            spoken: "bugun sahnede yeni bir konusma yapacagim once kisa bir giris yapacak sonra ses takibini deneyecegim ekranda kelimeler sirayla ilerleyecek".components(separatedBy: " ")
        )
    }

    func testEnglishSequentialReadingAdvances() {
        assertSequentialReading(
            script: "The quick brown fox jumps over the lazy dog near the river. Then the farmer walks home slowly before the storm arrives.",
            language: english,
            spoken: "the quick brown fox jumps over the lazy dog near the river then the farmer walks home slowly before the storm arrives".components(separatedBy: " ")
        )
    }

    func testRussianSequentialReadingMatchesYoAsE() {
        assertSequentialReading(
            script: "Сегодня мы говорим о телесуфлёре, который помогает читать текст вслух. Ёлка стоит в углу комнаты.",
            language: russian,
            spoken: "сегодня мы говорим о телесуфлере который помогает читать текст вслух елка стоит в углу комнаты".components(separatedBy: " ")
        )
    }

    func testArabicHarakatStrippedAndAlefVariantsMatch() {
        XCTAssertEqual(Normalizer.normalize("إِنَّ", language: arabic), "ان")
        XCTAssertEqual(Normalizer.normalize("يَقْرَأُ", language: arabic), "يقرا")
        XCTAssertEqual(Normalizer.normalize("آمن", language: arabic), "امن")
        XCTAssertEqual(Normalizer.normalize("مدرسة", language: arabic), "مدرسه")
        XCTAssertEqual(Normalizer.normalize("على", language: arabic), "علي")

        assertSequentialReading(
            script: "إِنَّ الْمُعَلِّمَ يَقْرَأُ النَّصَّ بِوُضُوحٍ اليَوْمَ",
            language: arabic,
            spoken: ["ان", "المعلم", "يقرا", "النص", "بوضوح", "اليوم"]
        )
    }

    func testChineseTokenizesIntoSegmentsThatReproduceTheText() {
        let script = "我们今天去公园散步。天气很好，大家都很开心。"
        let tokens = ScriptTokenizer.tokenize(script, language: chinese)
        XCTAssertFalse(tokens.isEmpty)
        XCTAssertEqual(tokens.map(\.display).joined(), script)
        XCTAssertTrue(tokens.allSatisfy { !$0.display.isEmpty })
    }

    func testChineseAlignerAdvancesOnSentence() {
        let aligner = ScriptAligner(script: "我们今天去公园散步。天气很好，大家都很开心。", language: chinese)
        XCTAssertNotNil(aligner.consume(transcript: "天气很好"))
        XCTAssertGreaterThan(aligner.cursor, 0)
        XCTAssertTrue(aligner.tokens[aligner.cursor - 1].normalized.hasSuffix("好"))
    }

    func testJapaneseTokenizesAndAlignerAdvancesOnSentence() {
        let script = "今日は天気がいいです。公園に行きましょう。"
        let tokens = ScriptTokenizer.tokenize(script, language: japanese)
        XCTAssertFalse(tokens.isEmpty)
        XCTAssertEqual(tokens.map(\.display).joined(), script)

        let aligner = ScriptAligner(script: script, language: japanese)
        XCTAssertNotNil(aligner.consume(transcript: "公園に行きましょう"))
        XCTAssertTrue(aligner.tokens[aligner.cursor - 1].normalized.hasSuffix("う"))
    }

    func testUnspacedParagraphsFollowBlankLines() {
        let tokens = ScriptTokenizer.tokenize("第一段落。\n\n第二段落。", language: chinese)
        XCTAssertEqual(tokens.first?.paragraph, 0)
        XCTAssertEqual(tokens.last?.paragraph, 1)
    }

    func testTokenCountIsStableAcrossCalls() {
        let samples: [(String, ScriptLanguage)] = [
            ("Merhaba arkadaşlar, bugün notch.\n\nİkinci paragraf.", turkish),
            ("今天天气很好。我们去公园吧！", chinese),
            ("今日は天気がいいです。公園に行きましょう。", japanese),
            ("إِنَّ الْمُعَلِّمَ يَقْرَأُ النَّصَّ", arabic),
        ]
        for (text, language) in samples {
            let first = ScriptTokenizer.tokenize(text, language: language)
            let second = ScriptTokenizer.tokenize(text, language: language)
            XCTAssertEqual(first.count, second.count, language.id)
            XCTAssertEqual(first, second, language.id)
        }
    }

    func testHindiKeepsVowelSignsAndDropsDanda() {
        XCTAssertEqual(Normalizer.normalize("हिन्दी।", language: hindi), "हिन्दी")
    }

    func testLatinFoldingRemovesDiacriticsAndCase() {
        XCTAssertEqual(Normalizer.normalize("Café,", language: english), "cafe")
        XCTAssertEqual(Normalizer.normalize("Ёлка", language: russian), "елка")
    }

    func testNamedFallsBackToTurkish() {
        XCTAssertEqual(ScriptLanguage.named("xx-XX").id, "tr-TR")
        XCTAssertEqual(ScriptLanguage.named("").id, "tr-TR")
        XCTAssertFalse(ScriptLanguage.named("ja-JP").spaced)
        XCTAssertTrue(ScriptLanguage.named("ar-SA").rightToLeft)
    }
}
