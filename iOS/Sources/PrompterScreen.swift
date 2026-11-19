import SightlineCore
import SwiftUI

/// The recording screen: a short prompter band next to the front camera, the live preview scaled into the
/// rest of the screen, and the camera controls. Everything is placed from CameraLayout.
struct PrompterScreen: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var camera: CameraEngine
    @ObservedObject private var pro = ProStore.shared
    @ObservedObject private var settings = PhoneSettings.shared
    @ObservedObject private var sizer: DistanceSizer
    let onExit: () -> Void
    let onCameraSettings: () -> Void

    /// The item being moved or resized; nil when not arranging.
    @StateObject private var level = LevelMonitor()
    @State private var arranging: ArrangedItem?
    /// Frames while a drag is going on (and until Done), instead of the saved ones.
    @State private var liveFrames: ArrangedFrames?

    init(model: AppModel, onExit: @escaping () -> Void, onCameraSettings: @escaping () -> Void) {
        self.model = model
        _camera = ObservedObject(wrappedValue: model.camera)
        _sizer = ObservedObject(wrappedValue: model.sizer)
        self.onExit = onExit
        self.onCameraSettings = onCameraSettings
    }

    /// The horizon line is a live sensor reading; store screenshots leave it out.
    private static var hidesLevel: Bool {
        #if DEBUG
        ScreenshotMode.isActive
        #else
        false
        #endif
    }

    /// Height of one text line, matching the paragraph style the prompter view draws with.
    private var lineHeight: CGFloat {
        UIFont.systemFont(ofSize: CGFloat(sizer.appliedSize), weight: .semibold).lineHeight * CGFloat(settings.lineSpacing)
    }

    @ViewBuilder
    private func previewView(passThrough: CGRect, onLongPress: @escaping () -> Void) -> some View {
        #if DEBUG
        if ScreenshotMode.isActive {
            Group {
                if let image = ScreenshotMode.backdrop {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.4)
                }
            }
        } else {
            CameraPreview(engine: model.camera, passThrough: passThrough, onLongPress: onLongPress)
        }
        #else
        CameraPreview(engine: model.camera, passThrough: passThrough, onLongPress: onLongPress)
        #endif
    }

    @ViewBuilder
    private var previewBackdrop: some View {
        #if DEBUG
        if ScreenshotMode.isActive {
            Group {
                if let image = ScreenshotMode.backdrop {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.4)
                }
            }
            .blur(radius: 24)
            .overlay(Color.black.opacity(0.45))
        } else {
            CameraBackdrop(engine: model.camera)
                .blur(radius: 24)
                .overlay(Color.black.opacity(0.45))
        }
        #else
        CameraBackdrop(engine: model.camera)
            .blur(radius: 24)
            .overlay(Color.black.opacity(0.45))
        #endif
    }

    var body: some View {
        ZStack {
            // The outer reader only reports the real safe-area insets (camera cutout, home indicator). The inner
            // one covers the whole screen, so the layout can use every point and keep its own items clear of them.
            GeometryReader { safe in
                let insets = safe.safeAreaInsets
                GeometryReader { proxy in
                    screen(proxy, insets: insets)
                }
                .ignoresSafeArea()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .onAppear { level.start() }
        .onDisappear { level.stop() }
        .persistentSystemOverlays(.hidden)
        .overlay(alignment: .top) { TakeStatusCard(camera: camera) }
    }

    private func screen(_ proxy: GeometryProxy, insets: EdgeInsets) -> some View {
        let isLandscape = proxy.size.width > proxy.size.height
        let band = CameraLayout.RecordingBand(
            lineHeight: lineHeight,
            portraitLines: pro.isUnlocked ? CGFloat(settings.portraitLines) : 3,
            landscapeLines: pro.isUnlocked ? CGFloat(settings.landscapeLines) : 5,
            portraitWidthFraction: pro.isUnlocked ? CGFloat(settings.portraitWidthPercent / 100) : 1,
            landscapeWidth: pro.isUnlocked ? CGFloat(settings.landscapeColumnWidth) : 480,
            videoAspect: camera.aspect.ratio
        )
        func makeLayout(_ arrangement: Arrangement?) -> CameraLayout {
            CameraLayout.make(
                size: proxy.size,
                insets: ScreenInsets(
                    top: insets.top,
                    left: insets.leading,
                    bottom: insets.bottom,
                    right: insets.trailing
                ),
                isLandscape: isLandscape,
                cameraEdge: model.cameraEdge,
                readingDistanceCm: CGFloat(settings.readingDistanceCm),
                landscapeColumnWidth: pro.isUnlocked ? CGFloat(settings.landscapeColumnWidth) : 480,
                recording: band,
                arrangement: arrangement
            )
        }
        let saved = isLandscape ? settings.arrangementLandscape : settings.arrangementPortrait
        let automatic = makeLayout(nil)
        let stored = saved == nil ? automatic : makeLayout(saved)
        let layout = liveFrames.map { stored.placing($0) } ?? stored
        let geometry = layout.arrangement(videoAspect: camera.aspect.ratio, lineHeight: lineHeight)
        let canArrange = model.cameraOn && layout.previewFrame != nil
        func beginArranging(_ item: ArrangedItem) {
            guard canArrange, arranging == nil, let frames = stored.arrangedFrames else { return }
            liveFrames = frames
            arranging = item
        }
        func save(_ frames: ArrangedFrames) {
            let arrangement = Arrangement(frames: frames, in: layout.arrangeArea)
            if isLandscape { settings.arrangementLandscape = arrangement } else { settings.arrangementPortrait = arrangement }
        }
        // Touches on the controls must reach the SwiftUI buttons, not the text or the preview beneath.
        let controls = layout.controlsFrame.offsetBy(dx: proxy.frame(in: .global).minX, dy: proxy.frame(in: .global).minY)
        let passThrough = (model.controlsVisible || arranging != nil) ? controls : CGRect.zero
        return ZStack(alignment: .topLeading) {
            if model.cameraOn, layout.previewFrame != nil {
                // The same live picture fills the whole screen, dimmed and blurred, so no part of the screen is empty
                // around the exact frame in front of it.
                previewBackdrop
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            if model.cameraOn, let preview = layout.previewFrame {
                previewView(passThrough: passThrough, onLongPress: { beginArranging(.preview) })
                    .frame(width: preview.width, height: preview.height)
                    .overlay {
                        // Only landscape footage is cropped to vertical afterwards.
                        if layout.isLandscape { VerticalCropGuide(videoAspect: layout.previewAspect) }
                    }
                    .overlay { if !Self.hidesLevel { LevelOverlay(level: level) } }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .offset(x: preview.minX, y: preview.minY)
            }
            PrompterSurface(
                view: model.prompter,
                layout: layout,
                passThrough: passThrough,
                onLongPress: { beginArranging(.text) }
            )
            if let item = arranging {
                ArrangeOverlay(
                    frames: Binding(get: { liveFrames ?? layout.arrangedFrames ?? ArrangedFrames(preview: .zero, text: .zero) },
                                    set: { liveFrames = $0 }),
                    selected: Binding(get: { arranging ?? item }, set: { arranging = $0 }),
                    geometry: geometry,
                    onCommit: save
                )
                ArrangeBar(
                    layout: layout,
                    onReset: {
                        if isLandscape { settings.arrangementLandscape = nil } else { settings.arrangementPortrait = nil }
                        liveFrames = automatic.arrangedFrames
                    },
                    onDone: {
                        arranging = nil
                        liveFrames = nil
                    }
                )
            } else {
                ControlsPane(
                    model: model,
                    camera: model.camera,
                    sizer: model.sizer,
                    layout: layout,
                    onExit: onExit,
                    onCameraSettings: onCameraSettings
                )
            }
        }
        // A turn of the phone changes the free area, so arranging ends with it.
        .onChange(of: isLandscape) { _, _ in
            arranging = nil
            liveFrames = nil
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
    }
}

/// Hosts the UIKit prompter view. The view is owned by AppModel, so reading state survives sheets.
private struct PrompterSurface: UIViewRepresentable {
    let view: PrompterUIView
    let layout: CameraLayout
    let passThrough: CGRect
    let onLongPress: () -> Void

    func makeUIView(context: Context) -> PrompterUIView {
        view
    }

    func updateUIView(_ uiView: PrompterUIView, context: Context) {
        uiView.apply(layout)
        uiView.passThroughRect = passThrough
        uiView.onLongPress = onLongPress
    }
}

/// Camera controls in one glass capsule: a row along the bottom in portrait, a column on the far edge in
/// landscape. Record sits in the middle; the prompter and capture switches flank it, rarer actions live in "More".
private struct ControlsPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var camera: CameraEngine
    @ObservedObject var sizer: DistanceSizer
    let layout: CameraLayout
    let onExit: () -> Void
    let onCameraSettings: () -> Void

    var body: some View {
        let frame = layout.controlsFrame
        VStack(spacing: 6) {
            cameraStatus
            bar
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .opacity(model.controlsVisible ? 1 : 0)
        .allowsHitTesting(model.controlsVisible)
        .animation(.easeInOut(duration: 0.25), value: model.controlsVisible)
        .sensoryFeedback(.impact(weight: .medium), trigger: camera.isRecording)
    }

    private var bar: some View {
        let size: CGFloat = layout.isLandscape ? 40 : 42
        let stack = layout.isLandscape ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return stack {
            BarButton(title: "Back to scripts", systemImage: "xmark", identifier: "camera.exit", size: size) {
                if !camera.isProcessingTake { onExit() }
            }
            Spacer(minLength: 0)
            BarButton(
                title: model.isPlaying ? "Pause" : "Play",
                systemImage: model.isPlaying ? "pause.fill" : "play.fill",
                identifier: "camera.playpause", size: size
            ) { model.togglePlay() }
            Spacer(minLength: 0)
            BarButton(
                title: "Speech tracking",
                systemImage: model.isTracking ? "mic.fill" : "mic.slash",
                active: model.isTracking, identifier: "camera.tracking", size: size
            ) { model.toggleTracking() }
            Spacer(minLength: 0)
            RecordButton(isRecording: camera.isRecording, size: layout.isLandscape ? 54 : 58) {
                camera.toggleRecording()
            }
            Spacer(minLength: 0)
            BarButton(
                title: camera.monoAudio ? "Mono audio on" : "Mono audio off",
                systemImage: camera.monoAudio ? "speaker.fill" : "speaker.wave.2",
                active: camera.monoAudio, identifier: "camera.mono", size: size
            ) { camera.monoAudio.toggle() }
            Spacer(minLength: 0)
            ZoomButton(zoom: camera.zoomFactor, presets: camera.zoomPresets, size: size) { next in
                camera.setZoom(next, animated: true)
            }
            Spacer(minLength: 0)
            Menu {
                Button { onCameraSettings() } label: { Label("Camera settings", systemImage: "slider.horizontal.3") }
                Button { camera.switchCamera() } label: { Label("Switch camera", systemImage: "arrow.triangle.2.circlepath.camera") }
            } label: {
                BarIcon(systemImage: "ellipsis", active: false, size: size)
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("camera.more")
        }
        .padding(layout.isLandscape ? .vertical : .horizontal, 10)
        .padding(layout.isLandscape ? .horizontal : .vertical, 6)
        .barSurface()
        .padding(layout.isLandscape ? .horizontal : .horizontal, layout.isLandscape ? 2 : 10)
    }

    @ViewBuilder
    private var cameraStatus: some View {
        if camera.isRecording {
            let seconds = camera.recordedSeconds
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: Capsule())
        } else if let text = idleStatus {
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var idleStatus: String? {
        if let message = camera.message { return message }
        if sizer.tooFar { return "Move closer or use landscape" }
        return model.statusText.isEmpty ? nil : model.statusText
    }
}

/// Icon on a 44 pt hit area; an active switch gets a soft yellow capsule behind a yellow symbol.
private struct BarIcon: View {
    let systemImage: String
    let active: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(active ? Color.sightline : Color.white)
            .frame(width: size, height: size)
            .background(active ? Color.sightline.opacity(0.2) : Color.clear, in: Circle())
            .contentShape(Rectangle())
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct BarButton: View {
    let title: String
    let systemImage: String
    var active = false
    let identifier: String
    var size: CGFloat = 42
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BarIcon(systemImage: systemImage, active: active, size: size)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Cycles through the zoom presets: 0.5×, 1×, 2×, and so on.
private struct ZoomButton: View {
    let zoom: CGFloat
    let presets: [CGFloat]
    var size: CGFloat = 42
    let action: (CGFloat) -> Void

    var body: some View {
        Button {
            guard !presets.isEmpty else { return }
            let next = presets.first { $0 > zoom + 0.01 } ?? presets[0]
            action(next)
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(zoom == 1 ? Color.white : Color.sightline)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Zoom")
        .accessibilityValue(label)
        .accessibilityIdentifier("camera.zoom")
    }

    private var label: String {
        zoom == zoom.rounded() ? "\(Int(zoom))×" : String(format: "%.1f×", zoom)
    }
}

/// The record button: a white ring around a red dot that becomes a rounded square while recording.
private struct RecordButton: View {
    let isRecording: Bool
    var size: CGFloat = 58
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(.white, lineWidth: 3.5).frame(width: size, height: size)
                RoundedRectangle(cornerRadius: isRecording ? 6 : size / 2, style: .continuous)
                    .fill(Color.red)
                    .frame(width: isRecording ? size * 0.4 : size - 11, height: isRecording ? size * 0.4 : size - 11)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isRecording)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityIdentifier("camera.record")
    }
}

private extension View {
    /// The bar floats over the video: Liquid Glass on iOS 26, a dark material before that.
    @ViewBuilder
    func barSurface() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .environment(\.colorScheme, .dark)
        }
    }
}

/// Landscape recording: marks the centered 9:16 strip of the frame that stays when the clip is cropped to
/// a vertical video in the edit. The sides are dimmed, the strip edges get thin lines and faint thirds. Touches pass through.
private struct VerticalCropGuide: View {
    /// Width / height of the recorded picture. When the preview is wider than that the picture is cropped at the
    /// top and bottom, so the strip is measured on the picture's full height, not on the visible part.
    let videoAspect: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let strip = CameraLayout.verticalCropStrip(in: CGRect(origin: .zero, size: proxy.size), videoAspect: videoAspect)
            let width = strip.width
            let left = strip.minX
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: left, height: proxy.size.height)
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: left, height: proxy.size.height)
                    .offset(x: left + width)
                Rectangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 1, height: proxy.size.height)
                    .offset(x: left)
                Rectangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 1, height: proxy.size.height)
                    .offset(x: left + width - 1)
                // Rule-of-thirds lines inside the strip, barely there.
                ForEach(1..<3) { i in
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 0.5, height: proxy.size.height)
                        .offset(x: left + width * CGFloat(i) / 3)
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: width, height: 0.5)
                        .offset(x: left, y: proxy.size.height * CGFloat(i) / 3)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


/// Shown after a recording stops: what is being done to the take, then a way to open it in Photos.
private struct TakeStatusCard: View {
    @ObservedObject var camera: CameraEngine
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch camera.takeState {
            case .idle:
                EmptyView()
            case let .working(text, fraction):
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(text).font(.subheadline.weight(.semibold))
                        }
                        if let fraction { ProgressView(value: fraction).tint(Color.sightline) }
                        Text("Keep the app open until this finishes.").font(.caption).opacity(0.7)
                    }
                }
            case .saved:
                card {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.sightline)
                        Text("Saved to Photos").font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Button("Open Photos") {
                            if let url = URL(string: "photos-redirect://") { openURL(url) }
                        }
                        .buttonStyle(.borderedProminent).tint(Color.sightline).foregroundStyle(.black)
                        Button { camera.dismissTakeState() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Dismiss")
                    }
                }
            case let .failed(text):
                card {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(text).font(.subheadline)
                        Spacer(minLength: 8)
                        Button { camera.dismissTakeState() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Dismiss")
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: camera.takeState)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(.white)
            .padding(14)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.top, 60)
    }
}
