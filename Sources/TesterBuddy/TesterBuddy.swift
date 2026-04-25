import UIKit

/// Main entry point for the TesterBuddy iOS SDK.
///
/// Minimum setup (call once at app launch):
/// ```swift
/// TesterBuddy.configure(apiKey: "your_web_api_key")
/// ```
///
/// For URL scheme-based auto-identification (web apps), forward incoming URLs:
/// ```swift
/// .onOpenURL { url in TesterBuddy.handleURL(url) }
/// ```
public final class TesterBuddy {

    // MARK: - Public API

    /// Configure and start the SDK. Call this in `application(_:didFinishLaunchingWithOptions:)` or `App.init()`.
    /// Automatically identifies enrolled TesterBuddy testers by matching the device against
    /// an active testing session registered by the TesterBuddy app — no extra setup required.
    public static func configure(apiKey: String, userId: Int? = nil) {
        shared.apiKey = apiKey
        if let userId {
            shared.userId = userId
        } else if let saved = UserDefaults.standard.value(forKey: "TBTesterId") as? Int {
            shared.userId = saved
        } else {
            Task { await shared.detectTesterFromBackend() }
        }
        shared.setup()
    }

    /// Forward URL opens to let the SDK auto-identify testers who open the app via TesterBuddy deep link (web apps).
    /// Call this from your SwiftUI `.onOpenURL` modifier or `application(_:open:options:)`.
    /// - Returns: `true` if the URL was a TesterBuddy link and was handled.
    @discardableResult
    public static func handleURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              let idStr = items.first(where: { $0.name == "tb_tester_id" })?.value,
              let userId = Int(idStr) else { return false }
        shared.userId = userId
        UserDefaults.standard.set(userId, forKey: "TBTesterId")
        return true
    }

    /// Identify the current tester manually. Pass `nil` on logout.
    public static func setUserId(_ userId: Int?) {
        shared.userId = userId
        if let userId {
            UserDefaults.standard.set(userId, forKey: "TBTesterId")
        } else {
            UserDefaults.standard.removeObject(forKey: "TBTesterId")
        }
    }

    /// Set the current screen name included in all subsequent events.
    public static func setScreen(_ name: String) {
        shared.currentScreen = name
    }

    /// Manually log a custom event.
    public static func log(message: String, metadata: [String: String]? = nil) {
        let event = shared.eventSender.makeEvent(
            type: .custom,
            message: message,
            screenName: shared.currentScreen,
            metadata: metadata,
            testerId: shared.userId
        )
        shared.flush([event])
    }

    /// Manually log a network error.
    public static func logNetworkError(url: String, statusCode: Int? = nil, message: String? = nil) {
        var meta: [String: String] = ["url": url]
        if let code = statusCode { meta["statusCode"] = String(code) }
        let event = shared.eventSender.makeEvent(
            type: .networkError,
            message: message ?? "Network error: \(url)",
            screenName: shared.currentScreen,
            metadata: meta,
            testerId: shared.userId
        )
        shared.flush([event])
    }

    // MARK: - Internal

    static let shared = TesterBuddy()

    var apiKey: String = ""
    var userId: Int?
    var currentScreen: String?
    let eventSender = EventSender()

    private init() {}

    private func setup() {
        CrashReporter.install()
        ShakeDetector.install()
    }

    func flush(_ events: [TBEvent]) {
        guard !apiKey.isEmpty else { return }
        eventSender.send(events: events, apiKey: apiKey)
    }

    // Asks TesterBuddy backend if there's an active testing session for this device.
    // TesterBuddy app creates the session (POST /api/sdk/active-session) when the tester
    // taps "Start Testing". The hint is device model + OS version — same value on both apps.
    private func detectTesterFromBackend() async {
        guard !apiKey.isEmpty,
              let url = URL(string: "https://testerbuddy.app/api/sdk/active-session?hint=\(deviceHint())") else { return }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-tb-key")
        request.timeoutInterval = 5

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let testerId = json["testerId"] as? Int else { return }

        userId = testerId
        UserDefaults.standard.set(testerId, forKey: "TBTesterId")
    }

    private func deviceHint() -> String {
        let raw = UIDevice.current.model + "|" + UIDevice.current.systemVersion
        return Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
