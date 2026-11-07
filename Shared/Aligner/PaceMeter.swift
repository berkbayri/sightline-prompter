import Foundation

/// Estimates reading speed from cumulative progress samples.
public struct PaceMeter {
    private static let windowSeconds: TimeInterval = 30
    private static let maxPauseSeconds: TimeInterval = 4
    private static let maxJumpUnits = 40
    private static let minUnits = 8.0
    private static let minActiveSeconds: TimeInterval = 6

    private struct Segment {
        let end: TimeInterval
        let units: Double
        let seconds: TimeInterval
    }

    private var anchor: (units: Int, time: TimeInterval)?
    private var segments: [Segment] = []

    public init() {}

    /// `units` is cumulative progress; `time` is a monotonic clock in seconds.
    public mutating func record(units: Int, time: TimeInterval) {
        guard let start = anchor else {
            anchor = (units, time)
            return
        }
        let du = units - start.units
        let dt = time - start.time
        // Stalled reading keeps the anchor so the stall is measured as a gap.
        if du == 0 || dt <= 0 { return }
        // Backward movement means the reader repositioned; restart from here.
        if du < 0 {
            anchor = (units, time)
            return
        }
        // Manual scroll or paragraph jump: not reading speed.
        if du > Self.maxJumpUnits {
            anchor = (units, time)
            return
        }
        anchor = (units, time)
        // Pause: exclude both its time and any units that moved during it.
        if dt > Self.maxPauseSeconds { return }

        segments.append(Segment(end: time, units: Double(du), seconds: dt))
        let cutoff = time - Self.windowSeconds
        segments.removeAll { $0.end < cutoff }
    }

    public mutating func reset() {
        anchor = nil
        segments.removeAll()
    }

    /// Units per minute over the recent window, or nil until enough data.
    public func unitsPerMinute() -> Double? {
        var units = 0.0
        var seconds: TimeInterval = 0
        for segment in segments {
            units += segment.units
            seconds += segment.seconds
        }
        guard units >= Self.minUnits, seconds >= Self.minActiveSeconds, seconds > 0 else {
            return nil
        }
        return units / seconds * 60
    }

    /// Seconds to read `remainingUnits` at the current pace, or nil without a pace.
    public func remainingSeconds(remainingUnits: Int) -> Double? {
        guard let rate = unitsPerMinute() else { return nil }
        guard remainingUnits > 0 else { return 0 }
        return Double(remainingUnits) / rate * 60
    }
}
