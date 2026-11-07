import CoreGraphics

/// Which screen edge the front camera sits on. Portrait always has it at the top.
public enum CameraEdge: Sendable {
    case top, left, right
}

/// Screen insets as the safe area reports them (Dynamic Island, notch, home indicator).
public struct ScreenInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

/// Where the script goes so the reader looks at the front camera while reading.
///
/// Portrait: the text runs full width just under the Dynamic Island, and the reading line sits a few
/// centimeters below the camera, so the word being read is the one closest to the lens.
/// Landscape: the camera is on a short edge at mid-height. The text column hugs that edge, and the
/// reading line runs across the middle of the column, level with the camera. The controls take the far edge.
///
/// Pure geometry with no UIKit, so the rules can be tested on macOS.
public struct CameraLayout: Equatable, Sendable {
    /// Points per centimeter on iPhone screens (about 163 points per inch).
    public static let pointsPerCentimeter: CGFloat = 64

    /// Screen area the script text is drawn in. Text outside it is clipped.
    public let textFrame: CGRect
    /// Y of the reading line in screen coordinates. The word centered on it is the one being read.
    public let readingLineY: CGFloat
    /// Area for the transport controls and the status line.
    public let controlsFrame: CGRect
    public let cameraEdge: CameraEdge
    public let isLandscape: Bool
    /// Where the scaled-down camera preview goes while recording. Nil when the camera is off.
    public let previewFrame: CGRect?

    public init(
        textFrame: CGRect,
        readingLineY: CGFloat,
        controlsFrame: CGRect,
        cameraEdge: CameraEdge,
        isLandscape: Bool,
        previewFrame: CGRect? = nil
    ) {
        self.previewFrame = previewFrame
        self.textFrame = textFrame
        self.readingLineY = readingLineY
        self.controlsFrame = controlsFrame
        self.cameraEdge = cameraEdge
        self.isLandscape = isLandscape
    }

    /// - Parameters:
    ///   - readingDistanceCm: distance from the camera to the reading line, in centimeters (portrait).
    ///   - landscapeColumnWidth: preferred text column width in landscape, in points. Clamped to fit.
    public static func make(
        size: CGSize,
        insets: ScreenInsets,
        isLandscape: Bool,
        cameraEdge: CameraEdge,
        readingDistanceCm: CGFloat,
        landscapeColumnWidth: CGFloat,
        recording: RecordingBand? = nil
    ) -> CameraLayout {
        if let recording {
            return isLandscape
                ? recordingLandscape(size: size, insets: insets, cameraEdge: cameraEdge, columnWidth: landscapeColumnWidth, band: recording)
                : recordingPortrait(size: size, insets: insets, band: recording)
        }
        if isLandscape {
            return landscape(size: size, insets: insets, cameraEdge: cameraEdge, columnWidth: landscapeColumnWidth)
        }
        return portrait(size: size, insets: insets, readingDistanceCm: readingDistanceCm)
    }

    /// Camera mode: a short prompter band next to the lens, the live preview scaled into the rest.
    public struct RecordingBand: Equatable, Sendable {
        /// Height of one text line in points.
        public var lineHeight: CGFloat
        /// Height of the text area in lines, in portrait and in landscape.
        public var portraitLines: CGFloat
        public var landscapeLines: CGFloat
        /// Portrait text width as a fraction of the screen width (0...1); the area is centered.
        public var portraitWidthFraction: CGFloat
        /// Landscape text width in points.
        public var landscapeWidth: CGFloat
        /// Shape of the recorded video in landscape (width / height): 16:9 or 4:3.
        public var videoAspect: CGFloat

        public init(
            lineHeight: CGFloat,
            portraitLines: CGFloat = 3,
            landscapeLines: CGFloat = 5,
            portraitWidthFraction: CGFloat = 1,
            landscapeWidth: CGFloat = 480,
            videoAspect: CGFloat = 16.0 / 9.0
        ) {
            self.portraitWidthFraction = portraitWidthFraction
            self.landscapeWidth = landscapeWidth
            self.videoAspect = videoAspect
            self.lineHeight = lineHeight
            self.portraitLines = portraitLines
            self.landscapeLines = landscapeLines
        }
    }

    // MARK: - Layouts

    private static let margin: CGFloat = 16
    private static let portraitSideInset: CGFloat = 24
    private static let portraitControlsHeight: CGFloat = 96
    private static let landscapeRailWidth: CGFloat = 76
    private static let gap: CGFloat = 12
    private static let minimumColumnWidth: CGFloat = 200

    private static func portrait(size: CGSize, insets: ScreenInsets, readingDistanceCm: CGFloat) -> CameraLayout {
        let left = max(insets.left, portraitSideInset)
        let right = max(insets.right, portraitSideInset)
        // Text starts at the bottom edge of the Dynamic Island, like the notch panel on the Mac.
        let top = insets.top
        let controlsTop = size.height - insets.bottom - portraitControlsHeight
        let textFrame = CGRect(
            x: left,
            y: top,
            width: max(size.width - left - right, 1),
            height: max(controlsTop - top, 1)
        )

        // The camera is centered at the top; measure the reading line down from the top safe edge.
        let distance = max(readingDistanceCm, 0) * pointsPerCentimeter
        let readingLineY = min(max(insets.top + distance, textFrame.minY + 8), textFrame.maxY - 40)

        let controlsFrame = CGRect(
            x: 0,
            y: controlsTop,
            width: size.width,
            height: size.height - controlsTop
        )
        return CameraLayout(
            textFrame: textFrame,
            readingLineY: readingLineY,
            controlsFrame: controlsFrame,
            cameraEdge: .top,
            isLandscape: false
        )
    }

