import AppKit
import SwiftUI

@MainActor
final class LibraryWindowController {
    private let store: LibraryStore
    private let onActivate: (Script) -> Void
    private var window: NSWindow?

    init(store: LibraryStore, onActivate: @escaping (Script) -> Void) {
        self.store = store
        self.onActivate = onActivate
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sightline Prompter"
        window.minSize = NSSize(width: 760, height: 480)
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LibraryView(store: store, onActivate: onActivate))
        window.center()
        _ = window.setFrameAutosaveName("SightlineLibraryWindow")
        return window
    }
}
