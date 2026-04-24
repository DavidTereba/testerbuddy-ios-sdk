import UIKit

/// Main entry point for the TesterBuddy iOS SDK.
///
/// Minimum setup (call once at app launch):
/// ```swift
/// TesterBuddy.configure(apiKey: "your_web_api_key")
/// ```
///
/// For URL scheme-based auto-identification, forward incoming URLs:
/// ```swift
/// .onOpenURL { url in TesterBuddy.handleURL(url) }
/// ```
public final class TesterBuddy {

    // MARK: - Public API

    /// Configure and start the SDK. Call this in `application(_:didFinishLaunchingWithOptions:)` or `App.init()`.
    /// Automatically detects a TesterBuddy tester ID from the clipboard (placed there by the TesterBuddy app
    /// before opening TestFlight), so testers are identified without any extra steps.
    public static func configure(apiKey: String, userId: Int? = nil) {
        shared.apiKey = apiKey
        if let userId {
            shared.userId = userId
        } else {
            shared.detectTesterFromClipboard()
        }
        shared.setup()
    }

    /// Forward URL opens to let the SDK auto-identify testers who open the app via TesterBuddy deep link.
    /// Call this from your SwiftUI `.onOpenURL` modifier or `application(_:open:options:)`.
    /// - Returns: `true` if the URL was a TesterBuddy link and was handled.
    @discardableResult
    public static func handleURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              let idStr = items.first(where: { $0.name == "tb_tester_id" })?.value,
              let userId = Int(idStr) else { return false }
        shared.userId = userId
        return true
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

    // Reads the TesterBuddy tester token from clipboard (placed there by the TesterBuddy app before
    // opening TestFlight). Clears the token after reading so it doesn't persist across sessions.
    private func detectTesterFromClipboard() {
        let prefix = "tb:uid:"
        guard let clip = UIPasteboard.general.string,
              clip.hasPrefix(prefix),
              let uid = Int(clip.dropFirst(prefix.count)) else { return }
        userId = uid
        UIPasteboard.general.string = ""
    }
}
