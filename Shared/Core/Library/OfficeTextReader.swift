import Compression
import Foundation

/// Reads the text of .docx and .odt files. Both are zip archives holding XML, so the reader needs no
/// AppKit: it runs on iOS, where NSAttributedString cannot open these formats.
enum OfficeTextReader {
    enum Format {
        case wordprocessing, opendocument

        /// The XML part that holds the document body.
        var entryName: String {
            switch self {
            case .wordprocessing: "word/document.xml"
            case .opendocument: "content.xml"
            }
        }
    }

    enum ReadError: Error {
        case notAZipArchive
        case entryNotFound(String)
        case unsupportedCompression(Int)
        case corrupt
        case invalidXML
    }

    /// Paragraphs are joined with newlines, so blank paragraphs become the blank lines that separate
    /// paragraphs in ScriptTokenizer.
    static func text(at url: URL, format: Format) throws -> String {
        let archive = try Data(contentsOf: url)
        let xml = try ZipEntryReader.entry(named: format.entryName, in: archive)
        let delegate = OfficeXMLDelegate(format: format)
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse() else { throw ReadError.invalidXML }
        return delegate.paragraphs.joined(separator: "\n")
    }
}

/// Finds one entry in a zip archive by name, using the central directory.
enum ZipEntryReader {
    private static let endOfCentralDirectory = 0x0605_4b50
    private static let centralHeader = 0x0201_4b50
    private static let localHeader = 0x0403_4b50

    static func entry(named name: String, in archive: Data) throws -> Data {
        let bytes = [UInt8](archive)
        guard let end = endOfCentralDirectoryOffset(in: bytes) else {
            throw OfficeTextReader.ReadError.notAZipArchive
        }

        let count = try uint16(bytes, end + 10)
        var offset = try uint32(bytes, end + 16)
        for _ in 0..<count {
            guard try uint32(bytes, offset) == centralHeader else {
                throw OfficeTextReader.ReadError.corrupt
            }
            let method = try uint16(bytes, offset + 10)
            let compressedSize = try uint32(bytes, offset + 20)
            let uncompressedSize = try uint32(bytes, offset + 24)
            let nameLength = try uint16(bytes, offset + 28)
            let extraLength = try uint16(bytes, offset + 30)
            let commentLength = try uint16(bytes, offset + 32)
            let localOffset = try uint32(bytes, offset + 42)

            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else { throw OfficeTextReader.ReadError.corrupt }
            let entryName = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            if entryName == name {
                return try localData(
                    in: bytes,
                    at: localOffset,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize
                )
            }
            offset = nameStart + nameLength + extraLength + commentLength
        }
        throw OfficeTextReader.ReadError.entryNotFound(name)
    }

    /// The end record sits within the last 64 KiB, after an optional comment.
    private static func endOfCentralDirectoryOffset(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        var index = bytes.count - 22
        while index >= lowest {
            if (try? uint32(bytes, index)) == endOfCentralDirectory {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func localData(
        in bytes: [UInt8],
        at localOffset: Int,
        method: Int,
        compressedSize: Int,
        uncompressedSize: Int
    ) throws -> Data {
        guard try uint32(bytes, localOffset) == localHeader else {
            throw OfficeTextReader.ReadError.corrupt
        }
        let nameLength = try uint16(bytes, localOffset + 26)
        let extraLength = try uint16(bytes, localOffset + 28)
        let start = localOffset + 30 + nameLength + extraLength
        guard start + compressedSize <= bytes.count else { throw OfficeTextReader.ReadError.corrupt }
        let payload = Data(bytes[start..<(start + compressedSize)])

        switch method {
        case 0:
            return payload
        case 8:
            return try inflate(payload, expectedSize: uncompressedSize)
        default:
            throw OfficeTextReader.ReadError.unsupportedCompression(method)
        }
    }

    /// Raw DEFLATE, the method zip uses for compressed entries.
    private static func inflate(_ payload: Data, expectedSize: Int) throws -> Data {
        guard !payload.isEmpty, expectedSize > 0 else { throw OfficeTextReader.ReadError.corrupt }
        var output = [UInt8](repeating: 0, count: expectedSize)
        let written = payload.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
            output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
                compression_decode_buffer(
                    destination.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    destination.count,
                    source.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw OfficeTextReader.ReadError.corrupt }
        return Data(output.prefix(written))
    }

    private static func uint16(_ bytes: [UInt8], _ index: Int) throws -> Int {
        guard index >= 0, index + 2 <= bytes.count else { throw OfficeTextReader.ReadError.corrupt }
        return Int(bytes[index]) | Int(bytes[index + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], _ index: Int) throws -> Int {
        guard index >= 0, index + 4 <= bytes.count else { throw OfficeTextReader.ReadError.corrupt }
        return Int(bytes[index])
            | Int(bytes[index + 1]) << 8
            | Int(bytes[index + 2]) << 16
            | Int(bytes[index + 3]) << 24
    }
}

/// Collects paragraph text from document.xml (Word) or content.xml (OpenDocument).
private final class OfficeXMLDelegate: NSObject, XMLParserDelegate {
    private let format: OfficeTextReader.Format
    private(set) var paragraphs: [String] = []
    private var current = ""
    /// Inside a text run (Word w:t) or a paragraph (OpenDocument text:p / text:h).
    private var collecting = false

    init(format: OfficeTextReader.Format) {
        self.format = format
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch (format, elementName) {
        case (.wordprocessing, "w:t"):
            collecting = true
        case (.wordprocessing, "w:tab"):
            current += "\t"
        case (.wordprocessing, "w:br"):
            current += "\n"
        case (.opendocument, "text:p"), (.opendocument, "text:h"):
            collecting = true
        case (.opendocument, "text:s"):
            let count = Int(attributeDict["text:c"] ?? "1") ?? 1
            current += String(repeating: " ", count: max(count, 1))
        case (.opendocument, "text:tab"):
            current += "\t"
        case (.opendocument, "text:line-break"):
            current += "\n"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch (format, elementName) {
        case (.wordprocessing, "w:t"):
            collecting = false
        case (.wordprocessing, "w:p"):
            paragraphs.append(current)
            current = ""
        case (.opendocument, "text:p"), (.opendocument, "text:h"):
            paragraphs.append(current)
            current = ""
            collecting = false
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting {
            current += string
        }
    }
}
