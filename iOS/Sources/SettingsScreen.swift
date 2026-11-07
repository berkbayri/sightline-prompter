import Aligner
import SightlineCore
import SwiftUI

struct SettingsScreen: View {
    @ObservedObject private var settings = PhoneSettings.shared
    @ObservedObject private var catalog: LanguageCatalog
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel) {
        _catalog = ObservedObject(wrappedValue: model.catalog)
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    Label("Languages", systemImage: "globe")
                } footer: {
                    Text("On device works without an internet connection. Online languages use Apple's servers until their offline model is installed.")
                }

                Section {
                    slider("Font size", value: $settings.fontSize, range: 20...72, step: 1, unit: "pt")
                    slider("Auto-scroll speed", value: $settings.autoSpeed, range: 0...300, step: 5, unit: "pt/s")
                    Toggle("Show words per minute and time left", isOn: $settings.showPace)
                } header: {
                    Label("Reading", systemImage: "textformat.size")
                }

                Section {
                    Picker("Camera side", selection: $settings.cameraSide) {
                        ForEach(CameraSide.allCases) { side in
                            Text(side.name).tag(side)
                        }
                    }
                    .pickerStyle(.segmented)
                    slider("Reading line below camera", value: $settings.readingDistanceCm, range: 0.5...4, step: 0.1, unit: "cm", decimals: 1)
                } header: {
                    Label("Camera", systemImage: "camera")
                } footer: {
                    Text("The camera side follows the device orientation unless set here.")
                }

                Section {
                    slider("Portrait width", value: $settings.portraitWidthPercent, range: 30...100, step: 1, unit: "%")
                    slider("Portrait height", value: $settings.portraitLines, range: 1...8, step: 0.5, unit: "lines", decimals: 1)
                    slider("Landscape width", value: $settings.landscapeColumnWidth, range: 120...720, step: 10, unit: "pt")
                    slider("Landscape height", value: $settings.landscapeLines, range: 1...12, step: 0.5, unit: "lines", decimals: 1)
                } header: {
                    Label("Prompter area while recording", systemImage: "rectangle.and.text.magnifyingglass")
                } footer: {
                    Text("A narrow, short area keeps your eye movement small on the recording. Width is centered in portrait and sits next to the camera in landscape.")
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
                    slider("Deadzone", value: $settings.stickDeadzone, range: 0...0.4, step: 0.01, unit: "", decimals: 2)
                    Toggle("Light bar shows reading state", isOn: $settings.gamepadLight)
                } header: {
                    Label("Gamepad", systemImage: "gamecontroller")
                } footer: {
                    Text("Precise starts very slowly for fine adjustments. Smooth is in between. Linear is 1:1.")
                }

                Section {
                    shortcutRow("Play / pause", "Tap the text")
                    shortcutRow("Scroll", "Drag the text")
                    shortcutRow("Speech tracking", "Mic button")
                    shortcutRow("Controller", "DualSense over Bluetooth")
                } header: {
                    Label("Controls", systemImage: "hand.tap")
                } footer: {
                    Text("Dragging moves the reading position. Speech tracking continues from the words now on screen.")
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
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        decimals: Int = 0
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title) {
                Text(valueText(value.wrappedValue, unit: unit, decimals: decimals))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func valueText(_ value: Double, unit: String, decimals: Int) -> String {
        let number = String(format: "%.\(decimals)f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private func shortcutRow(_ action: String, _ input: String) -> some View {
        LabeledContent(action) {
            Text(input)
                .foregroundStyle(.secondary)
        }
    }
}
