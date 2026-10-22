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

    private let norms: [String]
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

        self.tokens = tokens
        self.language = language
        self.norms = norms
        self.nonEmptyBefore = before
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
        let lo = max(lower, cursor - ScriptAligner.backWindow)
        let hi = min(upper, cursor + ScriptAligner.forwardWindow)
        guard !heard.isEmpty, lo <= hi else { return nil }

        var best: (score: Double, cursor: Int)?
        for start in lo...hi {
            let matches = align(heard, from: start, upper: upper)
            guard let first = matches.first, let last = matches.last else { continue }
            let newCursor = last.index + 1
            let skipped = nonEmptyBefore[last.index + 1] - nonEmptyBefore[first.index] - matches.count
            let score = matches.reduce(0.0) { $0 + $1.sim } - ScriptAligner.skipPenalty * Double(skipped)
            let singleExact = matches.count == 1 && matches[0].sim == 1
                && norms[last.index].count >= 5 && last.index < cursor + 12
            guard score >= ScriptAligner.minScore || singleExact else { continue }

            // Backward only for re-reading (>=3 exact in a row); big forward jumps need >=4.
            let run = exactRun(matches)
            if newCursor < cursor && run < 3 { continue }
            if newCursor - cursor > 60 && run < 4 { continue }

            if let b = best, b.score > score || (b.score == score && abs(b.cursor - cursor) <= abs(newCursor - cursor)) {
                continue
            }
            best = (score, newCursor)
        }

        guard let chosen = best, chosen.cursor != cursor else { return nil }
        cursor = chosen.cursor
        return cursor
    }

    /// Greedy monotone alignment starting at script index `start`. Each heard word may match
    /// one of the next 3 non-empty script words; unmatched heard words are skipped as noise.
    private func align(_ heard: [String], from start: Int, upper: Int) -> [Match] {
        var matches: [Match] = []
        var s = start
        for word in heard {
            var seen = 0
            var pick: Match?
            var j = s
            while j <= upper && seen < 3 {
                if !norms[j].isEmpty {
                    seen += 1
                    let sim = Normalizer.similarity(norms[j], word)
                    let numeric = norms[j].contains { $0.isNumber }
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

    /// Unspaced transcripts are segmented the same way as the script, so both sides produce comparable words.
    private func heardWords(_ text: String) -> [String] {
        ScriptTokenizer.tokenize(text, language: language)
            .map(\.normalized)
            .filter { !$0.isEmpty }
    }
}
