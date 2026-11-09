import Foundation
import SightlineCore

enum LibraryLocation: Equatable {
    case iCloudDrive
    case documents
    case custom(URL)

    private static let defaultsKey = "libraryLocation"
    private static let folderName = "Sightline Prompter"

    /// Where the first versions kept scripts in iCloud Drive: a plain folder, not the app's container.
    private static var legacyICloudFolder: URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return root.appendingPathComponent(folderName, isDirectory: true)
    }

    private static var documentsRoot: URL {
        // The Documents folder of the app: ~/Documents, or the app's own container when sandboxed (Mac App Store).
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
    }

    /// iCloud Drive (the shared container, or the plain folder of earlier versions) when available, otherwise ~/Documents.
    private static var automatic: LibraryLocation {
        LibraryContainer.documentsURL == nil && legacyICloudFolder == nil ? .documents : .iCloudDrive
    }

    /// Scripts saved by earlier versions are moved into the shared library once per launch.
    private static var adoptedLegacyScripts = false

    /// The default library folder, used when the user has not picked one.
    static func resolve() -> URL {
        automatic.url
    }

    static var current: LibraryLocation {
        get {
            guard let stored = UserDefaults.standard.dictionary(forKey: defaultsKey),
                  let kind = stored["kind"] as? String
            else { return automatic }
            switch kind {
            case "iCloudDrive": return .iCloudDrive
            case "documents": return .documents
            case "custom":
                guard let path = stored["path"] as? String else { return automatic }
                return .custom(URL(fileURLWithPath: path, isDirectory: true))
            default: return automatic
            }
        }
        set {
            var stored: [String: String] = [:]
            switch newValue {
            case .iCloudDrive: stored["kind"] = "iCloudDrive"
            case .documents: stored["kind"] = "documents"
            case .custom(let url):
                stored["kind"] = "custom"
                stored["path"] = url.path
            }
            UserDefaults.standard.set(stored, forKey: defaultsKey)
        }
    }

    /// The folder scripts are stored in. Created on access if missing.
    var url: URL {
        let folder: URL
        switch self {
        case .iCloudDrive:
            if let shared = LibraryContainer.documentsURL {
                folder = shared
                if !Self.adoptedLegacyScripts {
                    Self.adoptedLegacyScripts = true
                    let legacy = [Self.legacyICloudFolder, Self.documentsRoot.appendingPathComponent(Self.folderName, isDirectory: true)]
                    LibraryContainer.adopt(from: legacy.compactMap { $0 }, into: shared)
                }
            } else if let legacy = Self.legacyICloudFolder {
                // No container (a build without the iCloud entitlement): the plain iCloud Drive folder still syncs.
                folder = legacy
            } else {
                folder = Self.documentsRoot.appendingPathComponent(Self.folderName, isDirectory: true)
            }
        case .documents:
            folder = Self.documentsRoot.appendingPathComponent(Self.folderName, isDirectory: true)
        case .custom(let url):
            folder = url
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Human-readable location for the settings UI.
    var displayName: String {
        switch self {
        case .iCloudDrive: return "iCloud Drive (shared with iPhone)"
        case .documents: return "This Mac (Documents)"
        case .custom(let url): return url.lastPathComponent
        }
    }
}
