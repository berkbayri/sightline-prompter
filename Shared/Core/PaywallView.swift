import SwiftUI

/// The Sightline Pro upgrade screen, shared by iPhone and Mac. Shows the plans with their App Store prices,
/// the renewal terms Apple requires, Restore Purchases, and links to the privacy policy and terms.
public struct PaywallView: View {
    @ObservedObject private var store: ProStore
    private let onClose: () -> Void
    @State private var selected: String?

    public init(store: ProStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
    }

    private static let features: [(String, String)] = [
        ("waveform", "Unlimited voice following"),
        ("video", "Record 4K, 60 fps, HDR and ProRes, without a time limit"),
        ("globe", "Voice following in all 31 languages"),
        ("rectangle.and.text.magnifyingglass", "Adjust the prompter width and height"),
        ("gamecontroller", "DualSense controller and pace readout"),
        ("macbook.and.iphone", "One purchase for iPhone and Mac"),
    ]

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 34))
                        .foregroundStyle(.yellow)
                    Text("Sightline Pro")
                        .font(.largeTitle.bold())
                    Text("Read to the camera without limits.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.features, id: \.1) { feature in
                        Label(feature.1, systemImage: feature.0)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                offerList

                Button {
                    guard let offer = store.offers.first(where: { $0.id == (selected ?? store.offers.first?.id) }) else { return }
                    Task { await store.purchase(offer) }
                } label: {
                    Text(continueTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .disabled(store.offers.isEmpty || store.isBusy)
                .accessibilityIdentifier("paywall.continue")

                if let message = store.message {
                    Text(message).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                }

                HStack(spacing: 20) {
                    Button("Restore Purchases") { Task { await store.restore() } }
                    Link("Privacy Policy", destination: URL(string: "https://berkbayri.github.io/sightline-prompter/privacy.html")!)
                    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                .font(.footnote)

                Text("Yearly and monthly plans renew automatically. Payment is charged to your Apple Account when you confirm the purchase, and the plan renews unless you cancel at least 24 hours before the period ends. Manage or cancel in your Apple Account settings. A free trial turns into a paid yearly plan at the end of the trial unless you cancel. Lifetime is a one-time purchase.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Not now", action: onClose)
                    .font(.footnote)
                    .accessibilityIdentifier("paywall.close")
            }
            .padding(20)
        }
        .onChange(of: store.isUnlocked) { _, unlocked in
            if unlocked { onClose() }
        }
        .task { if store.offers.isEmpty { await store.loadProducts() } }
    }

    @ViewBuilder
    private var offerList: some View {
        if store.offers.isEmpty {
            VStack(spacing: 8) {
                if store.loadFailed {
                    Text("Prices are not available right now. Check your connection and try again.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await store.loadProducts() } }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90)
        } else {
            VStack(spacing: 10) {
                ForEach(store.offers) { offer in
                    let isSelected = (selected ?? store.offers.first?.id) == offer.id
                    Button {
                        selected = offer.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(offer.title).font(.headline)
                                    if let badge = offer.badge {
                                        Text(badge)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.yellow, in: Capsule())
                                            .foregroundStyle(.black)
                                    }
                                }
                                if let trial = offer.trial {
                                    Text(trial).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(offer.price).font(.headline)
                                Text(offer.period).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isSelected ? Color.yellow : Color.secondary.opacity(0.35), lineWidth: isSelected ? 2 : 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("paywall.offer.\(offer.kind)")
                }
            }
        }
    }

    private var continueTitle: String {
        guard let offer = store.offers.first(where: { $0.id == (selected ?? store.offers.first?.id) }) else { return "Continue" }
        switch offer.kind {
        case .lifetime: return "Unlock for \(offer.price)"
        case .yearly: return offer.trial != nil ? "Start free trial" : "Subscribe for \(offer.price)"
        case .monthly: return "Subscribe for \(offer.price)"
        }
    }
}
