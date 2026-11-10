import CoreGraphics
import XCTest
@testable import SightlineCore

final class ArrangementTests: XCTestCase {
    private let area = CGRect(x: 20, y: 60, width: 350, height: 600)
    private let aspect: CGFloat = 9.0 / 16.0

    private var geometry: ArrangementGeometry {
        ArrangementGeometry(area: area, aspect: aspect)
    }

    private func assertValid(_ frames: ArrangedFrames, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(area.contains(frames.preview), "preview outside area: \(frames.preview)", file: file, line: line)
        XCTAssertTrue(area.contains(frames.text), "text outside area: \(frames.text)", file: file, line: line)
        XCTAssertFalse(frames.preview.intersects(frames.text), "items overlap", file: file, line: line)
        XCTAssertEqual(frames.preview.width / frames.preview.height, aspect, accuracy: 0.001, file: file, line: line)
    }

    private var start: ArrangedFrames {
        ArrangedFrames(
            preview: CGRect(x: 20, y: 200, width: 180, height: 180 / aspect),
            text: CGRect(x: 20, y: 60, width: 350, height: 120)
        )
    }

    func testStartIsValid() {
        assertValid(start)
    }

    func testPreviewResizeKeepsAspectRatio() {
        for width in stride(from: 100.0, through: 340.0, by: 20.0) {
            assertValid(geometry.resizePreview(in: start, width: CGFloat(width)))
        }
    }

    func testGrowingThePreviewShrinksTheText() {
        let wide = ArrangedFrames(
            preview: CGRect(x: 20, y: 60, width: 100, height: 100 / aspect),
            text: CGRect(x: 20, y: 250, width: 350, height: 410)
        )
        assertValid(wide)
        let grown = geometry.resizePreview(in: wide, width: 250)
        assertValid(grown)
        XCTAssertGreaterThan(grown.preview.width, 100)
        XCTAssertLessThan(grown.text.height * grown.text.width, wide.text.height * wide.text.width)
    }

    func testGrowingTheTextShrinksThePreviewKeepingItsShape() {
        let grown = geometry.resizeText(in: start, size: CGSize(width: 350, height: 400))
        assertValid(grown)
        XCTAssertGreaterThanOrEqual(grown.text.height, 120)
        XCTAssertLessThanOrEqual(grown.preview.width, start.preview.width)
    }

