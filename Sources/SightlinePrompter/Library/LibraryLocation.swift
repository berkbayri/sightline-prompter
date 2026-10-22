import Foundation

enum LibraryLocation: Equatable {
    case iCloudDrive
    case documents
    case custom(URL)

    private static let defaultsKey = "libraryLocation"
    private static let folderName = "Sightline Prompter"

    private static var iCloudDriveRoot: URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return root
    }

    private static var documentsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
    }

    /// iCloud Drive when it is available, otherwise ~/Documents.
    private static var automatic: LibraryLocation {
        iCloudDriveRoot == nil ? .documents : .iCloudDrive
    }

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
            folder = (Self.iCloudDriveRoot ?? Self.documentsRoot)
                .appendingPathComponent(Self.folderName, isDirectory: true)
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
        case .iCloudDrive: return "iCloud Drive"
        case .documents: return "This Mac (Documents)"
        case .custom(let url): return url.lastPathComponent
        }
    }
}
