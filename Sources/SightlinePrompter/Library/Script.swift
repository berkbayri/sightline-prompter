import Aligner
import Foundation

struct Script: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var languageID: String
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(
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

    var language: ScriptLanguage {
        ScriptLanguage.named(languageID)
    }

    /// Words for spaced languages, visible characters otherwise.
    var wordCount: Int {
        if language.spaced {
            return text.split(whereSeparator: { $0.isWhitespace }).count
        }
        return text.reduce(into: 0) { count, character in
            if !character.isWhitespace { count += 1 }
        }
    }

    func estimatedMinutes(wordsPerMinute: Double = 130) -> Double {
        Double(wordCount) / wordsPerMinute
    }
}
