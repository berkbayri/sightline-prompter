/// What Sightline Prompter can offer for a language on this Mac.
public enum LanguageReadiness: Equatable {
    /// Recognition runs on device: the offline model is installed, or the recognizer has its own on-device model.
    case onDevice
    /// Apple offers a one-click download of the offline model, which the app starts itself.
    case onlineDownloadable
    /// Recognition uses Apple's servers because no offline model is available.
    case online
    /// The speech recognizer does not exist or is not available for the language.
    case unavailable
}

public extension LanguageReadiness {
    static func evaluate(
        recognizerAvailable: Bool,
        onDeviceSupported: Bool,
        transcriberSupported: Bool,
        transcriberInstalled: Bool
    ) -> LanguageReadiness {
        guard recognizerAvailable else { return .unavailable }
        if onDeviceSupported || (transcriberSupported && transcriberInstalled) {
            return .onDevice
        }
        if transcriberSupported {
            return .onlineDownloadable
        }
        return .online
    }
}
