import Aligner
import SightlineCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @StateObject private var catalog = LanguageCatalog()

    /// Offered languages, plus the current one even when this Mac cannot recognize it, so the picker keeps its value.
    private var pickerOptions: [ScriptLanguage] {
        var options = catalog.pickerLanguages
        if let current = ScriptLanguage.all.first(where: { $0.id == settings.scriptLanguage }),
           !options.contains(current) {
            options.append(current)
        }
        return options
    }

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $settings.scriptLanguage) {
                    ForEach(pickerOptions) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                LabeledContent("Library") {
                    Text(LibraryLocation.current.displayName)
                        .foregroundStyle(.secondary)
                }
                Button("Open Library…") {
                    NotificationCenter.default.post(name: .openLibrary, object: nil)
                }
            } header: {
                Label("Script", systemImage: "text.alignleft")
            } footer: {
                Text("The active script is chosen in the Library. Speech tracking listens in the selected language. Only languages listed below are offered here.")
            }

            Section {
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
                Label("Languages", systemImage: "globe")
            } footer: {
                Text("On device works without an internet connection. Online languages use Apple's servers until their offline model is installed.")
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
                Label("Window", systemImage: "macwindow")
            }

            Section {
                slider("Font size", value: $settings.fontSize, range: 12...72, step: 1, unit: "pt")
                slider("Auto-scroll speed", value: $settings.autoSpeed, range: 0...300, step: 5, unit: "pt/s")
                Toggle("Show words per minute and time left", isOn: $settings.showPace)
            } header: {
                Label("Reading", systemImage: "textformat.size")
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
                Label("Gamepad", systemImage: "gamecontroller")
            } footer: {
                Text("Precise starts very slowly for fine adjustments. Smooth is in between. Linear is 1:1.")
            }

            Section {
                shortcutRow("Play / pause", "Click text · X")
                shortcutRow("Restart", "Square")
                shortcutRow("Speed", "D-pad up / down")
                shortcutRow("Scroll", "Left stick · mouse wheel")
                shortcutRow("Jump paragraph", "L1 / R1")
                shortcutRow("Speech tracking", "Triangle")
                shortcutRow("Show / hide", "Circle")
            } header: {
                Label("Controls", systemImage: "keyboard")
            } footer: {
                Text("Manual scrolling moves the reading position. Speech tracking continues from the words now on screen.")
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

