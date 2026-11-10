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
    }

    func testRecordingPreviewShowsTheWholePictureAsLargeAsTheScreenAllows() {
        let screens = [CGSize(width: 393, height: 852), CGSize(width: 852, height: 393)]
        for aspect in [16.0 / 9.0, 4.0 / 3.0] {
            for size in screens {
                let landscape = size.width > size.height
                let band = CameraLayout.RecordingBand(lineHeight: 40, videoAspect: CGFloat(aspect))
                let layout = CameraLayout.make(
                    size: size, insets: ScreenInsets(top: landscape ? 0 : 59, left: landscape ? 59 : 0, bottom: 21),
                    isLandscape: landscape, cameraEdge: .left,
                    readingDistanceCm: 0.5, landscapeColumnWidth: 480, recording: band
                )
                let preview = layout.previewFrame ?? .zero
                // The picture is never cropped: the preview has exactly the shape of the video.
                let shape = landscape ? CGFloat(aspect) : 1 / CGFloat(aspect)
                XCTAssertEqual(preview.width / preview.height, shape, accuracy: 0.001)
                // And it is as large as the screen allows: it touches the screen on one axis.
                XCTAssertTrue(abs(preview.width - size.width) < 0.5 || abs(preview.height - size.height) < 0.5)
                XCTAssertTrue(CGRect(origin: .zero, size: size).contains(preview))
                // The text and the controls sit on top of it.
                XCTAssertTrue(preview.intersects(layout.textFrame))
            }
        }
    }

    // MARK: - Vertical crop guide

    func testVerticalCropStripIsExactlyNineBySixteenForEveryPreviewShape() {
        let frames = [
            CGRect(x: 0, y: 0, width: 699, height: 393),    // landscape 16:9 fitted by height
            CGRect(x: 76, y: 0, width: 524, height: 393),   // landscape 4:3 fitted by height
            CGRect(x: 30, y: 20, width: 400, height: 225),  // hand-placed 16:9
            CGRect(x: 0, y: 0, width: 852, height: 393),    // wide preview that crops top and bottom
        ]
        for aspect in [16.0 / 9.0, 4.0 / 3.0] {
            for frame in frames {
                let strip = CameraLayout.verticalCropStrip(in: frame, videoAspect: CGFloat(aspect))
                // The picture's own height: the frame's, or more when the frame crops the top and bottom.
                let pictureHeight = max(frame.height, frame.width / CGFloat(aspect))
                XCTAssertEqual(strip.width / pictureHeight, 9.0 / 16.0, accuracy: 0.0001)
                XCTAssertEqual(strip.midX, frame.midX, accuracy: 0.001)
            }
        }
    }

    func testVerticalCropStripOfAnUncroppedPreviewLooksNineBySixteenOnScreen() {
        // A preview with the exact shape of the video shows the whole picture, so the strip drawn on screen has the
        // ratio 9:16 itself: width / height.
        for aspect in [16.0 / 9.0, 4.0 / 3.0] {
            let frame = CGRect(x: 10, y: 5, width: 393 * CGFloat(aspect), height: 393)
            let strip = CameraLayout.verticalCropStrip(in: frame, videoAspect: CGFloat(aspect))
            XCTAssertEqual(strip.width / strip.height, 9.0 / 16.0, accuracy: 0.0001)
        }
    }

    func testVerticalCropOfCommonVideoSizesIsNineBySixteen() {
        // The same rule on the recorded pixels: height H gives a crop of H * 9 / 16 wide.
        for (width, height) in [(3840.0, 2160.0), (1920.0, 1080.0), (4032.0, 3024.0), (1280.0, 720.0)] {
            let strip = CameraLayout.verticalCropStrip(
                in: CGRect(x: 0, y: 0, width: width, height: height), videoAspect: CGFloat(width / height)
            )
            XCTAssertEqual(strip.width, height * 9 / 16, accuracy: 0.0001)
            XCTAssertEqual(strip.width / strip.height, 9.0 / 16.0, accuracy: 0.0001)
        }
    }

    func testRecordingPreviewIsExactlyTheShapeOfTheVideoInPortraitToo() {
        let portraitSize = CGSize(width: 393, height: 852)
        let band = CameraLayout.RecordingBand(lineHeight: 40, videoAspect: 16.0 / 9.0)
        let portrait = CameraLayout.make(
            size: portraitSize, insets: ScreenInsets(top: 59, bottom: 34), isLandscape: false, cameraEdge: .top,
            readingDistanceCm: 0.5, landscapeColumnWidth: 480, recording: band
        )
        let preview = portrait.previewFrame ?? .zero
        XCTAssertEqual(preview.width / preview.height, 9.0 / 16.0, accuracy: 0.001)
        XCTAssertEqual(preview.width, portraitSize.width, accuracy: 0.5)
    }
}
