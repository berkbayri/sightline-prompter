import Foundation
import XCTest
@testable import SightlineCore

final class ScriptImporterTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        try super.tearDownWithError()
    }

    private func writeFile(named name: String, contents: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testPlainTextUsesFileNameAsTitleAndTrimsWhitespace() throws {
        let url = try writeFile(named: "Keynote.txt", contents: "  The quick brown fox jumps over the lazy dog.  \n")

        let imported = try ScriptImporter.importFile(at: url)

        XCTAssertEqual(imported.title, "Keynote")
        XCTAssertEqual(imported.text, "The quick brown fox jumps over the lazy dog.")
        XCTAssertEqual(imported.languageID, "en-US")
    }

    func testUnsupportedExtensionIsRejected() throws {
        let url = try writeFile(named: "notes.xyz", contents: "text")

        XCTAssertThrowsError(try ScriptImporter.importFile(at: url)) { error in
            guard case ScriptImporter.ImportError.unsupportedFormat(let name) = error else {
                return XCTFail("Expected unsupportedFormat, got \(error)")
            }
            XCTAssertEqual(name, "xyz")
        }
    }
}
