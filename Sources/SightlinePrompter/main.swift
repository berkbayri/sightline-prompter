import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    // Regular policy: Dock icon and normal activation, so clicking the panel focuses the app.
    app.setActivationPolicy(.regular)
    // Local strong reference is kept alive by app.run() below.
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
