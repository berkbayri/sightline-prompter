import XCTest
@testable import Aligner

final class LanguageReadinessTests: XCTestCase {
    private func evaluate(
        recognizer: Bool = true,
        onDevice: Bool = false,
        transcriber: Bool = false,
        installed: Bool = false
    ) -> LanguageReadiness {
        LanguageReadiness.evaluate(
            recognizerAvailable: recognizer,
            onDeviceSupported: onDevice,
            transcriberSupported: transcriber,
            transcriberInstalled: installed
        )
    }

    func testUnavailableWhenRecognizerMissing() {
        for mask in 0..<8 {
            let result = evaluate(
                recognizer: false,
                onDevice: mask & 1 != 0,
                transcriber: mask & 2 != 0,
                installed: mask & 4 != 0
            )
            XCTAssertEqual(result, .unavailable, "mask \(mask)")
        }
    }

    func testOnDeviceWhenRecognizerHasOnDeviceModel() {
        XCTAssertEqual(evaluate(onDevice: true), .onDevice)
        XCTAssertEqual(evaluate(onDevice: true, transcriber: true), .onDevice)
    }

    func testOnDeviceWhenTranscriberModelInstalled() {
        XCTAssertEqual(evaluate(transcriber: true, installed: true), .onDevice)
    }

    func testOnlineDownloadableWhenTranscriberSupportedButNotInstalled() {
        XCTAssertEqual(evaluate(transcriber: true), .onlineDownloadable)
    }

    func testOnlineWhenNoOfflinePathExists() {
        XCTAssertEqual(evaluate(), .online)
        XCTAssertEqual(evaluate(installed: true), .online)
    }

    func testTurkishStyleLanguageWithoutDownloadUsesDictationOrOnline() {
        XCTAssertEqual(evaluate(onDevice: true), .onDevice)
        XCTAssertEqual(evaluate(onDevice: false), .online)
    }
}
