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
    private var recognizer: SFSpeechRecognizer?
    private var language: ScriptLanguage
    private let engine = AVAudioEngine()
    /// The engine stays up across recognition sessions; the tap feeds whichever request the box holds.
    private let box = RequestBox()
    private var task: SFSpeechRecognitionTask?
    private var restartWork: Task<Void, Never>?
    /// Bumped per session so callbacks from ended sessions are ignored.
    private var generation = 0
    private var lastPartial = ""
    private var failures = 0

    /// True when the recognizer has no on-device model for the language, so audio goes to Apple's servers.
    var usesServerRecognition: Bool {
        recognizer?.supportsOnDeviceRecognition == false
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
        Self.requestAccess { [weak self] speechOK, micOK in
            Task { @MainActor in self?.launch(speechOK: speechOK, micOK: micOK) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        restartWork?.cancel()
        restartWork = nil
        generation += 1
        endCurrentTask()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        onStatus?("Stopped")
    }

    private func launch(speechOK: Bool, micOK: Bool) {
        guard !isRunning else { return }
        guard speechOK, micOK else {
            onStatus?("Microphone or speech permission denied")
            return
        }
        guard let recognizer else {
            onStatus?("Speech recognizer could not be created")
            return
        }
        do {
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: makeTapBlock(box))
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            onStatus?(error.localizedDescription)
            return
        }
        isRunning = true
        beginSession()
        guard isRunning else { return }
        onStatus?(recognizer.supportsOnDeviceRecognition
            ? "Listening…"
            : "On-device model not installed — using server recognition")
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            stop()
            onStatus?("Speech recognizer unavailable")
            return
        }
        generation += 1
        let gen = generation

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .dictation
        box.set(request)

        let handler: @Sendable (SFSpeechRecognitionResult?, Error?) -> Void = { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let message = error?.localizedDescription
            Task { @MainActor in
                self?.handleResult(generation: gen, text: text, isFinal: isFinal, errorMessage: message)
            }
        }
        task = recognizer.recognitionTask(with: request, resultHandler: handler)
    }

    private func handleResult(generation gen: Int, text: String?, isFinal: Bool, errorMessage: String?) {
        guard isRunning, gen == generation else { return }
        if let text, !text.isEmpty { process(text) }
        guard isFinal || errorMessage != nil else { return }

        // Session ended (time limit, error or silence). Start a fresh one; the cursor is kept.
        failures = errorMessage == nil ? 0 : failures + 1
        generation += 1
        endCurrentTask()
        let delay = failures >= 5 ? 2.0 : 0.2
        if failures >= 5, let errorMessage { onStatus?("Retrying recognition: \(errorMessage)") }
        restartWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.isRunning else { return }
            self.beginSession()
        }
    }

    private func process(_ text: String) {
        guard text != lastPartial else { return }
        lastPartial = text
        failures = 0

        // The reader only ever speaks words on screen, so matching is limited to them.
        aligner.allowedRange = visibleWords?()
        guard let cursor = aligner.consume(transcript: text) else { return }
        onCursorChange?(cursor)
    }

    private func endCurrentTask() {
        box.take()?.endAudio()
        task?.cancel()
        task = nil
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

/// Holds the live recognition request; the audio tap appends to it from the audio thread.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }

    func take() -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let current = request
        request = nil
        return current
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }
}

/// Built outside the main actor so the tap runs on the audio thread without isolation checks.
private func makeTapBlock(_ box: RequestBox) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
    { buffer, _ in box.append(buffer) }
}
