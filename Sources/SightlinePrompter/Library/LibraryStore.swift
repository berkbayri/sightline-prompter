import Aligner
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var scripts: [Script] = []
    @Published private(set) var lastError: String?

    let directory: URL

    private static let fileExtension = "sightline"
    private static let saveDelay: UInt64 = 500_000_000
    private static let reloadDelay: UInt64 = 300_000_000
    private static let downloadPollDelay: UInt64 = 4_000_000_000
    private static let maxDownloadPolls = 30

    private var pendingSaves: [UUID: Task<Void, Never>] = [:]
    /// Scripts whose last write failed; kept in memory so a reload does not drop them.
    private var failedSaves: Set<UUID> = []
    private var reloadTask: Task<Void, Never>?
    private var downloadPollTask: Task<Void, Never>?
    private var downloadPolls = 0
    private var watcher: DispatchSourceFileSystemObject?

    init(directory: URL? = nil) {
        let folder = directory ?? LibraryLocation.current.url
        self.directory = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
        startWatching()
    }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Self.fileExtension)")
    }

    func load() {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        let names = Set(entries.map(\.lastPathComponent))

        var loaded: [Script] = []
        var knownIDs: Set<UUID> = []
        var failures: [String] = []
        var placeholders = 0

        for entry in entries {
            let name = entry.lastPathComponent
            if let id = Self.scriptID(fromFileName: name) {
                knownIDs.insert(id)
                do {
                    loaded.append(try read(entry))
                } catch {
                    failures.append("\(name): \(error.localizedDescription)")
                }
            } else if let realName = Self.fileName(forPlaceholder: name),
                      let id = Self.scriptID(fromFileName: realName) {
                knownIDs.insert(id)
                if !names.contains(realName) {
                    placeholders += 1
                    try? fileManager.startDownloadingUbiquitousItem(
                        at: directory.appendingPathComponent(realName)
                    )
                }
            }
        }

        let current = Dictionary(scripts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged = loaded.map { onDisk -> Script in
            guard let inMemory = current[onDisk.id] else { return onDisk }
            if hasUnsavedChanges(onDisk.id) || inMemory.updatedAt >= onDisk.updatedAt {
                return inMemory
            }
            return onDisk
        }
        let mergedIDs = Set(merged.map(\.id))
        for inMemory in scripts where !mergedIDs.contains(inMemory.id) {
            if knownIDs.contains(inMemory.id) || hasUnsavedChanges(inMemory.id) {
                merged.append(inMemory)
            }
        }
        merged.sort { $0.updatedAt > $1.updatedAt }
        if merged != scripts {
            scripts = merged
        }

        if !failures.isEmpty {
            lastError = failures.joined(separator: "\n")
        } else if failedSaves.isEmpty {
            lastError = nil
        }

        if placeholders > 0 {
            scheduleDownloadPoll()
        } else {
            downloadPolls = 0
        }
    }

    /// Writes the script to disk and keeps the in-memory copy in sync.
    func save(_ script: Script) {
        pendingSaves[script.id]?.cancel()
        pendingSaves[script.id] = nil
        do {
            try write(script)
            failedSaves.remove(script.id)
            lastError = failedSaves.isEmpty ? nil : lastError
        } catch {
            failedSaves.insert(script.id)
            lastError = "Could not save \"\(script.title)\": \(error.localizedDescription)"
        }
        upsert(script)
    }

    @discardableResult
    func create(title: String = "Untitled", language: ScriptLanguage, text: String = "") -> Script {
        let now = Date()
        let script = Script(
            title: title,
            languageID: language.id,
            text: text,
            createdAt: now,
            updatedAt: now
        )
        save(script)
        return script
    }

    func delete(_ id: UUID) {
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil
        failedSaves.remove(id)
        scripts.removeAll { $0.id == id }

        let fileManager = FileManager.default
        for url in [fileURL(for: id), placeholderURL(for: id)] where fileManager.fileExists(atPath: url.path) {
            do {
                try trash(url)
            } catch {
                lastError = "Could not move \"\(url.lastPathComponent)\" to the Trash: \(error.localizedDescription)"
            }
        }
    }

    func rename(_ id: UUID, to title: String) {
        update(id, title: title)
    }

    @discardableResult
    func duplicate(_ id: UUID) -> Script? {
        guard let original = scripts.first(where: { $0.id == id }) else { return nil }
        let now = Date()
        let copy = Script(
            title: original.title + " copy",
            languageID: original.languageID,
            text: original.text,
            createdAt: now,
            updatedAt: now
        )
        save(copy)
        return copy
    }

    /// Applies the changed fields in memory and schedules a debounced save.
    func update(_ id: UUID, text: String? = nil, title: String? = nil, languageID: String? = nil) {
        guard var script = scripts.first(where: { $0.id == id }) else { return }
        var changed = false
        if let text, text != script.text {
            script.text = text
            changed = true
        }
        if let title, title != script.title {
            script.title = title
            changed = true
        }
        if let languageID, languageID != script.languageID {
            script.languageID = languageID
            changed = true
        }
        guard changed else { return }

        script.updatedAt = Date()
        upsert(script)
        scheduleSave(id)
    }

    // MARK: - Persistence

    private func scheduleSave(_ id: UUID) {
        pendingSaves[id]?.cancel()
        pendingSaves[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            self.pendingSaves[id] = nil
            if let script = self.scripts.first(where: { $0.id == id }) {
                self.save(script)
            }
        }
    }

    private func hasUnsavedChanges(_ id: UUID) -> Bool {
        pendingSaves[id] != nil || failedSaves.contains(id)
    }

    private func upsert(_ script: Script) {
        if let index = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts[index] = script
        } else {
            scripts.append(script)
        }
        scripts.sort { $0.updatedAt > $1.updatedAt }
    }

    private func write(_ script: Script) throws {
        let data = try ScriptFile.encoder.encode(script)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: fileURL(for: script.id),
            options: .forReplacing,
            error: &coordinationError
        ) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError {
            throw error
        }
    }

    private func read(_ url: URL) throws -> Script {
        var coordinationError: NSError?
        var data: Data?
        var readError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                data = try Data(contentsOf: coordinatedURL)
            } catch {
                readError = error
            }
        }
        if let error = coordinationError ?? readError {
            throw error
        }
        guard let data else { throw CocoaError(.fileReadUnknown) }
        return try ScriptFile.decoder.decode(Script.self, from: data)
    }

    private func trash(_ url: URL) throws {
        var coordinationError: NSError?
        var trashError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try FileManager.default.trashItem(at: coordinatedURL, resultingItemURL: nil)
            } catch {
                trashError = error
            }
        }
        if let error = coordinationError ?? trashError {
            throw error
        }
    }

    // MARK: - iCloud placeholders

    private func placeholderURL(for id: UUID) -> URL {
        directory.appendingPathComponent(".\(fileURL(for: id).lastPathComponent).icloud")
    }

    /// ".<uuid>.sightline.icloud" -> "<uuid>.sightline"
    private static func fileName(forPlaceholder name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".\(fileExtension).icloud") else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    private static func scriptID(fromFileName name: String) -> UUID? {
        let suffix = ".\(fileExtension)"
        guard name.hasSuffix(suffix) else { return nil }
        return UUID(uuidString: String(name.dropLast(suffix.count)))
    }

    private func scheduleDownloadPoll() {
        guard downloadPollTask == nil, downloadPolls < Self.maxDownloadPolls else { return }
        downloadPolls += 1
        downloadPollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.downloadPollDelay)
            guard let self else { return }
            self.downloadPollTask = nil
            self.load()
        }
    }

    // MARK: - Directory watching

    /// Reloads when files appear, change or disappear, e.g. when iCloud syncs another Mac's edits.
    private func startWatching() {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.reloadDelay)
            guard !Task.isCancelled, let self else { return }
            self.load()
        }
    }
}

/// On-disk JSON format: ISO 8601 dates with fractional seconds, so a reload
/// compares the same updatedAt values that were written.
private enum ScriptFile {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, out in
            var container = out.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: text) ?? plainFormatter.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(text)"
            )
        }
        return decoder
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter = ISO8601DateFormatter()
}
