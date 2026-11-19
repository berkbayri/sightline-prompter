import Combine
import Foundation
import SwiftUI

/// Publishes whether the iCloud account is usable, and updates when the user signs in or out while the app runs.
@MainActor
public final class ICloudAccount: ObservableObject {
    public static let shared = ICloudAccount()

    @Published public private(set) var status = LibraryContainer.Status.current
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSUbiquityIdentityDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Reads the account again. Call when the app becomes active: the user may have just signed in.
    public func refresh() {
        let current = LibraryContainer.Status.current
        if current != status { status = current }
    }
}

/// Shown instead of the app while no iCloud account is signed in (App Store builds only).
public struct SignInGateView: View {
    private let status: LibraryContainer.Status
    private let instructions: String
    private let openSettings: () -> Void

    public init(status: LibraryContainer.Status, instructions: String, openSettings: @escaping () -> Void) {
        self.status = status
        self.instructions = instructions
        self.openSettings = openSettings
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Sign in to iCloud")
                .font(.title2.bold())
            Text(status == .unavailable
                 ? "iCloud is not available to this app right now. Check that iCloud Drive is on for Sightline Prompter, then reopen the app."
                 : "Sightline Prompter keeps your scripts in iCloud, so they stay in sync between your iPhone and Mac. \(instructions)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            Button("Open Settings", action: openSettings)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("signin.gate")
    }
}
