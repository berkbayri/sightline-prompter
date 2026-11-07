import SightlineCore
import SwiftUI

@main
struct SightlinePrompterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
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
                CameraSettingsScreen(camera: model.camera)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            switch scene {
            case "recording":
                if let script = model.activeScript ?? model.library.scripts.first { model.activate(script) }
                model.setCameraOn(true)
                showingPrompter = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { model.prompter.setCursor(wordIndex: 3) }
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
