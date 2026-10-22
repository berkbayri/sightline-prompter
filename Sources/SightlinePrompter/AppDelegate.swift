import AppKit
import Aligner
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ControllerInputDelegate {
    private let prompter = PrompterView(settings: Settings.shared)
    private let tracker = SpeechTracker(script: Settings.shared.script, language: Settings.shared.scriptLanguage)
    private let controller = ControllerInput()
    private let light = GamepadLight()
    private let library = LibraryStore()
    private var pace = PaceMeter()
    private var totalWords = 0
    private var lastStatusWasError = false

    private var panel: NotchPanel!
    private var statusItem: NSStatusItem!
    private var trackingMenuItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var libraryWindow: LibraryWindowController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NotchPanel(prompter: prompter)
        panel.onAction = { [weak self] action in self?.handle(action) }
        panel.orderFrontRegardless()

        libraryWindow = LibraryWindowController(store: library) { [weak self] script in
            self?.activate(script)
        }

        setupStatusItem()
        observeSettings()
        loadActiveScript()
        refreshTotalWords()

        // Manual scrolling moves the reading position; speech tracking continues from there.
        prompter.onManualScrollEnded = { [weak self] index in
            self?.tracker.reset(to: index)
        }
        tracker.onCursorChange = { [prompter] index in
            prompter.setCursor(wordIndex: index)
        }
        tracker.visibleWords = { [prompter] in
            prompter.visibleWordRange()
        }
        tracker.onStatus = { [weak self] text in
            guard let self else { return }
            self.statusItem.button?.toolTip = text
            self.lastStatusWasError = !(text == "Listening…" || text == "Stopped" || text.hasPrefix("On-device"))
            self.panel.setStatus(text)
            self.refreshControls()
        }

        controller.delegate = self
        controller.start()
        startPaceSampling()
        refreshControls()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon brings the prompter back if it was hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.orderFrontRegardless()
        return true
    }

    // MARK: - Library and settings

    private func loadActiveScript() {
        if library.scripts.isEmpty, !Settings.shared.script.isEmpty {
            let script = library.create(
                title: "My script",
                language: ScriptLanguage.named(Settings.shared.scriptLanguage),
                text: Settings.shared.script
            )
            activate(script)
            return
        }
        let savedID = UUID(uuidString: Settings.shared.activeScriptID)
        if let script = library.scripts.first(where: { $0.id == savedID }) ?? library.scripts.first {
            activate(script)
        }
    }

    /// Loads a library script into the prompter and tracker.
    private func activate(_ script: Script) {
        Settings.shared.activeScriptID = script.id.uuidString
        Settings.shared.scriptLanguage = script.languageID
        Settings.shared.script = script.text
    }

    private func updateActiveScript(text: String? = nil, languageID: String? = nil) {
        guard let id = UUID(uuidString: Settings.shared.activeScriptID) else { return }
        library.update(id, text: text, languageID: languageID)
    }

    private func observeSettings() {
        Settings.shared.$script
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                self.tracker.setScript(text)
                self.updateActiveScript(text: text)
                self.refreshTotalWords()
            }
            .store(in: &cancellables)

        Settings.shared.$scriptLanguage
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] identifier in
                guard let self else { return }
                let language = ScriptLanguage.named(identifier)
                self.prompter.setLanguage(language)
                self.tracker.setLanguage(language.id)
                self.updateActiveScript(languageID: language.id)
                self.refreshTotalWords()
            }
            .store(in: &cancellables)

        // Edits made in the Library window flow back into the active prompter text.
        library.$scripts
            .receive(on: RunLoop.main)
            .sink { [weak self] scripts in
                guard let self,
                      let id = UUID(uuidString: Settings.shared.activeScriptID),
                      let active = scripts.first(where: { $0.id == id }) else { return }
                if active.text != Settings.shared.script {
                    Settings.shared.script = active.text
                }
                if active.languageID != Settings.shared.scriptLanguage {
                    Settings.shared.scriptLanguage = active.languageID
                }
            }
            .store(in: &cancellables)

        Settings.shared.$showPace
            .dropFirst()
            .sink { [weak self] _ in self?.refreshControls() }
            .store(in: &cancellables)

        Settings.shared.$gamepadLight
            .dropFirst()
            .sink { [weak self] _ in self?.refreshControls() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .openLibrary)
            .sink { [weak self] _ in self?.libraryWindow.show() }
            .store(in: &cancellables)
    }

    private func refreshTotalWords() {
        let language = ScriptLanguage.named(Settings.shared.scriptLanguage)
        totalWords = ScriptTokenizer.tokenize(Settings.shared.script, language: language).count
    }

    // MARK: - Pace

    private func startPaceSampling() {
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.samplePace() }
            .store(in: &cancellables)
    }

    private func samplePace() {
        let running = prompter.isPlaying || tracker.isRunning
        guard running, Settings.shared.showPace, totalWords > 0 else {
            if !running { pace.reset() }
            panel.setPace(nil)
            return
        }

        let index = prompter.currentWordIndex
        pace.record(units: index, time: ProcessInfo.processInfo.systemUptime)

        let language = ScriptLanguage.named(Settings.shared.scriptLanguage)
        var parts: [String] = []
        if language.spaced, let rate = pace.unitsPerMinute() {
            parts.append("\(Int(rate.rounded())) wpm")
        }
        if let seconds = pace.remainingSeconds(remainingUnits: totalWords - index) {
            parts.append("\(Self.clock(seconds)) left")
        }
        panel.setPace(parts.isEmpty ? nil : parts.joined(separator: " · "))
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Sightline Prompter")
            image?.isTemplate = true
            button.image = image
            if image == nil {
                button.title = "SP"
            }
            button.toolTip = "Sightline Prompter"
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("Show / Hide", #selector(toggleVisibility)))
        menu.addItem(menuItem("Library…", #selector(openLibrary), key: "l"))
        menu.addItem(menuItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(menuItem("Play / Pause", #selector(togglePlay)))
        menu.addItem(menuItem("Restart", #selector(restart)))

        let tracking = menuItem("Speech Tracking On / Off", #selector(toggleTracking))
        trackingMenuItem = tracking
        menu.addItem(tracking)

        menu.addItem(.separator())
        menu.addItem(menuItem("Quit", #selector(quit), key: "q"))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions (shared by menu, control bar and controller)

    private func handle(_ action: PanelAction) {
        switch action {
        case .playPause: togglePlay()
        case .restart: restart()
        case .slower: adjustSpeed(-1)
        case .faster: adjustSpeed(1)
        case .toggleTracking: toggleTracking()
        case .settings: openSettings()
        case .hide: panel.togglePanel()
        }
    }

    @objc private func toggleVisibility() {
        panel.togglePanel()
    }

    @objc private func togglePlay() {
        prompter.togglePlay()
        refreshControls()
    }

    @objc private func restart() {
        prompter.restart()
        tracker.reset(to: 0)
        refreshControls()
    }

    private func adjustSpeed(_ direction: Int) {
        prompter.adjustSpeed(by: CGFloat(direction) * 10)
    }

    @objc private func toggleTracking() {
        if tracker.isRunning {
            tracker.stop()
        } else {
            tracker.start()
        }
        refreshControls()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openLibrary() {
        libraryWindow.show()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Sightline Prompter Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            // Above the teleprompter panel (mainMenu + 1), so it can never end up behind it.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
            window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
            window.setContentSize(NSSize(width: 540, height: 640))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func refreshControls() {
        panel.setControlState(playing: prompter.isPlaying, tracking: tracker.isRunning)
        trackingMenuItem?.state = tracker.isRunning ? .on : .off
        light.set(lightState)
    }

    private var lightState: GamepadLight.State {
        guard Settings.shared.gamepadLight else { return .off }
        if tracker.isRunning { return .listening }
        if lastStatusWasError { return .error }
        if prompter.isPlaying { return .scrolling }
        return .idle
    }

    // MARK: - ControllerInputDelegate

    func controllerStick(_ value: Float) {
        prompter.setStick(CGFloat(value))
    }

    func controllerAdjustSpeed(_ direction: Int) {
        adjustSpeed(direction)
    }

    func controllerTogglePlay() {
        togglePlay()
    }

    func controllerRestart() {
        restart()
    }

    func controllerJumpParagraph(forward: Bool) {
        prompter.jumpParagraph(forward: forward)
        tracker.reset(to: prompter.currentWordIndex)
    }

    func controllerToggleTracking() {
        toggleTracking()
    }

    func controllerToggleVisibility() {
        panel.togglePanel()
    }
}
