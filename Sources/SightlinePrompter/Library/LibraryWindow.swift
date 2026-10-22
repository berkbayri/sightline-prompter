import Aligner
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    let onActivate: (Script) -> Void

    @State private var selection: UUID?
    @State private var searchText = ""
    @State private var draftTitle = ""
    @State private var draftText = ""
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument = TextExportDocument(text: "")
    @State private var exportName = "Script"
    @State private var confirmingDelete = false
    @State private var importMessage: String?
    @State private var isDropTargeted = false

    private static let importTypes: [UTType] = {
        var types: [UTType] = [.plainText, .rtf, .rtfd, .html, .pdf]
        for fileExtension in ["md", "markdown", "doc", "docx", "odt"] {
            if let type = UTType(filenameExtension: fileExtension) {
                types.append(type)
            }
        }
        return types
    }()

    init(store: LibraryStore, onActivate: @escaping (Script) -> Void) {
        _store = ObservedObject(wrappedValue: store)
        self.onActivate = onActivate
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            detail
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: Self.importTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: exportName
        ) { result in
            if case .failure(let error) = result {
                importMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Move this script to the Trash?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The script file is moved to the Trash.")
        }
        .alert("Something went wrong", isPresented: alertBinding) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .onAppear {
            if selection == nil {
                selection = store.scripts.first?.id
            }
            loadDrafts()
        }
        .onChange(of: selection) { _, _ in
            loadDrafts()
        }
        .onChange(of: draftTitle) { _, newValue in
            if let id = selection {
                store.update(id, title: newValue)
            }
        }
        .onChange(of: draftText) { _, newValue in
            if let id = selection {
                store.update(id, text: newValue)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(filteredScripts) { script in
                ScriptRow(script: script)
                    .tag(script.id)
                    .contextMenu {
                        Button("Duplicate") {
                            if let copy = store.duplicate(script.id) {
                                selection = copy.id
                            }
                        }
                        Button("Show in Finder") {
                            selection = script.id
                            revealSelected()
                        }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            selection = script.id
                            confirmingDelete = true
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search scripts")
        .overlay {
            if store.scripts.isEmpty {
                ContentUnavailableView(
                    "Drop Files Here",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Drop a document to import it, or create a new script.")
                )
            } else if filteredScripts.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            importProviders(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let script = selectedScript {
            editor(for: script)
                .toolbar { toolbarItems(for: script) }
        } else if store.scripts.isEmpty {
            ContentUnavailableView {
                Label("No Scripts Yet", systemImage: "text.alignleft")
            } description: {
                Text("Create a script, or import a document (txt, md, rtf, html, pdf, docx, odt).")
            } actions: {
                Button("New Script", action: createScript)
                    .buttonStyle(.borderedProminent)
                Button("Import…") { showingImporter = true }
            }
            .toolbar { newAndImportItems }
        } else {
            ContentUnavailableView(
                "Select a Script",
                systemImage: "doc.text",
                description: Text("Choose a script from the sidebar.")
            )
            .toolbar { newAndImportItems }
        }
    }

    private func editor(for script: Script) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("Title", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                Picker("Language", selection: languageBinding) {
                    ForEach(ScriptLanguage.all) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Text(statsSummary(for: script))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $draftText)
                .font(.system(size: 14))
                .environment(\.layoutDirection, script.language.rightToLeft ? .rightToLeft : .leftToRight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
    }

    @ToolbarContentBuilder
    private func toolbarItems(for script: Script) -> some ToolbarContent {
        newAndImportItems
        ToolbarItemGroup {
            Button(action: beginExport) {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            Button(action: revealSelected) {
                Label("Show in Finder", systemImage: "folder")
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                onActivate(script)
            } label: {
                Label("Set as Active Script", systemImage: "play.fill")
            }
        }
    }

    @ToolbarContentBuilder
    private var newAndImportItems: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: createScript) {
                Label("New", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)
            Button {
                showingImporter = true
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
        }
    }

    // MARK: - State helpers

    private var selectedScript: Script? {
        store.scripts.first { $0.id == selection }
    }

    private var filteredScripts: [Script] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.scripts }
        return store.scripts.filter {
            $0.title.localizedStandardContains(query) || $0.text.localizedStandardContains(query)
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { selectedScript?.languageID ?? "en-US" },
            set: { newValue in
                if let id = selection {
                    store.update(id, languageID: newValue)
                }
            }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )
    }

    /// Copies the stored script into the editor fields. Re-applying the same
    /// values through onChange is a no-op in the store.
    private func loadDrafts() {
        draftTitle = selectedScript?.title ?? ""
        draftText = selectedScript?.text ?? ""
    }

    // MARK: - Actions

    private func createScript() {
        let language = selectedScript?.language ?? ScriptLanguage.named("en-US")
        let script = store.create(title: "Untitled", language: language)
        selection = script.id
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        let index = store.scripts.firstIndex { $0.id == id }
        store.delete(id)
        if let index, !store.scripts.isEmpty {
            selection = store.scripts[min(index, store.scripts.count - 1)].id
        } else {
            selection = nil
        }
    }

    private func beginExport() {
        guard let script = selectedScript else { return }
        exportDocument = TextExportDocument(text: ScriptImporter.exportText(script))
        exportName = script.title.isEmpty ? "Script" : script.title
        showingExporter = true
    }

    private func revealSelected() {
        guard let id = selection else { return }
        let file = store.fileURL(for: id)
        let target = FileManager.default.fileExists(atPath: file.path) ? file : store.directory
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private func importFiles(_ urls: [URL]) {
        var failures: [String] = []
        var lastImported: UUID?
        for url in urls {
            do {
                let imported = try ScriptImporter.importFile(at: url)
                let script = store.create(
                    title: imported.title,
                    language: ScriptLanguage.named(imported.languageID),
                    text: imported.text
                )
                lastImported = script.id
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if let lastImported {
            selection = lastImported
        }
        if !failures.isEmpty {
            importMessage = failures.joined(separator: "\n")
        }
    }

    private func importProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    importFiles([url])
                }
            }
        }
        return true
    }
}

private struct ScriptRow: View {
    let script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(script.title.isEmpty ? "Untitled" : script.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(script.language.name)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Text(statsSummary(for: script))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// "N words · about M min", or "N characters" for unspaced languages.
private func statsSummary(for script: Script) -> String {
    let count = script.wordCount
    guard count > 0 else { return "Empty" }
    let unit = script.language.spaced ? "words" : "characters"
    let minutes = script.estimatedMinutes()
    let time = minutes < 1 ? "under 1 min" : "about \(Int(minutes.rounded())) min"
    return "\(count) \(unit) · \(time)"
}

/// Carries plain text to the file exporter.
private struct TextExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
