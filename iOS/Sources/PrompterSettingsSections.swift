import SightlineCore
import SwiftUI

/// What you adjust while recording: reading, microphone, prompter placement, gamepad. Lives in the camera screen's
/// settings so it is one tap from the prompter; the main Settings keeps scripts, languages and Pro.
struct PrompterSettingsSections: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = PhoneSettings.shared
    @ObservedObject private var pro = ProStore.shared
    @AppStorage(AudioSession.preferredInputKey) private var micUID = ""
    @State private var mics: [(uid: String, name: String)] = []
    let dismiss: () -> Void

    var body: some View {
                    Section {
                        Picker("Microphone", selection: $micUID) {
                            Text("Automatic").tag("")
                            ForEach(mics, id: \.uid) { Text($0.name).tag($0.uid) }
                            // A saved mic that is unplugged keeps its row so the picker never shows a blank selection.
                            if !micUID.isEmpty, !mics.contains(where: { $0.uid == micUID }) {
                                Text("Unplugged microphone").tag(micUID)
                            }
                        }
                        .onAppear { mics = AudioSession.inputs() }
                    } header: {
                        Label("Audio input", systemImage: "mic")
                    } footer: {
                        Text("Pick a USB, wired or Bluetooth microphone for voice following and recording. Automatic uses whatever iOS routes.")
                    }

                    Section {
                        slider("Font size", value: $settings.fontSize, range: 20...72, step: 1, unit: "pt")
                        slider("Line spacing", value: $settings.lineSpacing, range: 1.0...2.0, step: 0.05, unit: "×", decimals: 2)
                        slider("Letter spacing", value: $settings.letterSpacing, range: -0.02...0.2, step: 0.01, unit: "em", decimals: 2)
                        slider("Auto-scroll speed", value: $settings.autoSpeed, range: 0...300, step: 5, unit: "pt/s")
                        Toggle("Show words per minute and time left", isOn: $settings.showPace)
                            .disabled(!pro.isUnlocked)
                        if !pro.isUnlocked { lockRow("Pace readout is part of Sightline Pro") }
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

                    if !pro.isUnlocked {
                        Section { lockRow("Unlock the prompter area with Sightline Pro") }
                    }

                    Section {
                        slider("Portrait width", value: $settings.portraitWidthPercent, range: 30...100, step: 1, unit: "%")
                        slider("Portrait height", value: $settings.portraitLines, range: 1...8, step: 0.5, unit: "lines", decimals: 1)
                        slider("Landscape width", value: $settings.landscapeColumnWidth, range: 120...720, step: 10, unit: "pt")
                        slider("Landscape height", value: $settings.landscapeLines, range: 1...12, step: 0.5, unit: "lines", decimals: 1)
                    } header: {
                        Label("Prompter area while recording", systemImage: "rectangle.and.text.magnifyingglass")
                    } footer: {
                        Text(pro.isUnlocked
                             ? "A narrow, short area keeps your eye movement small on the recording. Width is centered in portrait and sits next to the camera in landscape."
                             : "Adjusting the prompter area is part of Sightline Pro.")
                    }
                    .disabled(!pro.isUnlocked)

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

    private func lockRow(_ text: String) -> some View {
        ProLockRow(text) {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.showPaywall = true }
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
