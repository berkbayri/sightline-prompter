#if compiler(>=6.2)
import AVFoundation
import Aligner
import Foundation
import Speech

/// On-device recognition through SpeechTranscriber and SpeechAnalyzer (macOS 26+). Volatile results
/// are shown as they arrive and replaced once the analyzer finalizes them.
@available(macOS 26.0, *)
@MainActor
final class AnalyzerSpeechEngine: SpeechEngine {
    var onText: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var reservedLocale: Locale?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    /// Bumped per start and stop so late results from an ended run are ignored.
    private var run = 0

    /// The transcriber locale matching `locale` exactly. `supportedLocale(equivalentTo:)` is not used:
    /// it also returns locales the transcriber does not support (e.g. Hindi, Arabic, Russian).
    static func supportedLocale(for locale: Locale) async -> Locale? {
        let id = locale.identifier(.bcp47)
        return await SpeechTranscriber.supportedLocales.first { $0.identifier(.bcp47) == id }
    }

    /// True when the language's transcriber model is installed, so recognition can stay on device.
    static func isInstalled(_ locale: Locale) async -> Bool {
        guard let supported = await supportedLocale(for: locale) else {
            return false
        }
        let id = supported.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == id }
    }

    /// Downloads and installs the transcriber model for the locale. `progress` gets 0...1.
    static func install(locale: Locale, progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let supported = await AnalyzerSpeechEngine.supportedLocale(for: locale) else {
            throw SpeechEngineError.unsupportedLocale
        }
        let transcriber = makeTranscriber(locale: supported)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            progress(1)
            return
        }
        // The request only exposes progress as a property, so it is sampled while the download runs.
        let poll = Task { @MainActor in
            while !Task.isCancelled {
                progress(request.progress.fractionCompleted)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        defer { poll.cancel() }
        try await request.downloadAndInstall()
        progress(1)
    }

    func start(locale: Locale) async throws {
        stop()
        run += 1
        let current = run
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        var reserved: Locale?
        do {
            guard let supported = await AnalyzerSpeechEngine.supportedLocale(for: locale) else {
                throw SpeechEngineError.unsupportedLocale
            }
            let installed = await AnalyzerSpeechEngine.isInstalled(supported)
            if !installed {
                onStatus?("Downloading speech model…")
                try await AnalyzerSpeechEngine.install(locale: supported) { [weak self] fraction in
                    self?.onStatus?("Downloading speech model \(Int(fraction * 100))%")
                }
            }
            let transcriber = AnalyzerSpeechEngine.makeTranscriber(locale: supported)
            if try await AssetInventory.reserve(locale: supported) {
                reserved = supported
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: inputFormat
            ), let converter = AVAudioConverter(from: inputFormat, to: format) else {
                throw SpeechEngineError.noAudioFormat
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.prepareToAnalyze(in: format)
            guard run == current else { throw CancellationError() }

            // Nothing below suspends, so the run cannot be stopped halfway through the setup.
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            input.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: inputFormat,
                block: makeAnalyzerTap(continuation, converter, format)
            )
            do {
                audioEngine.prepare()
                try audioEngine.start()
            } catch {
                input.removeTap(onBus: 0)
                throw error
            }

            self.transcriber = transcriber
            self.analyzer = analyzer
            self.reservedLocale = reserved
            inputContinuation = continuation
            let spaced = ScriptLanguage.named(supported.identifier(.bcp47)).spaced

            analyzerTask = Task { [weak self] in
                do {
                    try await analyzer.start(inputSequence: stream)
                } catch {
                    guard let self, self.run == current else { return }
                    self.onStatus?(error.localizedDescription)
                }
            }
            resultsTask = Task { [weak self] in
                var finalized = ""
                var pending = ""
                do {
                    for try await result in transcriber.results {
                        guard let self, self.run == current else { return }
                        let text = String(result.text.characters)
                        if result.isFinal {
                            finalized = AnalyzerSpeechEngine.join(finalized, text, spaced: spaced)
                            pending = ""
                        } else {
                            pending = text
                        }
                        let cumulative = AnalyzerSpeechEngine.join(finalized, pending, spaced: spaced)
                        if !cumulative.isEmpty { self.onText?(cumulative) }
                    }
                } catch {
                    guard let self, self.run == current else { return }
                    self.onStatus?(error.localizedDescription)
                }
            }
            onStatus?("Listening…")
        } catch {
            if let reserved {
                await AssetInventory.release(reservedLocale: reserved)
            }
            throw error
        }
    }

    func stop() {
        run += 1
        resultsTask?.cancel()
        resultsTask = nil
        analyzerTask?.cancel()
        analyzerTask = nil
        inputContinuation?.finish()
        inputContinuation = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        let analyzer = self.analyzer
        let reserved = reservedLocale
        self.analyzer = nil
        transcriber = nil
        reservedLocale = nil
        guard analyzer != nil || reserved != nil else { return }
        Task {
            await analyzer?.cancelAndFinishNow()
            if let reserved {
                await AssetInventory.release(reservedLocale: reserved)
            }
        }
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    /// Joins finalized text to the next piece. Space-delimited languages get a separator when the
    /// analyzer did not provide one.
    private static func join(_ head: String, _ tail: String, spaced: Bool) -> String {
        guard spaced, !head.isEmpty, !tail.isEmpty,
              head.last?.isWhitespace == false, tail.first?.isWhitespace == false else {
            return head + tail
        }
        return head + " " + tail
    }
}

/// Built outside the main actor so the tap runs on the audio thread without isolation checks.
@available(macOS 26.0, *)
private func makeAnalyzerTap(
    _ continuation: AsyncStream<AnalyzerInput>.Continuation,
    _ converter: AVAudioConverter,
    _ format: AVAudioFormat
) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
    { buffer, _ in
        guard let converted = convertAnalyzerBuffer(buffer, using: converter, to: format) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }
}

@available(macOS 26.0, *)
private func convertAnalyzerBuffer(
    _ buffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    to format: AVAudioFormat
) -> AVAudioPCMBuffer? {
    let frames = Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(frames.rounded(.up)) + 64
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

    var supplied = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
        if supplied {
            inputStatus.pointee = .noDataNow
            return nil
        }
        supplied = true
        inputStatus.pointee = .haveData
        return buffer
    }
    guard status != .error, conversionError == nil, output.frameLength > 0 else { return nil }
    return output
}
#endif
