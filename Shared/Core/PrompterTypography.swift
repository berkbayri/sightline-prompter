import Foundation

/// Distance-adaptive prompter typography (docs/prompter-typography.md). Pure math, no UI and no camera:
/// the apps feed it a viewing distance and the screen's physical density and get a font size, a column
/// width, a line budget and a backing-plate opacity back. Every constant is the spec's section 10 value.
public enum PrompterTypography {
    // MARK: - Constants (spec section 10)

    public static let xHeightRatioFallback = 0.526
    public static let alphaNominalDeg = 0.40
    public static let alphaMinDeg = 0.25
    public static let alphaMaxDeg = 0.60
    public static let cplTarget = 22.0
    public static let cplMin = 13.0
    public static let cplMax = 30.0
    public static let avgCharAdvanceEm = 0.50
    public static let lineHeightMultiple = 1.30
    public static let wordSpacingEm = 0.04
    public static let thetaVComfortDeg = 3.0
    public static let thetaVMaxDeg = 5.0
    public static let thetaHHalfDeg = 4.2
    public static let ipdMm = 63.0
    public static let yawRejectDeg = 30.0
    public static let minIPDPx = 24.0
    public static let sizeStepRatio = 1.10
    public static let reverseStepRatio = 1.15
    public static let scrimAlphaMin = 0.12
    public static let scrimAlphaMax = 0.65
    public static let scrimTargetRatio = 7.0
    public static let macScrimAlpha = 0.65
    public static let colorReadAlpha = 0.55

    /// Vertical extent of the current-word highlight, y growing downwards: cap top to just under the baseline,
    /// padded in em so it scales with the text and sits on the glyphs, not on the (taller) line box.
    public static func highlightBand(baseline: Double, capHeight: Double, fontSize: Double) -> (top: Double, bottom: Double) {
        (baseline - capHeight - 0.14 * fontSize, baseline + 0.2 * fontSize)
    }
    public static let iPhoneMinFontSize = 20.0
    public static let macMinFontSize = 16.0
    /// Mac distance presets in centimetres, spec section 5.4.
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case close, desk, back, standing

