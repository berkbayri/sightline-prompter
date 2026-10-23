import Foundation

/// A language a script can be written in and read aloud in.
public struct ScriptLanguage: Identifiable, Hashable, Sendable {
    /// BCP-47 locale identifier used for speech recognition, e.g. "tr-TR".
    public let id: String
    /// Display name, in English.
    public let name: String
    /// Words are separated by spaces. False for Chinese, Japanese and Cantonese.
    public let spaced: Bool
    public let rightToLeft: Bool

    public init(id: String, name: String, spaced: Bool = true, rightToLeft: Bool = false) {
        self.id = id
        self.name = name
        self.spaced = spaced
        self.rightToLeft = rightToLeft
    }

    /// Every locale Apple offers for one-click offline download, plus Turkish. Turkish has no
    /// one-click download; it uses the system Dictation model when present and Apple's servers otherwise.
    public static let all: [ScriptLanguage] = [
        "en-US", "en-GB", "en-AU", "en-CA", "en-IE", "en-IN", "en-NZ", "en-SG", "en-ZA",
        "de-DE", "de-AT", "de-CH",
        "es-ES", "es-MX", "es-US", "es-CL",
        "fr-FR", "fr-CA", "fr-BE", "fr-CH",
        "it-IT", "it-CH",
        "pt-BR", "pt-PT",
        "ja-JP", "ko-KR",
        "zh-CN", "zh-HK", "zh-TW", "yue-CN",
        "tr-TR",
    ].map { id in
        ScriptLanguage(id: id, name: englishName(for: id), spaced: !unspacedPrefixes.contains { id.hasPrefix($0) })
    }

    private static let unspacedPrefixes = ["zh", "ja", "yue"]

    /// Languages no longer offered in pickers, kept so scripts saved in them still resolve.
    private static let legacy: [ScriptLanguage] = [
        ScriptLanguage(id: "ar-SA", name: "Arabic (Saudi Arabia)", rightToLeft: true),
        ScriptLanguage(id: "hi-IN", name: "Hindi (India)"),
        ScriptLanguage(id: "ru-RU", name: "Russian (Russia)"),
        ScriptLanguage(id: "id-ID", name: "Indonesian (Indonesia)"),
    ]

    /// Looks up a language by identifier, falling back to Turkish (the app's original language).
    public static func named(_ identifier: String) -> ScriptLanguage {
        (all + legacy).first { $0.id == identifier } ?? all.last!
    }

    private static func englishName(for identifier: String) -> String {
        Locale(identifier: "en_US").localizedString(forIdentifier: identifier) ?? identifier
    }
}
