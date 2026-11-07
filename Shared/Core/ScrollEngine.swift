import Foundation

/// Scroll state for the prompter: auto-speed, analog stick, eased follow, touch fling and manual offset.
/// Drawing and the display link live in the platform prompter views.
@MainActor
public final class ScrollEngine {
    /// Scrolled distance in points. Content moves up as this grows.
    public var offset: CGFloat = 0

    /// Largest allowed offset. Set by the prompter view after layout.
    public var maxOffset: CGFloat = 0 {
        didSet {
            let clamped = clampedOffset(offset)
            if clamped != offset {
                offset = clamped
                onChange?()
            }
        }
    }

    /// Auto-scroll speed in pt/s (mirrors the settings value).
    public var autoSpeed: CGFloat = 40

    /// Analog stick input, -1...1 (deadzone already applied by ControllerInput).
    public var stick: CGFloat = 0

    public var isPlaying = false

    /// Offset the follow ease moves toward. nil = not following.
    public var followTarget: CGFloat?

    /// Velocity left over from a touch fling, in pt/s. Decays to zero.
    public private(set) var inertia: CGFloat = 0

    /// Called whenever offset changes.
    public var onChange: (() -> Void)?

    /// Speed at full stick deflection (pt/s, mirrors the settings value).
    public var stickMaxSpeed: CGFloat = 400

    private let maxFollowSpeed: CGFloat = 1200
    private let followRate: CGFloat = 8
    private let maxFlingSpeed: CGFloat = 3000
    private let inertiaDecay: CGFloat = 4

    public init() {}

    /// True while tick() has work to do. The view uses it to pause the display link.
    public var isAnimating: Bool {
        isPlaying || stick != 0 || followTarget != nil || inertia != 0
    }

    /// True while a fling is still carrying the text. Manual-scroll settling waits for this to end.
    public var isCoasting: Bool {
        inertia != 0
    }

    public func tick(dt: CGFloat) {
        let step = min(max(dt, 0), 0.1)
        let previous = offset
        var next = offset

        if let target = followTarget {
            let goal = clampedOffset(target)
            let ease = (goal - next) * (1 - CGFloat(exp(Double(-step * followRate))))
            let limit = maxFollowSpeed * step
            next += min(max(ease, -limit), limit)
            if abs(goal - next) < 0.5 {
                followTarget = nil
            }
        }

        if inertia != 0 {
            next += inertia * step
            inertia *= CGFloat(exp(Double(-step * inertiaDecay)))
            if abs(inertia) < 2 {
                inertia = 0
            }
        }

        let velocity = (isPlaying ? autoSpeed : 0) + stick * stickMaxSpeed
        next += velocity * step
        let clamped = clampedOffset(next)
        if clamped != next {
            // Reached the end of the script: a fling must not keep pushing against it.
            inertia = 0
        }
        offset = clamped

        if offset != previous {
            onChange?()
        }
    }

    /// Manual scroll. Cancels the follow ease so the user is not fought.
    public func scroll(by delta: CGFloat) {
        guard delta != 0 else { return }
        followTarget = nil
        let next = clampedOffset(offset + delta)
        guard next != offset else { return }
        offset = next
        onChange?()
    }

    /// Starts coasting after a touch drag. Positive velocity moves the content up, like scroll(by:).
    public func fling(velocity: CGFloat) {
        followTarget = nil
        inertia = min(max(velocity, -maxFlingSpeed), maxFlingSpeed)
    }

    /// Stops a fling in progress, for example when the reader touches the text again.
    public func halt() {
        inertia = 0
    }

    public func restart() {
        offset = 0
        followTarget = nil
        inertia = 0
        onChange?()
    }

    private func clampedOffset(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), max(maxOffset, 0))
    }
}
