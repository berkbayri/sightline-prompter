import Aligner
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $settings.scriptLanguage) {
                    ForEach(ScriptLanguage.all) { language in
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
                Text("The active script is chosen in the Library. Speech tracking listens in the selected language. Languages other than English and Turkish use Apple's servers for recognition.")
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

/// Plots speed (y) against stick travel (x) for the chosen curve, after the deadzone.
private struct CurvePreview: View {
    let curve: StickCurve
    let deadzone: Double

    var body: some View {
        Canvas { context, size in
            let steps = 60
            var path = Path()
            for step in 0...steps {
                let travel = Float(step) / Float(steps)
                let x = CGFloat(step) / CGFloat(steps) * size.width
                let y = size.height - CGFloat(curve.apply(travel)) * size.height
                if step == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(.yellow), lineWidth: 2)

            let deadX = CGFloat(deadzone) * size.width
            var axis = Path()
            axis.move(to: CGPoint(x: deadX, y: 0))
            axis.addLine(to: CGPoint(x: deadX, y: size.height))
            context.stroke(axis, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomLeading) {
            Text("speed").font(.caption2).foregroundStyle(.secondary).padding(4)
        }
    }
}
