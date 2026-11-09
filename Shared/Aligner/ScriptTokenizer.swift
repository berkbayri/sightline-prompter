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

/// A delivery direction written as `[[like this]]` in the script. It is shown in the prompter, in its own
/// style, but never spoken: it is not a word, so the aligner, the word counts and the pace estimate skip it.
public struct ScriptCue: Equatable, Sendable {
    public let text: String
    /// True when the cue sits alone on its line(s). It is then drawn as its own block between paragraphs;
    /// otherwise it is drawn inline, between the words around it.
    public let standalone: Bool
    /// Paragraph the cue belongs to, in the numbering of `ScriptToken.paragraph`.
    public let paragraph: Int

    public init(text: String, standalone: Bool, paragraph: Int) {
        self.text = text
        self.standalone = standalone
        self.paragraph = paragraph
    }
}

/// One item of the script in reading order: a spoken word (by index into `tokens`) or a cue.
public enum ScriptElement: Equatable, Sendable {
    case word(Int)
    case cue(ScriptCue)
}

public struct ParsedScript: Equatable, Sendable {
    /// The spoken words. Cues are not in here.
    public let tokens: [ScriptToken]
    /// Words and cues in the order they appear in the script.
    public let elements: [ScriptElement]
}

/// Splits a script into words. The only place word boundaries are decided, so the aligner and the
/// prompter display always agree on indices.
///
/// Spaced languages split on whitespace. Unspaced languages (zh, ja) use `NLTokenizer` word segments;
/// punctuation stays attached to the preceding segment so the joined displays reproduce the text.
/// A blank line starts a new paragraph. Line breaks inside a paragraph are treated as spaces.
///
/// `[[...]]` blocks are delivery directions (see `ScriptCue`): they are taken out of the word stream and
/// reported separately in `parse(_:language:).elements`. Blocks do not nest, and an unclosed `[[` is plain text.
public enum ScriptTokenizer {
    /// The spoken words of the script. Delivery cues are left out.
    public static func tokenize(_ text: String, language: ScriptLanguage) -> [ScriptToken] {
        parse(text, language: language).tokens
    }

    public static func parse(_ text: String, language: ScriptLanguage) -> ParsedScript {
        let tokenizer = language.spaced ? nil : makeSegmenter(language)
        let (masked, cueTexts) = extractCues(text)
        var tokens: [ScriptToken] = []
        var elements: [ScriptElement] = []
        var paragraph = 0
        var breakNext = false

        for line in masked.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let lineParts = pieces(of: String(line), cueCount: cueTexts.count)
            let segmented: [(words: [String], cue: Int?)] = lineParts.map { piece in
                switch piece {
                case .text(let string): return (segments(of: string, tokenizer: tokenizer), nil)
                case .cue(let index): return ([], index)
                }
            }
            let hasWords = segmented.contains { !$0.words.isEmpty }
            let hasCues = segmented.contains { $0.cue != nil }

            if !hasWords && !hasCues {
                if !tokens.isEmpty { breakNext = true }
                continue
            }
            if !hasWords {
                // A line holding only cues is a block of its own; the words after it start a new paragraph.
                for case let (_, index?) in segmented {
                    elements.append(.cue(ScriptCue(text: cueTexts[index], standalone: true, paragraph: paragraph)))
                }
                if !tokens.isEmpty { breakNext = true }
                continue
            }
            if breakNext {
                paragraph += 1
                breakNext = false
            }
            for entry in segmented {
                if let index = entry.cue {
                    elements.append(.cue(ScriptCue(text: cueTexts[index], standalone: false, paragraph: paragraph)))
                }
                for display in entry.words {
                    let normalized = Normalizer.normalize(display, language: language)
                    elements.append(.word(tokens.count))
                    tokens.append(ScriptToken(display: display, normalized: normalized, paragraph: paragraph))
                }
            }
        }
        return ParsedScript(tokens: tokens, elements: elements)
    }

    // MARK: - Cues

    private static let cueOpen: Unicode.Scalar = "\u{E000}"
    private static let cueClose: Unicode.Scalar = "\u{E001}"

    private enum Piece {
        case text(String)
        case cue(Int)
    }

    /// Replaces each `[[...]]` with a private-use placeholder (`E000 index E001`) on one line, and returns the
    /// trimmed, single-spaced cue texts. An empty block is dropped. Without any block the text is returned as is.
    private static func extractCues(_ text: String) -> (masked: String, cues: [String]) {
        guard text.contains("[[") else { return (text, []) }
        var input = text
        // The placeholder characters are reserved: strip any that came with the text.
        input.unicodeScalars.removeAll { $0 == cueOpen || $0 == cueClose }

        var masked = ""
        var cues: [String] = []
        var rest = input[...]
        while let open = rest.range(of: "[["), let close = rest.range(of: "]]", range: open.upperBound..<rest.endIndex) {
            masked += rest[rest.startIndex..<open.lowerBound]
            let inner = rest[open.upperBound..<close.lowerBound]
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            if inner.isEmpty {
                masked += " "
            } else {
                masked += " \(cueOpen)\(cues.count)\(cueClose) "
                cues.append(inner)
            }
            rest = rest[close.upperBound...]
        }
        masked += rest
        return (masked, cues)
    }

    /// Splits one masked line into text runs and cue placeholders, in order.
    private static func pieces(of line: String, cueCount: Int) -> [Piece] {
        guard cueCount > 0, line.unicodeScalars.contains(cueOpen) else { return [.text(line)] }
        var result: [Piece] = []
        var text = ""
        var digits = ""
        var inCue = false
        for scalar in line.unicodeScalars {
            if scalar == cueOpen {
                if !text.isEmpty { result.append(.text(text)) }
                text = ""
                digits = ""
                inCue = true
            } else if scalar == cueClose, inCue {
                if let index = Int(digits), index < cueCount { result.append(.cue(index)) }
                inCue = false
            } else if inCue {
                digits.unicodeScalars.append(scalar)
            } else {
                text.unicodeScalars.append(scalar)
            }
        }
        if !text.isEmpty { result.append(.text(text)) }
        return result
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