        public var id: String { rawValue }
        public var centimeters: Double {
            switch self {
            case .close: 45
            case .desk: 60
            case .back: 80
            case .standing: 120
            }
        }
        public var name: String {
            switch self {
            case .close: "Close"
            case .desk: "Desk"
            case .back: "Back"
            case .standing: "Standing"
            }
        }
    }

    // MARK: - Size from distance (spec 1.3)

    /// Font size in points that makes the x-height subtend `alphaDeg` at `distanceMm`.
    public static func fontSize(distanceMm: Double, ppmm: Double, xr: Double = xHeightRatioFallback,
                                alphaDeg: Double = alphaNominalDeg) -> Double {
        distanceMm * tan(alphaDeg * .pi / 180) * ppmm / xr
    }

    /// x-height visual angle in degrees a font size gives at a distance.
    public static func alphaDeg(fontSize: Double, distanceMm: Double, ppmm: Double,
                                xr: Double = xHeightRatioFallback) -> Double {
        atan(fontSize * xr / ppmm / distanceMm) * 180 / .pi
    }

    /// Characters per line for a half-sweep of `thetaHDeg`; independent of distance (spec 1.4).
    public static func charsPerLine(thetaHDeg: Double = thetaHHalfDeg, alphaDeg: Double = alphaNominalDeg,
                                    xr: Double = xHeightRatioFallback) -> Double {
        4 * xr * tan(thetaHDeg * .pi / 180) / tan(alphaDeg * .pi / 180)
    }

    /// Largest size at which `cplMin` characters still fit in `usableWidth` points.
    public static func widthCap(usableWidth: Double) -> Double {
        usableWidth / (avgCharAdvanceEm * cplMin)
    }

    /// Characters that fit a line at a size, clamped to the spec's range; also the column width in points.
    public static func lineLayout(fontSize: Double, usableWidth: Double) -> (chars: Double, columnWidth: Double) {
        let chars = min(max(usableWidth / (avgCharAdvanceEm * fontSize), cplMin), cplTarget)
        return (chars, chars * avgCharAdvanceEm * fontSize)
    }

    /// Lines the band should show so the lowest one stays within `thetaDeg` below the lens (spec 3.2).
    public static func visibleLines(distanceMm: Double, g0Mm: Double, alphaDeg: Double,
                                    lineHeight: Double = lineHeightMultiple,
                                    thetaDeg: Double = thetaVComfortDeg, xr: Double = xHeightRatioFallback,
                                    minLines: Int = 1, maxLines: Int = 5) -> Int {
        let perLine = lineHeight * tan(alphaDeg * .pi / 180) / xr
        let n = Int(floor((tan(thetaDeg * .pi / 180) - g0Mm / distanceMm) / perLine + 0.55))
        return min(max(n, minLines), maxLines)
    }

    /// What the size controller wants for a distance: the clamped size, the angle it gives and whether
    /// the viewer is too far for this screen (spec 11, targetSize()).
    public struct Plan: Equatable, Sendable {
        public var fontSize: Double
        public var alphaDeg: Double
        public var tooFar: Bool
    }

    public static func plan(distanceMm: Double, ppmm: Double, usableWidth: Double, gain: Double = 1,
                            minSize: Double = iPhoneMinFontSize, xr: Double = xHeightRatioFallback) -> Plan {
        let ideal = fontSize(distanceMm: distanceMm, ppmm: ppmm, xr: xr) * gain
        let size = max(min(ideal, widthCap(usableWidth: usableWidth)), minSize)
        let alpha = alphaDeg(fontSize: size, distanceMm: distanceMm, ppmm: ppmm, xr: xr)
        return Plan(fontSize: size, alphaDeg: alpha, tooFar: alpha < alphaMinDeg)
    }

    /// Mac relative live mode: size follows the inverse of the face width in the image (spec 5.4).
    public static func relativeSize(reference: Double, ipdRefPx: Double, ipdPx: Double) -> Double {
        reference * ipdRefPx / ipdPx
    }

    // MARK: - Screen density (spec 2)

    /// Logical points per millimetre by iPhone model identifier; unknown models get the common 6.037.
    public static func iPhonePPMM(modelID: String) -> Double {
        switch modelID {
        case "iPhone13,1", "iPhone14,4": 6.507 // 12 mini, 13 mini: panel downsampled
        case "iPhone12,8", "iPhone14,6": 6.417 // SE 2, SE 3
        case "iPhone13,4", "iPhone14,3", "iPhone14,8": 6.010 // 12/13 Pro Max, 14 Plus
        default: 6.037
        }
    }

    /// Lens to top of the first text line, in mm. 4 on Dynamic Island iPhones, 6 on notch and bezel models.
    /// shortcut: iPhone15,2 and later are Dynamic Island except the 16e, extend when a notched model ships.
    public static func iPhoneGapMm(modelID: String) -> Double {
        guard modelID.hasPrefix("iPhone"), let major = Int(modelID.dropFirst(6).prefix { $0 != "," }) else { return 6 }
        return major >= 15 && modelID != "iPhone17,5" ? 4 : 6
    }

    /// Mac: points per millimetre from the screen's reported width; 5.064 (Air 13.6) when it is implausible.
    public static func macPPMM(frameWidthPt: Double, physicalWidthMm: Double) -> Double {
        physicalWidthMm >= 200 && frameWidthPt > 0 ? frameWidthPt / physicalWidthMm : 5.064
    }

    // MARK: - Distance from a face (spec 4.2)

    /// Focal length in pixels from a horizontal field of view.
    public static func focalPx(horizontalFOVDeg: Double, imageWidthPx: Double) -> Double {
        imageWidthPx / (2 * tan(horizontalFOVDeg * .pi / 360))
    }

    /// Optical-axis distance in mm from the pupil distance in pixels, or nil for an unusable frame
    /// (turned head, face too small).
    public static func distanceMm(ipdPx: Double, yawRad: Double, focalPx: Double) -> Double? {
        guard focalPx > 0, abs(yawRad) <= yawRejectDeg * .pi / 180 else { return nil }
        let corrected = ipdPx / cos(yawRad)
        guard corrected >= minIPDPx else { return nil }
        return focalPx * ipdMm / corrected
    }

    // MARK: - Contrast (spec 8.3)

    /// sRGB encoding of a linear luminance.
    public static func encode(_ linear: Double) -> Double {
        linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }

    /// Black backing opacity that gives white text `ratio`:1 over a background of the given sRGB-encoded
    /// luma (what a video frame's Y plane holds), clamped to the spec's 0.12 ... 0.65.
    public static func scrimAlpha(backgroundLuma: Double, ratio: Double = scrimTargetRatio) -> Double {
        let allowed = 1.05 / ratio - 0.05
        guard backgroundLuma > 0 else { return scrimAlphaMin }
        return min(max(1 - encode(allowed) / backgroundLuma, scrimAlphaMin), scrimAlphaMax)
    }
}

