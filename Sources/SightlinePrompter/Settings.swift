import Foundation

/// How stick travel maps to scroll speed. Travel is normalized to 0...1 after the deadzone.
enum StickCurve: String, CaseIterable, Identifiable {
    case linear, quadratic, cubic

    var id: String { rawValue }

    var name: String {
        switch self {
        case .linear: "Linear"
        case .quadratic: "Smooth"
        case .cubic: "Precise"
        }
    }

    /// Speed fraction 0...1 for a normalized travel 0...1. Smooth and Precise start slower.
    func apply(_ travel: Float) -> Float {
        switch self {
        case .linear: travel
        case .quadratic: travel * travel
        case .cubic: travel * travel * travel
        }
    }
}

/// Persisted user settings. Every property writes itself to UserDefaults on change.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key: String {
        case script, scriptLanguage, panelWidth, panelHeight, xOffset, fontSize, autoSpeed, hideFromCapture
        case stickCurve, stickMaxSpeed, stickDeadzone, activeScriptID, showPace, gamepadLight
    }

    private let defaults = UserDefaults.standard

    /// The teleprompter text.
    @Published var script: String {
        didSet { defaults.set(script, forKey: Key.script.rawValue) }
    }

    /// Locale identifier of the script, used by speech recognition (e.g. "tr-TR", "en-US").
    @Published var scriptLanguage: String {
        didSet { defaults.set(scriptLanguage, forKey: Key.scriptLanguage.rawValue) }
    }

    /// Panel width in points, set independently of the notch width.
    @Published var panelWidth: Double {
        didSet { defaults.set(panelWidth, forKey: Key.panelWidth.rawValue) }
    }

    /// Panel height in points, measured down from the top edge of the screen.
    @Published var panelHeight: Double {
        didSet { defaults.set(panelHeight, forKey: Key.panelHeight.rawValue) }
    }

    /// Horizontal offset of the panel center from the notch center (points, positive = right).
    @Published var xOffset: Double {
        didSet { defaults.set(xOffset, forKey: Key.xOffset.rawValue) }
    }

    /// Text font size in points.
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Key.fontSize.rawValue) }
    }

    /// Auto-scroll speed in points per second.
    @Published var autoSpeed: Double {
        didSet { defaults.set(autoSpeed, forKey: Key.autoSpeed.rawValue) }
    }

    /// When true the window is invisible to screen sharing and recording.
    @Published var hideFromCapture: Bool {
        didSet { defaults.set(hideFromCapture, forKey: Key.hideFromCapture.rawValue) }
    }

    /// Response curve of the gamepad stick.
    @Published var stickCurve: StickCurve {
        didSet { defaults.set(stickCurve.rawValue, forKey: Key.stickCurve.rawValue) }
    }

    /// Scroll speed at full stick deflection, in points per second.
    @Published var stickMaxSpeed: Double {
        didSet { defaults.set(stickMaxSpeed, forKey: Key.stickMaxSpeed.rawValue) }
    }

    /// Stick travel ignored around the center, as a fraction of full deflection.
    @Published var stickDeadzone: Double {
        didSet { defaults.set(stickDeadzone, forKey: Key.stickDeadzone.rawValue) }
    }

    /// Library script currently loaded into the prompter (UUID string, empty if none).
    @Published var activeScriptID: String {
        didSet { defaults.set(activeScriptID, forKey: Key.activeScriptID.rawValue) }
    }

    /// Shows words-per-minute and time left while the prompter is running.
    @Published var showPace: Bool {
        didSet { defaults.set(showPace, forKey: Key.showPace.rawValue) }
    }

    /// Drives the DualSense light bar to show tracking and scroll state.
    @Published var gamepadLight: Bool {
        didSet { defaults.set(gamepadLight, forKey: Key.gamepadLight.rawValue) }
    }

    private init() {
        script = defaults.string(forKey: Key.script.rawValue) ?? ""
        scriptLanguage = defaults.string(forKey: Key.scriptLanguage.rawValue) ?? "tr-TR"
        panelWidth = defaults.object(forKey: Key.panelWidth.rawValue) as? Double ?? 520
        panelHeight = defaults.object(forKey: Key.panelHeight.rawValue) as? Double ?? 220
        xOffset = defaults.object(forKey: Key.xOffset.rawValue) as? Double ?? 0
        fontSize = defaults.object(forKey: Key.fontSize.rawValue) as? Double ?? 26
        autoSpeed = defaults.object(forKey: Key.autoSpeed.rawValue) as? Double ?? 40
        hideFromCapture = defaults.object(forKey: Key.hideFromCapture.rawValue) as? Bool ?? true
        stickCurve = StickCurve(rawValue: defaults.string(forKey: Key.stickCurve.rawValue) ?? "") ?? .cubic
        stickMaxSpeed = defaults.object(forKey: Key.stickMaxSpeed.rawValue) as? Double ?? 400
        stickDeadzone = defaults.object(forKey: Key.stickDeadzone.rawValue) as? Double ?? 0.12
        activeScriptID = defaults.string(forKey: Key.activeScriptID.rawValue) ?? ""
        showPace = defaults.object(forKey: Key.showPace.rawValue) as? Bool ?? true
        gamepadLight = defaults.object(forKey: Key.gamepadLight.rawValue) as? Bool ?? true
    }
}
