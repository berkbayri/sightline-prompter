import SwiftUI
import SightlineCore
import UIKit

/// First-launch wizard: a welcome and the iCloud sign-in. Camera, microphone, speech and Photos ask for
/// access the first time they are used, with the reason in front of the user; the Pro offer follows the first take.
enum Onboarding {
    private static let key = "onboardingDone"

    static var isDone: Bool {
        get {
            #if DEBUG
            // Screenshot runs and UI tests start straight in the app.
            if UserDefaults.standard.object(forKey: "OnboardingStep") != nil { return false }
            if ScreenshotMode.scene != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
            #endif
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct OnboardingWizard: View {
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, icloud
    }

    @ObservedObject private var account = ICloudAccount.shared
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @State private var step = Step(rawValue: UserDefaults.standard.integer(forKey: "OnboardingStep")) ?? .welcome
    #else
    @State private var step = Step.welcome
    #endif

    var body: some View {
        VStack(spacing: 0) {
            progress.padding(.top, 20)
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: content.icon)
                    .font(.system(size: 56))
                    .foregroundStyle(Color.sightline)
                Text(content.title).font(.title.bold()).multilineTextAlignment(.center)
                Text(content.detail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                if step == .icloud, !account.status.blocksUse() {
                    Text("Signed in. iCloud Drive is on.").font(.footnote).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 28)
            Spacer()
            Button(action: primaryAction) {
                Text(primaryTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.sightline)
            .foregroundStyle(.black)
            .accessibilityIdentifier("onboarding.primary")
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { account.refresh() }
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.sightline : Color.secondary.opacity(0.3))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 28)
    }

    private var content: (icon: String, title: String, detail: String) {
        switch step {
        case .welcome:
            ("text.viewfinder", "Welcome to Sightline",
             "A teleprompter that listens. Your script follows your voice while your eyes stay on the lens.")
        case .icloud:
            ("icloud", "Sign in to iCloud",
             "Your scripts sync between iPhone and Mac through iCloud Drive. Sign in with your Apple Account in Settings and turn on iCloud Drive.")
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .icloud: account.status.blocksUse() ? "Open Settings" : "Continue"
        }
    }

    private func primaryAction() {
        switch step {
        case .welcome: step = .icloud
        case .icloud:
            if account.status.blocksUse() {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } else {
                onFinish()
            }
        }
    }
}
