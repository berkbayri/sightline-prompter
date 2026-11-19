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

    func testStatusTellsSignedOutFromMissingContainer() {
        XCTAssertEqual(LibraryContainer.Status.resolve(hasAccount: false, hasContainer: false), .signedOut)
        XCTAssertEqual(LibraryContainer.Status.resolve(hasAccount: false, hasContainer: true), .signedOut)
        XCTAssertEqual(LibraryContainer.Status.resolve(hasAccount: true, hasContainer: false), .unavailable)
        XCTAssertEqual(LibraryContainer.Status.resolve(hasAccount: true, hasContainer: true), .ready)
    }

    func testOnlyEnforcedBuildsLockTheAppUntilSignedIn() {
        for status in [LibraryContainer.Status.signedOut, .unavailable] {
            XCTAssertTrue(status.blocksUse(enforced: true))
            XCTAssertFalse(status.blocksUse(enforced: false))
        }
        XCTAssertFalse(LibraryContainer.Status.ready.blocksUse(enforced: true))
        // swift test builds Debug: the developer is never locked out.
        XCTAssertFalse(LibraryContainer.Status.isEnforced)
    }

    func testMissingOrIdenticalSourceIsHarmless() throws {
        let shared = try folder("shared")
        XCTAssertEqual(LibraryContainer.adopt(from: [root.appendingPathComponent("nope"), shared], into: shared), 0)
    }

    func testKeepingOriginalsCopiesInsteadOfMoving() throws {
        let old = try folder("old"), shared = try folder("shared")
        let id = UUID().uuidString
        try Data("a".utf8).write(to: old.appendingPathComponent("\(id).sightline"))
        XCTAssertEqual(LibraryContainer.adopt(from: [old], into: shared, keepOriginals: true), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shared.appendingPathComponent("\(id).sightline").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("\(id).sightline").path))
    }

    func testSnapshotKeepsADatedCopyOncePerDayAndPrunesOldOnes() throws {
        let library = try folder("lib"), backups = try folder("backups")
        try Data("a".utf8).write(to: library.appendingPathComponent("\(UUID().uuidString).sightline"))
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNotNil(LibraryContainer.snapshot(of: library, into: backups, keep: 2, now: day))
        XCTAssertNil(LibraryContainer.snapshot(of: library, into: backups, keep: 2, now: day), "second snapshot the same day")
        for n in 1...3 { LibraryContainer.snapshot(of: library, into: backups, keep: 2, now: day.addingTimeInterval(Double(n) * 86_400)) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 2)
    }

    func testAnEmptyLibraryIsNeverSnapshotted() throws {
        XCTAssertNil(LibraryContainer.snapshot(of: try folder("empty"), into: try folder("backups")))
    }
}
