import Aligner
import Foundation

public struct Script: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var languageID: String
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        languageID: String,
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.languageID = languageID
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Stored as "language" on disk so the file format matches the documented schema.
    private enum CodingKeys: String, CodingKey {
        case id, title, text, createdAt, updatedAt
        case languageID = "language"
    }

    public var language: ScriptLanguage {
        ScriptLanguage.named(languageID)
    }

    /// Words for spaced languages, visible characters otherwise.
    public var wordCount: Int {
        if language.spaced {
            return text.split(whereSeparator: { $0.isWhitespace }).count
        }
        return text.reduce(into: 0) { count, character in
            if !character.isWhitespace { count += 1 }
        }
    }

    public func estimatedMinutes(wordsPerMinute: Double = 130) -> Double {
        Double(wordCount) / wordsPerMinute
    }
}
