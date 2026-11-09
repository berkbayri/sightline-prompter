import Foundation

/// The iCloud container both apps keep the script library in, so a script added or edited on the Mac
/// shows up on the iPhone and the other way round. The container's `Documents` folder is shown in
/// iCloud Drive as "Sightline Prompter" (see `NSUbiquitousContainers` in each Info.plist).
public enum LibraryContainer {
    public static let identifier = "iCloud.com.berkbayri.SightlinePrompter"
    /// Name of the folder scripts used to live in (iPhone Documents, Mac iCloud Drive and Documents).
    public static let legacyFolderName = "Sightline Prompter"

    private static let fileExtension = "sightline"

    /// The shared library folder, created if needed. Nil when the container is not available: signed out of
    /// iCloud, iCloud Drive off for the app, or a build signed without the iCloud entitlement (a personal
    /// development team cannot have it). Resolved once per launch, because the first lookup can take a moment.
    public static let documentsURL: URL? = resolveDocuments()

    private static func resolveDocuments() -> URL? {
        let fileManager = FileManager.default
        if fileManager.ubiquityIdentityToken != nil,
           let container = fileManager.url(forUbiquityContainerIdentifier: identifier) {
            return makeFolder(container.appendingPathComponent("Documents", isDirectory: true))
        }
        return nil
    }

    private static func makeFolder(_ url: URL) -> URL? {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            return nil
        }
    }

    /// Moves the scripts found in the old folders into the shared library. A script whose id is already in the
    /// library is left where it is, so nothing is ever overwritten. Returns how many scripts were moved.
    @discardableResult
    public static func adopt(from sources: [URL], into destination: URL) -> Int {
        let fileManager = FileManager.default
        var moved = 0
        for source in sources where source.standardizedFileURL != destination.standardizedFileURL {
            guard let entries = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
                continue
            }
            for entry in entries where entry.pathExtension == fileExtension {
                let target = destination.appendingPathComponent(entry.lastPathComponent)
                guard !fileManager.fileExists(atPath: target.path) else { continue }
                if move(entry, to: target) { moved += 1 }
            }
        }
        return moved
    }

    private static func move(_ source: URL, to target: URL) -> Bool {
        var coordinationError: NSError?
        var moved = false
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: target, options: .forReplacing,
            error: &coordinationError
        ) { from, to in
            do {
                try FileManager.default.moveItem(at: from, to: to)
                moved = true
            } catch {
                moved = false
            }
        }
        return moved && coordinationError == nil
    }
}

#if os(iOS)
/// A folder the user picked in the Files app, remembered across launches. It is how a build without the iCloud
/// entitlement can still share scripts: pick the "Sightline Prompter" folder in iCloud Drive that the Mac uses.
public enum LibraryFolderBookmark {
    private static let key = "libraryFolderBookmark"
    nonisolated(unsafe) private static var accessed: URL?

    /// Remembers a folder returned by the Files picker.
    public static func save(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        UserDefaults.standard.set(try url.bookmarkData(), forKey: key)
    }

    public static func clear() {
        accessed?.stopAccessingSecurityScopedResource()
        accessed = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    public static var isSet: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    /// The remembered folder with access granted for the rest of the process. Nil when none is saved or it is gone.
    public static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        accessed = url
        if stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: key)
        }
        return url
    }
}
#endif
