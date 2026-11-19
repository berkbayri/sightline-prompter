import AppKit
import Combine
import SightlineCore

/// The size the prompter text is drawn at (docs/prompter-typography.md). With "Size text for my distance" on,
/// it is the research-based size for the chosen distance preset on this screen; with the optional camera mode
/// on, it also follows how far you lean back or forward, relative to where you sat when it started (the Mac
/// camera's field of view is unknown, so this never claims a metric distance). With it off, it is the Font size.
@MainActor
final class TextSizer: ObservableObject {
    static let shared = TextSizer()

    @Published private(set) var size: Double
    /// One line for the settings window about what the camera is doing.
    @Published private(set) var status = ""
    /// True when the last change came from the camera, so the prompter can ease it in.
    private(set) var lastChangeWasAuto = false
    /// Seconds since the speaker last moved on to a new word. Set by the prompter view.
    var speechPause: () -> Double = { 1 }

    private let settings = Settings.shared
    private var pipeline: AdaptiveTextSize
    private var camera: FaceCamera?
    private var cameraName = ""
    private var timer: Timer?
    private var startingCamera = false
    private var sessionReferencePx: Double?
    private var lastKey = ""
    private var cancellables = Set<AnyCancellable>()

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    private init() {
        let initial = Settings.shared.autoTextSize ? Self.presetSize(Settings.shared) : Settings.shared.fontSize
        size = initial
        pipeline = AdaptiveTextSize(initial: initial)
        settings.objectWillChange
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    // MARK: - Size from the preset

    private static func screenPPMM() -> Double {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen, let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return PrompterTypography.macPPMM(frameWidthPt: 0, physicalWidthMm: 0)
        }
        return PrompterTypography.macPPMM(frameWidthPt: Double(screen.frame.width), physicalWidthMm: CGDisplayScreenSize(id).width)
    }

    /// Width the text has inside the panel (the prompter view keeps 24 pt on each side).
    private static func usableWidth(_ settings: Settings) -> Double { max(settings.panelWidth - 48, 40) }

    private static func plan(_ settings: Settings, distanceMm: Double) -> PrompterTypography.Plan {
        PrompterTypography.plan(distanceMm: distanceMm, ppmm: screenPPMM(), usableWidth: usableWidth(settings),
                                minSize: PrompterTypography.macMinFontSize)
    }

    private static func presetSize(_ settings: Settings) -> Double {
        let preset = PrompterTypography.Preset(rawValue: settings.distancePreset) ?? .desk
        return plan(settings, distanceMm: preset.centimeters * 10).fontSize.rounded()
    }

    // MARK: - Following settings

    private func refresh() {
        guard settings.autoTextSize else {
            stopCamera()
            apply(settings.fontSize, auto: false)
            return
        }
        let base = Self.presetSize(settings)
        let key = "\(settings.distancePreset)|\(settings.panelWidth)|\(Self.screenPPMM())"
        if key != lastKey {
            // A new preset, panel width or screen: start from the model's size, and the next measurement is the new reference.
            lastKey = key
            sessionReferencePx = nil
            pipeline = AdaptiveTextSize(initial: base)
            apply(base, auto: false)
        }
        if settings.liveDistance { startCamera() } else { stopCamera() }
    }

    private func apply(_ value: Double, auto: Bool) {
        guard abs(value - size) > 0.01 else { return }
        lastChangeWasAuto = auto
        size = value
    }

    // MARK: - Camera

    private func startCamera() {
        guard camera == nil, !startingCamera else { return }
        startingCamera = true
        status = "Starting the camera…"
        let camera = FaceCamera()
        camera.onIPD = { [weak self] px in
            Task { @MainActor in self?.receive(ipdPx: px) }
        }
        Task { @MainActor in
            defer { startingCamera = false }
            do {
                cameraName = try await camera.start()
                guard settings.autoTextSize, settings.liveDistance else {
                    camera.stop()
                    return
                }
                self.camera = camera
                pipeline = AdaptiveTextSize(initial: size)
                timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
                status = "\(cameraName): waiting for a face"
            } catch FaceCameraError.denied {
                status = "Camera access is off. Allow it in System Settings > Privacy & Security > Camera."
                settings.liveDistance = false
            } catch {
                status = "No built-in camera was found."
                settings.liveDistance = false
            }
        }
    }

    private func stopCamera() {
        timer?.invalidate()
        timer = nil
        camera?.stop()
        camera = nil
        status = ""
    }

    private func receive(ipdPx: Double) {
        guard camera != nil else { return }
        pipeline.add(1 / ipdPx, at: Self.now) // proportional to the distance
    }

    private func tick() {
        let base = Self.presetSize(settings)
        let width = Self.usableWidth(settings)
        let next = pipeline.tick(at: Self.now, speechPause: speechPause()) { [self] measurement in
            let ipd = 1 / measurement
            let reference = sessionReferencePx ?? (settings.liveReferencePx > 0 ? settings.liveReferencePx : ipd)
            sessionReferencePx = reference
            let wanted = PrompterTypography.relativeSize(reference: base, ipdRefPx: reference, ipdPx: ipd)
            return max(min(wanted, PrompterTypography.widthCap(usableWidth: width)), PrompterTypography.macMinFontSize)
        }
        if let next { apply(next, auto: true) }
        let seen = (pipeline.age(at: Self.now) ?? .infinity) <= AdaptiveTextSize.noFaceTimeout
        let line = "\(cameraName): " + (seen ? "following your distance" : "waiting for a face")
        if line != status { status = line }
    }

    /// "Set my distance": the face width now is where you sit, and the current preset's size is right for it.
    func calibrate() {
        guard let measurement = pipeline.smoothed else { return }
        settings.liveReferencePx = 1 / measurement
        sessionReferencePx = 1 / measurement
        pipeline = AdaptiveTextSize(initial: Self.presetSize(settings))
        apply(Self.presetSize(settings), auto: false)
    }
}
