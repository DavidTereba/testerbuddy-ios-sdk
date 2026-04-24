import UIKit

/// Main entry point for the TesterBuddy iOS SDK.
///
/// Minimum setup (call once at app launch):
/// ```swift
/// TesterBuddy.configure(apiKey: "your_web_api_key")
/// ```
///
/// After login, identify the tester:
/// ```swift
/// TesterBuddy.setUserId(123)
/// ```
///
/// Track screens so events include context:
/// ```swift
/// TesterBuddy.setScreen("HomeView")
/// ```
public final class TesterBuddy {

    // MARK: - Public API

    /// Configure and start the SDK. Call this in `application(_:didFinishLaunchingWithOptions:)` or `App.init()`.
    public static func configure(apiKey: String, userId: Int? = nil) {
        shared.apiKey = apiKey
        if let userId { shared.userId = userId }
        shared.setup()
    }

    /// Identify the current tester after login. Pass `nil` on logout.
    public static func setUserId(_ userId: Int?) {
        shared.userId = userId
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
}
