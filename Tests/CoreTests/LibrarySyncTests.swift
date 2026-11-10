import XCTest
@testable import SightlineCore

/// What a second device writing into the shared folder looks like from this device.
@MainActor
final class LibrarySyncTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func folder(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRefreshPicksUpScriptsAddedChangedAndRemovedByAnotherDevice() throws {
        let shared = folder("shared")
        let here = LibraryStore(directory: shared)
        let there = LibraryStore(directory: shared)

        let added = there.create(title: "From the other device", language: .named("en-US"), text: "one two three")
        here.refresh()
        XCTAssertEqual(here.scripts.map(\.title), ["From the other device"])

        there.update(added.id, text: "one two three four")
        there.save(there.scripts[0])
        here.refresh()
        XCTAssertEqual(here.scripts.first?.text, "one two three four")

        there.delete(added.id)
        here.refresh()
        XCTAssertTrue(here.scripts.isEmpty)
    }

    func testRelocateSwitchesToTheOtherFolderAndBack() {
        let phone = folder("phone")
        let shared = folder("shared")
        let store = LibraryStore(directory: phone)
        store.create(title: "Local", language: .named("en-US"), text: "local")
        LibraryStore(directory: shared).create(title: "On the Mac", language: .named("en-US"), text: "mac")

        store.relocate(to: shared)
        XCTAssertEqual(store.scripts.map(\.title), ["On the Mac"])
        store.create(title: "New here", language: .named("en-US"), text: "new")
        XCTAssertEqual(Set(LibraryStore(directory: shared).scripts.map(\.title)), ["On the Mac", "New here"])

        store.relocate(to: phone)
        XCTAssertEqual(store.scripts.map(\.title), ["Local"])
    }

    func testNothingIsLostWhenLocalScriptsAreAdoptedBeforeRelocating() {
        let phone = folder("phone")
        let shared = folder("shared")
        LibraryStore(directory: phone).create(title: "Local", language: .named("en-US"), text: "local")
        LibraryStore(directory: shared).create(title: "On the Mac", language: .named("en-US"), text: "mac")

        LibraryContainer.adopt(from: [phone], into: shared)
        let store = LibraryStore(directory: phone)
        store.relocate(to: shared)
        XCTAssertEqual(Set(store.scripts.map(\.title)), ["Local", "On the Mac"])
    }
}
