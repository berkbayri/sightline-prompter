import Aligner
import Foundation

/// Keeps one `.sightline` JSON file per script in a folder, and mirrors the folder in memory.
@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var scripts: [Script] = []
    @Published public private(set) var lastError: String?

    public private(set) var directory: URL

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
    private var pollTask: Task<Void, Never>?
    private var presenter: FolderPresenter?
    private var lastSignature = ""
    /// How often the folder is checked for changes made by another device. iCloud does not always raise file
    /// events for files it brings in, so the folder is also polled.
    private static let pollDelay: UInt64 = 2_000_000_000
    /// Every this many polls the folder is read in full even if its listing looks unchanged: a file iCloud is still
    /// bringing in can keep its old size and date until it is read.
    private static let fullReloadEvery = 4

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        startWatching()
        startPolling()
        startPresenting()
    }

    /// Points the library at another folder (for example the iCloud Drive folder shared with the Mac) without a
    /// restart. Scripts in the old folder are not touched; the caller moves them first if they should come along.
    public func relocate(to newDirectory: URL) {
        guard newDirectory.standardizedFileURL != directory.standardizedFileURL else { return }
        for task in pendingSaves.values { task.cancel() }
        pendingSaves = [:]
        failedSaves = []
        reloadTask?.cancel()
        downloadPollTask?.cancel()
        watcher?.cancel()
        watcher = nil
        stopPresenting()
        directory = newDirectory
        try? FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        scripts = []
        lastSignature = ""
        load()
        startWatching()
        startPresenting()
    }

    /// Registers as a file presenter of the folder, so the system tells this store when another process or iCloud
    /// changes, adds or removes a script, even when no file event reaches the directory watcher.
    private func startPresenting() {
        let presenter = FolderPresenter(url: directory)
        presenter.onChange = { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        NSFileCoordinator.addFilePresenter(presenter)
        self.presenter = presenter
    }

    private func stopPresenting() {
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        presenter = nil
    }

    /// Writes every script in the folder again, through file coordination. Files that reached a shared iCloud
    /// folder without being written by this app (moved in, or put there by an earlier build) are then noticed by
    /// iCloud and uploaded.
    public func republishAll() {
        for script in scripts {
            try? write(script)
        }
    }

    /// Reloads if anything in the folder changed. Cheap enough to call on every app activation.
    public func refresh() {
        let signature = folderSignature()
        guard signature != lastSignature else { return }
        load()
    }

    private func folderSignature() -> String {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [])) ?? []
        return entries
            .map { url -> String in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let time = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                return "\(url.lastPathComponent)|\(time)|\(values?.fileSize ?? 0)"
            }
            .sorted()
            .joined(separator: "\n")
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollDelay)
                guard let self, !Task.isCancelled else { return }
                ticks += 1
                if ticks % Self.fullReloadEvery == 0 {
                    self.load()
                } else {
                    self.refresh()
                }
            }
        }
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Self.fileExtension)")
    }

    public func load() {
        defer { logSync() }
        lastSignature = folderSignature()
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
    public func save(_ script: Script) {
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
    public func create(title: String = "Untitled", language: ScriptLanguage, text: String = "") -> Script {
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

    /// Removes the script file. macOS moves it to the Trash; iOS has no Trash for app files, so it is deleted.
    public func delete(_ id: UUID) {
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil
        failedSaves.remove(id)
        scripts.removeAll { $0.id == id }

        let fileManager = FileManager.default
        for url in [fileURL(for: id), placeholderURL(for: id)] where fileManager.fileExists(atPath: url.path) {
            do {
                try discard(url)
            } catch {
                lastError = "Could not remove \"\(url.lastPathComponent)\": \(error.localizedDescription)"
            }
        }
    }

    public func rename(_ id: UUID, to title: String) {
        update(id, title: title)
    }

    @discardableResult
    public func duplicate(_ id: UUID) -> Script? {
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
    public func update(_ id: UUID, text: String? = nil, title: String? = nil, languageID: String? = nil) {
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

    private func discard(_ url: URL) throws {
        var coordinationError: NSError?
        var discardError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                #if os(macOS)
                try FileManager.default.trashItem(at: coordinatedURL, resultingItemURL: nil)
                #else
                try FileManager.default.removeItem(at: coordinatedURL)
                #endif
            } catch {
                discardError = error
            }
        }
        if let error = coordinationError ?? discardError {
            throw error
        }
    }

    // MARK: - Sync log (debug builds)

    /// Debug builds keep a short log of what each reload found, in Caches/sync.log, to see why a change from the
    /// other device did or did not arrive.
    private func logSync() {
        #if DEBUG
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let url = caches.appendingPathComponent("sync.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let newest = scripts.map(\.updatedAt).max().map { ISO8601DateFormatter().string(from: $0) } ?? "-"
        let line = "\(stamp) dir=\(directory.lastPathComponent) scripts=\(scripts.count) newestUpdate=\(newest)\n"
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        text += line
        if text.utf8.count > 20_000 { text = String(text.suffix(10_000)) }
        try? text.write(to: url, atomically: true, encoding: .utf8)
        #endif
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

/// Tells the store when the system sees a change in the library folder.
private final class FolderPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    var onChange: (() -> Void)?

    init(url: URL) {
        presentedItemURL = url
        super.init()
    }

    func presentedItemDidChange() { onChange?() }
    func presentedSubitemDidAppear(at url: URL) { onChange?() }
    func presentedSubitemDidChange(at url: URL) { onChange?() }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
        onChange?()
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
