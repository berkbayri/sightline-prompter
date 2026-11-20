import SightlineCore
import SwiftUI
import UIKit

@main
struct SightlinePrompterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SignInGate(model: model)
                .preferredColorScheme(.dark)
                .tint(Color.sightline)
        }
    }
}

/// App Store builds stay locked on a sign-in screen until an iCloud account is signed in. Debug builds skip it.
struct SignInGate: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var account = ICloudAccount.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var onboarded = Onboarding.isDone

    var body: some View {
        Group {
            if !onboarded {
                OnboardingWizard {
                    Onboarding.isDone = true
                Analytics.track("onboarding_done")
                    onboarded = true
                }
            } else if account.status.blocksUse() {
                SignInGateView(
                    status: account.status,
                    instructions: "Open Settings, sign in with your Apple Account at the top, and turn on iCloud Drive.",
                    openSettings: {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                )
            } else {
                RootView(model: model)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { account.refresh() }
        }
        .onChange(of: account.status) { _, status in
            if status == .ready { model.switchToSharedLibrary() }
        }
    }
}

/// The script picker is the home screen. Choosing a script opens the recording screen: the prompter band
/// and the scaled camera preview. Scrolling pauses while a sheet is open.
struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPrompter = false
    @State private var showingSettings = false
    @State private var showingCameraSettings = false

    var body: some View {
        LibraryScreen(
            model: model,
            onUse: { script in
                model.activate(script)
                model.setCameraOn(true)
                showingPrompter = true
            },
            onSettings: { showingSettings = true }
        )
        .sheet(isPresented: $showingSettings) {
            SettingsScreen(model: model)
        }
        .sheet(isPresented: Binding(get: { model.showPaywall && !showingPrompter }, set: { model.showPaywall = $0 })) {
            PaywallView(store: model.pro) { model.showPaywall = false }
        }
        .fullScreenCover(isPresented: $showingPrompter) {
            PrompterScreen(
                model: model,
                onExit: {
                    model.pause()
                    model.setCameraOn(false)
                    showingPrompter = false
                },
                onCameraSettings: { showingCameraSettings = true }
            )
            .sheet(isPresented: $showingCameraSettings) {
                CameraSettingsScreen(model: model)
            }
            .sheet(isPresented: Binding(get: { model.showPaywall && showingPrompter }, set: { model.showPaywall = $0 })) {
                PaywallView(store: model.pro) { model.showPaywall = false }
            }
            .onChange(of: showingCameraSettings) { _, isOpen in
                if isOpen { model.pause() }
            }
        }
        #if DEBUG
        .onAppear { openScreenshotScene() }
        #endif
        .onChange(of: showingPrompter) { _, showing in
            if !showing, model.paywallWhenDone, !model.pro.isUnlocked {
                model.paywallWhenDone = false
                model.showPaywall = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.enterBackground()
            case .active: model.enterForeground()
            default: break
            }
        }
    }

    #if DEBUG
    /// Opens the screen named by `-ScreenshotScene` (simulator screenshots for the App Store).
    private func openScreenshotScene() {
        guard let scene = ScreenshotMode.scene else { return }
        if UserDefaults.standard.bool(forKey: "ScreenshotLandscape"),
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            switch scene {
            case "recording":
                if let script = model.activeScript ?? model.library.scripts.first { model.activate(script) }
                model.setCameraOn(true)
                showingPrompter = true
                if ScreenshotMode.autoAdvanceWPM > 0 {
                    var word = 0
                    Timer.scheduledTimer(withTimeInterval: 60 / ScreenshotMode.autoAdvanceWPM, repeats: true) { timer in
                        word += 1
                        model.prompter.setCursor(wordIndex: word)
                        if word >= (model.activeScript?.wordCount ?? 0) { timer.invalidate() }
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { model.prompter.setCursor(wordIndex: 3) }
                }
                // `-ScreenshotEditing YES`: opens the on-prompter editor, caret on the current word.
                if UserDefaults.standard.bool(forKey: "ScreenshotEditing") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { model.beginEditing() }
                }
            case "settings": showingSettings = true
            case "paywall": model.showPaywall = true
            case "camera":
                model.setCameraOn(true)
                showingPrompter = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showingCameraSettings = true }
            default: break
            }
        }
    }
    #endif
}
