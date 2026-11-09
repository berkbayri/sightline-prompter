import XCTest
@testable import SightlineCore

final class LibraryContainerTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testOldScriptsMoveIntoTheSharedLibrary() throws {
        let old = try folder("old"), shared = try folder("shared")
        let id = UUID().uuidString
        try Data("a".utf8).write(to: old.appendingPathComponent("\(id).sightline"))
        try Data("x".utf8).write(to: old.appendingPathComponent("notes.txt"))

        XCTAssertEqual(LibraryContainer.adopt(from: [old], into: shared), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shared.appendingPathComponent("\(id).sightline").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.appendingPathComponent("\(id).sightline").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("notes.txt").path))
    }

    func testAScriptAlreadyInTheSharedLibraryIsNeverOverwritten() throws {
        let old = try folder("old"), shared = try folder("shared")
        let name = "\(UUID().uuidString).sightline"
        try Data("old".utf8).write(to: old.appendingPathComponent(name))
        try Data("new".utf8).write(to: shared.appendingPathComponent(name))

        XCTAssertEqual(LibraryContainer.adopt(from: [old], into: shared), 0)
        XCTAssertEqual(try String(contentsOf: shared.appendingPathComponent(name), encoding: .utf8), "new")
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent(name).path))
    }

    func testMissingOrIdenticalSourceIsHarmless() throws {
        let shared = try folder("shared")
        XCTAssertEqual(LibraryContainer.adopt(from: [root.appendingPathComponent("nope"), shared], into: shared), 0)
    }
}
