import Aligner
import Combine
import Foundation
import Speech

/// Readiness of each supported language on this device, and installs of offline speech models.
@MainActor
public final class LanguageCatalog: ObservableObject {
    @Published public private(set) var readiness: [String: LanguageReadiness] = [:]
    /// Install progress 0...1 for languages whose offline model is downloading.
    @Published public private(set) var progress: [String: Double] = [:]
    @Published public private(set) var errors: [String: String] = [:]

    public init() {}

    /// Languages to offer in pickers. Until the first refresh finishes, every language is offered.
    public var pickerLanguages: [ScriptLanguage] {
        ScriptLanguage.all.filter { readiness[$0.id] != .unavailable }
    }

    public func refresh() {
        Task { [weak self] in
            guard let self else { return }
            var result: [String: LanguageReadiness] = [:]
            for language in ScriptLanguage.all {
                result[language.id] = await self.evaluate(language)
            }
            self.readiness = result
        }
    }

    public func installOffline(_ id: String) async {
        guard progress[id] == nil, readiness[id] == .onlineDownloadable else { return }
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *) {
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
        var transcriberSupported = false
        var transcriberInstalled = false
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *), SpeechTranscriber.isAvailable {
            transcriberSupported = await AnalyzerSpeechEngine.supportedLocale(for: locale) != nil
            if transcriberSupported {
                transcriberInstalled = await AnalyzerSpeechEngine.isInstalled(locale)
            }
        }
        #endif
        return LanguageReadiness.evaluate(
            recognizerAvailable: recognizer?.isAvailable ?? false,
            onDeviceSupported: recognizer?.supportsOnDeviceRecognition ?? false,
            transcriberSupported: transcriberSupported,
            transcriberInstalled: transcriberInstalled
        )
    }
}
