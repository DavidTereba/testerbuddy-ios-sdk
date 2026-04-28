import Foundation

/// Thread-safe file-backed event queue.
///
/// Events are written to the caches directory. On the next successful
/// flush to `/api/sdk/ingest` the file is deleted. If the device is
/// offline or the request fails, events stay on disk and are retried
/// on the next `flush` call (typically next app launch).
///
/// Capacity is capped at 500 events — oldest events are dropped first
/// when the cap is exceeded.
final class OfflineQueue {

    private let fileURL: URL
    private let lock = NSLock()
    private static let cap = 500

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        fileURL = caches.appendingPathComponent("TBOfflineQueue.json")
    }

    // MARK: - Public

    /// Append events to the queue.
    func enqueue(_ events: [TBEvent]) {
        lock.lock(); defer { lock.unlock() }
        var existing = _load()
        existing.append(contentsOf: events)
        if existing.count > Self.cap {
            existing = Array(existing.suffix(Self.cap))
        }
        _save(existing)
    }

    /// Remove and return all queued events.
    func drainAll() -> [TBEvent] {
        lock.lock(); defer { lock.unlock() }
        let events = _load()
        _clear()
        return events
    }

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return _load().isEmpty
    }

    // MARK: - Private

    private func _load() -> [TBEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? JSONDecoder().decode([TBEvent].self, from: data)
        else { return [] }
        return events
    }

    private func _save(_ events: [TBEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func _clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
