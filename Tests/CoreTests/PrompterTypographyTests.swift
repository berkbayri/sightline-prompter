import CoreVideo
import XCTest
@testable import SightlineCore

/// Expected numbers are the tables of docs/prompter-typography.md (sections 1 to 8), not recomputed here.
final class PrompterTypographyTests: XCTestCase {
    private typealias T = PrompterTypography
    private let phone = 6.037 // iPhone 16 Pro
    private let air = 5.064 // MacBook Air 13.6

    // MARK: Size from distance (section 6 tables)

    func testIPhoneIdealSizeFollowsTheTable() {
        let table: [(m: Double, pt: Double)] = [(0.3, 24), (0.4, 32), (0.5, 40), (0.6, 48), (0.8, 64), (1.0, 80), (1.5, 120)]
        for row in table {
            XCTAssertEqual(T.fontSize(distanceMm: row.m * 1000, ppmm: phone), row.pt, accuracy: 0.6, "\(row.m) m")
        }
    }

    func testIPhoneWidthCapAndAngleFollowTheTable() {
        // Usable width 370 pt: size stops at 57 pt, the angle drops with distance.
        let table: [(m: Double, pt: Double, alpha: Double)] = [(0.3, 24, 0.40), (0.6, 48, 0.40), (0.8, 57, 0.36), (1.0, 57, 0.28), (1.5, 57, 0.19)]
        for row in table {
            let plan = T.plan(distanceMm: row.m * 1000, ppmm: phone, usableWidth: 370)
            XCTAssertEqual(plan.fontSize, row.pt, accuracy: 1, "\(row.m) m")
            XCTAssertEqual(plan.alphaDeg, row.alpha, accuracy: 0.01, "\(row.m) m")
        }
    }

    func testPortraitPhoneIsTooFarBeyondAboutOnePointOneMetres() {
        XCTAssertFalse(T.plan(distanceMm: 1000, ppmm: phone, usableWidth: 370).tooFar)
        XCTAssertFalse(T.plan(distanceMm: 1100, ppmm: phone, usableWidth: 370).tooFar)
        XCTAssertTrue(T.plan(distanceMm: 1200, ppmm: phone, usableWidth: 370).tooFar)
        XCTAssertTrue(T.plan(distanceMm: 2000, ppmm: phone, usableWidth: 370).tooFar)
        // Landscape roughly doubles the usable width and moves the limit to about 2.4 m.
        XCTAssertFalse(T.plan(distanceMm: 2300, ppmm: phone, usableWidth: 780).tooFar)
        XCTAssertTrue(T.plan(distanceMm: 2500, ppmm: phone, usableWidth: 780).tooFar)
    }

    func testMacSizesFollowTheTable() {
        let table: [(m: Double, pt: Double)] = [(0.4, 27), (0.5, 34), (0.6, 40), (0.7, 47), (0.8, 54), (1.0, 67), (1.5, 101)]
        for row in table {
            XCTAssertEqual(T.fontSize(distanceMm: row.m * 1000, ppmm: air), row.pt, accuracy: 0.7, "\(row.m) m")
        }
        let far = T.plan(distanceMm: 1500, ppmm: air, usableWidth: 488, minSize: T.macMinFontSize)
        XCTAssertEqual(far.fontSize, 75, accuracy: 1)
        XCTAssertEqual(far.alphaDeg, 0.30, accuracy: 0.01)
    }

    func testPresetsAndDefaultsAgreeWithTheModel() {
        XCTAssertEqual(T.Preset.allCases.map(\.centimeters), [45, 60, 80, 120])
        // Section 7 defaults: 36 pt at 45 cm on an iPhone, 40 pt at 60 cm on a Mac.
        XCTAssertEqual(T.fontSize(distanceMm: 450, ppmm: phone), 36, accuracy: 0.3)
        XCTAssertEqual(T.fontSize(distanceMm: 600, ppmm: air), 40, accuracy: 0.5)
        // The old defaults: 34 pt is 0.40 deg at 42 cm, 26 pt is only 0.26 deg at 60 cm.
        XCTAssertEqual(T.alphaDeg(fontSize: 34, distanceMm: 420, ppmm: phone), 0.40, accuracy: 0.01)
        XCTAssertEqual(T.alphaDeg(fontSize: 26, distanceMm: 600, ppmm: air), 0.26, accuracy: 0.01)
    }

