import Aligner
import SwiftUI

/// One language in the settings list: its offline state, and a download button when it has one.
public struct LanguageRow: View {
    public let language: ScriptLanguage
    public let readiness: LanguageReadiness?
    public let progress: Double?
    public let error: String?
    public let install: () -> Void

    public init(
        language: ScriptLanguage,
        readiness: LanguageReadiness?,
        progress: Double?,
        error: String?,
        install: @escaping () -> Void
    ) {
        self.language = language
        self.readiness = readiness
        self.progress = progress
        self.error = error
        self.install = install
    }

    public var body: some View {
        LabeledContent(language.name) {
            VStack(alignment: .trailing, spacing: 4) {
                switch readiness {
                case nil:
                    Text("Checking…")
                        .foregroundStyle(.secondary)
                case .onDevice?:
                    Text("On device")
                        .foregroundStyle(.secondary)
                case .onlineDownloadable?:
                    if let progress {
                        ProgressView(value: progress)
                            .frame(width: 140)
                    } else {
                        Button("Download for offline use", action: install)
                    }
                case .online?:
                    Text("Online")
                        .foregroundStyle(.secondary)
                case .unavailable?:
                    Text("Unavailable")
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

/// Plots speed (y) against stick travel (x) for the chosen curve, after the deadzone.
public struct CurvePreview: View {
    public let curve: StickCurve
    public let deadzone: Double

    public init(curve: StickCurve, deadzone: Double) {
        self.curve = curve
        self.deadzone = deadzone
    }

    public var body: some View {
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

/// "N words · about M min", or "N characters" for unspaced languages.
public func statsSummary(for script: Script) -> String {
    let count = script.wordCount
    guard count > 0 else { return "Empty" }
    let unit = script.language.spaced ? "words" : "characters"
    let minutes = script.estimatedMinutes()
    let time = minutes < 1 ? "under 1 min" : "about \(Int(minutes.rounded())) min"
    return "\(count) \(unit) · \(time)"
}
