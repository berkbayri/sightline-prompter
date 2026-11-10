import Aligner
import SightlineCore
import SwiftUI
import UniformTypeIdentifiers

/// The home screen: pick the script to read, or create, import, edit and delete scripts.
struct LibraryScreen: View {
    let model: AppModel
    let onUse: (Script) -> Void
    let onSettings: () -> Void
    @ObservedObject private var library: LibraryStore

    @State private var path: [UUID] = []
    @State private var searchText = ""
    @State private var showingImporter = false
    @State private var pendingDelete: Script?
    @State private var message: String?
    @State private var choosingSyncFolder = false
    @State private var isShared = AppModel.isShared
    @State private var explainingSync = false
    @State private var askedThisLaunch = false

    init(model: AppModel, onUse: @escaping (Script) -> Void, onSettings: @escaping () -> Void) {
        self.model = model
        self.onUse = onUse
        self.onSettings = onSettings
        _library = ObservedObject(wrappedValue: model.library)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filteredScripts) { script in
                    Button {
                        onUse(script)
                    } label: {
                        ScriptRow(script: script, isActive: script.id == model.activeScript?.id)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = script
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            library.duplicate(script.id)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.indigo)
                        Button {
                            path.append(script.id)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            .overlay { emptyState }
            .searchable(text: $searchText, prompt: "Search scripts")
            .navigationTitle("Scripts")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                ScriptEditor(library: library, scriptID: id)
            }
            .toolbar { toolbarItems }
            .onAppear {
                // Without the iCloud entitlement the phone cannot reach iCloud Drive by itself: it asks for the
                // folder once, remembers it, and does not ask again.
                if !isShared, !askedThisLaunch {
                    askedThisLaunch = true
                    explainingSync = true
                }
            }
            .alert("Keep your scripts in iCloud Drive", isPresented: $explainingSync) {
                Button("Choose Folder") { choosingSyncFolder = true }
            } message: {
                Text("Open iCloud Drive and choose the folder Sightline Prompter, or iCloud Drive itself. Your scripts on this iPhone move there and match your Mac.")
            }
            .fileImporter(isPresented: $choosingSyncFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    do {
                        try model.useSharedFolder(url)
                        isShared = true
                    } catch {
                        message = "Could not use that folder: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    message = error.localizedDescription
                }
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
                    message = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Delete this script?",
                isPresented: deleteBinding,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteConfirmed() }
            } message: {
                Text("The script file is removed from this iPhone.")
            }
            .alert("Something went wrong", isPresented: messageBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    // MARK: - Content

    private var filteredScripts: [Script] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.scripts }
        return library.scripts.filter {
            $0.title.localizedStandardContains(query) || $0.text.localizedStandardContains(query)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if library.scripts.isEmpty {
            ContentUnavailableView(
                "No Scripts",
                systemImage: "text.alignleft",
                description: Text("Create a script, or import a document: txt, md, rtf, html, pdf, docx or odt.")
            )
        } else if filteredScripts.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onSettings) {
                Label("Settings", systemImage: "gearshape")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showingImporter = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            Button {
                createScript()
            } label: {
                Label("New", systemImage: "square.and.pencil")
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )
    }

    private static let importTypes: [UTType] = {
        var types: [UTType] = [.plainText, .rtf, .rtfd, .html, .pdf]
        for fileExtension in ["md", "markdown", "doc", "docx", "odt"] {
            if let type = UTType(filenameExtension: fileExtension) {
                types.append(type)
            }
        }
        return types
    }()

    // MARK: - Actions

    private func createScript() {
        let script = library.create(title: "Untitled", language: .named("en-US"))
        path.append(script.id)
    }

    private func deleteConfirmed() {
        guard let script = pendingDelete else { return }
        pendingDelete = nil
        library.delete(script.id)
        model.libraryDidChange()
    }

    /// Files from the picker are outside the sandbox, so each one is opened as a security-scoped resource.
    private func importFiles(_ urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let imported = try ScriptImporter.importFile(at: url)
                library.create(
                    title: imported.title,
                    language: .named(imported.languageID),
                    text: imported.text
                )
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            message = failures.joined(separator: "\n")
        }
    }
}

/// Editor for one script. Edits save to the library as they are typed.
struct ScriptEditor: View {
    @ObservedObject var library: LibraryStore
    let scriptID: UUID

    @State private var title = ""
    @State private var text = ""

    private var script: Script? {
        library.scripts.first { $0.id == scriptID }
    }

    private var languageOptions: [ScriptLanguage] {
        var options = ScriptLanguage.all
        if let current = script?.language, !options.contains(current) {
            options.append(current)
        }
        return options
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                Picker("Language", selection: languageBinding) {
                    ForEach(languageOptions) { language in
                        Text(language.name).tag(language.id)
                    }
                }
            } footer: {
                if let script {
                    Text(statsSummary(for: script))
                }
            }

            Section("Script") {
                TextEditor(text: $text)
                    .font(.system(size: 17))
                    .frame(minHeight: 320)
                    .environment(\.layoutDirection, script?.language.rightToLeft == true ? .rightToLeft : .leftToRight)
            }
        }
        .navigationTitle(title.isEmpty ? "Untitled" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: text) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            title = script?.title ?? ""
            text = script?.text ?? ""
        }
        .onChange(of: title) { _, value in
            library.update(scriptID, title: value)
        }
        .onChange(of: text) { _, value in
            library.update(scriptID, text: value)
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { script?.languageID ?? "en-US" },
            set: { library.update(scriptID, languageID: $0) }
        )
    }
}

private struct ScriptRow: View {
    let script: Script
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(script.title.isEmpty ? "Untitled" : script.title)
                    .font(.headline)
                    .lineLimit(1)
                if isActive {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Active script")
                }
            }
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
