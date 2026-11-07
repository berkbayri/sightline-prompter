import Foundation

/// What the free version of Sightline Prompter includes. Everything else needs Sightline Pro.
public enum FreeTier {
    /// Longest video recording on iPhone, in seconds.
    public static let maxRecordSeconds = 120
    /// Longest voice-following run before it asks for Pro, in seconds.
    public static let maxTrackingSeconds: TimeInterval = 120
    /// Highest recording resolution (height in pixels) and frame rate.
    public static let maxVideoHeight = 1080
    public static let maxFrameRate = 30
    /// Languages (by language code) that voice following works in without Pro.
    public static let languageCodes: Set<String> = ["en", "tr", "es"]

    /// True when voice following in this language (BCP-47, e.g. "tr-TR") is part of the free version.
    public static func allowsLanguage(_ id: String) -> Bool {
        let code = id.prefix(while: { $0 != "-" && $0 != "_" }).lowercased()
        return languageCodes.contains(code)
    }
}