    func testMacRelativeSizeIsInverseToFaceWidth() {
        XCTAssertEqual(T.relativeSize(reference: 40, ipdRefPx: 50, ipdPx: 25), 80, accuracy: 0.001)
        XCTAssertEqual(T.relativeSize(reference: 40, ipdRefPx: 50, ipdPx: 100), 20, accuracy: 0.001)
    }

    // MARK: Characters per line, lines, margins

    func testCharactersPerLineFollowTheTable() {
        let table: [(theta: Double, alpha: Double, cpl: Double)] = [
            (3, 0.30, 21), (3, 0.40, 16), (3, 0.55, 12), (4, 0.30, 28), (4, 0.40, 21), (4, 0.55, 15),
            (5, 0.30, 35), (5, 0.40, 26), (5, 0.55, 19),
        ]
        for row in table {
            XCTAssertEqual(T.charsPerLine(thetaHDeg: row.theta, alphaDeg: row.alpha), row.cpl, accuracy: 0.6, "\(row.theta) / \(row.alpha)")
        }
    }

    func testColumnWidthKeepsTwentyTwoCharactersAndTheWidthCap() {
        let narrow = T.lineLayout(fontSize: 24, usableWidth: 370)
        XCTAssertEqual(narrow.chars, 22)
        XCTAssertEqual(narrow.columnWidth, 264, accuracy: 0.01)
        let wide = T.lineLayout(fontSize: 48, usableWidth: 370)
        XCTAssertEqual(wide.chars, 370 / 24, accuracy: 0.01)
        XCTAssertEqual(wide.columnWidth, 370, accuracy: 0.01)
        XCTAssertEqual(T.lineLayout(fontSize: 80, usableWidth: 370).chars, 13) // never below 13
        XCTAssertEqual(T.widthCap(usableWidth: 370), 56.92, accuracy: 0.01)
    }

    func testLineBudgetFollowsTheTable() {
        // d (m): lines at 3, 4 and 5 degrees, alpha 0.40, lh 1.30, g0 4 mm.
        let table: [(m: Double, n: [Int])] = [(0.3, [2, 3, 4]), (0.4, [3, 4, 5]), (0.5, [3, 4, 5]), (0.6, [3, 4, 5]), (1.0, [3, 4, 5]), (1.5, [3, 4, 5])]
        for row in table {
            let counts = [3.0, 4.0, 5.0].map {
                T.visibleLines(distanceMm: row.m * 1000, g0Mm: 4, alphaDeg: 0.40, thetaDeg: $0)
            }
            XCTAssertEqual(counts, row.n, "\(row.m) m")
        }
        XCTAssertEqual(T.visibleLines(distanceMm: 1500, g0Mm: 4, alphaDeg: 0.30, thetaDeg: 3, maxLines: 7), 4)
        XCTAssertEqual(T.visibleLines(distanceMm: 1500, g0Mm: 4, alphaDeg: 0.30, thetaDeg: 5, maxLines: 7), 7)
    }

    // MARK: Screens

    func testScreenDensityTables() {
        XCTAssertEqual(T.iPhonePPMM(modelID: "iPhone17,1"), 6.037)
        XCTAssertEqual(T.iPhonePPMM(modelID: "iPhone99,1"), 6.037) // unknown future model
        XCTAssertEqual(T.iPhonePPMM(modelID: "iPhone14,4"), 6.507, accuracy: 0.001) // 13 mini
        XCTAssertEqual(T.iPhonePPMM(modelID: "iPhone14,6"), 6.417, accuracy: 0.001) // SE 3
        XCTAssertEqual(T.iPhonePPMM(modelID: "iPhone14,3"), 6.010, accuracy: 0.001) // 13 Pro Max
        XCTAssertEqual(T.macPPMM(frameWidthPt: 1470, physicalWidthMm: 290.3), 5.064, accuracy: 0.01)
        XCTAssertEqual(T.macPPMM(frameWidthPt: 1470, physicalWidthMm: 0), 5.064)
        XCTAssertEqual(T.macPPMM(frameWidthPt: 1470, physicalWidthMm: 120), 5.064)
    }

    func testLensGapByModel() {
        XCTAssertEqual(T.iPhoneGapMm(modelID: "iPhone17,1"), 4) // 17 Pro, Dynamic Island
        XCTAssertEqual(T.iPhoneGapMm(modelID: "iPhone15,2"), 4)
        XCTAssertEqual(T.iPhoneGapMm(modelID: "iPhone14,5"), 6) // 13, notch
        XCTAssertEqual(T.iPhoneGapMm(modelID: "iPhone14,6"), 6) // SE 3
        XCTAssertEqual(T.iPhoneGapMm(modelID: "iPhone17,5"), 6) // 16e, notch
        XCTAssertEqual(T.iPhoneGapMm(modelID: "arm64"), 6)
    }

