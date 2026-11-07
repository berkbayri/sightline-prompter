import Aligner
import Foundation
import XCTest
@testable import SightlineCore

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    func testScriptSurvivesAReload() {
        let store = LibraryStore(directory: folder)
        let created = store.create(title: "Talk", language: .named("en-US"), text: "Hello there")

        let reloaded = LibraryStore(directory: folder)

        XCTAssertEqual(reloaded.scripts.count, 1)
        XCTAssertEqual(reloaded.scripts.first?.id, created.id)
        XCTAssertEqual(reloaded.scripts.first?.text, "Hello there")
        XCTAssertEqual(reloaded.scripts.first?.languageID, "en-US")
    }

    func testFileNameIsTheScriptIdentifier() {
        let store = LibraryStore(directory: folder)
        let script = store.create(title: "Talk", language: .named("en-US"))

        let expected = folder.appendingPathComponent("\(script.id.uuidString).sightline")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    }
}
