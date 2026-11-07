import AVFoundation
import Aligner
import Foundation
import Speech

/// Listens to speech in the script's language and reports the script word the reader is at.
@MainActor
public final class SpeechTracker {
    public var onCursorChange: ((Int) -> Void)?
    public var onStatus: ((String) -> Void)?
    /// Word range currently on screen. Speech is only matched inside it.
    public var visibleWords: (() -> ClosedRange<Int>?)?
    public private(set) var isRunning = false
    /// True while audio comes from another capture session (the camera records and passes its audio through
    /// `feed`). The microphone and the audio session are then left to that session.
    public private(set) var usesExternalAudio = false

    private var script: String
    private var aligner: ScriptAligner
    private var language: ScriptLanguage
    private var recognizer: SFSpeechRecognizer?
    private var engine: SpeechEngine?
    private var analyzerActive = false
    private var lastPartial = ""
    /// Bumped on every start and stop so a launch that finishes late is discarded.
    private var session = 0
    /// Set when a phone call or other system interruption stopped tracking, so it resumes afterwards.
    private var resumeAfterInterruption = false
    #if os(iOS)
    private var interruptionObserver: NSObjectProtocol?
    #endif

    /// True when audio goes to Apple's servers: the legacy engine on a language without an on-device model.
    public var usesServerRecognition: Bool {
        !analyzerActive && recognizer?.supportsOnDeviceRecognition == false
    }