    // MARK: Distance from a face (section 4.2 and 4.3)

    func testPinholeDistanceMatchesTheErrorTable() {
        let focal = T.focalPx(horizontalFOVDeg: 70, imageWidthPx: 640)
        XCTAssertEqual(focal, 457, accuracy: 1)
        // ipd_px column of the table: 72, 48, 29, 19, 14 px at 0.4, 0.6, 1.0, 1.5, 2.0 m.
        // Beyond 1 m the face is under the 24 px floor and is rejected, so only the first three are measurable.
        for row: (px: Double, mm: Double) in [(72, 400), (48, 600), (29, 1000)] {
            let d = T.distanceMm(ipdPx: row.px, yawRad: 0, focalPx: focal)!
            XCTAssertEqual(d, row.mm, accuracy: row.mm * 0.02, "\(row.px) px")
        }
        XCTAssertNil(T.distanceMm(ipdPx: 19, yawRad: 0, focalPx: focal)) // 1.5 m
        // One pixel off at 0.4 m is a 1.4% error.
        let near = T.distanceMm(ipdPx: 72, yawRad: 0, focalPx: focal)!
        let off = T.distanceMm(ipdPx: 71, yawRad: 0, focalPx: focal)!
        XCTAssertEqual(off / near - 1, 0.014, accuracy: 0.002)
    }

    func testYawIsCorrectedAndRejectedPastThirtyDegrees() {
        let focal = T.focalPx(horizontalFOVDeg: 70, imageWidthPx: 640)
        let yaw = 10.0 * .pi / 180
        let turned = T.distanceMm(ipdPx: 72 * cos(yaw), yawRad: yaw, focalPx: focal)!
        XCTAssertEqual(turned, 400, accuracy: 3)
        XCTAssertNil(T.distanceMm(ipdPx: 60, yawRad: 31 * .pi / 180, focalPx: focal))
        XCTAssertNotNil(T.distanceMm(ipdPx: 60, yawRad: 29 * .pi / 180, focalPx: focal))
    }

    func testFaceTooSmallIsInvalid() {
        XCTAssertNil(T.distanceMm(ipdPx: 23, yawRad: 0, focalPx: 457))
        XCTAssertNotNil(T.distanceMm(ipdPx: 24, yawRad: 0, focalPx: 457))
        XCTAssertNil(T.distanceMm(ipdPx: 60, yawRad: 0, focalPx: 0))
    }

    // MARK: Contrast (section 8.3 table)

    func testScrimAlphaFollowsTheContrastTable() {
        // Rows are linear luminance; the video's Y plane holds the sRGB-encoded value.
        let table: [(lum: Double, aa: Double, aaa: Double)] = [(0.90, 0.51, 0.63), (0.70, 0.46, 0.59), (0.50, 0.37, 0.53), (0.30, 0.20, 0.40)]
        for row in table {
            let luma = T.encode(row.lum)
            XCTAssertEqual(T.scrimAlpha(backgroundLuma: luma, ratio: 4.5), row.aa, accuracy: 0.015, "AA \(row.lum)")
            XCTAssertEqual(T.scrimAlpha(backgroundLuma: luma, ratio: 7), row.aaa, accuracy: 0.015, "AAA \(row.lum)")
        }
    }

    func testScrimAlphaIsClampedForDarkAndBlownOutScenes() {
        XCTAssertEqual(T.scrimAlpha(backgroundLuma: 0), 0.12)
        XCTAssertEqual(T.scrimAlpha(backgroundLuma: 0.2), 0.12) // dark scene: halo-only floor
        XCTAssertEqual(T.scrimAlpha(backgroundLuma: 1.0), 0.65) // white sky: never above 0.65
    }

    // MARK: 1 Euro filter and smoothing (section 4.4)

    func testOneEuroPassesAConstantAndSmoothsAStillSignal() {
        var euro = OneEuroFilter()
        XCTAssertEqual(euro.filter(5, at: 0), 5)
        for step in 1...20 { XCTAssertEqual(euro.filter(5, at: Double(step) * 0.2), 5, accuracy: 1e-9) }

        var noisy = OneEuroFilter()
        var worst = 0.0
        for step in 0..<50 {
            let jitter = step.isMultiple(of: 2) ? 0.005 : -0.005 // 0.5% distance jitter
            let out = noisy.filter(6 + jitter, at: Double(step) * 0.2)
            if step >= 10 { worst = max(worst, abs(out - 6)) }
        }
        XCTAssertLessThan(worst, 0.003) // well under the raw jitter
    }

