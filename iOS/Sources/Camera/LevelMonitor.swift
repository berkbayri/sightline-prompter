import CoreMotion
import SwiftUI

/// Tilt of the phone, for the level on the camera view. `roll` is the tilt of the picture's horizon in degrees,
/// measured from the nearest upright or sideways position (so portrait and landscape both read 0 when level).
/// `pitch` is how far the phone leans back or forward from vertical, in degrees.
@MainActor
final class LevelMonitor: ObservableObject {
    @Published private(set) var roll: Double = 0
    @Published private(set) var pitch: Double = 0

    private let motion = CMMotionManager()

    /// Within this many degrees the phone counts as level.
    static let levelTolerance = 1.0

    var isLevel: Bool { abs(roll) <= Self.levelTolerance }
    var isPlumb: Bool { abs(pitch) <= 2.0 }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let gravity = data?.gravity else { return }
            Task { @MainActor in self?.update(gravity: gravity) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    private func update(gravity g: CMAcceleration) {
        // Angle of gravity in the screen plane: 0 for upright portrait, ±90 for landscape.
        let angle = atan2(g.x, -g.y) * 180 / .pi
        // Distance from the nearest multiple of 90 degrees.
        var tilt = angle.truncatingRemainder(dividingBy: 90)
        if tilt > 45 { tilt -= 90 }
        if tilt < -45 { tilt += 90 }
        // Smoothed so the line does not jitter.
        roll = roll * 0.7 + tilt * 0.3
        // Gravity along the screen normal: 0 when the phone stands upright, ±1 when it lies flat.
        pitch = pitch * 0.7 + asin(max(-1, min(1, g.z))) * 180 / .pi * 0.3
    }
}

/// A spirit level over the camera picture: a horizon line that tilts with the phone and a bubble that shows
/// the lean. Both turn green when the phone is level and upright. Touches pass through.
struct LevelOverlay: View {
    @ObservedObject var level: LevelMonitor

    var body: some View {
        GeometryReader { proxy in
            let level = self.level
            let color: Color = level.isLevel ? .green : .white.opacity(0.85)
            let length = min(proxy.size.width, proxy.size.height) * 0.14
            ZStack {
                // Horizon line, rotated against the tilt so it stays level with the world.
                Capsule()
                    .fill(color)
                    .frame(width: length * 2, height: 1)
                    .rotationEffect(.degrees(-level.roll))
                // Bubble: leans with the pitch, centered when the phone is upright.
                Circle()
                    .strokeBorder(level.isPlumb ? Color.green : Color.white.opacity(0.6), lineWidth: 1)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .fill(level.isPlumb ? Color.green : Color.white.opacity(0.85))
                            .frame(width: 4, height: 4)
                            .offset(y: CGFloat(max(-1, min(1, level.pitch / 20))) * 4)
                    )
                Text(String(format: "%+.0f°", level.roll))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
                    .offset(y: 18)
            }
            .shadow(color: .black.opacity(0.7), radius: 1.5)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
