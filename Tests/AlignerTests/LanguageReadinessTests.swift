import XCTest
@testable import Aligner

final class LanguageReadinessTests: XCTestCase {
    private func evaluate(
        recognizer: Bool = true,
        onDevice: Bool = false,
        transcriber: Bool = false,
        installed: Bool = false,
        system: Bool = false
    ) -> LanguageReadiness {
        LanguageReadiness.evaluate(
            recognizerAvailable: recognizer,
            onDeviceSupported: onDevice,
            transcriberSupported: transcriber,
            transcriberInstalled: installed,
            systemSupportsTranscriber: system
        )
    }

    func testUnavailableWhenRecognizerMissing() {
        for mask in 0..<16 {
            let result = evaluate(
                recognizer: false,
                onDevice: mask & 1 != 0,
                transcriber: mask & 2 != 0,
                installed: mask & 4 != 0,
                system: mask & 8 != 0
            )
            XCTAssertEqual(result, .unavailable, "mask \(mask)")
        }
    }

    func testOnDeviceWhenRecognizerHasOnDeviceModel() {
        XCTAssertEqual(evaluate(onDevice: true), .onDevice)
        XCTAssertEqual(evaluate(onDevice: true, transcriber: true, system: true), .onDevice)
    }

    func testOnDeviceWhenTranscriberModelInstalled() {
        XCTAssertEqual(evaluate(transcriber: true, installed: true, system: true), .onDevice)
        XCTAssertEqual(evaluate(transcriber: true, installed: true, system: false), .onDevice)
    }

    func testOnlineDownloadableWhenTranscriberSupportedButNotInstalled() {
        XCTAssertEqual(evaluate(transcriber: true, system: true), .onlineDownloadable)
    }

    func testNeedsDictationSetupWhenSystemLacksTranscriber() {
        XCTAssertEqual(evaluate(transcriber: true, system: false), .needsDictationSetup)
    }

    func testNeedsDictationSetupWhenLanguageUnsupportedByTranscriber() {
        XCTAssertEqual(evaluate(system: true), .needsDictationSetup)
        XCTAssertEqual(evaluate(installed: true, system: true), .needsDictationSetup)
    }

    func testEvaluateNeverReturnsOnline() {
        for mask in 0..<32 {
            let result = evaluate(
                recognizer: mask & 16 != 0,
                onDevice: mask & 1 != 0,
                transcriber: mask & 2 != 0,
                installed: mask & 4 != 0,
                system: mask & 8 != 0
            )
            XCTAssertNotEqual(result, LanguageReadiness.online, "mask \(mask)")
        }
    }

    /// Expected readiness for the languages on the reference Mac (macOS 26, only en-* installed).
    func testReferenceMacLanguages() {
        XCTAssertEqual(evaluate(onDevice: true, transcriber: true, installed: true, system: true), .onDevice)
        XCTAssertEqual(evaluate(onDevice: true, system: true), .onDevice)
        XCTAssertEqual(evaluate(transcriber: true, system: true), .onlineDownloadable)
        XCTAssertEqual(evaluate(system: true), .needsDictationSetup)
    }
}
