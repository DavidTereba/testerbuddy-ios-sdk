import UIKit

/// Main entry point for the TesterBuddy iOS SDK.
///
/// Minimum setup (call once at app launch):
/// ```swift
/// TesterBuddy.configure(apiKey: "your_web_api_key")
/// ```
public final class TesterBuddy {

    // MARK: - Public API

    /// Configure and start the SDK. Call once in `App.init()` or
    /// `application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// - Parameters:
    ///   - apiKey: Your app's SDK key from the TesterBuddy dashboard.
    ///   - userId: Optional — manually identify the tester. If omitted the SDK
    ///     attempts auto-identification via a one-time clipboard token.
    ///   - enableANRDetection: Report ANR (main thread blocked ≥ 5 s). Default `true`.
    ///   - enableNetworkMonitoring: Intercept failed URLSession requests and report
    ///     them as `network_error` events. Default `false` (opt-in).
    ///   - enableSessionTracking: Send session start/end events. Default `true`.
    ///   - enableAnnouncements: Poll for developer announcements and show banners.
    ///     Default `true`.
    ///   - debugLogging: Print diagnostic messages to the console via `os_log`.
    ///     Default `false`. Disable before shipping to the App Store.
    public static func configure(
        apiKey: String,
        userId: Int? = nil,
        enableANRDetection: Bool = true,
        enableNetworkMonitoring: Bool = false,
        enableSessionTracking: Bool = true,
        enableAnnouncements: Bool = true,
        debugLogging: Bool = false
    ) {
        TBLogger.isEnabled = debugLogging

        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            TBLogger.warn("configure() called with an empty apiKey — all events will be dropped.")
            return
        }

        shared.apiKey = apiKey
        TBLogger.debug("SDK configured. apiKey prefix: \(String(apiKey.prefix(6)))…")

        if let userId {
            shared.userId = userId
            UserDefaults.standard.set(userId, forKey: "TBTesterId")
            TBLogger.debug("Tester identified manually: \(userId)")
        } else if let saved = UserDefaults.standard.value(forKey: "TBTesterId") as? Int {
            shared.userId = saved
            TBLogger.debug("Tester restored from storage: \(saved)")
        } else {
            Task { await shared.detectTesterFromClipboard() }
        }

        shared.setup(
            anr: enableANRDetection,
            network: enableNetworkMonitoring,
            sessions: enableSessionTracking,
            announcements: enableAnnouncements
        )
    }

    /// Forward URL opens for web-app tester auto-identification.
    /// TesterBuddy appends `?tb_tester_id=` to the test URL when opening it.
    /// Call from `.onOpenURL { url in TesterBuddy.handleURL(url) }`.
    /// - Returns: `true` if the URL contained a TesterBuddy tester ID.
    @discardableResult
    public static func handleURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idStr = components.queryItems?.first(where: { $0.name == "tb_tester_id" })?.value,
              let userId = Int(idStr) else { return false }
        shared.userId = userId
        UserDefaults.standard.set(userId, forKey: "TBTesterId")
        TBLogger.debug("Tester identified via URL: \(userId)")
        return true
    }

    /// Manually identify the current tester. Pass `nil` on logout.
    public static func setUserId(_ userId: Int?) {
        shared.userId = userId
        if let userId {
            UserDefaults.standard.set(userId, forKey: "TBTesterId")
            TBLogger.debug("Tester set: \(userId)")
        } else {
            UserDefaults.standard.removeObject(forKey: "TBTesterId")
            TBLogger.debug("Tester cleared")
        }
    }

    /// Set the current screen name — included in all subsequent events.
    public static func setScreen(_ name: String) {
        shared.currentScreen = name
        TBLogger.debug("Screen: \(name)")
    }

    /// Log a custom event.
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

    /// Manually log a network error (e.g. when network monitoring is disabled).
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

    // Thread-safe mutable state — read/written from main thread, ANR watchdog,
    // URLSession callbacks, and crash handlers; protect with a lock.
    private let _lock = NSLock()
    private var _apiKey: String = ""
    private var _userId: Int?
    private var _currentScreen: String?

    var apiKey: String {
        get { _lock.lock(); defer { _lock.unlock() }; return _apiKey }
        set { _lock.lock(); defer { _lock.unlock() }; _apiKey = newValue }
    }
    var userId: Int? {
        get { _lock.lock(); defer { _lock.unlock() }; return _userId }
        set { _lock.lock(); defer { _lock.unlock() }; _userId = newValue }
    }
    var currentScreen: String? {
        get { _lock.lock(); defer { _lock.unlock() }; return _currentScreen }
        set { _lock.lock(); defer { _lock.unlock() }; _currentScreen = newValue }
    }

    let eventSender = EventSender()

    private var sessionTracker: SessionTracker?
    private var anrDetector: ANRDetector?
    private var announcementManager: AnnouncementManager?

    private init() {}

    private func setup(anr: Bool, network: Bool, sessions: Bool, announcements: Bool) {
        CrashReporter.install()
        ShakeDetector.install()

        if anr {
            anrDetector = ANRDetector()
            anrDetector?.start()
            TBLogger.debug("ANR detection started")
        }

        if network {
            TBNetworkProtocol.enable()
            TBLogger.debug("Network monitoring enabled")
        }

        if sessions {
            sessionTracker = SessionTracker()
            sessionTracker?.start()
            TBLogger.debug("Session tracking started")
        }

        if announcements {
            announcementManager = AnnouncementManager()
            announcementManager?.start(apiKey: apiKey)
            TBLogger.debug("Announcement polling started")
        }
    }

    func flush(_ events: [TBEvent], completion: ((Bool) -> Void)? = nil) {
        guard !apiKey.isEmpty else {
            TBLogger.warn("flush called but apiKey is empty — \(events.count) event(s) dropped")
            completion?(false)
            return
        }
        TBLogger.debug("Flushing \(events.count) event(s)")
        eventSender.send(events: events, apiKey: apiKey, completion: completion)
    }

    // MARK: - Tester auto-identification via clipboard

    /// Clipboard is accessed at most `maxClipboardAttempts` times across the
    /// app's lifetime. This prevents repeated "App pasted from TesterBuddy"
    /// banners for regular App Store users who never enrolled as testers.
    private static let clipboardAttemptKey = "TBClipboardAttempts"
    private static let maxClipboardAttempts = 5

    private func detectTesterFromClipboard() async {
        let attempts = UserDefaults.standard.integer(forKey: Self.clipboardAttemptKey)
        guard attempts < Self.maxClipboardAttempts else { return }
        UserDefaults.standard.set(attempts + 1, forKey: Self.clipboardAttemptKey)

        let prefix = "tb:"
        guard let clip = UIPasteboard.general.string, clip.hasPrefix(prefix) else { return }
        let token = String(clip.dropFirst(prefix.count))

        // Clear clipboard immediately — token is single-use
        await MainActor.run { UIPasteboard.general.string = "" }

        guard !token.isEmpty,
              let url = URL(string: "https://testerbuddy.app/api/sdk/tester-tokens/\(token)")
        else { return }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-tb-key")
        request.timeoutInterval = 5

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let testerId = json["testerId"] as? Int
        else {
            TBLogger.debug("Clipboard token resolution failed")
            return
        }

        userId = testerId
        UserDefaults.standard.set(testerId, forKey: "TBTesterId")
        // Saturate attempt counter — successful identification, no more clipboard reads needed
        UserDefaults.standard.set(Self.maxClipboardAttempts, forKey: Self.clipboardAttemptKey)
        TBLogger.debug("Tester identified via clipboard: \(testerId)")
    }
}
