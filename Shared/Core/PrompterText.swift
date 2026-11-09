import Aligner
import Foundation

#if canImport(AppKit)
import AppKit
public typealias PrompterFont = NSFont
public typealias PrompterColor = NSColor
#else
import UIKit
public typealias PrompterFont = UIFont
public typealias PrompterColor = UIColor
#endif

/// Builds the attributed text both prompters draw: the spoken words, plus the `[[delivery cues]]` of the
/// script in their own style. Word indices are those of `ScriptTokenizer`, so cues never shift them.
/// This is the one place the layout of words and cues is decided, for the Mac and the iPhone alike.
public enum PrompterText {
    public struct Word {
        public let range: NSRange
        public let paragraph: Int
    }

    public struct CueRun {
        public let range: NSRange
        /// Number of spoken words before the cue. The cue counts as read once the cursor is past them.
        public let wordsBefore: Int
        public let standalone: Bool
    }

    public struct Result {
        public let attributed: NSAttributedString
        public let words: [Word]
        public let cues: [CueRun]
        /// Index of the first word of each paragraph, in paragraph order.
        public let paragraphStarts: [Int]
    }

    // MARK: - Cue appearance

    private static let cueRGB: (CGFloat, CGFloat, CGFloat) = (0.45, 0.80, 1.0)
    /// Cue text is smaller than the script, so it reads as a note and not as something to say.
    private static let cueSizeRatio: CGFloat = 0.62

    public static func cueColor(wordsBefore: Int, cursor: Int) -> PrompterColor {
        PrompterColor(red: cueRGB.0, green: cueRGB.1, blue: cueRGB.2, alpha: wordsBefore < cursor ? 0.35 : 0.95)
    }

    public static func cueBackground(wordsBefore: Int, cursor: Int) -> PrompterColor {
        PrompterColor(red: cueRGB.0, green: cueRGB.1, blue: cueRGB.2, alpha: wordsBefore < cursor ? 0.06 : 0.16)
    }

    // MARK: - Build

    public static func build(
        script: String,
        language: ScriptLanguage,
        fontSize: CGFloat,
        cursor: Int,
        wordColor: (Int) -> PrompterColor
    ) -> Result {
        let parsed = ScriptTokenizer.parse(script, language: language)
        let tokens = parsed.tokens

        let font = PrompterFont.systemFont(ofSize: fontSize, weight: .semibold)
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.35
        style.paragraphSpacing = fontSize * 0.8
        style.lineBreakMode = .byWordWrapping
        style.baseWritingDirection = language.rightToLeft ? .rightToLeft : .natural
        style.alignment = language.rightToLeft ? .right : .left

        let cueFont = italic(PrompterFont.systemFont(ofSize: fontSize * cueSizeRatio, weight: .medium))
        let cueBlockStyle = NSMutableParagraphStyle()
        cueBlockStyle.lineHeightMultiple = 1.25
        cueBlockStyle.paragraphSpacing = fontSize * 0.55
        cueBlockStyle.lineBreakMode = .byWordWrapping
        cueBlockStyle.baseWritingDirection = style.baseWritingDirection
        cueBlockStyle.alignment = style.alignment

        let separatorAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: style,
            .foregroundColor: PrompterColor(white: 1, alpha: 0.95),
        ]
        let spacer = language.spaced ? " " : ""

        let text = NSMutableAttributedString()
        var words: [Word] = []
        var cues: [CueRun] = []
        var starts: [Int] = []
        var lastWordParagraph: Int?
        /// Paragraph of the text built so far; nil right after a standalone cue.
        var openParagraph: Int?

        func endsWithNewline() -> Bool {
            text.length == 0 || (text.string as NSString).character(at: text.length - 1) == 10
        }

        for element in parsed.elements {
            switch element {
            case .word(let index):
                let token = tokens[index]
                if lastWordParagraph != token.paragraph {
                    starts.append(index)
                }
                if openParagraph != token.paragraph {
                    if !endsWithNewline() {
                        text.append(NSAttributedString(string: "\n", attributes: separatorAttributes))
                    }
                } else if !spacer.isEmpty, !endsWithNewline() {
                    text.append(NSAttributedString(string: spacer, attributes: separatorAttributes))
                }
                let range = NSRange(location: text.length, length: token.display.utf16.count)
                text.append(NSAttributedString(string: token.display, attributes: [
                    .font: font,
                    .paragraphStyle: style,
                    .foregroundColor: wordColor(index),
                ]))
                words.append(Word(range: range, paragraph: token.paragraph))
                lastWordParagraph = token.paragraph
                openParagraph = token.paragraph

            case .cue(let cue) where cue.standalone:
                if !endsWithNewline() {
                    text.append(NSAttributedString(string: "\n", attributes: separatorAttributes))
                }
                let range = NSRange(location: text.length, length: cue.text.utf16.count + 2)
                text.append(NSAttributedString(string: "\u{00A0}\(cue.text)\u{00A0}", attributes: [
                    .font: cueFont,
                    .paragraphStyle: cueBlockStyle,
                    .foregroundColor: cueColor(wordsBefore: words.count, cursor: cursor),
                    .backgroundColor: cueBackground(wordsBefore: words.count, cursor: cursor),
                ]))
                text.append(NSAttributedString(string: "\n", attributes: [
                    .font: cueFont,
                    .paragraphStyle: cueBlockStyle,
                ]))
                cues.append(CueRun(range: range, wordsBefore: words.count, standalone: true))
                openParagraph = nil

            case .cue(let cue):
                if let open = openParagraph, open != cue.paragraph, !endsWithNewline() {
                    // The cue opens a new paragraph that its words continue.
                    text.append(NSAttributedString(string: "\n", attributes: separatorAttributes))
                } else if openParagraph != nil, !spacer.isEmpty, !endsWithNewline() {
                    text.append(NSAttributedString(string: spacer, attributes: separatorAttributes))
                }
                let range = NSRange(location: text.length, length: cue.text.utf16.count + 2)
                text.append(NSAttributedString(string: "\u{00A0}\(cue.text)\u{00A0}", attributes: [
                    .font: cueFont,
                    .paragraphStyle: style,
                    .foregroundColor: cueColor(wordsBefore: words.count, cursor: cursor),
                    .backgroundColor: cueBackground(wordsBefore: words.count, cursor: cursor),
                ]))
                cues.append(CueRun(range: range, wordsBefore: words.count, standalone: false))
                openParagraph = cue.paragraph
            }
        }

        return Result(attributed: text, words: words, cues: cues, paragraphStarts: starts)
    }

    private static func italic(_ font: PrompterFont) -> PrompterFont {
        #if canImport(AppKit)
        let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
        return PrompterFont(descriptor: descriptor, size: font.pointSize) ?? font
        #else
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) else { return font }
        return PrompterFont(descriptor: descriptor, size: font.pointSize)
        #endif
    }
}
