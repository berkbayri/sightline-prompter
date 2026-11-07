import Foundation

/// How stick travel maps to scroll speed. Travel is normalized to 0...1 after the deadzone.
public enum StickCurve: String, CaseIterable, Identifiable, Sendable {
    case linear, quadratic, cubic

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .linear: "Linear"
        case .quadratic: "Smooth"
        case .cubic: "Precise"
        }
    }

    /// Speed fraction 0...1 for a normalized travel 0...1. Smooth and Precise start slower.
    public func apply(_ travel: Float) -> Float {
        switch self {
        case .linear: travel
        case .quadratic: travel * travel
        case .cubic: travel * travel * travel
        }
    }
}
