import AppKit
import SwiftUI

extension NSColor {
    /// The iPhone app's accent (`Color.sightline`) for AppKit views.
    static let sightline = NSColor(Color.sightline)
}

extension NSWindow {
    /// Same look as the iPhone app: always dark, so the yellow accent reads the same in every window.
    func applySightlineStyle() {
        appearance = NSAppearance(named: .darkAqua)
    }
}
