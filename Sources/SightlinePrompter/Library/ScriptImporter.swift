import Aligner
import AppKit
import Foundation
import NaturalLanguage
import PDFKit

enum ScriptImporter {
    enum ImportError: LocalizedError {
        case unsupportedFormat(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let extensionName):
                return "Unsupported file type\(extensionName.isEmpty ? "" : ": .\(extensionName)")."
            case .unreadable(let name):
                return "Could not read \(name)."
            }
        }
    }

    /// Reads a document and returns its title (file name without extension), plain text and suggested language.
    /// Must run on the main thread: rich-text and HTML import use AppKit.
    static func importFile(at url: URL) throws -> (title: String, text: String, languageID: String) {
        let title = url.deletingPathExtension().lastPathComponent
        let raw: String

        switch url.pathExtension.lowercased() {
        case "txt", "md", "markdown":
            raw = try readPlainText(url)
        case "rtf":
            raw = try readAttributed(url, type: .rtf)
        case "rtfd":
            raw = try readAttributed(url, type: .rtfd)
        case "html", "htm":
            raw = try readAttributed(url, type: .html)
        case "doc":
            raw = try readAttributed(url, type: .docFormat)
        case "docx":
            raw = try readAttributed(url, type: .officeOpenXML)
        case "odt":
            raw = try readAttributed(url, type: .openDocument)
        case "pdf":
            raw = try readPDF(url)
        case let other:
            throw ImportError.unsupportedFormat(other)
        }

        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, text, suggestedLanguageID(for: text))
    }

    static func exportText(_ script: Script) -> String {
        script.text
    }

    // MARK: - Readers

    private static func readPlainText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let decoded: String?
        if let utf8 = String(data: data, encoding: .utf8) {
            decoded = utf8
        } else if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            decoded = String(data: data, encoding: .utf16)
        } else {
            decoded = String(data: data, encoding: .windowsCP1254)
        }
        if let decoded {
            return stripByteOrderMark(decoded)
        }

        var encoding: String.Encoding = .utf8
        do {
            return stripByteOrderMark(try String(contentsOf: url, usedEncoding: &encoding))
        } catch {
            throw ImportError.unreadable(url.lastPathComponent)
        }
    }

    private static func readAttributed(_ url: URL, type: NSAttributedString.DocumentType) throws -> String {
        do {
            let attributed = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
            // Inline attachments (images) leave object-replacement characters behind.
            return attributed.string.replacingOccurrences(of: "\u{FFFC}", with: "")
        } catch {
            throw ImportError.unreadable(url.lastPathComponent)
        }
    }

    private static func readPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw ImportError.unreadable(url.lastPathComponent)
        }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index)?.string {
                pages.append(page)
            }
        }
        return reflow(pages.joined(separator: "\n"))
    }

    // MARK: - Cleanup

    private static func stripByteOrderMark(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// Turns PDF line breaks into flowing text while keeping blank-line paragraph breaks.
    private static func reflow(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var paragraphs: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty {
                paragraphs.append(current)
                current = ""
            }
        }

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }
            if isPageNumberLine(line) {
                continue
            }
            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-"),
                      let first = line.first, first.isLowercase,
                      let beforeHyphen = current.dropLast().last, beforeHyphen.isLetter {
                current.removeLast()
                current += line
            } else {
                current += " " + line
            }
        }
        flush()
        return paragraphs.joined(separator: "\n\n")
    }

    /// Matches lines such as "12", "- 12 -" or "Page 12" (1 to 3 digits, so years are kept).
    private static func isPageNumberLine(_ line: String) -> Bool {
        var core = line.trimmingCharacters(in: CharacterSet(charactersIn: "-\u{2013}\u{2014} "))
        for prefix in ["page ", "sayfa "] where core.lowercased().hasPrefix(prefix) {
            core = String(core.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return (1...3).contains(core.count) && core.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: - Language

    private static let languageMapping: [NLLanguage: String] = [
        .english: "en-US",
        .simplifiedChinese: "zh-CN",
        .traditionalChinese: "zh-CN",
        .hindi: "hi-IN",
        .spanish: "es-ES",
        .french: "fr-FR",
        .arabic: "ar-SA",
        .portuguese: "pt-BR",
        .russian: "ru-RU",
        .indonesian: "id-ID",
        .japanese: "ja-JP",
        .turkish: "tr-TR",
    ]

    /// Best match among the supported languages, judged on the first 2000 characters.
    static func suggestedLanguageID(for text: String) -> String {
        let sample = String(text.prefix(2000))
        guard !sample.isEmpty else { return "en-US" }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 11)
        for (language, _) in hypotheses.sorted(by: { $0.value > $1.value }) {
            if let identifier = languageMapping[language] {
                return identifier
            }
        }
        return "en-US"
    }
}
