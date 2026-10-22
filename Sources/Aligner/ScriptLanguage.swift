import Foundation

/// A language a script can be written in and read aloud in.
public struct ScriptLanguage: Identifiable, Hashable, Sendable {
    /// BCP-47 locale identifier used for speech recognition, e.g. "tr-TR".
    public let id: String
    /// Name in the language itself, shown in pickers.
    public let name: String
    /// Words are separated by spaces. False for Chinese and Japanese.
    public let spaced: Bool
    public let rightToLeft: Bool

    public init(id: String, name: String, spaced: Bool = true, rightToLeft: Bool = false) {
        self.id = id
        self.name = name
        self.spaced = spaced
        self.rightToLeft = rightToLeft
    }

    /// The languages Sightline Prompter supports, in picker order.
    public static let all: [ScriptLanguage] = [
        ScriptLanguage(id: "en-US", name: "English"),
        ScriptLanguage(id: "zh-CN", name: "中文（简体）", spaced: false),
        ScriptLanguage(id: "hi-IN", name: "हिन्दी"),
        ScriptLanguage(id: "es-ES", name: "Español"),
        ScriptLanguage(id: "fr-FR", name: "Français"),
        ScriptLanguage(id: "ar-SA", name: "العربية", rightToLeft: true),
        ScriptLanguage(id: "pt-BR", name: "Português"),
        ScriptLanguage(id: "ru-RU", name: "Русский"),
        ScriptLanguage(id: "id-ID", name: "Bahasa Indonesia"),
        ScriptLanguage(id: "ja-JP", name: "日本語", spaced: false),
        ScriptLanguage(id: "tr-TR", name: "Türkçe"),
    ]

    /// Looks up a language by identifier, falling back to Turkish (the app's original language).
    public static func named(_ identifier: String) -> ScriptLanguage {
        all.first { $0.id == identifier } ?? all.last!
    }
}
