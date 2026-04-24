import UIKit

final class EventSender {

    private let endpoint = URL(string: "https://testerbuddy.app/api/sdk/ingest")!

    let sessionId: String = UUID().uuidString

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

    func send(events: [TBEvent], apiKey: String) {
        guard !events.isEmpty, !apiKey.isEmpty else { return }

        struct Payload: Encodable {
            let events: [TBEvent]
        }

        guard let body = try? JSONEncoder().encode(Payload(events: events)) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-tb-key")
        request.httpBody = body
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request).resume()
    }
}
