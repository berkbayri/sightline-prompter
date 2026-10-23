import Foundation

/// Turns microphone audio into script text. `onText` carries the full transcript of the current
/// utterance (finalized plus volatile), because ScriptAligner expects cumulative partials.
@MainActor
protocol SpeechEngine: AnyObject {
    var onText: ((String) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    func start(locale: Locale) async throws
    func stop()
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
