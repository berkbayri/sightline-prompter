import Foundation

/// Follows the reader's position from cumulative partial transcripts. Pure logic, no UI.
/// Indices are word indices of the script (see `ScriptTokenizer`).
public final class ScriptAligner {
    public private(set) var tokens: [ScriptToken]
    private let language: ScriptLanguage
    /// Index of the next word expected to be spoken (last matched index + 1).
    public private(set) var cursor = 0

    /// Words the reader can currently see. Matches are only accepted inside this range,
    /// so speech is never aligned to text that is off screen. nil = unrestricted.
    public var allowedRange: ClosedRange<Int>?

    private struct Match {
        let index: Int
        let sim: Double
    }

    private static let backWindow = 8
    private static let forwardWindow = 40
    private static let heardTail = 8
    private static let minScore = 1.6 - 1e-6
    private static let skipPenalty = 0.05
    /// A short run of matches right at the cursor is trusted with a lower score: it is the next words
    /// the reader is expected to say, so the cursor reacts at once instead of waiting for more words.
    private static let nearScore = 1.2

    private let norms: [String]
    /// For script words that are digits ("2024"): the words a reader says for them.
    private let numberWords: [Int: Set<String>]
    /// nonEmptyBefore[i] = number of non-empty tokens in tokens[0..<i].
    private let nonEmptyBefore: [Int]

    public convenience init(script: String) {
        self.init(script: script, language: .named("tr-TR"))
    }

    public init(script: String, language: ScriptLanguage) {
        let tokens = ScriptTokenizer.tokenize(script, language: language)
        let norms = tokens.map(\.normalized)
        var before = [0]
        for n in norms { before.append(before[before.count - 1] + (n.isEmpty ? 0 : 1)) }

        var spelled: [Int: Set<String>] = [:]
        for (i, n) in norms.enumerated() where !n.isEmpty && n.allSatisfy({ $0.isNumber }) {
            if let words = NumberWords.words(for: n, language: language) { spelled[i] = Set(words) }
        }

        self.tokens = tokens
        self.language = language
        self.norms = norms
        self.nonEmptyBefore = before
        self.numberWords = spelled
    }

    public func reset(to index: Int) {
        cursor = min(max(index, 0), tokens.count)
    }

    /// Feeds the full current partial transcript. Only the last few heard words are aligned,
    /// so repeated growing partials do not double-count. Returns the new cursor if it changed.
    public func consume(transcript: String) -> Int? {
        let heard = Array(heardWords(transcript).suffix(ScriptAligner.heardTail))
        let upper = min(tokens.count - 1, allowedRange?.upperBound ?? Int.max)
        let lower = max(0, allowedRange?.lowerBound ?? 0)
        guard !heard.isEmpty, lower <= upper else { return nil }

        // The same script word is compared with the same heard word from many start positions.
        var similarities: [Int: Double] = [:]

        // Near the cursor first: the reader is going on from where they were.
        let lo = max(lower, cursor - ScriptAligner.backWindow)
        let hi = min(upper, cursor + ScriptAligner.forwardWindow)
        var best = lo <= hi
            ? search(heard, starts: lo...hi, upper: upper, relocating: false, similarities: &similarities)
            : nil

        // Nothing near the cursor: the reader may have scrolled somewhere else. Whatever is on screen is
        // what they will read next, so any of the visible words can be the new position.
        if best == nil, allowedRange != nil {
            best = search(heard, starts: lower...upper, upper: upper, relocating: true, similarities: &similarities)
        }

        guard let chosen = best, chosen.cursor != cursor else { return nil }
        cursor = chosen.cursor
        return cursor
    }

