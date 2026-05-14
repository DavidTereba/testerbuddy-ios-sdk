import Foundation

// File-level global — C function pointers cannot capture type-scoped context,
// so the previous handler must live at module scope to be reachable from the closure.
private var _tbPreviousExceptionHandler: NSUncaughtExceptionHandler?

enum CrashReporter {

    // Keep the key as a compile-time constant so the closure can use it directly.
    static let pendingKey = "TBPendingCrashes"

    static func install() {
        flushPending()
        installExceptionHandler()
    }

    // Send crashes from the previous session (saved before app died)
    private static func flushPending() {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let events = try? JSONDecoder().decode([TBEvent].self, from: data) else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        TBLogger.debug("Flushing \(events.count) crash event(s) from previous session")
        TesterBuddy.shared.flush(events)
    }

    private static func installExceptionHandler() {
        _tbPreviousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            let message = "\(exception.name.rawValue): \(exception.reason ?? "no reason")"
            let stack = exception.callStackSymbols.prefix(40).joined(separator: "\n")

            let event = TesterBuddy.shared.eventSender.makeEvent(
                type: .crash,
                message: message,
                stack: stack,
                screenName: TesterBuddy.shared.currentScreen,
                testerId: TesterBuddy.shared.userId
            )

            if let data = try? JSONEncoder().encode([event]) {
                UserDefaults.standard.set(data, forKey: CrashReporter.pendingKey)
                // Mark next session as post-crash so the dashboard can compute
                // crash-free session rate correctly.
                SessionTracker.markCrash()
                UserDefaults.standard.synchronize()
            }

            _tbPreviousExceptionHandler?(exception)
        }
    }
}
