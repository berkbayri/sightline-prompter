import XCTest
@testable import Aligner

final class PaceMeterTests: XCTestCase {
    /// Feeds `seconds` of reading at `wordsPerSecond`, sampled every 0.5 s.
    private func read(_ meter: inout PaceMeter, from start: Double, seconds: Double,
                      wordsPerSecond: Double, units: inout Int) -> Double {
        var t = start
        let end = start + seconds
        while t < end - 1e-9 {
            t += 0.5
            units += Int((wordsPerSecond * 0.5).rounded())
            meter.record(units: units, time: t)
        }
        return t
    }

    func testConstantRateReportsUnitsPerMinute() throws {
        var meter = PaceMeter()
        var units = 0
        _ = read(&meter, from: 0, seconds: 20, wordsPerSecond: 2, units: &units)
        let rate = try XCTUnwrap(meter.unitsPerMinute())
        XCTAssertEqual(rate, 120, accuracy: 1)
    }

    func testPausesLongerThanFourSecondsDoNotReduceRate() {
        var meter = PaceMeter()
        var units = 0
        var t = read(&meter, from: 0, seconds: 10, wordsPerSecond: 2, units: &units)
        // Reader stops for 6 s: units stay put.
        for _ in 0..<12 {
            t += 0.5
            meter.record(units: units, time: t)
        }
        t = read(&meter, from: t, seconds: 10, wordsPerSecond: 2, units: &units)
        let rate = try? XCTUnwrap(meter.unitsPerMinute())
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate ?? 0, 120, accuracy: 2)
    }

    func testSixtyUnitJumpIsIgnored() {
        var meter = PaceMeter()
        var units = 0
        var t = read(&meter, from: 0, seconds: 10, wordsPerSecond: 2, units: &units)
        units += 60
        meter.record(units: units, time: t + 0.5)
        t += 0.5
        t = read(&meter, from: t, seconds: 10, wordsPerSecond: 2, units: &units)
        let rate = try? XCTUnwrap(meter.unitsPerMinute())
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate ?? 0, 120, accuracy: 2)
    }

    func testRemainingSecondsAtKnownRate() {
        var meter = PaceMeter()
        var units = 0
        _ = read(&meter, from: 0, seconds: 20, wordsPerSecond: 2, units: &units)
        let remaining = try? XCTUnwrap(meter.remainingSeconds(remainingUnits: 240))
        XCTAssertNotNil(remaining)
        XCTAssertEqual(remaining ?? 0, 120, accuracy: 2)
        XCTAssertEqual(meter.remainingSeconds(remainingUnits: 0), 0)
    }

    func testNilBeforeMinimumData() {
        var meter = PaceMeter()
        XCTAssertNil(meter.unitsPerMinute())
        XCTAssertNil(meter.remainingSeconds(remainingUnits: 100))

        // 8 units in 2 s: enough units, not enough active time.
        var units = 0
        _ = read(&meter, from: 0, seconds: 2, wordsPerSecond: 4, units: &units)
        XCTAssertNil(meter.unitsPerMinute())
        XCTAssertNil(meter.remainingSeconds(remainingUnits: 100))

        meter.reset()
        XCTAssertNil(meter.unitsPerMinute())
    }
}
