import AVFoundation
import Aligner
import Foundation
import Speech

/// Listens to speech in the script's language and reports the script word the reader is at.
@MainActor
final class SpeechTracker {
    var onCursorChange: ((Int) -> Void)?
    var onStatus: ((String) -> Void)?
    /// Word range currently on screen. Speech is only matched inside it.
    var visibleWords: (() -> ClosedRange<Int>?)?
    private(set) var isRunning = false

    private var script: String
    private var aligner: ScriptAligner
    private var language: ScriptLanguage
    private var recognizer: SFSpeechRecognizer?
    private var engine: SpeechEngine?
    private var analyzerActive = false
    private var lastPartial = ""
    /// Bumped on every start and stop so a launch that finishes late is discarded.
    private var session = 0

    /// True when audio goes to Apple's servers: the legacy engine on a language without an on-device model.
    var usesServerRecognition: Bool {
        !analyzerActive && recognizer?.supportsOnDeviceRecognition == false
    }

    init(script: String, language: String) {
        let resolved = ScriptLanguage.named(language)
        self.script = script
        self.language = resolved
        aligner = ScriptAligner(script: script, language: resolved)
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: resolved.id))
    }

    func setLanguage(_ identifier: String) {
        setLanguage(ScriptLanguage.named(identifier))
    }

    /// Switches the recognition language and re-segments the script. A running session is restarted
    /// with the new locale. The cursor keeps its word index.
    func setLanguage(_ language: ScriptLanguage) {
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

    func setScript(_ text: String) {
        script = text
        aligner = ScriptAligner(script: text, language: language)
        lastPartial = ""
    }

    func reset(to wordIndex: Int) {
        aligner.reset(to: wordIndex)
        lastPartial = ""
    }

    func start() {
        guard !isRunning else { return }
        let token = session
        Self.requestAccess { [weak self] speechOK, micOK in
            Task { @MainActor in await self?.launch(token: token, speechOK: speechOK, micOK: micOK) }
        }
    }

    func stop() {
        session += 1
        guard isRunning else { return }
        isRunning = false
        analyzerActive = false
        engine?.stop()
        engine = nil
        onStatus?("Stopped")
    }

    private func launch(token: Int, speechOK: Bool, micOK: Bool) async {
        guard token == session, !isRunning else { return }
        guard speechOK, micOK else {
            onStatus?("Microphone or speech permission denied")
            return
        }
        isRunning = true
        let locale = Locale(identifier: language.id)

        if let analyzer = await analyzerEngineIfReady(locale) {
            let analyzerError = await attach(analyzer, locale: locale, token: token)
            guard isRunning, token == session else { return }
            if analyzerError == nil {
                analyzerActive = true
                return
            }
        }

        let legacyError = await attach(LegacySpeechEngine(), locale: locale, token: token)
        guard isRunning, token == session else { return }
        analyzerActive = false
        if let legacyError {
            isRunning = false
            engine = nil
            onStatus?(legacyError.localizedDescription)
        }
    }

    /// The on-device analyzer engine, used only where the legacy engine would send audio to Apple's
    /// servers and the language model is installed. Languages the legacy engine handles on device
    /// keep using it.
    private func analyzerEngineIfReady(_ locale: Locale) async -> SpeechEngine? {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *),
           recognizer?.supportsOnDeviceRecognition == false,
           await AnalyzerSpeechEngine.isInstalled(locale) {
            return AnalyzerSpeechEngine()
        }
        #endif
        return nil
    }

    /// Makes the engine current and starts it. Returns the failure, leaving no engine behind.
    private func attach(_ candidate: SpeechEngine, locale: Locale, token: Int) async -> Error? {
        engine = candidate
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

    private func process(_ text: String) {
        guard text != lastPartial else { return }
        lastPartial = text

        // The reader only ever speaks words on screen, so matching is limited to them.
        aligner.allowedRange = visibleWords?()
        guard let cursor = aligner.consume(transcript: text) else { return }
        onCursorChange?(cursor)
    }

    /// Asks for speech and microphone access. Callbacks arrive on arbitrary threads.
    private nonisolated static func requestAccess(_ done: @escaping @Sendable (Bool, Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speech in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                done(speech == .authorized, mic)
            }
        }
    }
}
