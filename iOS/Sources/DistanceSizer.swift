import Combine
import Foundation
import SightlineCore
import UIKit

/// Keeps the prompter text sized for where you sit (docs/prompter-typography.md). While the camera runs and
/// Auto text size is on, the front camera's pupil distance gives the viewing distance; the shared pipeline
/// smooths it and commits a new size only when it has really changed. With the setting off, no face, or no
/// camera, the size is simply the Font size setting. A size you set by hand always wins at once and teaches
/// a personal gain, so the model fits your face and eyes.
@MainActor
final class DistanceSizer: ObservableObject {
    /// The size the prompter draws, in points.
    @Published private(set) var appliedSize: Double
    /// Smoothed viewing distance in centimetres while a face is seen; nil otherwise.
    @Published private(set) var distanceCm: Double?
    /// Too far for this screen at a readable size: the hint is shown.
    @Published private(set) var tooFar = false
    /// True when the last size change was made by Auto, so the prompter can ease it in.
    private(set) var lastChangeWasAuto = false

    private let settings: PhoneSettings
    private let ppmm: Double
    private var pipeline: AdaptiveTextSize
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Width the text column can use, in points. Set by the app.
    var usableWidth: () -> Double = { 370 }
    /// Seconds since the speaker last moved on to a new word. Set by the app.
    var speechPause: () -> Double = { 1 }
    /// The reader is dragging the text. Set by the app.
    var isInteracting: () -> Bool = { false }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// The iPhone model identifier ("iPhone17,1"); the simulator reports the model it pretends to be.
    static let modelID: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }()

    init(settings: PhoneSettings) {
        self.settings = settings
        ppmm = PrompterTypography.iPhonePPMM(modelID: Self.modelID)
        #if DEBUG
        if ScreenshotMode.isActive {
            // Store screenshots do not depend on who is holding the phone: a fixed 45 cm.
            let fixed = PrompterTypography.fontSize(distanceMm: ScreenshotMode.simulatedDistanceCm * 10, ppmm: ppmm)
            appliedSize = fixed
            pipeline = AdaptiveTextSize(initial: fixed)
            return
        }
        #endif
        appliedSize = settings.fontSize
        pipeline = AdaptiveTextSize(initial: settings.fontSize)

        settings.$fontSize
            .dropFirst()
            .sink { [weak self] size in self?.userChangedSize(size) }
            .store(in: &cancellables)
    }

    private func plan(_ distanceMm: Double, gain: Double? = nil) -> PrompterTypography.Plan {
        PrompterTypography.plan(distanceMm: distanceMm, ppmm: ppmm, usableWidth: usableWidth(), gain: gain ?? settings.personalGain)
    }

    // MARK: - Running

    /// Starts listening for distances (the camera is running, Auto is on). Every start begins fresh, so the
    /// first measurement is applied at once.
    func start() {
        guard timer == nil else { return }
        pipeline = AdaptiveTextSize(initial: appliedSize)
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Stops measuring. The size stays where it is.
    func stop() {
        timer?.invalidate()
        timer = nil
        distanceCm = nil
        tooFar = false
    }

    /// One distance measurement in millimetres, from the camera.
    func ingest(distanceMm: Double) {
        guard timer != nil else { return }
        pipeline.add(distanceMm, at: Self.now)
    }

    private func tick() {
        let time = Self.now
        let size = pipeline.tick(at: time, speechPause: speechPause(), userInteracting: isInteracting()) { [self] in plan($0).fontSize }
        if let size, size != appliedSize {
            lastChangeWasAuto = true
            appliedSize = size
        }
        let seen = (pipeline.age(at: time) ?? .infinity) <= AdaptiveTextSize.noFaceTimeout
        let distance = seen ? pipeline.smoothed : nil
        // Rounded to 5 cm: the estimate is good to about 6 to 9 percent, so no false precision.
        let shown = distance.map { ($0 / 50).rounded() * 5 }
        if shown != distanceCm { distanceCm = shown }
        let far = distance.map { plan($0).tooFar } ?? false
        if far != tooFar { tooFar = far }
    }

    /// The Font size setting changed by hand. It applies at once; with Auto running it also teaches the gain.
    private func userChangedSize(_ size: Double) {
        lastChangeWasAuto = false
        appliedSize = size
        pipeline.manual(size, at: Self.now)
        if timer != nil, let distance = pipeline.smoothed {
            let ideal = plan(distance, gain: 1).fontSize
            settings.personalGain = min(max(size / ideal, 0.8), 1.25)
        }
    }

    /// Auto text size was turned off: back to the Font size setting.
    func autoTurnedOff() {
        stop()
        lastChangeWasAuto = false
        appliedSize = settings.fontSize
    }
}
