import Foundation

/// Scroll state for the prompter: auto-speed, analog stick, eased follow and manual offset.
/// Drawing and the display link live in PrompterView.
@MainActor
final class ScrollEngine {
    /// Scrolled distance in points. Content moves up as this grows.
    var offset: CGFloat = 0

    /// Largest allowed offset. Set by PrompterView after layout.
    var maxOffset: CGFloat = 0 {
        didSet {
            let clamped = clampedOffset(offset)
            if clamped != offset {
                offset = clamped
                onChange?()
            }
        }
    }

    /// Auto-scroll speed in pt/s (mirrors Settings.autoSpeed).
    var autoSpeed: CGFloat = 40

    /// Analog stick input, -1...1 (deadzone already applied by ControllerInput).
    var stick: CGFloat = 0

    var isPlaying = false

    /// Offset the follow ease moves toward. nil = not following.
    var followTarget: CGFloat?

    /// Called whenever offset changes.
    var onChange: (() -> Void)?

    /// Speed at full stick deflection (pt/s, mirrors Settings.stickMaxSpeed).
    var stickMaxSpeed: CGFloat = 400

    private let maxFollowSpeed: CGFloat = 1200
    private let followRate: CGFloat = 8

    /// True while tick() has work to do. The view uses it to pause the display link.
    var isAnimating: Bool {
        isPlaying || stick != 0 || followTarget != nil
    }

    func tick(dt: CGFloat) {
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

        let velocity = (isPlaying ? autoSpeed : 0) + stick * stickMaxSpeed
        next += velocity * step
        offset = clampedOffset(next)

        if offset != previous {
            onChange?()
        }
    }

    /// Manual scroll. Cancels the follow ease so the user is not fought.
    func scroll(by delta: CGFloat) {
        guard delta != 0 else { return }
        followTarget = nil
        let next = clampedOffset(offset + delta)
        guard next != offset else { return }
        offset = next
        onChange?()
    }

    func restart() {
        offset = 0
        followTarget = nil
        onChange?()
    }

    private func clampedOffset(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), max(maxOffset, 0))
    }
}
