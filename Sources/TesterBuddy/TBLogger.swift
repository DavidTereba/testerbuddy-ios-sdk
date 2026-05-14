import os

/// SDK-internal logger. Enable at configure time with `debugLogging: true`.
/// Warnings are always emitted via `os_log` regardless of the flag.
enum TBLogger {

    static var isEnabled = false

    private static let logger = Logger(
        subsystem: "app.testerbuddy.sdk",
        category: "TesterBuddy"
    )

    static func debug(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let m = message()
        logger.debug("[TesterBuddy] \(m, privacy: .public)")
    }

    static func warn(_ message: String) {
        logger.warning("[TesterBuddy] ⚠️ \(message, privacy: .public)")
    }
}
