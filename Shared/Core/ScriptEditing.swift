import Aligner
import Foundation

/// Maps between word indices and positions in the raw script text, so editing the script on the prompter
/// can put the caret on the current word and put the reading position back after the edit. Word counting is
/// always `ScriptTokenizer`'s, run on the text with every `[[...]]` cue blanked out (same UTF-16 length), so
/// the indices agree with the aligner and the prompter. shortcut: unspaced languages (zh, ja) are counted on
/// text prefixes, so a position inside a word can be off by one word; upgrade if that is ever noticed.
public enum ScriptEditing {
    /// The text with each closed `[[...]]` block replaced by spaces; unclosed `[[` stays, as in the tokenizer.
    private static func masked(_ text: String) -> NSString {
        let result = NSMutableString(string: text)
        var from = 0
        while from < result.length {
            let open = result.range(of: "[[", range: NSRange(location: from, length: result.length - from))
            guard open.location != NSNotFound else { break }
            let after = open.location + open.length
            let close = result.range(of: "]]", range: NSRange(location: after, length: result.length - after))
            guard close.location != NSNotFound else { break }
            let end = close.location + close.length
            let range = NSRange(location: open.location, length: end - open.location)
            result.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
            from = end
        }
        return result
    }

    private static func count(_ text: NSString, upTo end: Int, _ language: ScriptLanguage) -> Int {
        ScriptTokenizer.tokenize(text.substring(to: end), language: language).count
    }

    /// The word at a UTF-16 position: the word the position touches, or the next one when it sits in a gap.
    public static func wordIndex(atOffset offset: Int, in text: String, language: ScriptLanguage) -> Int {
        let ns = masked(text)
        let end = min(max(offset, 0), ns.length)
        let touching = end > 0 && Unicode.Scalar(UInt32(ns.character(at: end - 1))).map { !CharacterSet.whitespacesAndNewlines.contains($0) } ?? true
        return max(count(ns, upTo: end, language) - (touching ? 1 : 0), 0)
    }

    /// UTF-16 position where the word starts; the end of the text when there is no such word.
    public static func startOffset(ofWord index: Int, in text: String, language: ScriptLanguage) -> Int {
        let ns = masked(text)
        guard index >= 0, count(ns, upTo: ns.length, language) > index else { return ns.length }
        // Smallest prefix that holds word `index`: it ends on the word's first character.
        var low = 1, high = ns.length
        while low < high {
            let mid = (low + high) / 2
            if count(ns, upTo: mid, language) > index { high = mid } else { low = mid + 1 }
        }
        return ns.rangeOfComposedCharacterSequence(at: low - 1).location
    }

    /// Where the reading position goes after the script changed from `old` to `new`. Edits after the word keep
    /// its index, edits before shift it, and a word that was edited away gives way to the word now in its place.
    public static func remap(word: Int, old: String, new: String, language: ScriptLanguage) -> Int {
        let total = ScriptTokenizer.tokenize(new, language: language).count
        guard total > 0 else { return 0 }
        let a = old as NSString, b = new as NSString
        let shortest = min(a.length, b.length)
        var head = 0
        while head < shortest, a.character(at: head) == b.character(at: head) { head += 1 }
        var tail = 0
        while tail < shortest - head, a.character(at: a.length - 1 - tail) == b.character(at: b.length - 1 - tail) { tail += 1 }

        let start = startOffset(ofWord: word, in: old, language: language)
        let index: Int
        if start < head {
            index = word
        } else if start >= a.length - tail {
            index = wordIndex(atOffset: start - a.length + b.length, in: new, language: language)
        } else {
            index = wordIndex(atOffset: head, in: new, language: language)
        }
        return min(max(index, 0), total - 1)
    }
}