// MARK: - 1 Euro filter (spec 4.4)

/// Casiez, Roussel and Vogel's 1 Euro filter: heavy smoothing while the signal is still, light when it moves.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var dCutoff: Double
    private var last: (time: Double, value: Double, derivative: Double)?

    public init(minCutoff: Double = 0.4, beta: Double = 5, dCutoff: Double = 1) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        1 / (1 + 1 / (2 * .pi * cutoff) / dt)
    }

    public mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let previous = last else {
            last = (time, value, 0)
            return value
        }
        guard time > previous.time else { return previous.value }
        let dt = time - previous.time
        let rawDerivative = (value - previous.value) / dt
        let derivative = previous.derivative + Self.alpha(cutoff: dCutoff, dt: dt) * (rawDerivative - previous.derivative)
        let cutoff = minCutoff + beta * abs(derivative)
        let smoothed = previous.value + Self.alpha(cutoff: cutoff, dt: dt) * (value - previous.value)
        last = (time, smoothed, derivative)
        return smoothed
    }
}

/// Median of the last five distances, then a 1 Euro filter on ln(distance), so a 10% move is the same
/// step at 0.4 m as at 2 m and a blink does not move the text.
public struct DistanceSmoother: Sendable {
    private var window: [Double] = []
    private var euro = OneEuroFilter()

    public init() {}

    /// Smoothed distance in mm after adding a measurement taken at `time` seconds.
    public mutating func add(distanceMm: Double, at time: Double) -> Double {
        window.append(log(distanceMm))
        if window.count > 5 { window.removeFirst() }
        let median = window.sorted()[window.count / 2]
        return exp(euro.filter(median, at: time))
    }
}

// MARK: - Size controller (spec 4.4)

/// Decides when a new text size is committed: on a geometric grid, only after the target has stayed 10%
/// (15% for a reversal) away for 1.5 s, at least 3 s after the last change, and at a speech pause
/// (or after waiting 4 s). Time is passed in, so it is deterministic.
public struct TextSizeController: Sendable {
    public static let gridBase = 20.0
    public static let dwell = 1.5
    public static let minGap = 3.0
    public static let maxWait = 4.0
    public static let pauseApply = 0.25
    public static let manualHold = 2.0

    public private(set) var current: Double
    private var exceededSince: Double?
    private var lastChange = -Double.infinity
    private var lastManual = -Double.infinity
    private var lastDirection = 0.0

    public init(initial: Double) {
        current = initial
    }

    /// The grid point (ratio 1.10, rounded to half a point) nearest a size.
    public static func snap(_ size: Double) -> Double {
        let steps = (log(size / gridBase) / log(PrompterTypography.sizeStepRatio)).rounded()
        return (gridBase * pow(PrompterTypography.sizeStepRatio, steps) * 2).rounded() / 2
    }

    /// The user changed the size by hand: it applies at once and holds for two seconds.
    public mutating func manual(_ size: Double, at time: Double) {
        current = size
        lastManual = time
        exceededSince = nil
    }

