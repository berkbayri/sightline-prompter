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
    public static var documentsURL: URL? {
        if resolvedDocuments == nil { resolvedDocuments = resolveDocuments() }
        return resolvedDocuments
    }

    /// Cached once found. Looked up again while missing, so signing in to iCloud while the app runs is noticed.
    nonisolated(unsafe) private static var resolvedDocuments: URL?

    private static func resolveDocuments() -> URL? {
        let fileManager = FileManager.default
        if fileManager.ubiquityIdentityToken != nil,
           let container = fileManager.url(forUbiquityContainerIdentifier: identifier) {
            return makeFolder(container.appendingPathComponent("Documents", isDirectory: true))
        }
        return nil
    }

    /// Whether the script library can sync through iCloud right now. Read fresh each time, so Settings shows the
    /// state after the user signs in; `documentsURL` itself stays resolved once per launch.
    public enum Status: Equatable {
        /// Signed in and the container is reachable.
        case ready
        /// No iCloud account, or iCloud Drive is off: the user has to sign in.
        case signedOut
        /// Signed in, but this build cannot reach the container (no iCloud entitlement).
        case unavailable

        /// App Store builds need an iCloud account to be used at all. Debug and developer builds never ask for one,
        /// because a personal development team cannot sign the iCloud entitlement.
        public static let isEnforced: Bool = {
            #if DEBUG || SIGHTLINE_DEV
            false
            #else
            true
            #endif
        }()

        /// True when the app must stay locked behind the sign-in screen.
        public func blocksUse(enforced: Bool = Status.isEnforced) -> Bool {
            enforced && self != .ready
        }

        public static func resolve(hasAccount: Bool, hasContainer: Bool) -> Status {
            guard hasAccount else { return .signedOut }
            return hasContainer ? .ready : .unavailable
        }

        public static var current: Status {
            resolve(hasAccount: FileManager.default.ubiquityIdentityToken != nil, hasContainer: documentsURL != nil)
        }
    }

    /// True for the container's Documents folder, which iCloud Drive lists as "Sightline Prompter".
    public static func isContainerDocuments(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasSuffix("/" + identifier.replacingOccurrences(of: ".", with: "~") + "/Documents")
    }

    /// A "Sightline Prompter" folder inside the library, left by a build that nested the library one level down.
    public static func nestedFolder(in library: URL) -> URL {
        library.appendingPathComponent(legacyFolderName, isDirectory: true)
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
    /// With `keepOriginals` the source files stay where they are (recovery from a folder the user still owns).
    @discardableResult
    public static func adopt(from sources: [URL], into destination: URL, keepOriginals: Bool = false) -> Int {
        let fileManager = FileManager.default
        var moved = 0
        for source in sources where source.standardizedFileURL != destination.standardizedFileURL {
            guard let entries = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
                continue
            }
            for entry in entries where entry.pathExtension == fileExtension {
                let target = destination.appendingPathComponent(entry.lastPathComponent)
                guard !fileManager.fileExists(atPath: target.path) else { continue }
                if move(entry, to: target, keepOriginal: keepOriginals) { moved += 1 }
            }
        }
        return moved
    }

    /// A dated copy of every script in the library, kept next to the app's own files (Files app > Sightline
    /// Prompter > Sightline Backups). One snapshot per day, the newest `keep` are kept. This is the net under every
    /// move, sync or update: whatever happens to the library folder, yesterday's scripts are still on the device.
    /// Returns the snapshot folder when one was made.
    @discardableResult
    public static func snapshot(of library: URL, into backups: URL, keep: Int = 7, now: Date = Date()) -> URL? {
        let fileManager = FileManager.default
        let scripts = ((try? fileManager.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == fileExtension }
        guard !scripts.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let folder = backups.appendingPathComponent(formatter.string(from: now), isDirectory: true)
        guard !fileManager.fileExists(atPath: folder.path) else { return nil }
        do { try fileManager.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return nil }
        var copied = 0
        for script in scripts {
            if (try? fileManager.copyItem(at: script, to: folder.appendingPathComponent(script.lastPathComponent))) != nil {
                copied += 1
            }
        }
        guard copied > 0 else { try? fileManager.removeItem(at: folder); return nil }
        let old = ((try? fileManager.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(keep)
        for url in old { try? fileManager.removeItem(at: url) }
        return folder
    }

    /// Copies the file into the destination through file coordination (so iCloud notices the new file), and only
    /// removes the original once the copy is there. A plain move can leave the file where iCloud never sees it.
    private static func move(_ source: URL, to target: URL, keepOriginal: Bool = false) -> Bool {
        var readError: NSError?
        var data: Data?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: [], error: &readError) { url in
            data = try? Data(contentsOf: url)
        }
        guard readError == nil, let data else { return false }

        var writeError: NSError?
        var written = false
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: target, options: .forReplacing, error: &writeError) { url in
            do {
                try data.write(to: url, options: .atomic)
                written = true
            } catch {
                written = false
            }
        }
        guard writeError == nil, written, FileManager.default.fileExists(atPath: target.path) else { return false }

        guard !keepOriginal else { return true }
        var removeError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: source, options: .forDeleting, error: &removeError) { url in
            try? FileManager.default.removeItem(at: url)
        }
        return true
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
        // The library is always the folder named "Sightline Prompter": the one picked, or inside the one picked
        // (iCloud Drive itself), so the phone and the Mac end up in the same place.
        // The folder iCloud Drive shows as "Sightline Prompter" is the container's own Documents folder, which is
        // already the library.
        guard url.lastPathComponent != LibraryContainer.legacyFolderName, !LibraryContainer.isContainerDocuments(url)
        else { return url }
        let folder = url.appendingPathComponent(LibraryContainer.legacyFolderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }
}
#endif
