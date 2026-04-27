import UIKit

/// Main entry point for the TesterBuddy iOS SDK.
///
/// Minimum setup (call once at app launch):
/// ```swift
/// TesterBuddy.configure(apiKey: "your_web_api_key")
/// ```
///
/// For web app URL-based auto-identification, forward incoming URLs:
/// ```swift
/// .onOpenURL { url in TesterBuddy.handleURL(url) }
/// ```
public final class TesterBuddy {

    // MARK: - Public API

    /// Configure and start the SDK. Call this in `application(_:didFinishLaunchingWithOptions:)` or `App.init()`.
    ///
    /// **Automatic tester identification for TestFlight apps:**
    /// When a tester taps "Start Testing" in the TesterBuddy app, a one-time token is placed in
    /// the clipboard. On first launch of the developer's app, this SDK reads the token and exchanges
    /// it with the TesterBuddy backend to identify the tester — no manual setup required.
    /// The system will briefly show "App pasted from TesterBuddy" — this is expected behaviour
    /// in a beta testing context.
    public static func configure(apiKey: String, userId: Int? = nil) {
        shared.apiKey = apiKey
        if let userId {
            shared.userId = userId
            UserDefaults.standard.set(userId, forKey: "TBTesterId")
        } else if let saved = UserDefaults.standard.value(forKey: "TBTesterId") as? Int {
            // Reuse previously identified tester — no network call needed
            shared.userId = saved
        } else {
            // First launch: try to identify via clipboard token left by TesterBuddy app
            Task { await shared.detectTesterFromClipboard() }
        }
        shared.setup()
    }

    /// Forward URL opens to auto-identify testers for web apps.
    /// TesterBuddy appends `?tb_tester_id=` to the test URL when opening it.
    /// Call from `.onOpenURL { url in TesterBuddy.handleURL(url) }` or `application(_:open:options:)`.
    /// - Returns: `true` if the URL contained a TesterBuddy tester ID and was handled.
    @discardableResult
    public static func handleURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idStr = components.queryItems?.first(where: { $0.name == "tb_tester_id" })?.value,
              let userId = Int(idStr) else { return false }
        shared.userId = userId
        UserDefaults.standard.set(userId, forKey: "TBTesterId")
        return true
    }

    /// Manually identify the current tester. Pass `nil` on logout.
    public static func setUserId(_ userId: Int?) {
        shared.userId = userId
        if let userId {
            UserDefaults.standard.set(userId, forKey: "TBTesterId")
        } else {
            UserDefaults.standard.removeObject(forKey: "TBTesterId")
        }
    }

    /// Set the current screen name — included in all subsequent events.
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

    // MARK: - Tester auto-identification

    /// Reads a TesterBuddy one-time token from clipboard (placed there by the TesterBuddy app
    /// before opening TestFlight) and exchanges it for the tester's ID via the backend.
    /// The token is in the format "tb:{UUID}" and is cleared from clipboard after reading.
    private func detectTesterFromClipboard() async {
        let prefix = "tb:"
        guard let clip = UIPasteboard.general.string,
              clip.hasPrefix(prefix) else { return }

        let token = String(clip.dropFirst(prefix.count))

        // Clear clipboard immediately — token is single-use
        await MainActor.run { UIPasteboard.general.string = "" }

        guard !token.isEmpty,
              let url = URL(string: "https://testerbuddy.app/api/sdk/tester-tokens/\(token)") else { return }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-tb-key")
        request.timeoutInterval = 5

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let testerId = json["testerId"] as? Int else { return }

        userId = testerId
        UserDefaults.standard.set(testerId, forKey: "TBTesterId")
    }
}