    /// Jumps to a size without waiting (the first measurement).
    public mutating func reset(to size: Double, at time: Double) {
        current = Self.snap(size)
        lastChange = time
        exceededSince = nil
    }

    /// Feeds the wanted size; returns the new size when one is committed.
    public mutating func update(target: Double, at time: Double, speechPause: Double,
                                atParagraphBreak: Bool = false, userInteracting: Bool = false) -> Double? {
        let move = log(target / current)
        let direction = move.sign == .minus ? -1.0 : 1.0
        let threshold = direction == lastDirection || lastDirection == 0
            ? PrompterTypography.sizeStepRatio : PrompterTypography.reverseStepRatio
        guard abs(move) >= log(threshold) else {
            exceededSince = nil
            return nil
        }
        let since = exceededSince ?? time
        exceededSince = since
        guard time - since >= Self.dwell, time - lastChange >= Self.minGap,
              time - lastManual >= Self.manualHold, !userInteracting else { return nil }
        guard speechPause >= Self.pauseApply || atParagraphBreak || time - since >= Self.maxWait else { return nil }
        let next = Self.snap(target)
        guard next != current else { return nil }
        current = next
        lastChange = time
        lastDirection = direction
        exceededSince = nil
        return next
    }
}

// MARK: - Live sizing pipeline

/// Measurements in, committed text sizes out: smoothing, the size grid, hysteresis and timing in one place,
/// so the iPhone (metric distance) and the Mac (relative face width) share it. A measurement is anything
/// proportional to the viewing distance (millimetres, or 1 / pupil pixels); the caller maps it to a size.
public struct AdaptiveTextSize: Sendable {
    public static let noFaceTimeout = 5.0

    private var smoother = DistanceSmoother()
    private var controller: TextSizeController
    private var firstDone = false
    public private(set) var smoothed: Double?
    private var lastSample: Double?

    public init(initial: Double) {
        controller = TextSizeController(initial: initial)
    }

    public var size: Double { controller.current }

    /// Adds one raw measurement taken at `time` seconds.
    public mutating func add(_ measurement: Double, at time: Double) {
        smoothed = smoother.add(distanceMm: measurement, at: time)
        lastSample = time
    }

    /// Seconds since the last measurement; nil before the first one.
    public func age(at time: Double) -> Double? {
        lastSample.map { time - $0 }
    }

    /// The user set a size: it applies at once and the controller holds off for two seconds.
    public mutating func manual(_ size: Double, at time: Double) {
        controller.manual(size, at: time)
    }

    /// Run about every 200 ms. `target` maps the smoothed measurement to the wanted size. Returns a size to
    /// apply, or nil. The first measurement is applied at once; later ones go through the controller.
    /// With no face for five seconds nothing is returned, so the last size stays.
    public mutating func tick(at time: Double, speechPause: Double, userInteracting: Bool = false,
                              target: (Double) -> Double) -> Double? {
        guard let smoothed, let age = age(at: time), age <= Self.noFaceTimeout else { return nil }
        let wanted = target(smoothed)
        if !firstDone {
            firstDone = true
            controller.reset(to: wanted, at: time)
            return controller.current
        }
        return controller.update(target: wanted, at: time, speechPause: speechPause, userInteracting: userInteracting)
    }
}

// MARK: - Defaults migration

/// 1.0.3 changed the default text style. A setting the user never touched is not stored, so it simply
/// reads the new default; the one thing to repair is a value that equals an old default, which an older
/// build may have written on its own. Runs once, guarded by a version key.
public enum TypographyDefaults {
    public static let versionKey = "typographyDefaultsVersion"
    public static let version = 1

    public static func migrate(_ defaults: UserDefaults, oldDefaults: [String: Double]) {
        guard defaults.integer(forKey: versionKey) < version else { return }
        for (key, old) in oldDefaults where defaults.object(forKey: key) as? Double == old {
            defaults.removeObject(forKey: key)
        }
        defaults.set(version, forKey: versionKey)
    }
}
