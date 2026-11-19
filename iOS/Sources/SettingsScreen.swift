import Aligner
import SightlineCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @ObservedObject private var catalog: LanguageCatalog
    @ObservedObject private var pro = ProStore.shared
    @ObservedObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Analytics.enabledKey) private var shareUsage = true
    @State private var recovering = false
    @State private var recoveredCount: Int?

    init(model: AppModel) {
        _catalog = ObservedObject(wrappedValue: model.catalog)
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if pro.isUnlocked {
                        Label("Sightline Pro is active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        ProBanner {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.showPaywall = true }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    #if DEBUG
                    if !ScreenshotMode.isActive { Toggle("Debug: act as Pro", isOn: $pro.debugPro) }
                    #endif
                } header: {
                    Text("Sightline Pro")
                } footer: {
                    Text(pro.isUnlocked ? "One purchase covers iPhone and Mac." : "Free: voice following and recording up to 2 minutes, 1080p, in English, Turkish and Spanish. Pro removes every limit.")
                }

                librarySection

                Section {
                    ForEach(ScriptLanguage.all) { language in
                        LanguageRow(
                            language: language,
                            readiness: catalog.readiness[language.id],
                            progress: catalog.progress[language.id],
                            error: catalog.errors[language.id]
                        ) {
                            Task { await catalog.installOffline(language.id) }
                        }
                    }
                } header: {
                    Text("Languages")
                } footer: {
                    Text("On device works without an internet connection. Online languages use Apple's servers until their offline model is installed.")
                }

                Section {
                    Toggle("Share anonymous usage", isOn: $shareUsage)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Counts which screens and limits are reached, tied to a random ID. Never your scripts, voice, video or Apple Account.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { catalog.refresh() }
            .fileImporter(isPresented: $recovering, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { recoveredCount = model.recoverScripts(from: url) }
            }
            .alert("Restore scripts", isPresented: Binding(get: { recoveredCount != nil }, set: { if !$0 { recoveredCount = nil } })) {
                Button("OK") { recoveredCount = nil }
            } message: {
                let count = recoveredCount ?? 0
                Text(count == 0 ? "No new scripts were found in that folder." : "\(count) script(s) were copied into your library. The folder was not changed.")
            }
        }
    }

    /// Where scripts are stored. With the iCloud container they sync with the Mac on their own. A build that cannot
    /// have it (a personal development team) can still share by pointing at the Mac's iCloud Drive folder.
    private var librarySection: some View {
        Section {
            LabeledContent("Scripts") {
                Text(AppModel.libraryDescription).foregroundStyle(.secondary)
            }
            switch LibraryContainer.Status.current {
            case .ready:
                Label("Signed in to iCloud", systemImage: "checkmark.icloud.fill").foregroundStyle(.green)
            case .signedOut:
                Label("Not signed in to iCloud", systemImage: "icloud.slash").foregroundStyle(.orange)
                Button("Sign in to iCloud in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            case .unavailable:
                EmptyView()
            }
            Button("Restore scripts from a folder…") { recovering = true }
        } header: {
            Text("Library")
        } footer: {
            if LibraryContainer.documentsURL != nil {
                Text("Scripts you add or edit here appear on your Mac, and the other way round. They are the files in iCloud Drive > Sightline Prompter. A dated backup is kept in Files > Sightline Prompter > Sightline Backups.")
            } else {
                Text("Scripts are the files in iCloud Drive > Sightline Prompter, the same folder the Mac app uses.")
            }
        }
    }
}
