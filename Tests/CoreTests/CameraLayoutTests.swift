import CoreGraphics
import XCTest
@testable import SightlineCore

final class CameraLayoutTests: XCTestCase {
    /// Dynamic Island iPhone in portrait.
    private let portraitSize = CGSize(width: 393, height: 852)
    private let portraitInsets = ScreenInsets(top: 59, left: 0, bottom: 34, right: 0)

    /// Dynamic Island iPhone in landscape, with the island on the left.
    private let landscapeSize = CGSize(width: 852, height: 393)
    private let landscapeLeftInsets = ScreenInsets(top: 0, left: 59, bottom: 21, right: 0)

    private func portrait(distance: CGFloat = 1) -> CameraLayout {
        CameraLayout.make(
            size: portraitSize,
            insets: portraitInsets,
            isLandscape: false,
            cameraEdge: .top,
            readingDistanceCm: distance,
            landscapeColumnWidth: 480
        )
    }

    private func landscape(edge: CameraEdge, insets: ScreenInsets, columnWidth: CGFloat = 480) -> CameraLayout {
        CameraLayout.make(
            size: landscapeSize,
            insets: insets,
            isLandscape: true,
            cameraEdge: edge,
            readingDistanceCm: 1,
            landscapeColumnWidth: columnWidth
        )
    }

    // MARK: - Portrait

    func testPortraitTextStartsAtTheBottomOfTheCameraArea() {
        let layout = portrait()
        XCTAssertEqual(layout.textFrame.minY, portraitInsets.top, accuracy: 0.5)
        XCTAssertFalse(layout.isLandscape)
        XCTAssertEqual(layout.cameraEdge, .top)
    }

    func testPortraitReadingLineSitsOneCentimeterBelowTheCamera() {
        let layout = portrait(distance: 1)
        XCTAssertEqual(layout.readingLineY, portraitInsets.top + CameraLayout.pointsPerCentimeter, accuracy: 0.5)
        XCTAssertTrue(layout.textFrame.minY < layout.readingLineY && layout.readingLineY < layout.textFrame.maxY)
    }

    func testPortraitReadingLineStaysInsideTheTextArea() {
        let far = portrait(distance: 20)
        XCTAssertLessThanOrEqual(far.readingLineY, far.textFrame.maxY - 40)
        let near = portrait(distance: 0)
        XCTAssertGreaterThanOrEqual(near.readingLineY, near.textFrame.minY + 8)
    }

    func testPortraitTextDoesNotOverlapControls() {
        let layout = portrait()
        XCTAssertLessThanOrEqual(layout.textFrame.maxY, layout.controlsFrame.minY)
        XCTAssertEqual(layout.controlsFrame.maxY, portraitSize.height, accuracy: 0.5)
    }

    // MARK: - Landscape

    func testLandscapeReadingLineIsLevelWithTheCamera() {
        let layout = landscape(edge: .left, insets: landscapeLeftInsets)
        XCTAssertTrue(layout.isLandscape)
        XCTAssertEqual(layout.readingLineY, landscapeSize.height / 2, accuracy: 0.5)
    }

    func testLandscapeTextHugsTheCameraEdge() {
        let layout = landscape(edge: .left, insets: landscapeLeftInsets)
        XCTAssertGreaterThanOrEqual(layout.textFrame.minX, landscapeLeftInsets.left)
        XCTAssertLessThan(layout.textFrame.minX, landscapeLeftInsets.left + 24)
    }

    func testLandscapeControlsSitOnTheFarEdge() {
        let layout = landscape(edge: .left, insets: landscapeLeftInsets)
        XCTAssertLessThanOrEqual(layout.textFrame.maxX, layout.controlsFrame.minX)
        XCTAssertEqual(layout.controlsFrame.maxX, landscapeSize.width - 16, accuracy: 0.5)
    }

    func testLandscapeCameraOnRightMirrorsTheLayout() {
        let rightInsets = ScreenInsets(top: 0, left: 0, bottom: 21, right: 59)
        let layout = landscape(edge: .right, insets: rightInsets)
        XCTAssertEqual(layout.cameraEdge, .right)
        XCTAssertLessThanOrEqual(layout.controlsFrame.maxX, layout.textFrame.minX)
        XCTAssertEqual(layout.textFrame.maxX, landscapeSize.width - 59 - 12, accuracy: 0.5)
    }

    func testLandscapeColumnIsClampedToTheAvailableWidth() {
        let layout = landscape(edge: .left, insets: landscapeLeftInsets, columnWidth: 2000)
        XCTAssertLessThanOrEqual(layout.textFrame.maxX, layout.controlsFrame.minX)
    }

    func testLandscapeColumnNeverNarrowerThanTheMinimum() {
        let layout = landscape(edge: .left, insets: landscapeLeftInsets, columnWidth: 10)
        XCTAssertEqual(layout.textFrame.width, 200, accuracy: 0.5)
    }

    // MARK: - Recording band

    func testPortraitRecordingTextWidthAndHeightFollowTheSettings() {
        let size = CGSize(width: 393, height: 852)
        let insets = ScreenInsets(top: 59, bottom: 34)
        let band = CameraLayout.RecordingBand(lineHeight: 50, portraitLines: 2, portraitWidthFraction: 0.5)
        let layout = CameraLayout.make(
            size: size, insets: insets, isLandscape: false, cameraEdge: .top,
            readingDistanceCm: 0.5, landscapeColumnWidth: 480, recording: band
        )
        XCTAssertEqual(layout.textFrame.width, 196.5, accuracy: 0.5)
        XCTAssertEqual(layout.textFrame.midX, size.width / 2, accuracy: 0.5)
        XCTAssertEqual(layout.textFrame.height, 100, accuracy: 0.5)
        XCTAssertEqual(layout.textFrame.minY, 59, accuracy: 0.5)
        // The preview does not shrink with the text.
        XCTAssertGreaterThan(layout.previewFrame?.width ?? 0, 200)
    }

    func testLandscapeRecordingTextWidthAndHeightFollowTheSettings() {
        let size = CGSize(width: 852, height: 393)
        let band = CameraLayout.RecordingBand(lineHeight: 40, landscapeLines: 3, landscapeWidth: 220)
        let layout = CameraLayout.make(
            size: size, insets: ScreenInsets(left: 59), isLandscape: true, cameraEdge: .left,
            readingDistanceCm: 0.5, landscapeColumnWidth: 220, recording: band
        )
        XCTAssertEqual(layout.textFrame.width, 220, accuracy: 0.5)
        XCTAssertEqual(layout.textFrame.height, 120, accuracy: 0.5)
        XCTAssertEqual(layout.textFrame.midY, size.height / 2, accuracy: 0.5)
        XCTAssertGreaterThan(layout.previewFrame?.minX ?? 0, layout.textFrame.maxX)
    }
}