    func testOneEuroFollowsADeliberateMoveFasterThanAFixedCutoff() {
        var adaptive = OneEuroFilter()
        var fixed = OneEuroFilter(beta: 0)
        _ = adaptive.filter(6, at: 0); _ = fixed.filter(6, at: 0)
        var a = 0.0, f = 0.0
        for step in 1...5 { // ln distance moves by 0.4 over one second
            let value = 6 + 0.4 * Double(step) / 5
            a = adaptive.filter(value, at: Double(step) * 0.2)
            f = fixed.filter(value, at: Double(step) * 0.2)
        }
        XCTAssertGreaterThan(a, f)
        XCTAssertGreaterThan(a, 6.25)
    }

    func testSmootherDropsAnOutlierAndWorksInLogSpace() {
        var smoother = DistanceSmoother()
        var last = 0.0
        for step in 0..<4 { last = smoother.add(distanceMm: 500, at: Double(step) * 0.2) }
        XCTAssertEqual(last, 500, accuracy: 0.001)
        last = smoother.add(distanceMm: 2000, at: 0.8) // blink or landmark glitch
        XCTAssertEqual(last, 500, accuracy: 25)
    }

    // MARK: Size bucketing, hysteresis and timing (section 4.4)

    func testSnapUsesATenPercentGrid() {
        XCTAssertEqual(TextSizeController.snap(20), 20)
        XCTAssertEqual(TextSizeController.snap(22.1), 22)
        XCTAssertEqual(TextSizeController.snap(40), 39)
        let a = TextSizeController.snap(60), b = TextSizeController.snap(60 * 1.1)
        XCTAssertEqual(b / a, 1.1, accuracy: 0.02)
    }

    func testControllerNeedsTenPercentHeldForOneAndAHalfSeconds() {
        var controller = TextSizeController(initial: 39)
        XCTAssertNil(controller.update(target: 39 * 1.08, at: 0, speechPause: 1)) // inside the step
        XCTAssertNil(controller.update(target: 39 * 1.12, at: 1, speechPause: 1)) // starts the dwell
        XCTAssertNil(controller.update(target: 39 * 1.12, at: 2, speechPause: 1)) // 1.0 s held, not enough
        XCTAssertEqual(controller.update(target: 39 * 1.12, at: 2.6, speechPause: 1), TextSizeController.snap(39 * 1.12))
    }

    func testControllerWaitsForASpeechPauseButNotMoreThanFourSeconds() {
        var controller = TextSizeController(initial: 39)
        XCTAssertNil(controller.update(target: 50, at: 0, speechPause: 0))
        XCTAssertNil(controller.update(target: 50, at: 2, speechPause: 0.1)) // talking: not applied
        XCTAssertNil(controller.update(target: 50, at: 3.9, speechPause: 0.1))
        XCTAssertNotNil(controller.update(target: 50, at: 4.1, speechPause: 0.1)) // waited 4 s
    }

    func testControllerHonoursMinimumGapAndReversalThreshold() {
        var controller = TextSizeController(initial: 39)
        _ = controller.update(target: 50, at: 0, speechPause: 1)
        XCTAssertNotNil(controller.update(target: 50, at: 1.6, speechPause: 1))
        let now = controller.current
        // Back down by 12%: not enough for a reversal (needs 15%).
        XCTAssertNil(controller.update(target: now * 0.88, at: 6, speechPause: 1))
        XCTAssertNil(controller.update(target: now * 0.88, at: 9, speechPause: 1))
        // 20% down is enough, and only once the gap since the last change has passed.
        XCTAssertNil(controller.update(target: now * 0.8, at: 10, speechPause: 1))
        XCTAssertNotNil(controller.update(target: now * 0.8, at: 11.6, speechPause: 1))
    }

    func testControllerHoldsWhileTheUserDragsOrJustChangedTheSize() {
        var controller = TextSizeController(initial: 39)
        _ = controller.update(target: 50, at: 0, speechPause: 1, userInteracting: true)
        XCTAssertNil(controller.update(target: 50, at: 2, speechPause: 1, userInteracting: true))
        controller.manual(44, at: 10)
        XCTAssertEqual(controller.current, 44)
        _ = controller.update(target: 60, at: 10.1, speechPause: 1)
        XCTAssertNil(controller.update(target: 60, at: 11.7, speechPause: 1)) // inside the 2 s after a manual change
        XCTAssertNotNil(controller.update(target: 60, at: 12.2, speechPause: 1))
    }

