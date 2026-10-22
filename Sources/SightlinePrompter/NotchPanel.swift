import AppKit
import Combine

enum PanelAction: Int, CaseIterable {
    case playPause, restart, slower, faster, toggleTracking, settings, hide
}

/// Content view that reports pointer entry and exit, used to show the control bar on hover.
private final class PanelContentView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}

/// Grip that moves the panel horizontally by writing the horizontal offset setting.
private final class MoveGrip: NSView {
    init() {
        super.init(frame: .zero)
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: "Move")?
            .withSymbolConfiguration(configuration) ?? NSImage())
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        toolTip = "Drag to move the window sideways"
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDragged(with event: NSEvent) {
        let settings = Settings.shared
        settings.xOffset = min(max(settings.xOffset + Double(event.deltaX), -600), 600)
    }
}

@MainActor
final class NotchPanel: NSPanel {
    let prompter: PrompterView
    /// Receives control bar button presses.
    var onAction: ((PanelAction) -> Void)?

    private let content = PanelContentView()
    private let controlBar = NSView()
    private let statusDot = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "Speech off")
    private var baseStatus: String? = "Speech off"
    private var paceText: String?
    private let speedLabel = NSTextField(labelWithString: "")
    private var playPauseButton: NSButton?
    private var trackingButton: NSButton?
    private var cancellables = Set<AnyCancellable>()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(prompter: PrompterView) {
        self.prompter = prompter
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        // Joins every Space (including fullscreen apps) and moves with the user's Space swipes.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // Panel sits at the screen top, so the rounded corners are the BOTTOM ones.
        // Unflipped macOS layer coords: minY = bottom.
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.layer?.cornerRadius = 18
        content.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        content.layer?.masksToBounds = true
        contentView = content
        content.addSubview(prompter)

        setupControlBar()
        content.onHoverChange = { [weak self] hovering in
            self?.setControlBarVisible(hovering)
        }

        observeSettings()
    }

    /// Re-applies frame and capture flag from Settings.shared.
    func reposition() {
        let settings = Settings.shared
        apply(
            width: CGFloat(settings.panelWidth),
            height: CGFloat(settings.panelHeight),
            xOffset: CGFloat(settings.xOffset),
            hideFromCapture: settings.hideFromCapture
        )
    }

    func togglePanel() {
        if isVisible {
            orderOut(nil)
        } else {
            orderFrontRegardless()
        }
    }

    /// Keeps the play/pause icon and tracking tint in sync with the real state.
    func setControlState(playing: Bool, tracking: Bool) {
        playPauseButton?.image = symbol(playing ? "pause.fill" : "play.fill", playing ? "Pause" : "Play", size: 16)
        trackingButton?.contentTintColor = tracking ? .systemYellow : .white
        statusDot.contentTintColor = tracking ? .systemGreen : .secondaryLabelColor
    }

    /// Short status line next to the controls, e.g. "Listening" or a permission error.
    func setStatus(_ text: String) {
        baseStatus = text
        refreshStatusLabel()
    }

    /// Pace line such as "148 wpm · 2:14 left"; nil hides it.
    func setPace(_ text: String?) {
        paceText = text
        refreshStatusLabel()
    }

    private func refreshStatusLabel() {
        statusLabel.stringValue = [baseStatus, paceText].compactMap { $0 }.joined(separator: "  ·  ")
    }

    private func apply(width: CGFloat, height: CGFloat, xOffset: CGFloat, hideFromCapture: Bool) {
        guard let screen = targetScreen() else { return }

        let frame = NSRect(
            x: screen.frame.midX + xOffset - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        sharingType = hideFromCapture ? .none : .readOnly
        setFrame(frame, display: true)

        // Content starts below the notch (0 on notch-less screens) plus a small gutter.
        let topInset = screen.safeAreaInsets.top + 8
        prompter.autoresizingMask = [.width, .height]
        prompter.frame = NSRect(x: 0, y: 0, width: width, height: max(0, height - topInset))
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - Control bar

    private func setupControlBar() {
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.alphaValue = 0

        let stack = NSStackView(views: [
            statusStack(),
            divider(),
            makeButton(for: .restart),
            makeButton(for: .playPause),
            makeButton(for: .toggleTracking),
            divider(),
            makeButton(for: .slower),
            speedStack(),
            makeButton(for: .faster),
            divider(),
            MoveGrip(),
            makeButton(for: .settings),
            makeButton(for: .hide),
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 10)

        let glass = makeGlassContainer(around: stack)
        glass.translatesAutoresizingMaskIntoConstraints = false
        controlBar.addSubview(glass)
        content.addSubview(controlBar)

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor),
            glass.topAnchor.constraint(equalTo: controlBar.topAnchor),
            glass.bottomAnchor.constraint(equalTo: controlBar.bottomAnchor),
            controlBar.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            controlBar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            controlBar.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 12),
            controlBar.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
        ])

        Settings.shared.$autoSpeed
            .sink { [weak self] speed in
                self?.speedLabel.stringValue = "\(Int(speed.rounded()))"
            }
            .store(in: &cancellables)
    }

    /// Liquid Glass on macOS 26, a HUD material on earlier systems.
    private func makeGlassContainer(around stack: NSView) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 16
            glass.contentView = stack
            return glass
        }
        #endif
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    private func statusStack() -> NSView {
        statusDot.image = symbol("circle.fill", "Status", size: 8)
        statusDot.contentTintColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.preferredMaxLayoutWidth = 140
        let row = NSStackView(views: [statusDot, statusLabel])
        row.spacing = 6
        return row
    }

    private func speedStack() -> NSView {
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        speedLabel.textColor = .white
        speedLabel.alignment = .center
        speedLabel.toolTip = "Auto-scroll speed (pt/s)"
        speedLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return speedLabel
    }

    private func divider() -> NSView {
        let line = NSBox()
        line.boxType = .custom
        line.borderWidth = 0
        line.fillColor = NSColor(white: 1, alpha: 0.18)
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return line
    }

    private func makeButton(for action: PanelAction) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(controlPressed(_:)))
        button.image = symbolImage(for: action)
        button.tag = action.rawValue
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.toolTip = tooltip(for: action)
        button.setButtonType(.momentaryChange)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true

        switch action {
        case .playPause: playPauseButton = button
        case .toggleTracking: trackingButton = button
        default: break
        }
        return button
    }

    private func symbolImage(for action: PanelAction) -> NSImage? {
        let name: String
        switch action {
        case .playPause: name = "play.fill"
        case .restart: name = "backward.end.fill"
        case .slower: name = "minus"
        case .faster: name = "plus"
        case .toggleTracking: name = "waveform"
        case .settings: name = "gearshape.fill"
        case .hide: name = "eye.slash.fill"
        }
        return symbol(name, tooltip(for: action), size: 14)
    }

    private func symbol(_ name: String, _ description: String, size: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(configuration)
    }

    private func tooltip(for action: PanelAction) -> String {
        switch action {
        case .playPause: "Play / Pause"
        case .restart: "Restart"
        case .slower: "Slower"
        case .faster: "Faster"
        case .toggleTracking: "Speech tracking on / off"
        case .settings: "Settings"
        case .hide: "Hide window"
        }
    }

    @objc private func controlPressed(_ sender: NSButton) {
        guard let action = PanelAction(rawValue: sender.tag) else { return }
        onAction?(action)
    }

    private func setControlBarVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            controlBar.animator().alphaValue = visible ? 1 : 0
        }
    }

    // MARK: - Settings

    private func observeSettings() {
        let settings = Settings.shared

        // @Published emits in willSet, so use the emitted values instead of re-reading Settings.
        Publishers.CombineLatest4(settings.$panelWidth, settings.$panelHeight, settings.$xOffset, settings.$hideFromCapture)
            .sink { [weak self] width, height, xOffset, hide in
                self?.apply(
                    width: CGFloat(width),
                    height: CGFloat(height),
                    xOffset: CGFloat(xOffset),
                    hideFromCapture: hide
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
    }
}
