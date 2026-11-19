import SwiftUI

/// Small upgrade entry for the places a free user already looks: the script list and Settings.
public struct ProBanner: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.sightline)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go Pro").font(.headline)
                    Text("Unlimited voice following, 4K recording, 31 languages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.sightline.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.sightline.opacity(0.35), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pro.banner")
    }
}

/// The product itself, on the paywall: a prompter band where the word being read moves along, which is exactly
/// what voice following does and what the free version cuts off after two minutes.
struct ProDemoStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let words = "Look at the lens while you read. The script follows your voice, word by word.".split(separator: " ").map(String.init)
    private static let beat = 0.45

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.beat)) { context in
            let count = Self.words.count
            let step = reduceMotion ? 4 : Int(context.date.timeIntervalSinceReferenceDate / Self.beat) % (count + 4)
            Self.words.enumerated().reduce(Text("")) { text, entry in
                let color: Color = entry.offset < step ? .white.opacity(0.35) : entry.offset == step ? .yellow : .white
                return text + Text(entry.element + " ").foregroundStyle(color)
            }
            .font(.system(size: 22, weight: .semibold))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: the word being read is highlighted and the script follows your voice")
    }
}

/// Free against Pro, from the same constants the app enforces, so the table cannot drift from the limits.
struct ProComparison: View {
    private static let rows: [(String, String, String)] = [
        ("Voice following", "\(Int(FreeTier.maxTrackingSeconds / 60)) min per run", "No limit"),
        ("Languages", "\(FreeTier.languageCodes.count)", "31"),
        ("Video on iPhone", "\(FreeTier.maxVideoHeight)p, \(FreeTier.maxFrameRate) fps, \(FreeTier.maxRecordSeconds / 60) min", "4K, 60 fps, HDR, ProRes, no limit"),
        ("Prompter size", "Fixed", "Adjustable"),
        ("Pace readout, controller", "Not included", "Included"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                Color.clear.frame(height: 1)
                Text("Free").font(.caption.bold()).foregroundStyle(.secondary)
                Text("Pro").font(.caption.bold()).foregroundStyle(Color.sightline)
            }
            Divider().gridCellColumns(3)
            ForEach(Self.rows, id: \.0) { row in
                GridRow(alignment: .firstTextBaseline) {
                    Text(row.0).font(.subheadline)
                    Text(row.1).font(.footnote).foregroundStyle(.secondary)
                    Text(row.2).font(.footnote.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// First row of a section that is Pro only: says so and opens the paywall, instead of leaving dimmed controls
/// that do nothing when tapped.
public struct ProLockRow: View {
    private let text: String
    private let action: () -> Void

    public init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(text, systemImage: "lock.fill")
                .foregroundStyle(Color.sightline)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pro.lock")
    }
}
