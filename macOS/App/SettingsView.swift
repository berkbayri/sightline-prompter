import Aligner
import SightlineCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @StateObject private var catalog = LanguageCatalog()
    @ObservedObject private var pro = ProStore.shared
    @AppStorage(Analytics.enabledKey) private var shareUsage = true

    /// Offered languages, plus the current one even when this Mac cannot recognize it, so the picker keeps its value.
    private var pickerOptions: [ScriptLanguage] {
        var options = catalog.pickerLanguages
        if let current = ScriptLanguage.all.first(where: { $0.id == settings.scriptLanguage }),
           !options.contains(current) {
            options.append(current)
        }
        return options
    }

    private func lockRow(_ text: String) -> some View {
        ProLockRow(text) { (NSApp.delegate as? AppDelegate)?.openPaywall() }
    }

    var body: some View {
        Form {
            Section {
                if pro.isUnlocked {
                    Label("Sightline Pro is active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    ProBanner { (NSApp.delegate as? AppDelegate)?.openPaywall() }
                }
                #if DEBUG
                Toggle("Debug: act as Pro", isOn: $pro.debugPro)
                #endif
            } header: {
                Text("Sightline Pro")
            } footer: {
                Text(pro.isUnlocked ? "One purchase covers iPhone and Mac." : "Free: voice following up to 2 minutes at a time, in English, Turkish and Spanish. Pro removes every limit and adds the controller and pace readout.")
            }

            Section {
                LabeledContent("Scripts") {
                    Text(LibraryLocation.current.displayName)
                        .foregroundStyle(.secondary)
                }
                switch LibraryContainer.Status.current {
                case .ready:
                    Label("Signed in to iCloud", systemImage: "checkmark.icloud.fill").foregroundStyle(.green)
                case .signedOut:
                    Label("Not signed in to iCloud", systemImage: "icloud.slash").foregroundStyle(.orange)
                    Button("Sign in to iCloud in System Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                case .unavailable:
                    EmptyView()
                }
                Button("Open Library…") {
                    NotificationCenter.default.post(name: .openLibrary, object: nil)
                }
            } header: {
                Text("Library")
            } footer: {
                Text("Scripts you add or edit here appear on your iPhone, and the other way round. They are the files in iCloud Drive > Sightline Prompter.")
            }

            Section {
                Picker("Speech language", selection: $settings.scriptLanguage) {
                    ForEach(pickerOptions) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                ForEach(ScriptLanguage.all) { language in
                    LanguageRow(
                        language: language,
                        readiness: catalog.readiness[language.id],
                        progress: catalog.progress[language.id],
                        error: catalog.errors[language.id],
                        install: { Task { await catalog.installOffline(language.id) } }
                    )
                }
            } header: {
                Text("Languages")
            } footer: {
                Text("On device works without an internet connection. Online languages use Apple's servers until their offline model is installed. Speech tracking listens in the speech language above.")
            }

            Section {
                slider("Width", value: $settings.panelWidth, range: 240...1400, step: 10, unit: "pt")
                slider("Height", value: $settings.panelHeight, range: 120...600, step: 10, unit: "pt")
                slider("Horizontal position", value: $settings.xOffset, range: -600...600, step: 1, unit: "pt")
                Button("Center under notch") {
                    settings.xOffset = 0
                }
                Toggle("Hide from screen sharing", isOn: $settings.hideFromCapture)
            } header: {
                Text("Window")
            }

            Section {
                slider("Font size", value: $settings.fontSize, range: 12...72, step: 1, unit: "pt")
                slider("Auto-scroll speed", value: $settings.autoSpeed, range: 0...300, step: 5, unit: "pt/s")
                Toggle("Show words per minute and time left", isOn: $settings.showPace)
                    .disabled(!pro.isUnlocked)
                if !pro.isUnlocked { lockRow("Pace readout is part of Sightline Pro") }
            } header: {
                Text("Reading")
            }

            if !pro.isUnlocked {
                Section { lockRow("Controller tuning is part of Sightline Pro") }
            }

            Section {
                Picker("Response", selection: $settings.stickCurve) {
                    ForEach(StickCurve.allCases) { curve in
                        Text(curve.name).tag(curve)
                    }
                }
                .pickerStyle(.segmented)
                CurvePreview(curve: settings.stickCurve, deadzone: settings.stickDeadzone)
                    .frame(height: 90)
                slider("Max speed", value: $settings.stickMaxSpeed, range: 50...800, step: 10, unit: "pt/s")
                slider("Deadzone", value: $settings.stickDeadzone, range: 0...0.4, step: 0.01, unit: "")
                Toggle("Light bar shows reading state", isOn: $settings.gamepadLight)
            } header: {
                Text("Gamepad")
            } footer: {
                Text("Precise starts very slowly for fine adjustments. Smooth is in between. Linear is 1:1.")
            }
            .disabled(!pro.isUnlocked)

            Section {
                shortcutRow("Play / pause", "Click text · X")
                shortcutRow("Restart", "Square")
                shortcutRow("Speed", "D-pad up / down")
                shortcutRow("Scroll", "Left stick · mouse wheel")
                shortcutRow("Jump paragraph", "L1 / R1")
                shortcutRow("Speech tracking", "Triangle")
                shortcutRow("Show / hide", "Circle")
            } header: {
                Text("Controls")
            } footer: {
                Text("Manual scrolling moves the reading position. Speech tracking continues from the words now on screen.")
            }

            Section {
                Toggle("Share anonymous usage", isOn: $shareUsage)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Counts which screens and limits are reached, tied to a random ID. Never your scripts, voice, video or Apple Account.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 680)
        .onAppear { catalog.refresh() }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title) {
                Text(valueText(value.wrappedValue, unit: unit))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func valueText(_ value: Double, unit: String) -> String {
        if unit.isEmpty {
            return String(format: "%.2f", value)
        }
        return "\(Int(value.rounded())) \(unit)"
    }

    private func shortcutRow(_ action: String, _ input: String) -> some View {
        LabeledContent(action) {
            Text(input)
                .foregroundStyle(.secondary)
        }
    }
}

extension Notification.Name {
    static let openLibrary = Notification.Name("SightlinePrompter.openLibrary")
}

