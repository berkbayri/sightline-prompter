import Aligner
import Combine
import Foundation
import Speech

/// Readiness of each supported language on this Mac, and installs of offline speech models.
@MainActor
final class LanguageCatalog: ObservableObject {
    @Published private(set) var readiness: [String: LanguageReadiness] = [:]
    /// Install progress 0...1 for languages whose offline model is downloading.
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var errors: [String: String] = [:]

    /// Languages to offer in pickers. Until the first refresh finishes, every language is offered.
    var pickerLanguages: [ScriptLanguage] {
        ScriptLanguage.all.filter { readiness[$0.id] != .unavailable }
    }

    func refresh() {
        Task { [weak self] in
            guard let self else { return }
            var result: [String: LanguageReadiness] = [:]
            for language in ScriptLanguage.all {
                result[language.id] = await self.evaluate(language)
            }
            self.readiness = result
        }
    }

    func installOffline(_ id: String) async {
        guard progress[id] == nil, readiness[id] == .onlineDownloadable else { return }
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            errors[id] = nil
            progress[id] = 0
            do {
                try await AnalyzerSpeechEngine.install(locale: Locale(identifier: id)) { [weak self] fraction in
                    self?.progress[id] = fraction
                }
            } catch {
                errors[id] = error.localizedDescription
            }
            progress[id] = nil
            refresh()
        }
        #endif
    }

    private func evaluate(_ language: ScriptLanguage) async -> LanguageReadiness {
        let locale = Locale(identifier: language.id)
        let recognizer = SFSpeechRecognizer(locale: locale)
        var systemSupports = false
        var transcriberSupported = false
        var transcriberInstalled = false
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            systemSupports = SpeechTranscriber.isAvailable
            if systemSupports {
                let supported = await AnalyzerSpeechEngine.supportedLocale(for: locale)
                transcriberSupported = supported != nil
                if transcriberSupported {
                    transcriberInstalled = await AnalyzerSpeechEngine.isInstalled(locale)
                }
            }
        }
        #endif
        return LanguageReadiness.evaluate(
            recognizerAvailable: recognizer?.isAvailable ?? false,
            onDeviceSupported: recognizer?.supportsOnDeviceRecognition ?? false,
            transcriberSupported: transcriberSupported,
            transcriberInstalled: transcriberInstalled,
            systemSupportsTranscriber: systemSupports
        )
    }
}
