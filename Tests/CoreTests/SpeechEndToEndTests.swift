import AVFoundation
import XCTest
import Aligner
@testable import SightlineCore

/// Real recognition, end to end: English text is spoken by the system voice, fed in real time through the
/// camera-audio path of AnalyzerSpeechEngine, and aligned to the script. Slow and needs the on-device model,
/// so it only runs with SIGHTLINE_E2E=1.
@available(macOS 26.0, iOS 26.0, *)
@MainActor
final class SpeechEndToEndTests: XCTestCase {
    private let script = """
    Hello, my name is Berk. Today I will show you how a teleprompter helps you speak to the camera with confidence. \
    The word you are reading always sits right under the lens, so you keep eye contact with your audience.

    Now let us count together: one, two, three, four, five, twenty five, one hundred, one thousand. \
    Thank you very much for watching, and see you in the next video.
    """

    func testSpeechThroughCameraAudioPath() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIGHTLINE_E2E"] == "1", "set SIGHTLINE_E2E=1")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sightline-e2e", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = dir.appendingPathComponent("script.txt")
        let audio = dir.appendingPathComponent("speech.wav")
        try script.write(to: text, atomically: true, encoding: .utf8)
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "-r", "170", "-f", text.path, "-o", audio.path, "--data-format=LEI16@48000"]
        try say.run()
        say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0)

        let file = try AVAudioFile(forReading: audio)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate

        let aligner = ScriptAligner(script: script, language: .named("en-US"))
        let engine = AnalyzerSpeechEngine(externalAudio: true)
        engine.contextualStrings = ["teleprompter", "Berk"]
        var timeline: [(time: Double, cursor: Int, heard: String)] = []
        let began = Date()
        engine.onText = { text in
            _ = aligner.consume(transcript: text)
            timeline.append((Date().timeIntervalSince(began), aligner.cursor, String(text.suffix(40))))
        }
        engine.onStatus = { print("status:", $0) }
        try await engine.start(locale: Locale(identifier: "en-US"))

        // Feed the audio at real-time speed, 100 ms at a time, like the camera does.
        let chunk = AVAudioFrameCount(format.sampleRate / 10)
        let startedFeeding = Date()
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
            try file.read(into: buffer, frameCount: chunk)
            engine.append(buffer)
            let due = Double(file.framePosition) / format.sampleRate
            let wait = due - Date().timeIntervalSince(startedFeeding)
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        }
        try await Task.sleep(nanoseconds: 3_000_000_000)
        engine.stop()

        let total = aligner.tokens.count
        print("audio \(String(format: "%.1f", duration)) s, words \(total), final cursor \(aligner.cursor)")
        var lastCursor = -1
        for entry in timeline where entry.cursor != lastCursor {
            lastCursor = entry.cursor
            let word = entry.cursor > 0 ? aligner.tokens[entry.cursor - 1].display : "-"
            print(String(format: "t=%5.1fs cursor=%3d after \"%@\"   heard …%@", entry.time, entry.cursor, word, entry.heard))
        }
        XCTAssertGreaterThanOrEqual(aligner.cursor, total - 3, "cursor stopped at \(aligner.cursor) of \(total)")
        let numbers = aligner.tokens.firstIndex { $0.display == "twenty" } ?? 0
        XCTAssertTrue(timeline.contains { $0.cursor > numbers + 3 }, "the cursor never crossed the spoken numbers")
    }
}