    public init(script: String, language: String) {
        let resolved = ScriptLanguage.named(language)
        self.script = script
        self.language = resolved
        aligner = ScriptAligner(script: script, language: resolved)
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: resolved.id))
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let kind = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            Task { @MainActor in self?.handleInterruption(kind) }
        }
        #endif
    }

    public func setLanguage(_ identifier: String) {
        setLanguage(ScriptLanguage.named(identifier))
    }

    /// Switches the recognition language and re-segments the script. A running session is restarted
    /// with the new locale. The cursor keeps its word index.
    public func setLanguage(_ language: ScriptLanguage) {
        guard language != self.language else { return }
        let wasRunning = isRunning
        let cursor = aligner.cursor
        stop()
        self.language = language
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.id))
        aligner = ScriptAligner(script: script, language: language)
        aligner.reset(to: cursor)
        lastPartial = ""
        if wasRunning { start() }
    }

    /// Switches between the microphone and audio fed from a capture session. A running session restarts.
    public func setExternalAudio(_ on: Bool) {
        guard on != usesExternalAudio else { return }
        let wasRunning = isRunning
        stop()
        usesExternalAudio = on
        if wasRunning { start() }
    }

    /// Passes microphone audio from the capture session to the recognizer.
    public func feed(_ buffer: AVAudioPCMBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        let gap = now - lastFeed
        lastFeed = now
        // The camera's audio went quiet for a moment (a notification sound, a call, a camera switch) and
        // is back: start recognition fresh, since the recognizer may have given up in the meantime.
        if isRunning, usesExternalAudio, lastFeed > 0, gap > 1.5 {
            restartRecognition()
            return
        }
        engine?.append(buffer)
    }

    /// Free version: how long one tracking run may last. nil means no limit.
    public var sessionLimit: (() -> TimeInterval?)?
    /// Called after a run ended because the limit was reached.
    public var onLimitReached: (() -> Void)?
    private var limitTask: Task<Void, Never>?

    private func armLimit() {
        limitTask?.cancel()
        limitTask = nil
        guard let seconds = sessionLimit?() else { return }
        limitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.stop()
            self.onLimitReached?()
        }
    }

    /// When audio last arrived from the capture session, in system uptime seconds.
    private var lastFeed: TimeInterval = 0

    /// Starts the recognizer again, keeping the position in the script.
    private func restartRecognition() {
        guard isRunning else { return }
        stop()
        start()
    }

    public func setScript(_ text: String) {
        script = text
        aligner = ScriptAligner(script: text, language: language)
        lastPartial = ""
    }

    public func reset(to wordIndex: Int) {
        aligner.reset(to: wordIndex)
        lastPartial = ""
    }

    public func start() {
        guard !isRunning else { return }
        resumeAfterInterruption = false
        let token = session
        Self.requestAccess { [weak self] speechOK, micOK in
            Task { @MainActor in await self?.launch(token: token, speechOK: speechOK, micOK: micOK) }
        }
    }

    public func stop() {
        limitTask?.cancel()
        limitTask = nil
        session += 1
        guard isRunning else { return }
        isRunning = false
        analyzerActive = false
        engine?.stop()
        engine = nil
        if !usesExternalAudio {
            AudioSession.deactivate()
        }
        onStatus?("Stopped")
    }

    private func launch(token: Int, speechOK: Bool, micOK: Bool) async {
        guard token == session, !isRunning else { return }
        guard speechOK, micOK else {
            onStatus?("Microphone or speech permission denied")
            return
        }
        if !usesExternalAudio {
            do {
                try AudioSession.activateForListening()
            } catch {
                onStatus?("Audio unavailable: \(error.localizedDescription)")
                return
            }
        }
        isRunning = true
        armLimit()
        let locale = Locale(identifier: language.id)

        if let analyzer = await analyzerEngineIfReady(locale) {
            let analyzerError = await attach(analyzer, locale: locale, token: token)
            guard isRunning, token == session else { return }
            if analyzerError == nil {
                analyzerActive = true
                return
            }
        }

        let legacyError = await attach(LegacySpeechEngine(externalAudio: usesExternalAudio), locale: locale, token: token)
        guard isRunning, token == session else { return }
        analyzerActive = false
        if let legacyError {
            isRunning = false
            engine = nil
            if !usesExternalAudio {
                AudioSession.deactivate()
            }
            onStatus?(legacyError.localizedDescription)
        }
    }

    /// The on-device analyzer engine, used only where the legacy engine would send audio to Apple's
    /// servers and the language model is installed. Languages the legacy engine handles on device
    /// keep using it. With external audio (the camera) it takes the same buffers the legacy engine would.
    private func analyzerEngineIfReady(_ locale: Locale) async -> SpeechEngine? {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *),
           recognizer?.supportsOnDeviceRecognition == false,
           await AnalyzerSpeechEngine.isInstalled(locale) {
            return AnalyzerSpeechEngine(externalAudio: usesExternalAudio)
        }
        #endif
        return nil
    }

    /// Makes the engine current and starts it. Returns the failure, leaving no engine behind.
    private func attach(_ candidate: SpeechEngine, locale: Locale, token: Int) async -> Error? {
        engine = candidate
        candidate.contextualStrings = contextHints()
        candidate.onText = { [weak self] text in self?.process(text) }
        candidate.onStatus = { [weak self] status in self?.onStatus?(status) }
        do {
            try await candidate.start(locale: locale)
            return nil
        } catch {
            candidate.stop()
            if engine === candidate { engine = nil }
            return error
        }
    }

    /// Distinct words of the script from the cursor on, longest first within the next stretch: the words a
    /// recognizer is most likely to get wrong (names, rare and long words).
    private func contextHints() -> [String] {
        var seen = Set<String>()
        var hints: [String] = []
        for token in aligner.tokens.dropFirst(aligner.cursor).prefix(600) {
            let word = token.display.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            guard word.count >= 4, seen.insert(word.lowercased()).inserted else { continue }
            hints.append(word)
        }
        return Array(hints.sorted { $0.count > $1.count }.prefix(100))
    }

    private func process(_ text: String) {
        guard text != lastPartial else { return }
        lastPartial = text

        // The reader only ever speaks words on screen, so matching is limited to them.
        aligner.allowedRange = visibleWords?()
        guard let cursor = aligner.consume(transcript: text) else { return }
        onCursorChange?(cursor)
    }

    #if os(iOS)
    /// A phone call or Siri takes the microphone: stop, then start again when the system gives it back.
    private func handleInterruption(_ kind: AVAudioSession.InterruptionType?) {
        // Camera audio belongs to the capture session, which rides out an interruption on its own, and
        // `feed` restarts recognition when the audio comes back. Stopping here would leave tracking off
        // whenever the matching "ended" never arrives.
        guard !usesExternalAudio else { return }
        switch kind {
        case .began:
            guard isRunning else { return }
            resumeAfterInterruption = true
            stop()
        case .ended:
            guard resumeAfterInterruption else { return }
            resumeAfterInterruption = false
            start()
        default:
            break
        }
    }
    #endif

    /// Asks for speech and microphone access. Callbacks arrive on arbitrary threads.
    private nonisolated static func requestAccess(_ done: @escaping @Sendable (Bool, Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speech in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                done(speech == .authorized, mic)
            }
        }
    }
}

/// Microphone session setup. iOS needs an active record session before the input node reports a format.
/// macOS has no session to configure.
enum AudioSession {
    static func activateForListening() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: [])
        #endif
    }

    static func deactivate() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
