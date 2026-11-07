#if DEBUG
import SightlineCore
import SwiftUI
import UIKit

/// Debug builds only: lets the simulator show the screens used for App Store screenshots, where there is
/// no camera. Launch with `-ScreenshotScene picker|recording|settings|paywall|camera` and, for the
/// recording scene, `-ScreenshotBackdrop /path/to/image.png` (shown instead of the live preview).
enum ScreenshotMode {
    static var scene: String? { UserDefaults.standard.string(forKey: "ScreenshotScene") }
    static var isActive: Bool { scene != nil }

    static var backdrop: UIImage? {
        guard let path = UserDefaults.standard.string(forKey: "ScreenshotBackdrop") else { return nil }
        return UIImage(contentsOfFile: path)
    }

    static let scripts: [(title: String, text: String)] = [
        ("Product launch video", """
        Hi, I'm Berk, and today I want to show you something I have been building for a long time.

        Most videos fall apart in the first ten seconds, because we look away from the camera to read. This fixes that. The words sit right under the lens, and they move at the speed of your voice.

        Let me show you how it works in under a minute.
        """),
        ("YouTube intro", "Welcome back to the channel. In this video, we are going to cover three things you can do today to look more confident on camera."),
        ("Conference keynote", "Good morning, everyone. Thank you for being here. Over the next twenty minutes I want to share what we learned."),
        ("Türkçe Örnek Metin", "Merhaba, ben Berk. Bugün size teleprompter ile kamera karşısında nasıl daha rahat konuşabileceğinizi anlatacağım."),
        ("Welcome", "Welcome to Sightline Prompter."),
    ]
}
#endif
