import Foundation

/// Detects Application Not Responding (ANR) scenarios.
///
/// A background watchdog pings the main thread every second.
/// If the main thread doesn't respond within `threshold` seconds,
/// an ANR event is logged and sent to the TesterBuddy dashboard.
/// Detection rearms automatically once the main thread becomes responsive again.
final class ANRDetector {

    private let threshold: TimeInterval
    private let queue = DispatchQueue(label: "app.testerbuddy.anr", qos: .background)
    private var isReporting = false

    init(threshold: TimeInterval = 5.0) {
        self.threshold = threshold
    }

    func start() {
        queue.async { [weak self] in
            self?.watchLoop()
        }
    }

    // MARK: - Private

    private func watchLoop() {
        while true {
            Thread.sleep(forTimeInterval: 1.0)
            let semaphore = DispatchSemaphore(value: 0)
            let sent = Date()

            DispatchQueue.main.async {
                semaphore.signal()
            }

            let result = semaphore.wait(timeout: .now() + threshold)

            if result == .timedOut {
                if !isReporting {
                    isReporting = true
                    let blocked = Date().timeIntervalSince(sent)
                    report(blockedFor: blocked)
                }
            } else {
                isReporting = false
            }
        }
    }

    private func report(blockedFor seconds: TimeInterval) {
        let event = TesterBuddy.shared.eventSender.makeEvent(
            type: .anr,
            message: "ANR: main thread blocked for \(Int(seconds))s",
            screenName: TesterBuddy.shared.currentScreen,
            testerId: TesterBuddy.shared.userId
        )
        TesterBuddy.shared.flush([event])
    }
}
