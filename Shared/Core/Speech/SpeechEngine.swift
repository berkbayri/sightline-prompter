import AVFoundation
import Foundation

/// Turns microphone audio into script text. `onText` carries the full transcript of the current
/// utterance (finalized plus volatile), because ScriptAligner expects cumulative partials.
@MainActor
protocol SpeechEngine: AnyObject {
    var onText: ((String) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    /// Words from the script, offered to the recognizer as hints so names and rare words are heard right.
    var contextualStrings: [String] { get set }
    func start(locale: Locale) async throws
    func stop()
    /// Audio from an outside source. Only engines started for external audio use it.
    func append(_ buffer: AVAudioPCMBuffer)
}

extension SpeechEngine {
    func append(_ buffer: AVAudioPCMBuffer) {}
}

enum SpeechEngineError: LocalizedError {
    case recognizerUnavailable
    case unsupportedLocale
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer unavailable"
        case .unsupportedLocale:
            return "Speech model is not available for this language"
        case .noAudioFormat:
            return "No audio format compatible with speech analysis"
        }
    }
}
