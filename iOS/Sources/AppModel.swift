import Aligner
import Combine
import SightlineCore
import UIKit

/// Holds the teleprompter's state: the library, the active script, speech tracking, gamepad, pace and
/// control visibility. The iPhone counterpart of the macOS AppDelegate.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var activeScript: Script?
    @Published private(set) var isPlaying = false
    @Published private(set) var isTracking = false
    @Published private(set) var statusText = ""
    @Published private(set) var paceText: String?
    @Published private(set) var controlsVisible = true
    /// Camera side in landscape, from the device orientation. The Camera setting can override it.
    @Published private(set) var deviceCameraEdge: CameraEdge = .left
    /// Camera mode: the live preview is behind the prompter text and the camera controls replace the transport row.
    @Published private(set) var cameraOn = false

    let settings = PhoneSettings.shared
    let library: LibraryStore
    let catalog = LanguageCatalog()
    let prompter = PrompterUIView(settings: PhoneSettings.shared)
    let tracker = SpeechTracker(script: "", language: "en-US")
    let camera = CameraEngine()

    private let controller = ControllerInput()
    private let light = GamepadLight()
    private var pace = PaceMeter()
    private var totalWords = 0
    private var lastStatusWasError = false
    private var hideTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Camera edge the layout uses in landscape, after the Camera setting is applied.
    var cameraEdge: CameraEdge {
        switch settings.cameraSide {
        case .automatic: deviceCameraEdge
        case .left: .left
        case .right: .right
        }
    }

    init() {
        library = LibraryStore(directory: Self.libraryFolder)
        UIApplication.shared.isIdleTimerDisabled = true

        prompter.onManualScrollEnded = { [weak self] index in self?.tracker.reset(to: index) }
        prompter.onTap = { [weak self] in
            self?.togglePlay()
            self?.showControls()
        }
        tracker.onCursorChange = { [prompter] index in prompter.setCursor(wordIndex: index) }
        tracker.visibleWords = { [prompter] in prompter.visibleWordRange() }
        tracker.onStatus = { [weak self] text in self?.receiveStatus(text) }
        camera.onAudioBuffer = { [weak self] buffer in self?.tracker.feed(buffer) }
        controller.delegate = self
        controller.stickResponse = { [settings] in (Float(settings.stickDeadzone), settings.stickCurve) }
        controller.start()

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default
            .publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in self?.deviceOrientationChanged() }
            .store(in: &cancellables)
        updateDeviceCameraEdge()

        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.samplePace() }
            .store(in: &cancellables)

        settings.$gamepadLight
            .dropFirst()
            .sink { [weak self] _ in self?.refreshControls() }
            .store(in: &cancellables)

        if library.scripts.isEmpty {
            library.create(title: "Welcome", language: .named("en-US"), text: Self.welcomeText)
        }
        seedTurkishSample()
        reloadActiveScript()

        // While the camera records, the script follows the speaker: tracking starts with the camera.
        camera.$status
            .sink { [weak self] status in
                guard status == .running, let self, self.cameraOn, !self.tracker.isRunning else { return }
                self.tracker.start()
                self.refreshControls()
            }
            .store(in: &cancellables)
    }

    // MARK: - Library and active script

    /// Adds a Turkish test script once, so Turkish recognition can be tried without importing anything.
    private func seedTurkishSample() {
        let key = "seededTurkishSample"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        library.create(title: "Türkçe Örnek Metin", language: .named("tr-TR"), text: Self.turkishSampleText)
    }

    /// Loads a library script into the prompter and the speech tracker.
    func activate(_ script: Script?) {
        activeScript = script
        settings.activeScriptID = script?.id.uuidString ?? ""

        let language = script?.language ?? .named("en-US")
        let text = script?.text ?? ""
        prompter.load(script: text, language: language)
        tracker.setScript(text)
        tracker.setLanguage(language)
        tracker.reset(to: 0)

        totalWords = ScriptTokenizer.tokenize(text, language: language).count
        pace.reset()
        refreshControls()
    }

    /// Loads the script that was active last time, or the first one in the library.
    func reloadActiveScript() {
        let id = UUID(uuidString: settings.activeScriptID)
        activate(library.scripts.first { $0.id == id } ?? library.scripts.first)
    }

    /// Called when the Library closes: picks up edits to the active script, or a deleted one.
    func libraryDidChange() {
        guard let active = activeScript,
              let updated = library.scripts.first(where: { $0.id == active.id }) else {
            reloadActiveScript()
            return
        }
        if updated.text != active.text || updated.languageID != active.languageID {
            activate(updated)
        }
    }

    // MARK: - Transport

    func togglePlay() {
        prompter.togglePlay()
        refreshControls()
    }

    /// Stops auto-scroll, for example when a sheet opens over the prompter.
    func pause() {
        if prompter.isPlaying {
            togglePlay()
        }
    }

    func restart() {
        prompter.restart()
        tracker.reset(to: 0)
        refreshControls()
    }

    func adjustSpeed(_ direction: Int) {
        prompter.adjustSpeed(by: CGFloat(direction) * 10)
    }

    func toggleTracking() {
        if tracker.isRunning {
            tracker.stop()
        } else {
            tracker.start()
        }
        refreshControls()
    }

    /// The app left the foreground: stop scrolling, listening and the camera. A recording in progress is saved.
    func enterBackground() {
        pause()
        if tracker.isRunning {
            tracker.stop()
        }
        if cameraOn {
            camera.stop()
        }
    }

    /// The app is active again: restart the camera if camera mode was on.
    func enterForeground() {
        if cameraOn {
            camera.start()
        }
    }

    // MARK: - Camera mode

    /// Camera mode also moves speech tracking onto the camera's microphone audio, so the two never open the
    /// microphone at the same time.
    func setCameraOn(_ on: Bool) {
        cameraOn = on
        if !on, tracker.isRunning {
            // Leaving the camera ends tracking; switching audio source would reopen the microphone.
            tracker.stop()
        }
        prompter.setCameraMode(on)
        tracker.setExternalAudio(on)
        if on {
            camera.start()
        } else {
            camera.stop()
        }
        refreshControls()
    }

    // MARK: - Controls visibility

    func showControls() {
        controlsVisible = true
        scheduleAutoHide()
    }

    func toggleControls() {
        if controlsVisible {
            hideTask?.cancel()
            controlsVisible = false
        } else {
            showControls()
        }
    }

    /// While the script scrolls the controls fade out, so the text is unobstructed. Paused, they stay.
    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard isPlaying else { return }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self, self.isPlaying else { return }
            self.controlsVisible = false
        }
    }

    // MARK: - Status

    private func receiveStatus(_ text: String) {
        statusText = text
        lastStatusWasError = !(text == "Listening…" || text == "Stopped" || text.hasPrefix("On-device"))
        refreshControls()
    }

    private func refreshControls() {
        isPlaying = prompter.isPlaying
        isTracking = tracker.isRunning
        light.set(lightState)
        scheduleAutoHide()
    }

    private var lightState: GamepadLight.State {
        guard settings.gamepadLight else { return .off }
        if tracker.isRunning { return .listening }
        if lastStatusWasError { return .error }
        if prompter.isPlaying { return .scrolling }
        return .idle
    }

    private func deviceOrientationChanged() {
        updateDeviceCameraEdge()
        camera.updateOrientation(UIDevice.current.orientation)
    }

    private func updateDeviceCameraEdge() {
        switch UIDevice.current.orientation {
        case .landscapeLeft: deviceCameraEdge = .left
        case .landscapeRight: deviceCameraEdge = .right
        default: break
        }
    }

    private func samplePace() {
        let running = prompter.isPlaying || tracker.isRunning
        guard running, settings.showPace, totalWords > 0 else {
            if !running { pace.reset() }
            paceText = nil
            return
        }

        let index = prompter.currentWordIndex
        pace.record(units: index, time: ProcessInfo.processInfo.systemUptime)

        let language = activeScript?.language ?? .named("en-US")
        var parts: [String] = []
        if language.spaced, let rate = pace.unitsPerMinute() {
            parts.append("\(Int(rate.rounded())) wpm")
        }
        if let seconds = pace.remainingSeconds(remainingUnits: totalWords - index) {
            parts.append("\(Self.clock(seconds)) left")
        }
        paceText = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Storage

    /// Scripts live in Documents/Sightline Prompter, visible in the Files app.
    private static var libraryFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sightline Prompter", isDirectory: true)
    }

    private static let turkishSampleText = """
    Merhaba, ben Berk. Bugün size teleprompter ile kamera karşısında nasıl daha rahat konuşabileceğinizi anlatacağım.

    Metni okurken gözleriniz sürekli kameraya yakın kalır. Böylece izleyiciyle göz teması kurduğunuz izlenimini verirsiniz. Okuduğunuz kelime, ön kameranın hemen altında durur.

    Konuşmaya başladığınızda uygulama sesinizi dinler ve metni sizin hızınıza göre kaydırır. Yavaş konuşursanız yavaşlar, hızlandığınızda size yetişir. Duraksadığınızda ise olduğu yerde bekler.

    Şimdi birkaç zor kelime deneyelim: çocukların güzel şarkıları, ığdır'dan gelen öğretmen, yağmurlu bir pazartesi sabahı. Ayrıca sayıları da okuyalım: bir, iki, üç, dört, beş, yirmi beş, yüz, bin.

    Videoyu bitirmeden önce izleyicilere teşekkür etmeyi unutmayın. İzlediğiniz için çok teşekkür ederim, bir sonraki videoda görüşmek üzere, hoşça kalın.
    """

    private static let welcomeText = """
    Welcome to Sightline Prompter.

    Hold the phone so the front camera is close to the text. The word you are reading sits just below the lens, so you can look at the camera while you read.

    Tap the text to start and stop scrolling. Turn on speech tracking, and the script follows your voice. Add your own scripts in Library.
    """
}

// MARK: - ControllerInputDelegate

extension AppModel: ControllerInputDelegate {
    func controllerStick(_ value: Float) {
        prompter.setStick(CGFloat(value))
    }

    func controllerAdjustSpeed(_ direction: Int) {
        adjustSpeed(direction)
    }

    func controllerTogglePlay() {
        togglePlay()
    }

    func controllerRestart() {
        restart()
    }

    func controllerJumpParagraph(forward: Bool) {
        prompter.jumpParagraph(forward: forward)
        tracker.reset(to: prompter.currentWordIndex)
    }

    func controllerToggleTracking() {
        toggleTracking()
    }

    func controllerToggleVisibility() {
        toggleControls()
    }
}
