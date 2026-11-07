import SightlineCore
import SwiftUI

/// The recording screen: a short prompter band next to the front camera, the live preview scaled into the
/// rest of the screen, and the camera controls. Everything is placed from CameraLayout.
struct PrompterScreen: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var camera: CameraEngine
    @ObservedObject private var settings = PhoneSettings.shared
    let onExit: () -> Void
    let onCameraSettings: () -> Void

    init(model: AppModel, onExit: @escaping () -> Void, onCameraSettings: @escaping () -> Void) {
        self.model = model
        _camera = ObservedObject(wrappedValue: model.camera)
        self.onExit = onExit
        self.onCameraSettings = onCameraSettings
    }

    /// Height of one text line, matching the paragraph style the prompter view draws with.
    private var lineHeight: CGFloat {
        UIFont.systemFont(ofSize: CGFloat(settings.fontSize), weight: .semibold).lineHeight * 1.35
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let insets = proxy.safeAreaInsets
                let layout = CameraLayout.make(
                    size: proxy.size,
                    insets: ScreenInsets(
                        top: insets.top,
                        left: insets.leading,
                        bottom: insets.bottom,
                        right: insets.trailing
                    ),
                    isLandscape: proxy.size.width > proxy.size.height,
                    cameraEdge: model.cameraEdge,
                    readingDistanceCm: CGFloat(settings.readingDistanceCm),
                    landscapeColumnWidth: CGFloat(settings.landscapeColumnWidth),
                    recording: CameraLayout.RecordingBand(
                        lineHeight: lineHeight,
                        portraitLines: CGFloat(settings.portraitLines),
                        landscapeLines: CGFloat(settings.landscapeLines),
                        portraitWidthFraction: CGFloat(settings.portraitWidthPercent / 100),
                        landscapeWidth: CGFloat(settings.landscapeColumnWidth),
                        videoAspect: camera.aspect.ratio
                    )
                )
                // Touches on the controls must reach the SwiftUI buttons, not the text or the preview beneath.
                let controls = layout.controlsFrame.offsetBy(dx: proxy.frame(in: .global).minX, dy: proxy.frame(in: .global).minY)
                let passThrough = model.controlsVisible ? controls : CGRect.zero
                ZStack(alignment: .topLeading) {
                    if model.cameraOn, let preview = layout.previewFrame {
                        CameraPreview(engine: model.camera, passThrough: passThrough)
                            .frame(width: preview.width, height: preview.height)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .offset(x: preview.minX, y: preview.minY)
                    }
                    PrompterSurface(view: model.prompter, layout: layout, passThrough: passThrough)
                    ControlsPane(
                        model: model,
                        camera: model.camera,
                        layout: layout,
                        onExit: onExit,
                        onCameraSettings: onCameraSettings
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

/// Hosts the UIKit prompter view. The view is owned by AppModel, so reading state survives sheets.
private struct PrompterSurface: UIViewRepresentable {
    let view: PrompterUIView
    let layout: CameraLayout
    let passThrough: CGRect

    func makeUIView(context: Context) -> PrompterUIView {
        view
    }

    func updateUIView(_ uiView: PrompterUIView, context: Context) {
        uiView.apply(layout)
        uiView.passThroughRect = passThrough
    }
}

/// Camera controls: a row along the bottom in portrait, a column on the far edge in landscape.
private struct ControlsPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var camera: CameraEngine
    let layout: CameraLayout
    let onExit: () -> Void
    let onCameraSettings: () -> Void

    var body: some View {
        let frame = layout.controlsFrame
        cameraPane
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .opacity(model.controlsVisible ? 1 : 0)
        .allowsHitTesting(model.controlsVisible)
        .animation(.easeInOut(duration: 0.25), value: model.controlsVisible)
    }

    // MARK: - Camera

    /// Zoom, record, camera switch and prompter play in one row (portrait) or column (landscape).
    private var cameraPane: some View {
        // Landscape has a column of eight controls, so the buttons shrink to fit.
        let size: CGFloat = layout.isLandscape ? 34 : 38
        return VStack(spacing: 8) {
            cameraStatus
            let stack = layout.isLandscape ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 6))
            stack {
                ZoomButton(zoom: camera.zoomFactor, presets: camera.zoomPresets, size: size) { next in
                    camera.setZoom(next, animated: true)
                }
                ControlButton(title: "Camera settings", systemImage: "slider.horizontal.3", identifier: "camera.settings", size: size, action: onCameraSettings)
                RecordButton(isRecording: camera.isRecording, size: size + 12) {
                    camera.toggleRecording()
                }
                ControlButton(title: "Switch camera", systemImage: "arrow.triangle.2.circlepath.camera", identifier: "camera.switch", size: size) {
                    camera.switchCamera()
                }
                ControlButton(
                    title: "Speech tracking",
                    systemImage: model.isTracking ? "mic.fill" : "mic.slash",
                    active: model.isTracking,
                    identifier: "camera.tracking",
                    size: size
                ) {
                    model.toggleTracking()
                }
                ControlButton(
                    title: model.isPlaying ? "Pause" : "Play",
                    systemImage: model.isPlaying ? "pause.fill" : "play.fill",
                    identifier: "camera.playpause",
                    size: size
                ) {
                    model.togglePlay()
                }
                ControlButton(title: "Back to scripts", systemImage: "xmark", identifier: "camera.exit", size: size, action: onExit)
            }
        }
    }

    @ViewBuilder
    private var cameraStatus: some View {
        let text = cameraStatusText
        if let text {
            Text(text)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var cameraStatusText: String? {
        if camera.isRecording {
            let seconds = camera.recordedSeconds
            return String(format: "● %02d:%02d", seconds / 60, seconds % 60)
        }
        if let message = camera.message { return message }
        return model.statusText.isEmpty ? nil : model.statusText
    }

}

private struct ControlButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    var active = false
    let identifier: String
    var size: CGFloat = 38
    let action: () -> Void

    var body: some View {
        let dimension: CGFloat = prominent ? 50 : size
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: prominent ? 21 : size * 0.42, weight: .semibold))
                .foregroundStyle(active ? Color.yellow : Color.white)
                .frame(width: dimension, height: dimension)
                .controlSurface(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

/// Cycles through the zoom presets: 0.5×, 1×, 2×, and so on.
private struct ZoomButton: View {
    let zoom: CGFloat
    let presets: [CGFloat]
    var size: CGFloat = 38
    let action: (CGFloat) -> Void

    var body: some View {
        Button {
            guard !presets.isEmpty else { return }
            let next = presets.first { $0 > zoom + 0.01 } ?? presets[0]
            action(next)
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .controlSurface(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom")
        .accessibilityValue(label)
        .accessibilityIdentifier("camera.zoom")
    }

    private var label: String {
        zoom == zoom.rounded() ? "\(Int(zoom))×" : String(format: "%.1f×", zoom)
    }
}

/// The record button: a red dot that becomes a square while recording.
private struct RecordButton: View {
    let isRecording: Bool
    var size: CGFloat = 50
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 3)
                    .frame(width: size, height: size)
                RoundedRectangle(cornerRadius: isRecording ? 4 : size / 2)
                    .fill(Color.red)
                    .frame(width: isRecording ? size * 0.44 : size * 0.8, height: isRecording ? size * 0.44 : size * 0.8)
            }
            .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityIdentifier("camera.record")
    }
}

private extension View {
    /// Liquid Glass on iOS 26, a material everywhere else.
    @ViewBuilder
    func controlSurface<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
