import UIKit

/// Tracks app sessions: launch count, session duration, crash-free runs.
///
/// Sends a `session` event to TesterBuddy on every launch (start)
/// and when the app goes to background (end). This lets the dashboard
/// show session counts, average duration, and crash-free session rate.
final class SessionTracker {

    private enum Keys {
        static let launchCount    = "TBLaunchCount"
        static let totalTime      = "TBTotalSessionTime"
        static let lastLaunchDate = "TBLastLaunchDate"
        static let didCrashLast   = "TBDidCrashLastSession"
    }

    private var sessionStart: Date?

    func start() {
        sessionStart = Date()

        let count = UserDefaults.standard.integer(forKey: Keys.launchCount) + 1
        UserDefaults.standard.set(count, forKey: Keys.launchCount)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastLaunchDate)

        // If we crashed last session the crash reporter already flushed the event —
        // clear the flag so this counts as a crash-free session unless we crash again.
        let crashedLast = UserDefaults.standard.bool(forKey: Keys.didCrashLast)
        UserDefaults.standard.set(false, forKey: Keys.didCrashLast)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        sendSessionEvent(subtype: "start", launchCount: count, crashedLastSession: crashedLast)
    }

    /// Called by CrashReporter before saving a crash — marks next session as post-crash.
    static func markCrash() {
        UserDefaults.standard.set(true, forKey: Keys.didCrashLast)
    }

    @objc private func appDidBackground() {
        guard let start = sessionStart else { return }
        let duration = Int(Date().timeIntervalSince(start))
        let total = UserDefaults.standard.integer(forKey: Keys.totalTime) + duration
        UserDefaults.standard.set(total, forKey: Keys.totalTime)
        sendSessionEvent(subtype: "end", duration: duration)
    }

    // MARK: - Private

    private func sendSessionEvent(subtype: String, launchCount: Int? = nil,
                                  duration: Int? = nil, crashedLastSession: Bool? = nil) {
        var meta: [String: String] = ["sessionEvent": subtype]
        if let lc = launchCount          { meta["launchCount"] = String(lc) }
        if let d  = duration             { meta["durationSeconds"] = String(d) }
        if let c  = crashedLastSession   { meta["crashedLastSession"] = c ? "true" : "false" }

        let total = UserDefaults.standard.integer(forKey: Keys.totalTime)
        meta["totalSessionSeconds"] = String(total)

        let event = TesterBuddy.shared.eventSender.makeEvent(
            type: .session,
            message: "Session \(subtype)",
            screenName: TesterBuddy.shared.currentScreen,
            metadata: meta,
            testerId: TesterBuddy.shared.userId
        )
        TesterBuddy.shared.flush([event])
    }
}
