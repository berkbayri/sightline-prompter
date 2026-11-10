import Combine
import Foundation
import SightlineCore

/// Which side the front camera is on in landscape. Automatic follows the device orientation.
enum CameraSide: String, CaseIterable, Identifiable {
    case automatic, left, right

    var id: String { rawValue }

    var name: String {
        switch self {
        case .automatic: "Automatic"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// Persisted iPhone settings. Every property writes itself to UserDefaults on change.
@MainActor
final class PhoneSettings: ObservableObject {
    static let shared = PhoneSettings()

    private enum Key: String {
        case activeScriptID, fontSize, autoSpeed, showPace, readingDistanceCm, landscapeColumnWidth
        case portraitWidthPercent, portraitLines, landscapeLines
        case arrangementPortrait, arrangementLandscape
        case cameraSide, stickCurve, stickMaxSpeed, stickDeadzone, gamepadLight
    }

    private let defaults = UserDefaults.standard

    /// Library script currently loaded into the prompter (UUID string, empty if none).
    @Published var activeScriptID: String {
        didSet { defaults.set(activeScriptID, forKey: Key.activeScriptID.rawValue) }
    }

    /// Text font size in points.
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Key.fontSize.rawValue) }
    }

    /// Auto-scroll speed in points per second.
    @Published var autoSpeed: Double {
        didSet { defaults.set(autoSpeed, forKey: Key.autoSpeed.rawValue) }
    }

    /// Shows words-per-minute and time left while the prompter is running.
    @Published var showPace: Bool {
        didSet { defaults.set(showPace, forKey: Key.showPace.rawValue) }
    }

    /// Portrait: distance from the front camera to the reading line, in centimeters.
    @Published var readingDistanceCm: Double {
        didSet { defaults.set(readingDistanceCm, forKey: Key.readingDistanceCm.rawValue) }
    }

    /// Landscape: preferred width of the text column, in points.
    @Published var landscapeColumnWidth: Double {
        didSet { defaults.set(landscapeColumnWidth, forKey: Key.landscapeColumnWidth.rawValue) }
    }

    /// Camera mode, portrait: width of the text area as a percentage of the screen width.
    @Published var portraitWidthPercent: Double {
        didSet { defaults.set(portraitWidthPercent, forKey: Key.portraitWidthPercent.rawValue) }
    }

    /// Camera mode, portrait: height of the text area in lines.
    @Published var portraitLines: Double {
        didSet { defaults.set(portraitLines, forKey: Key.portraitLines.rawValue) }
    }

    /// Camera mode, landscape: height of the text area in lines.
    @Published var landscapeLines: Double {
        didSet { defaults.set(landscapeLines, forKey: Key.landscapeLines.rawValue) }
    }

    /// Camera mode: where the user put the preview and the text, per orientation. Nil is the automatic layout.
    @Published var arrangementPortrait: Arrangement? {
        didSet { store(arrangementPortrait, key: .arrangementPortrait) }
    }

    @Published var arrangementLandscape: Arrangement? {
        didSet { store(arrangementLandscape, key: .arrangementLandscape) }
    }

    @Published var cameraSide: CameraSide {
        didSet { defaults.set(cameraSide.rawValue, forKey: Key.cameraSide.rawValue) }
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

    /// Drives the DualSense light bar to show tracking and scroll state.
    @Published var gamepadLight: Bool {
        didSet { defaults.set(gamepadLight, forKey: Key.gamepadLight.rawValue) }
    }

    private func store(_ arrangement: Arrangement?, key: Key) {
        if let arrangement, let data = try? JSONEncoder().encode(arrangement) {
            defaults.set(data, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    private static func load(_ key: Key) -> Arrangement? {
        UserDefaults.standard.data(forKey: key.rawValue).flatMap { try? JSONDecoder().decode(Arrangement.self, from: $0) }
    }

    private init() {
        activeScriptID = defaults.string(forKey: Key.activeScriptID.rawValue) ?? ""
        fontSize = defaults.object(forKey: Key.fontSize.rawValue) as? Double ?? 34
        autoSpeed = defaults.object(forKey: Key.autoSpeed.rawValue) as? Double ?? 40
        showPace = defaults.object(forKey: Key.showPace.rawValue) as? Bool ?? true
        readingDistanceCm = defaults.object(forKey: Key.readingDistanceCm.rawValue) as? Double ?? 0.5
        landscapeColumnWidth = defaults.object(forKey: Key.landscapeColumnWidth.rawValue) as? Double ?? 480
        portraitWidthPercent = defaults.object(forKey: Key.portraitWidthPercent.rawValue) as? Double ?? 100
        portraitLines = defaults.object(forKey: Key.portraitLines.rawValue) as? Double ?? 3
        landscapeLines = defaults.object(forKey: Key.landscapeLines.rawValue) as? Double ?? 5
        arrangementPortrait = Self.load(.arrangementPortrait)
        arrangementLandscape = Self.load(.arrangementLandscape)
        cameraSide = CameraSide(rawValue: defaults.string(forKey: Key.cameraSide.rawValue) ?? "") ?? .automatic
        stickCurve = StickCurve(rawValue: defaults.string(forKey: Key.stickCurve.rawValue) ?? "") ?? .cubic
        stickMaxSpeed = defaults.object(forKey: Key.stickMaxSpeed.rawValue) as? Double ?? 400
        stickDeadzone = defaults.object(forKey: Key.stickDeadzone.rawValue) as? Double ?? 0.12
        gamepadLight = defaults.object(forKey: Key.gamepadLight.rawValue) as? Bool ?? true
    }
}
