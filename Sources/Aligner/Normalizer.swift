import Foundation

/// Word normalization and fuzzy comparison. Normalization depends on the script's language;
/// word boundaries come from `ScriptTokenizer`.
public enum Normalizer {
    private static let turkishLocale = Locale(identifier: "tr_TR")
    private static let turkishFolds: [Character: Character] = [
        "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "â": "a", "î": "i", "û": "u",
    ]

    /// Turkish normalization, kept for callers that have no language.
    public static func normalize(_ word: String) -> String {
        normalizeTurkish(word)
    }

    public static func normalize(_ word: String, language: ScriptLanguage) -> String {
        switch language.id.prefix(while: { $0 != "-" }) {
        case "tr": return normalizeTurkish(word)
        case "ar": return normalizeArabic(word)
        case "zh", "ja": return keepWordScalars(word.precomposedStringWithCompatibilityMapping)
        case "hi": return keepWordScalars(word.precomposedStringWithCanonicalMapping)
        default: return normalizeLatin(word)
        }
    }

    /// Script words the aligner matches against. Turkish uses the app's original rules.
    public static func tokenize(_ text: String) -> [ScriptToken] {
        ScriptTokenizer.tokenize(text, language: .named("tr-TR"))
    }

    /// `a` is the script word, `b` the heard word (both normalized).
    public static func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        // ASR writes numbers as words ("2024" vs "iki bin yirmi dört"): weak wildcard.
        if a.allSatisfy({ $0.isNumber }) || b.allSatisfy({ $0.isNumber }) { return 0.4 }
        let x = Array(a), y = Array(b)
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        // Turkish suffix tolerance: "geliyor" vs "geliyorum".
        if short.count >= 4 && long.starts(with: short) { return 0.85 }
        if 1 - Double(levenshtein(x, y)) / Double(max(x.count, y.count)) >= 0.75 { return 0.6 }
        // Shared stem.
        return zip(x, y).prefix { $0 == $1 }.count >= 4 ? 0.5 : 0
    }

    private static func normalizeTurkish(_ word: String) -> String {
        var out = ""
        for ch in word.lowercased(with: turkishLocale).precomposedStringWithCanonicalMapping {
            let c = turkishFolds[ch] ?? ch
            if c.isLetter || c.isNumber { out.append(c) }
        }
        return out
    }

    /// Case and diacritics folded, so "ёлка" matches "елка" and "café" matches "cafe".
    private static func normalizeLatin(_ word: String) -> String {
        var out = String.UnicodeScalarView()
        for u in word.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
        where isLetterOrNumber(u) {
            out.append(u)
        }
        return String(out)
    }

    /// Harakat and tatweel are dropped; alef hamza/madda/wasla forms, alef maksura and ta marbuta
    /// fold to the plain letters that ASR output uses.
    private static func normalizeArabic(_ word: String) -> String {
        var out = String.UnicodeScalarView()
        for u in word.precomposedStringWithCanonicalMapping.unicodeScalars {
            switch u.value {
            case 0x064B...0x065F, 0x0670, 0x0640:
                continue
            case 0x0622, 0x0623, 0x0625, 0x0671:
                out.append("\u{0627}")
            case 0x0649:
                out.append("\u{064A}")
            case 0x0629:
                out.append("\u{0647}")
            default:
                if isLetterOrNumber(u) || isMark(u) { out.append(u) }
            }
        }
        return String(out)
    }

    /// CJK and Devanagari keep their characters and combining marks (Devanagari vowel signs are marks);
    /// only punctuation and symbols are dropped.
    private static func keepWordScalars(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for u in text.unicodeScalars where isLetterOrNumber(u) || isMark(u) {
            out.append(u)
        }
        return String(out)
    }

    private static func isLetterOrNumber(_ u: Unicode.Scalar) -> Bool {
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    private static func isMark(_ u: Unicode.Scalar) -> Bool {
        switch u.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + [Int](repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
