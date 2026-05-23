import UIKit

/// Tracks app sessions: launch count, session duration, crash-free runs.
final class SessionTracker {

    private enum Keys {
        static let launchCount    = "TBLaunchCount"
        static let totalTime      = "TBTotalSessionTime"
        static let didCrashLast   = "TBDidCrashLastSession"
        static let processStarted = "TBProcessSessionStarted"
    }

    private var sessionStart: Date?
    private var processLaunchCount = 0
    private var crashedLastSession = false
    private var sentProcessStartMetadata = false

    func start() {
        let alreadyStarted = UserDefaults.standard.bool(forKey: Keys.processStarted)
        if !alreadyStarted {
            processLaunchCount = UserDefaults.standard.integer(forKey: Keys.launchCount) + 1
            crashedLastSession = UserDefaults.standard.bool(forKey: Keys.didCrashLast)
            UserDefaults.standard.set(processLaunchCount, forKey: Keys.launchCount)
            UserDefaults.standard.set(false, forKey: Keys.didCrashLast)
            UserDefaults.standard.set(true, forKey: Keys.processStarted)
        } else {
            processLaunchCount = UserDefaults.standard.integer(forKey: Keys.launchCount)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        if UIApplication.shared.applicationState == .active {
            appDidBecomeActive()
        }
    }

    static func markCrash() {
        UserDefaults.standard.set(true, forKey: Keys.didCrashLast)
    }

    @objc private func appDidBecomeActive() {
        SessionContext.beginForegroundSession()
        sessionStart = Date()

        let launchCount: Int? = sentProcessStartMetadata ? nil : {
            sentProcessStartMetadata = true
            return processLaunchCount
        }()
        let crashed: Bool? = launchCount != nil ? crashedLastSession : nil

        sendSessionEvent(subtype: "start", launchCount: launchCount, crashedLastSession: crashed)
    }

    @objc private func appDidBackground() {
        guard let start = sessionStart else { return }
        let duration = Int(Date().timeIntervalSince(start))
        let total = UserDefaults.standard.integer(forKey: Keys.totalTime) + duration
        UserDefaults.standard.set(total, forKey: Keys.totalTime)
        sendSessionEvent(subtype: "end", duration: duration)
    }

    private func sendSessionEvent(subtype: String, launchCount: Int? = nil,
                                  duration: Int? = nil, crashedLastSession: Bool? = nil) {
        var meta = SessionContext.baseMetadata(subtype: subtype)
        if let lc = launchCount { meta["launchCount"] = String(lc) }
        if let d = duration { meta["durationSeconds"] = String(d) }
        if let c = crashedLastSession { meta["crashedLastSession"] = c ? "true" : "false" }

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
