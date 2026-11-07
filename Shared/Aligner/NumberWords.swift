import Foundation

/// Spoken numbers. Recognizers write "yirmi beş" as "25", scripts often spell them out; both sides are
/// compared as words, so a number the reader says is found whichever way it was written.
enum NumberWords {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: NumberFormatter] = [:]
    nonisolated(unsafe) private static var cache: [String: [String]] = [:]

    /// The normalized words of a number in the language ("25", tr -> ["yirmi", "bes"]). nil when the
    /// digits are not a plain integer, are too long, or the language has no spelled-out form.
    static func words(for digits: String, language: ScriptLanguage) -> [String]? {
        guard language.spaced, !digits.isEmpty, digits.count <= 12,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(digits) else { return nil }
        let key = language.id + "|" + digits
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit.isEmpty ? nil : hit }

        let formatter: NumberFormatter
        if let existing = formatters[language.id] {
            formatter = existing
        } else {
            formatter = NumberFormatter()
            formatter.numberStyle = .spellOut
            formatter.locale = Locale(identifier: language.id)
            formatters[language.id] = formatter
        }
        let spelled = formatter.string(from: NSNumber(value: value)) ?? ""
        let words = spelled
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "\u{00AD}" })
            .map { Normalizer.normalize(String($0), language: language) }
            .filter { !$0.isEmpty }
        if cache.count > 4000 { cache.removeAll() }
        cache[key] = words
        return words.isEmpty ? nil : words
    }
}
