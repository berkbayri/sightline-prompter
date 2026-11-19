import Foundation

/// Anonymous product analytics: which screens and limits people reach, never scripts, audio, video or identity.
/// Events go to PostHog and Google Analytics 4 over their HTTP APIs, so no tracking SDK ships in the app.
/// Both stay silent until their keys below are filled in, and debug builds never send anything.
public enum Analytics {
    /// PostHog project API key (public by design) and the host of the project's region.
    static let posthogKey = "phc_tL9Nc8zhomH3HKMLzD3w4sUVdaf2Rng5oqB6JE4Yfy7J"
    static let posthogHost = "https://eu.i.posthog.com"
    /// Google Analytics 4 data stream: measurement ID ("G-…") and its Measurement Protocol API secret (kept out of git,
    /// see AnalyticsSecrets.swift).
    static let gaMeasurementID = "G-7774H65GDJ"
    static let gaAPISecret = AnalyticsSecrets.gaAPISecret

    public static let enabledKey = "analyticsEnabled"

    /// Settings switch, on by default; the privacy policy describes exactly what is sent.
    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Random per install, never linked to an Apple Account, device ID or advertising ID.
    private static var installID: String {
        let key = "analyticsInstallID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    public static func track(_ name: String, _ properties: [String: String] = [:]) {
        #if DEBUG
        return
        #else
        guard isEnabled else { return }
        var props = properties
        props["app_version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        #if os(macOS)
        props["platform"] = "mac"
        #else
        props["platform"] = "iphone"
        #endif
        let id = installID
        if !posthogKey.isEmpty { send(posthog: name, props, id) }
        if !gaMeasurementID.isEmpty, !gaAPISecret.isEmpty { send(ga: name, props, id) }
        #endif
    }

    private static func send(posthog name: String, _ props: [String: String], _ id: String) {
        var properties: [String: Any] = props
        properties["$process_person_profile"] = false
        post("\(posthogHost)/capture/", ["api_key": posthogKey, "event": name, "distinct_id": id, "properties": properties])
    }

    private static func send(ga name: String, _ props: [String: String], _ id: String) {
        let url = "https://www.google-analytics.com/mp/collect?measurement_id=\(gaMeasurementID)&api_secret=\(gaAPISecret)"
        post(url, ["client_id": id, "events": [["name": name, "params": props]]])
    }

    private static func post(_ url: String, _ body: [String: Any]) {
        guard let url = URL(string: url), let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 10
        // Fire and forget: analytics must never slow or break the app.
        URLSession.shared.dataTask(with: request).resume()
    }
}