    func testTextAndPreviewNeverOverlapWhateverIsDone() {
        var frames = start
        var seed: UInt64 = 7
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 1000) / 1000
        }
        for _ in 0..<500 {
            switch Int(next() * 4) {
            case 0: frames = geometry.resizePreview(in: frames, width: 60 + next() * 320)
            case 1: frames = geometry.resizeText(in: frames, size: CGSize(width: 60 + next() * 330, height: 40 + next() * 560))
            case 2: frames = geometry.move(.preview, in: frames, to: CGPoint(x: next() * 400, y: next() * 700))
            default: frames = geometry.move(.text, in: frames, to: CGPoint(x: next() * 400, y: next() * 700))
            }
            assertValid(frames)
        }
    }

    func testMoveStaysInsideTheArea() {
        let moved = geometry.move(.text, in: start, to: CGPoint(x: -500, y: 5000))
        XCTAssertTrue(area.contains(moved.text))
        XCTAssertEqual(moved.text.size, start.text.size)
    }

    func testMoveSlidesOutOfTheOtherItem() {
        let moved = geometry.move(.preview, in: start, to: CGPoint(x: 20, y: 100))
        assertValid(moved)
        XCTAssertEqual(moved.preview.size.width, start.preview.width, accuracy: 0.001)
    }

    func testMoveWithNoFreeSpotKeepsThePlace() {
        // The text fills the whole area but a strip: nothing fits beside it.
        let tight = ArrangedFrames(
            preview: CGRect(x: 20, y: 60, width: 96, height: 96 / aspect),
            text: CGRect(x: 20, y: 60 + 96 / aspect + 8, width: 350, height: 600 - 96 / aspect - 8)
        )
        assertValid(tight)
        let moved = geometry.move(.text, in: tight, to: CGPoint(x: 20, y: 60))
        assertValid(moved)
    }

    func testSavedArrangementRoundTripsAndScalesToAnotherScreen() {
        let saved = Arrangement(frames: start, in: area)
        XCTAssertEqual(ArrangementGeometry(area: area, aspect: aspect).resolve(saved).preview.width, start.preview.width, accuracy: 0.5)

        let smaller = CGRect(x: 10, y: 50, width: 300, height: 480)
        let frames = ArrangementGeometry(area: smaller, aspect: aspect).resolve(saved)
        XCTAssertTrue(smaller.contains(frames.preview))
        XCTAssertTrue(smaller.contains(frames.text))
        XCTAssertFalse(frames.preview.intersects(frames.text))
    }

    func testSavedArrangementFollowsAChangedAspectRatio() {
        let saved = Arrangement(frames: start, in: area)
        let square = ArrangementGeometry(area: area, aspect: 3.0 / 4.0).resolve(saved)
        XCTAssertEqual(square.preview.width / square.preview.height, 3.0 / 4.0, accuracy: 0.001)
        XCTAssertFalse(square.preview.intersects(square.text))
    }

    func testOverlappingSavedArrangementIsRepaired() {
        let bad = Arrangement(
            preview: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0),
            text: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        let frames = geometry.resolve(bad)
        XCTAssertFalse(frames.preview.intersects(frames.text))
        XCTAssertTrue(area.contains(frames.preview))
        XCTAssertTrue(area.contains(frames.text))
    }

    // MARK: - In the camera layout

    private func layout(landscape: Bool, arrangement: Arrangement?) -> CameraLayout {
        CameraLayout.make(
            size: landscape ? CGSize(width: 852, height: 393) : CGSize(width: 393, height: 852),
            insets: landscape ? ScreenInsets(top: 0, left: 59, bottom: 21, right: 0) : ScreenInsets(top: 59, left: 0, bottom: 34, right: 0),
            isLandscape: landscape,
            cameraEdge: .left,
            readingDistanceCm: 0.5,
            landscapeColumnWidth: 480,
            recording: CameraLayout.RecordingBand(lineHeight: 46, videoAspect: 16.0 / 9.0),
            arrangement: arrangement
        )
    }

    func testLayoutOffersAnAreaAndKeepsItemsInsideItWithoutOverlap() {
        for landscape in [false, true] {
            let automatic = layout(landscape: landscape, arrangement: nil)
            XCTAssertGreaterThan(automatic.arrangeArea.width, 100)
            let frames = automatic.arrangedFrames!
            let saved = Arrangement(frames: frames, in: automatic.arrangeArea)
            let arranged = layout(landscape: landscape, arrangement: saved)
            let result = arranged.arrangedFrames!
            XCTAssertFalse(result.preview.intersects(result.text), "landscape=\(landscape)")
            XCTAssertTrue(arranged.arrangeArea.contains(result.preview))
            XCTAssertTrue(arranged.arrangeArea.contains(result.text))
            XCTAssertFalse(result.text.intersects(arranged.controlsFrame))
            XCTAssertFalse(result.preview.intersects(arranged.controlsFrame))
        }
    }

    func testArrangedPreviewKeepsTheVideoShape() {
        let moved = Arrangement(
            preview: CGRect(x: 0.2, y: 0.5, width: 0.5, height: 0),
            text: CGRect(x: 0, y: 0, width: 1, height: 0.3)
        )
        let portrait = layout(landscape: false, arrangement: moved).previewFrame!
        XCTAssertEqual(portrait.width / portrait.height, 9.0 / 16.0, accuracy: 0.001)
        let wide = layout(landscape: true, arrangement: moved).previewFrame!
        XCTAssertEqual(wide.width / wide.height, 16.0 / 9.0, accuracy: 0.001)
    }
}
