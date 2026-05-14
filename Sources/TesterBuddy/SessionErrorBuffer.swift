import Foundation

/// In-memory ring buffer of recent session errors.
///
/// Entries are automatically attached to feedback reports so developers
/// can see what went wrong before the tester submitted feedback —
/// similar to the console errors the web SDK captures.
///
/// The buffer is never persisted; it only covers the current app session.
/// Capacity is capped at 30 entries (oldest dropped first).
final class SessionErrorBuffer {

    static let shared = SessionErrorBuffer()

    struct Entry: Encodable {
        let type: String
        let message: String
        let time: String    // HH:mm:ss
        let stack: String?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private static let cap = 30

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private init() {}

    func record(type: String, message: String, stack: String? = nil) {
        let entry = Entry(
            type: type,
            message: message,
            time: timeFormatter.string(from: Date()),
            stack: stack
        )
        lock.lock(); defer { lock.unlock() }
        entries.append(entry)
        if entries.count > Self.cap {
            entries.removeFirst(entries.count - Self.cap)
        }
    }

    /// Returns all entries serialized as a compact JSON string, or `nil` if the buffer is empty.
    func jsonString() -> String? {
        lock.lock()
        let copy = entries
        lock.unlock()
        guard !copy.isEmpty,
              let data = try? JSONEncoder().encode(copy),
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }
}