    private static func landscape(
        size: CGSize,
        insets: ScreenInsets,
        cameraEdge: CameraEdge,
        columnWidth: CGFloat
    ) -> CameraLayout {
        let cameraOnLeft = cameraEdge != .right
        let cameraInset = max(cameraOnLeft ? insets.left : insets.right, margin)
        let farInset = max(cameraOnLeft ? insets.right : insets.left, margin)

        // Space between the camera side and the controls rail on the far side.
        let available = size.width - cameraInset - farInset - landscapeRailWidth - 2 * gap
        let width = max(min(columnWidth, available), minimumColumnWidth)

        let textX = cameraOnLeft ? cameraInset + gap : size.width - cameraInset - gap - width
        let textFrame = CGRect(x: textX, y: margin, width: width, height: max(size.height - 2 * margin, 1))

        let railX = cameraOnLeft
            ? size.width - farInset - landscapeRailWidth
            : farInset
        let controlsFrame = CGRect(x: railX, y: margin, width: landscapeRailWidth, height: textFrame.height)

        return CameraLayout(
            textFrame: textFrame,
            readingLineY: size.height / 2,
            controlsFrame: controlsFrame,
            cameraEdge: cameraOnLeft ? .left : .right,
            isLandscape: true
        )
    }
}

extension CameraLayout {
    /// The largest rect of the given aspect ratio (width / height) that fits inside `area`, centered.
    static func fit(aspect: CGFloat, in area: CGRect) -> CGRect {
        guard area.width > 0, area.height > 0 else { return area }
        var width = area.width
        var height = width / aspect
        if height > area.height {
            height = area.height
            width = height * aspect
        }
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    fileprivate static func recordingPortrait(size: CGSize, insets: ScreenInsets, band: RecordingBand) -> CameraLayout {
        let left = max(insets.left, 24)
        let right = max(insets.right, 24)
        let top = insets.top
        let textHeight = band.lineHeight * band.portraitLines
        let fullWidth = max(size.width - left - right, 1)
        let textWidth = min(max(size.width * band.portraitWidthFraction, 120), fullWidth)
        let textFrame = CGRect(x: (size.width - textWidth) / 2, y: top, width: textWidth, height: textHeight)

        let controlsHeight: CGFloat = 76
        let controlsTop = size.height - insets.bottom - controlsHeight
        let controlsFrame = CGRect(x: 0, y: controlsTop, width: size.width, height: size.height - controlsTop)

        let area = CGRect(x: left, y: textFrame.maxY + 12, width: fullWidth, height: max(controlsTop - textFrame.maxY - 20, 1))
        // First line of the band is the reading line, so the word being read sits right under the lens.
        return CameraLayout(
            textFrame: textFrame,
            readingLineY: textFrame.minY + band.lineHeight / 2,
            controlsFrame: controlsFrame,
            cameraEdge: .top,
            isLandscape: false,
            previewFrame: fit(aspect: 1 / band.videoAspect, in: area)
        )
    }

    fileprivate static func recordingLandscape(
        size: CGSize,
        insets: ScreenInsets,
        cameraEdge: CameraEdge,
        columnWidth: CGFloat,
        band: RecordingBand
    ) -> CameraLayout {
        let cameraOnLeft = cameraEdge != .right
        let cameraInset = max(cameraOnLeft ? insets.left : insets.right, 16)
        let farInset = max(cameraOnLeft ? insets.right : insets.left, 16)
        let rail: CGFloat = 76
        let gap: CGFloat = 12

        let available = size.width - cameraInset - farInset - rail - 3 * gap
        // The preview keeps at least a third of the room, whatever the column width is set to.
        let width = max(min(columnWidth, available * 0.67), 120)
        let height = min(band.lineHeight * band.landscapeLines, size.height - 32)
        let textX = cameraOnLeft ? cameraInset + gap : size.width - cameraInset - gap - width
        let textFrame = CGRect(x: textX, y: (size.height - height) / 2, width: width, height: height)

        let railX = cameraOnLeft ? size.width - farInset - rail : farInset
        let controlsFrame = CGRect(x: railX, y: 16, width: rail, height: size.height - 32)

        let previewX = cameraOnLeft ? textFrame.maxX + gap : controlsFrame.maxX + gap
        let previewWidth = cameraOnLeft ? controlsFrame.minX - gap - previewX : textFrame.minX - gap - previewX
        let area = CGRect(x: previewX, y: 16, width: max(previewWidth, 1), height: size.height - 32)

        return CameraLayout(
            textFrame: textFrame,
            readingLineY: size.height / 2,
            controlsFrame: controlsFrame,
            cameraEdge: cameraOnLeft ? .left : .right,
            isLandscape: true,
            previewFrame: fit(aspect: band.videoAspect, in: area)
        )
    }
}