    func testResetTakesTheFirstMeasurementAtOnce() {
        var controller = TextSizeController(initial: 36)
        controller.reset(to: 48, at: 0)
        XCTAssertEqual(controller.current, TextSizeController.snap(48))
    }

    // MARK: Whole pipeline

    func testPipelineFollowsAWalkBackFromTheScreen() {
        // iPhone 16 Pro, a reader moves from 0.4 m to 0.8 m and stays: the size ends near 64 pt (width cap 57).
        var sizer = AdaptiveTextSize(initial: 36)
        let target: (Double) -> Double = { T.plan(distanceMm: $0, ppmm: 6.037, usableWidth: 780).fontSize }
        var sizes: [Double] = []
        var time = 0.0
        for _ in 0..<15 { // five seconds at 0.4 m
            sizer.add(400, at: time)
            if let s = sizer.tick(at: time, speechPause: 1, target: target) { sizes.append(s) }
            time += 0.2
        }
        XCTAssertEqual(sizes.first!, TextSizeController.snap(32), accuracy: 0.01) // first measurement is immediate
        for _ in 0..<60 { // twelve seconds at 0.8 m
            sizer.add(800, at: time)
            if let s = sizer.tick(at: time, speechPause: 1, target: target) { sizes.append(s) }
            time += 0.2
        }
        XCTAssertEqual(sizer.size, TextSizeController.snap(64), accuracy: 0.01)
        XCTAssertLessThanOrEqual(sizes.count, 6) // a few steady steps, not a flicker
    }

    func testPipelineKeepsTheLastSizeWhenTheFaceIsGone() {
        var sizer = AdaptiveTextSize(initial: 36)
        sizer.add(500, at: 0)
        XCTAssertNotNil(sizer.tick(at: 0, speechPause: 1, target: { _ in 40 }))
        XCTAssertNil(sizer.tick(at: 5.5, speechPause: 1, target: { _ in 80 }))
        XCTAssertEqual(sizer.size, TextSizeController.snap(40))
        XCTAssertEqual(sizer.age(at: 5.5)!, 5.5, accuracy: 0.001)
    }

    func testPipelineRelativeMacModeScalesWithFaceWidth() {
        // Mac: reference face 50 px at 40 pt. The reader leans back until the face is 25 px: size doubles.
        var sizer = AdaptiveTextSize(initial: 40)
        let target: (Double) -> Double = { T.relativeSize(reference: 40, ipdRefPx: 50, ipdPx: 1 / $0) }
        sizer.add(1.0 / 50, at: 0)
        _ = sizer.tick(at: 0, speechPause: 1, target: target)
        XCTAssertEqual(sizer.size, TextSizeController.snap(40))
        var time = 0.2
        for _ in 0..<40 {
            sizer.add(1.0 / 25, at: time)
            _ = sizer.tick(at: time, speechPause: 1, target: target)
            time += 0.2
        }
        XCTAssertEqual(sizer.size, TextSizeController.snap(80), accuracy: 0.01)
    }

    func testAFrameWithoutAFaceGivesNoSample() {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 160, 120, kCVPixelFormatType_32BGRA, nil, &buffer)
        XCTAssertNil(FaceMeasure.largestFace(in: buffer!))
        XCTAssertNil(FaceMeasure.largestFace(in: buffer!, orientation: .leftMirrored))
    }

    // MARK: Defaults migration

    func testMigrationRemovesAnOldDefaultOnceAndKeepsRealChoices() {
        let suite = "PrompterTypographyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(34.0, forKey: "fontSize") // equals the old default: never a real choice
        defaults.set(1.5, forKey: "lineSpacing") // the user's own value
        TypographyDefaults.migrate(defaults, oldDefaults: ["fontSize": 34, "lineSpacing": 1.35, "letterSpacing": 0])
        XCTAssertNil(defaults.object(forKey: "fontSize"))
        XCTAssertEqual(defaults.double(forKey: "lineSpacing"), 1.5)
        XCTAssertEqual(defaults.integer(forKey: TypographyDefaults.versionKey), TypographyDefaults.version)
        // A later, deliberate 34 survives: the migration does not run again.
        defaults.set(34.0, forKey: "fontSize")
        TypographyDefaults.migrate(defaults, oldDefaults: ["fontSize": 34])
        XCTAssertEqual(defaults.double(forKey: "fontSize"), 34)
    }
}
