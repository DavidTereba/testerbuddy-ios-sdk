import Foundation

enum CrashReporter {

    private static let pendingKey = "TBPendingCrashes"

    static func install() {
        flushPending()
        installExceptionHandler()
    }

    // Send crashes from the previous session (saved before app died)
    private static func flushPending() {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let events = try? JSONDecoder().decode([TBEvent].self, from: data) else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        TesterBuddy.shared.flush(events)
    }

    private static func installExceptionHandler() {
        let previous = NSGetUncaughtExceptionHandler()
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
                UserDefaults.standard.synchronize()
            }

            previous?(exception)
        }
    }
}
