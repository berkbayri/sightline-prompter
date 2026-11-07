import XCTest
@testable import SightlineCore

@MainActor
final class ScrollEngineTests: XCTestCase {
    func testFlingCoastsToAboutVelocityOverDecayAndStops() {
        let engine = ScrollEngine()
        engine.maxOffset = 500
        engine.fling(velocity: 400)
        XCTAssertTrue(engine.isAnimating)

        for _ in 0..<600 {
            engine.tick(dt: 1.0 / 60.0)
        }

        // Total travel of an exponentially decaying velocity is velocity / decay = 400 / 4 = 100 pt.
        XCTAssertFalse(engine.isCoasting)
        XCTAssertEqual(engine.offset, 100, accuracy: 3)
    }

    func testFlingStopsAtTheEndOfTheScript() {
        let engine = ScrollEngine()
        engine.maxOffset = 50
        engine.fling(velocity: 2000)

        for _ in 0..<120 {
            engine.tick(dt: 1.0 / 60.0)
        }

        XCTAssertEqual(engine.offset, 50, accuracy: 0.5)
        XCTAssertFalse(engine.isCoasting)
    }

    func testHaltCancelsAFling() {
        let engine = ScrollEngine()
        engine.maxOffset = 500
        engine.fling(velocity: 500)
        engine.halt()

        engine.tick(dt: 1.0 / 60.0)

        XCTAssertEqual(engine.offset, 0)
        XCTAssertFalse(engine.isCoasting)
    }

    func testManualScrollCancelsTheFollowEase() {
        let engine = ScrollEngine()
        engine.maxOffset = 500
        engine.followTarget = 300
        engine.scroll(by: 10)

        XCTAssertNil(engine.followTarget)
        XCTAssertEqual(engine.offset, 10)
    }

    func testOffsetStaysWithinBounds() {
        let engine = ScrollEngine()
        engine.maxOffset = 100
        engine.scroll(by: -50)
        XCTAssertEqual(engine.offset, 0)
        engine.scroll(by: 500)
        XCTAssertEqual(engine.offset, 100)
    }
}
