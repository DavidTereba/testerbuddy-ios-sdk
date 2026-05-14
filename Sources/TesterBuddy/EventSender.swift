import UIKit

final class EventSender {

    private let endpoint = URL(string: "https://testerbuddy.app/api/sdk/ingest")!
    let sessionId: String = UUID().uuidString
    let offlineQueue = OfflineQueue()

    lazy var userAgent: String = {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? "App"
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let os = UIDevice.current.systemVersion
        return "\(name)/\(version) iOS/\(os)"
    }()

    func makeEvent(
        type: TBEventType,
        message: String,
        stack: String? = nil,
        screenName: String? = nil,
        metadata: [String: String]? = nil,
        testerId: Int? = nil
    ) -> TBEvent {
        var meta = metadata ?? [:]
        meta["platform"] = "ios"
        meta["osVersion"] = UIDevice.current.systemVersion
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            meta["appBuild"] = build
        }
        return TBEvent(
            type: type.rawValue,
            pageUrl: screenName,
            message: message,
            stack: stack,
            metadata: meta,
            testerId: testerId,
            sessionId: sessionId,
            userAgent: userAgent
        )
    }

    /// Send events. Any queued offline events are prepended and sent together.
    /// On failure the full batch is re-queued for the next attempt.
    /// - Parameter completion: Called on the URLSession background queue with
    ///   `true` on HTTP 200, `false` on any error (events are re-queued for retry).
    func send(events: [TBEvent], apiKey: String, completion: ((Bool) -> Void)? = nil) {
        guard !apiKey.isEmpty else {
            completion?(false)
            return
        }

        // Drain offline queue and prepend to current batch
        let queued = offlineQueue.drainAll()
        let batch = queued + events
        guard !batch.isEmpty else {
            completion?(true)
            return
        }

        struct Payload: Encodable { let events: [TBEvent] }
        guard let body = try? JSONEncoder().encode(Payload(events: batch)) else {
            offlineQueue.enqueue(batch)
            completion?(false)
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-tb-key")
        request.httpBody = body
        request.timeoutInterval = 10

        let queue = self.offlineQueue
        URLSession.shared.dataTask(with: request) { _, response, error in
            let success = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            if !success {
                queue.enqueue(batch)
                let reason = error?.localizedDescription
                    ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                TBLogger.debug("Send failed (\(reason)) — \(batch.count) event(s) re-queued")
            } else {
                TBLogger.debug("Sent \(batch.count) event(s) successfully")
            }
            completion?(success)
        }.resume()
    }
}
