import AVFoundation
import Foundation
import Speech

/// SFSpeechRecognizer recognition. Runs on every supported macOS. Audio stays on device only when
/// the language's Dictation model is installed; otherwise Apple's servers recognize it.
@MainActor
final class LegacySpeechEngine: SpeechEngine {
    var onText: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    /// The engine stays up across recognition sessions; the tap feeds whichever request the box holds.
    private let box = RequestBox()
    private var task: SFSpeechRecognitionTask?
    private var restartWork: Task<Void, Never>?
    /// Bumped per session so callbacks from ended sessions are ignored.
    private var generation = 0
    private var lastText = ""
    private var failures = 0
    private var isRunning = false

    func start(locale: Locale) async throws {
        stop()
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechEngineError.recognizerUnavailable
        }
        self.recognizer = recognizer
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: makeTapBlock(box))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
        beginSession()
        onStatus?(recognizer.supportsOnDeviceRecognition
            ? "Listening…"
            : "On-device model not installed — using server recognition")
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
    }

    private func beginSession() {
        guard let recognizer else { return }
        guard recognizer.isAvailable else {
            onStatus?(SpeechEngineError.recognizerUnavailable.localizedDescription)
            scheduleRestart(after: 2)
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
        if let text, !text.isEmpty, text != lastText {
            lastText = text
            failures = 0
            onText?(text)
        }
        guard isFinal || errorMessage != nil else { return }

        // Session ended (time limit, error or silence). Start a fresh one; the cursor is kept.
        failures = errorMessage == nil ? 0 : failures + 1
        generation += 1
        endCurrentTask()
        if failures >= 5, let errorMessage { onStatus?("Retrying recognition: \(errorMessage)") }
        scheduleRestart(after: failures >= 5 ? 2 : 0.2)
    }

    private func scheduleRestart(after delay: Double) {
        restartWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.isRunning else { return }
            self.beginSession()
        }
    }

    private func endCurrentTask() {
        box.take()?.endAudio()
        task?.cancel()
        task = nil
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
