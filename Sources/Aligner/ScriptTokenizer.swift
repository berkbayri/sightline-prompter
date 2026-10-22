import Foundation
import NaturalLanguage

/// One displayed word of the script. Its index in the token array is the word index used by
/// both the aligner and PrompterView.
public struct ScriptToken: Equatable, Sendable {
    public let display: String
    public let normalized: String
    public let paragraph: Int

    public init(display: String, normalized: String, paragraph: Int) {
        self.display = display
        self.normalized = normalized
        self.paragraph = paragraph
    }
}

/// Splits a script into words. The only place word boundaries are decided, so the aligner and the
/// prompter display always agree on indices.
///
/// Spaced languages split on whitespace. Unspaced languages (zh, ja) use `NLTokenizer` word segments;
/// punctuation stays attached to the preceding segment so the joined displays reproduce the text.
/// A blank line starts a new paragraph. Line breaks inside a paragraph are treated as spaces.
public enum ScriptTokenizer {
    public static func tokenize(_ text: String, language: ScriptLanguage) -> [ScriptToken] {
        let tokenizer = language.spaced ? nil : makeSegmenter(language)
        var tokens: [ScriptToken] = []
        var paragraph = 0
        var breakNext = false
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let words = segments(of: String(line), tokenizer: tokenizer)
            if words.isEmpty {
                if !tokens.isEmpty { breakNext = true }
                continue
            }
            if breakNext {
                paragraph += 1
                breakNext = false
            }
            for display in words {
                let normalized = Normalizer.normalize(display, language: language)
                tokens.append(ScriptToken(display: display, normalized: normalized, paragraph: paragraph))
            }
        }
        return tokens
    }

    private static func makeSegmenter(_ language: ScriptLanguage) -> NLTokenizer {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(language.id.hasPrefix("ja") ? .japanese : .simplifiedChinese)
        return tokenizer
    }

    private static func segments(of line: String, tokenizer: NLTokenizer?) -> [String] {
        guard let tokenizer else {
            return line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        tokenizer.string = line
        var starts: [String.Index] = []
        tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in
            starts.append(range.lowerBound)
            return true
        }
        // Lines without any word segment (pure punctuation) stay as one token.
        guard !starts.isEmpty else { return [trimmed] }

        // Segment i runs from its word start to the next one, so the leading gap joins the first
        // word and trailing punctuation joins the last one.
        let bounds = [line.startIndex] + starts.dropFirst() + [line.endIndex]
        return zip(bounds, bounds.dropFirst())
            .map { String(line[$0..<$1]).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
