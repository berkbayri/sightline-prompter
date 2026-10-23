/// What Sightline Prompter can offer for a language on this Mac.
public enum LanguageReadiness: Equatable {
    /// Recognition runs on device with a model already installed.
    case onDevice
    /// Recognition runs on device once a model is downloaded, which the app can do itself.
    case onlineDownloadable
    /// Recognizer works but no on-device path is known. `evaluate` never returns this case.
    case online
    /// Recognizer works, but offline recognition needs a Dictation model set up in System Settings.
    /// Until then audio goes to Apple's servers.
    case needsDictationSetup
    /// The speech recognizer does not exist or is not available for the language.
    case unavailable
}

public extension LanguageReadiness {
    static func evaluate(
        recognizerAvailable: Bool,
        onDeviceSupported: Bool,
        transcriberSupported: Bool,
        transcriberInstalled: Bool,
        systemSupportsTranscriber: Bool
    ) -> LanguageReadiness {
        guard recognizerAvailable else { return .unavailable }
        if onDeviceSupported || (transcriberSupported && transcriberInstalled) {
            return .onDevice
        }
        if transcriberSupported && systemSupportsTranscriber {
            return .onlineDownloadable
        }
        return .needsDictationSetup
    }
}
