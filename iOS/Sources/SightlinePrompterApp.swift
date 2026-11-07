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
            .onChange(of: showingCameraSettings) { _, isOpen in
                if isOpen { model.pause() }
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
}
