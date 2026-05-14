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

    // Cancellation — protected by a lock so stop() is safe to call from any thread.
    private let cancelLock = NSLock()
    private var _isCancelled = false
    private var isCancelled: Bool {
        cancelLock.lock(); defer { cancelLock.unlock() }
        return _isCancelled
    }

    init(threshold: TimeInterval = 5.0) {
        self.threshold = threshold
    }

    func start() {
        cancelLock.lock()
        _isCancelled = false
        cancelLock.unlock()

        queue.async { [weak self] in
            self?.watchLoop()
        }
    }

    func stop() {
        cancelLock.lock()
        _isCancelled = true
        cancelLock.unlock()
    }

    deinit {
        stop()
    }

    // MARK: - Private

    private func watchLoop() {
        while !isCancelled {
            Thread.sleep(forTimeInterval: 1.0)
            guard !isCancelled else { return }

            let semaphore = DispatchSemaphore(value: 0)
            let sent = Date()

            DispatchQueue.main.async {
                semaphore.signal()
            }

            let result = semaphore.wait(timeout: .now() + threshold)
            guard !isCancelled else { return }

            if result == .timedOut {
                if !isReporting {
                    isReporting = true
                    let blocked = Date().timeIntervalSince(sent)
                    report(blockedFor: blocked)
                }
            } else {
                if isReporting {
                    TBLogger.debug("ANR resolved — main thread responsive again")
                }
                isReporting = false
            }
        }
    }

    private func report(blockedFor seconds: TimeInterval) {
        TBLogger.debug("ANR detected: main thread blocked for \(Int(seconds))s")
        let event = TesterBuddy.shared.eventSender.makeEvent(
            type: .anr,
            message: "ANR: main thread blocked for \(Int(seconds))s",
            screenName: TesterBuddy.shared.currentScreen,
            testerId: TesterBuddy.shared.userId
        )
        TesterBuddy.shared.flush([event])
    }
}
