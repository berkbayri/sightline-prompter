import GameController

/// Drives the light bar of every connected controller. `GCDeviceLight.color` is
/// writable on macOS 11+; controllers without a light return nil and are skipped.
@MainActor
final class GamepadLight {
    enum State {
        case off, idle, listening, scrolling, error
    }

    private(set) var state: State = .off
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }
    }

    func set(_ state: State) {
        self.state = state
        apply()
    }

    private func apply() {
        let color = Self.color(for: state)
        for controller in GCController.controllers() {
            controller.light?.color = color
        }
    }

    private static func color(for state: State) -> GCColor {
        switch state {
        case .off: GCColor(red: 0, green: 0, blue: 0)
        case .idle: GCColor(red: 0.25, green: 0.25, blue: 0.25)
        case .listening: GCColor(red: 0, green: 0.8, blue: 0.3)
        case .scrolling: GCColor(red: 0.1, green: 0.4, blue: 1)
        case .error: GCColor(red: 1, green: 0.15, blue: 0.1)
        }
    }
}
