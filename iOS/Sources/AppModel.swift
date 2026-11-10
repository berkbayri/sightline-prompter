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
    let pro = ProStore.shared
    /// Set when a free-version limit was hit or a Pro feature was tapped; the root view shows the paywall.
    @Published var showPaywall = false

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
        camera.isProUnlocked = { [pro] in pro.isUnlocked }
        camera.onRecordingLimit = { [weak self] in self?.showPaywall = true }
        tracker.sessionLimit = { [pro] in pro.isUnlocked ? nil : FreeTier.maxTrackingSeconds }
        tracker.onLimitReached = { [weak self] in
            self?.receiveStatus("Free voice following ended after \(Int(FreeTier.maxTrackingSeconds / 60)) minutes. Sightline Pro removes the limit.")
            self?.refreshControls()
            self?.showPaywall = true
        }
        #if DEBUG
        if !ScreenshotMode.isActive { pro.start() }
        #else
        pro.start()
        #endif
        pro.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // The entitlement may have changed: recompute what the camera offers.
                Task { @MainActor in self?.camera.entitlementChanged() }
            }
            .store(in: &cancellables)
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
        if Self.isShared { library.republishAll() }

        // Scripts changed on the other device show up in the prompter within seconds, in the camera view too.
        library.$scripts
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.libraryDidChange() }
            .store(in: &cancellables)
        camera.$isRecording
            .removeDuplicates()
            .filter { !$0 }
            .dropFirst()
            .sink { [weak self] _ in self?.libraryDidChange() }
            .store(in: &cancellables)

        seedTurkishSample()
        #if DEBUG
        if ScreenshotMode.isActive { seedScreenshotLibrary() }
        #endif
        reloadActiveScript()

        // While the camera records, the script follows the speaker: tracking starts with the camera.
        camera.$status
            .sink { [weak self] status in
                guard status == .running, let self, self.cameraOn, !self.tracker.isRunning else { return }
                self.startTrackingIfAllowed()
                self.refreshControls()
            }
            .store(in: &cancellables)
    }

    // MARK: - Library and active script

    #if DEBUG
    /// Fills the library with realistic scripts for App Store screenshots (simulator, debug builds only).
    private func seedScreenshotLibrary() {
        for script in library.scripts { library.delete(script.id) }
        for item in ScreenshotMode.scripts.reversed() {
            let id = item.title.hasPrefix("Türkçe") ? "tr-TR" : "en-US"
            library.create(title: item.title, language: .named(id), text: item.text)
        }
        pro.useSampleOffers()
        if let first = library.scripts.first(where: { $0.title == "Product launch video" }) {
            settings.activeScriptID = first.id.uuidString
        }
    }
    #endif

    /// Adds a Turkish test script once, so Turkish recognition can be tried without importing anything.
    /// Copies saved by earlier versions, whose opening line carried a personal name, are updated to the generic
    /// text. A sample the user has edited is left alone.
    private func seedTurkishSample() {
        let title = "Türkçe Örnek Metin"
        for script in library.scripts where script.title == title && script.text.hasPrefix("Merhaba, ben ") {
            library.update(script.id, text: Self.turkishSampleText)
        }
        let key = "seededTurkishSample"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        library.create(title: title, language: .named("tr-TR"), text: Self.turkishSampleText)
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

    #if DEBUG
    /// Appends a line to Caches/sync.log (debug builds), next to the library's own sync log.
    private static func debugLog(_ message: String) {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let url = caches.appendingPathComponent("sync.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (old + line).write(to: url, atomically: true, encoding: .utf8)
    }
    #endif

    /// Loads the script that was active last time, or the first one in the library.
    func reloadActiveScript() {
        let id = UUID(uuidString: settings.activeScriptID)
        activate(library.scripts.first { $0.id == id } ?? library.scripts.first)
    }

    /// Picks up edits to the active script (made here, or on the Mac and synced in), or a deleted one. The reading
    /// position stays where it was. While a take is being recorded the prompter text is left alone; the change is
    /// applied when the recording stops.
    func libraryDidChange() {
        guard !camera.isRecording else { return }
        guard let active = activeScript,
              let updated = library.scripts.first(where: { $0.id == active.id }) else {
            reloadActiveScript()
            return
        }
        if updated.text != active.text || updated.languageID != active.languageID {
            let position = prompter.currentWordIndex
            #if DEBUG
            Self.debugLog("active script updated from library at word \(position)")
            #endif
            activate(updated)
            if position > 0 {
                let clamped = min(position, max(totalWords - 1, 0))
                prompter.setCursor(wordIndex: clamped)
                tracker.reset(to: clamped)
            }
        } else if updated != active {
            activeScript = updated
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
            startTrackingIfAllowed()
        }
        refreshControls()
    }

    /// Starts voice following. In the free version only English, Turkish and Spanish scripts are followed.
    private func startTrackingIfAllowed() {
        let language = activeScript?.language ?? .named("en-US")
        guard pro.isUnlocked || FreeTier.allowsLanguage(language.id) else {
            receiveStatus("Voice following in \(language.name) is part of Sightline Pro.")
            showPaywall = true
            return
        }
        tracker.start()
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
        // Edits made on the Mac while the app was in the background.
        library.load()
    }

    // MARK: - Camera mode

    /// Camera mode also moves speech tracking onto the camera's microphone audio, so the two never open the
    /// microphone at the same time.
    func setCameraOn(_ on: Bool) {
        #if DEBUG
        if ScreenshotMode.isActive {
            // No camera in the simulator: only the layout is set up.
            cameraOn = on
            prompter.setCameraMode(on)
            refreshControls()
            return
        }
        #endif
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
        guard running, settings.showPace, pro.isUnlocked, totalWords > 0 else {
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

    /// This phone's own library folder: Documents/Sightline Prompter, visible in the Files app. Used when iCloud is
    /// not available, and as the place earlier versions saved scripts.
    private static var localLibraryFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(LibraryContainer.legacyFolderName, isDirectory: true)
    }

    /// Where scripts live, best first: the iCloud container shared with the Mac app (iCloud Drive > Sightline Prompter),
    /// a folder picked in Settings (for builds that cannot have the iCloud entitlement), or this phone only. Scripts
    /// saved on the phone earlier are moved into the shared folder.
    private static var libraryFolder: URL {
        if let shared = LibraryContainer.documentsURL ?? LibraryFolderBookmark.resolve() {
            LibraryContainer.adopt(from: [localLibraryFolder, LibraryContainer.nestedFolder(in: shared)], into: shared)
            return shared
        }
        return localLibraryFolder
    }

    /// True when scripts live in a folder shared with the Mac (the iCloud container or a folder chosen in Files).
    static var isShared: Bool {
        LibraryContainer.documentsURL != nil || LibraryFolderBookmark.isSet
    }

    /// Starts sharing scripts through a folder the user picked in iCloud Drive. The scripts on this phone move into
    /// it, and the library switches to it at once.
    func useSharedFolder(_ picked: URL) throws {
        try LibraryFolderBookmark.save(picked)
        guard let folder = LibraryFolderBookmark.resolve() else {
            throw CocoaError(.fileReadNoPermission)
        }
        LibraryContainer.adopt(from: [Self.localLibraryFolder, LibraryContainer.nestedFolder(in: folder)], into: folder)
        library.relocate(to: folder)
        library.republishAll()
        reloadActiveScript()
    }

    /// Where the library is stored now, for Settings.
    static var libraryDescription: String {
        if LibraryContainer.documentsURL != nil { return "iCloud Drive, shared with your Mac" }
        if LibraryFolderBookmark.isSet { return "Folder you chose in Files" }
        return "This iPhone only"
    }

    private static let turkishSampleText = """
    Merhaba sevgili izleyiciler. Bugün size teleprompter ile kamera karşısında nasıl daha rahat konuşabileceğinizi anlatacağım.

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
        guard pro.isUnlocked else { return }
        prompter.setStick(CGFloat(value))
    }

    func controllerAdjustSpeed(_ direction: Int) {
        guard pro.isUnlocked else { return }
        adjustSpeed(direction)
    }

    func controllerTogglePlay() {
        guard pro.isUnlocked else { return }
        togglePlay()
    }

    func controllerRestart() {
        guard pro.isUnlocked else { return }
        restart()
    }

    func controllerJumpParagraph(forward: Bool) {
        guard pro.isUnlocked else { return }
        prompter.jumpParagraph(forward: forward)
        tracker.reset(to: prompter.currentWordIndex)
    }

    func controllerToggleTracking() {
        guard pro.isUnlocked else { return }
        toggleTracking()
    }

    func controllerToggleVisibility() {
        guard pro.isUnlocked else { return }
        toggleControls()
    }
}