    private func search(
        _ heard: [String],
        starts: ClosedRange<Int>,
        upper: Int,
        relocating: Bool,
        similarities: inout [Int: Double]
    ) -> (score: Double, cursor: Int)? {
        var best: (score: Double, cursor: Int)?
        for start in starts {
            let matches = align(heard, from: start, upper: upper, similarities: &similarities)
            guard let first = matches.first, let last = matches.last else { continue }
            let newCursor = last.index + 1
            let skipped = nonEmptyBefore[last.index + 1] - nonEmptyBefore[first.index] - matches.count
            let score = matches.reduce(0.0) { $0 + $1.sim } - ScriptAligner.skipPenalty * Double(skipped)

            if relocating {
                // A jump needs real evidence: two good matches in a row, or one long exact word.
                let longExact = matches.count == 1 && matches[0].sim == 1 && norms[last.index].count >= 6
                guard score >= ScriptAligner.minScore || longExact else { continue }
            } else {
                let singleExact = matches.count == 1 && matches[0].sim == 1
                    && norms[last.index].count >= 5 && last.index < cursor + 12
                // The next expected word on its own: moves the cursor on the first word of an utterance.
                let nextWord = matches.count == 1 && matches[0].sim >= 0.85 && skipped == 0
                    && nonEmptyBefore[first.index] - nonEmptyBefore[min(cursor, tokens.count)] <= 1
                // Two or more matches right at the cursor.
                let nearRun = matches.count >= 2 && score >= ScriptAligner.nearScore && skipped <= 1
                    && nonEmptyBefore[first.index] - nonEmptyBefore[min(cursor, tokens.count)] <= 2
                guard score >= ScriptAligner.minScore || singleExact || nextWord || nearRun else { continue }

                // Backward only for re-reading (>=3 exact in a row); big forward jumps need >=4.
                let run = exactRun(matches)
                if newCursor < cursor && run < 3 { continue }
                if newCursor - cursor > 60 && run < 4 { continue }
            }

            if let b = best, b.score > score || (b.score == score && abs(b.cursor - cursor) <= abs(newCursor - cursor)) {
                continue
            }
            best = (score, newCursor)
        }
        return best
    }

    /// Greedy monotone alignment starting at script index `start`. Each heard word may match
    /// one of the next 3 non-empty script words; unmatched heard words are skipped as noise.
    private func align(_ heard: [String], from start: Int, upper: Int, similarities: inout [Int: Double]) -> [Match] {
        var matches: [Match] = []
        var s = start
        for (heardIndex, word) in heard.enumerated() {
            var seen = 0
            var pick: Match?
            var j = s
            while j <= upper && seen < 3 {
                if !norms[j].isEmpty {
                    seen += 1
                    let key = j &* 16 &+ heardIndex
                    var sim: Double
                    if let known = similarities[key] {
                        sim = known
                    } else {
                        sim = Normalizer.similarity(norms[j], word)
                        similarities[key] = sim
                    }
                    let numeric = norms[j].contains { $0.isNumber }
                    // A digit script word is also matched by the words of that number, as heard.
                    if numeric, sim < 0.75, numberWords[j]?.contains(word) == true { sim = 0.75 }
                    if (sim >= 0.5 || (sim >= 0.4 && numeric)) && sim > (pick?.sim ?? 0) {
                        pick = Match(index: j, sim: sim)
                    }
                }
                j += 1
            }
            if let p = pick {
                matches.append(p)
                s = p.index + 1
            }
        }
        return matches
    }

    private func exactRun(_ matches: [Match]) -> Int {
        var best = 0, run = 0, prev = -2
        for m in matches {
            run = m.sim == 1 ? (m.index == prev + 1 ? run + 1 : 1) : 0
            prev = m.index
            best = max(best, run)
        }
        return best
    }

    /// The last words heard, normalized like the script. Numbers the recognizer wrote as digits become the
    /// words a reader says ("25" -> "yirmi", "beş"). Only the end of the transcript is looked at, so the cost
    /// does not grow with the length of the recording. Unspaced transcripts are segmented like the script.
    private func heardWords(_ text: String) -> [String] {
        let tail = ScriptAligner.recentText(of: text, spaced: language.spaced)
        var words: [String] = []
        for token in ScriptTokenizer.tokenize(tail, language: language) {
            let word = token.normalized
            guard !word.isEmpty else { continue }
            if let spelled = NumberWords.words(for: word, language: language) {
                words.append(contentsOf: spelled)
            } else {
                words.append(word)
            }
        }
        return words
    }

    /// The end of a transcript: enough words to cover `heardTail` after number expansion.
    private static func recentText(of text: String, spaced: Bool) -> String {
        if spaced {
            // Walk back from the end: a long transcript is never split as a whole.
            var index = text.endIndex
            var count = 0
            var inWord = false
            while index > text.startIndex {
                let previous = text.index(before: index)
                if text[previous].isWhitespace {
                    if inWord {
                        inWord = false
                        if count == 24 { return String(text[index...]) }
                    }
                } else if !inWord {
                    inWord = true
                    count += 1
                }
                index = previous
            }
            return text
        }
        return String(text.suffix(60))
    }
}
