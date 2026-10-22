import AppKit
import GameController

@MainActor
protocol ControllerInputDelegate: AnyObject {
    /// Positive = reader moves forward (stick pushed down, text scrolls up); -1...1.
    func controllerStick(_ value: Float)
    func controllerAdjustSpeed(_ direction: Int)
    func controllerTogglePlay()
    func controllerRestart()
    func controllerJumpParagraph(forward: Bool)
    func controllerToggleTracking()
    func controllerToggleVisibility()
}

@MainActor
final class ControllerInput {
    weak var delegate: ControllerInputDelegate?

    private var observers: [NSObjectProtocol] = []
    private var attached: [ObjectIdentifier: GCController] = [:]
    private var lastStick: Float = 0
    private var repeatTask: Task<Void, Never>?

    func start() {
        GCController.shouldMonitorBackgroundEvents = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.attach(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.detach(controller) }
        })
        for controller in GCController.controllers() {
            attach(controller)
        }
    }

    private func attach(_ controller: GCController) {
        // microGamepad (Siri Remote) intentionally ignored.
        guard let pad = controller.extendedGamepad,
              attached[ObjectIdentifier(controller)] == nil else { return }
        attached[ObjectIdentifier(controller)] = controller

        // GCController yAxis is +1 at top; invert so stick down = positive (forward).
        pad.leftThumbstick.yAxis.valueChangedHandler = { [weak self] _, value in
            Task { @MainActor in self?.handleStick(-value) }
        }
        pad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleSpeed(+1, pressed: pressed) }
        }
        pad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleSpeed(-1, pressed: pressed) }
        }
        bind(pad.buttonA) { $0.delegate?.controllerTogglePlay() }
        bind(pad.buttonX) { $0.delegate?.controllerRestart() }
        bind(pad.buttonY) { $0.delegate?.controllerToggleTracking() }
        bind(pad.buttonB) { $0.delegate?.controllerToggleVisibility() }
        bind(pad.buttonMenu) { $0.delegate?.controllerToggleVisibility() }
        bind(pad.leftShoulder) { $0.delegate?.controllerJumpParagraph(forward: false) }
        bind(pad.rightShoulder) { $0.delegate?.controllerJumpParagraph(forward: true) }
    }

    private func detach(_ controller: GCController) {
        guard attached.removeValue(forKey: ObjectIdentifier(controller)) != nil else { return }
        stopSpeedRepeat()
        if let pad = controller.extendedGamepad {
            pad.leftThumbstick.yAxis.valueChangedHandler = nil
            let buttons: [GCControllerButtonInput] = [
                pad.dpad.up, pad.dpad.down, pad.buttonA, pad.buttonB, pad.buttonX,
                pad.buttonY, pad.buttonMenu, pad.leftShoulder, pad.rightShoulder
            ]
            buttons.forEach { $0.pressedChangedHandler = nil }
        }
        if lastStick != 0 {
            lastStick = 0
            delegate?.controllerStick(0)
        }
    }

    /// Fires the action once per press on the main actor.
    private func bind(_ button: GCControllerButtonInput?, _ action: @escaping @MainActor (ControllerInput) -> Void) {
        button?.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                guard let self else { return }
                action(self)
            }
        }
    }

    private func handleStick(_ raw: Float) {
        let settings = Settings.shared
        let dz = Float(settings.stickDeadzone)
        let magnitude = abs(raw)
        var value: Float = 0
        if magnitude > dz {
            let travel = (magnitude - dz) / (1 - dz)
            value = (raw < 0 ? -1 : 1) * settings.stickCurve.apply(travel)
        }
        guard abs(value - lastStick) > 0.001 || (value == 0 && lastStick != 0) else { return }
        lastStick = value
        delegate?.controllerStick(value)
    }

    private func handleSpeed(_ direction: Int, pressed: Bool) {
        stopSpeedRepeat()
        guard pressed else { return }
        delegate?.controllerAdjustSpeed(direction)
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                self.delegate?.controllerAdjustSpeed(direction)
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    private func stopSpeedRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
