import Foundation

/// URLProtocol subclass that intercepts URLSession requests and reports
/// failed or errored calls to TesterBuddy as `network_error` events.
///
/// Only captures requests through `URLSession.shared` or sessions using
/// `.default` configuration. Requests to `testerbuddy.app` are excluded
/// to prevent infinite loops.
///
/// Opt-in: enable via `TesterBuddy.configure(apiKey:, networkMonitoring: true)`.
final class TBNetworkProtocol: URLProtocol {

    private static let handledKey = "TBNetworkProtocolHandled"
    private var dataTask: URLSessionDataTask?

    // MARK: - Registration

    static func enable() {
        URLProtocol.registerClass(TBNetworkProtocol.self)
    }

    static func disable() {
        URLProtocol.unregisterClass(TBNetworkProtocol.self)
    }

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool {
        // Don't intercept SDK's own requests or already-handled requests
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
        guard !(request.url?.host?.contains("testerbuddy.app") ?? false) else { return false }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Mark as handled to avoid re-entry
        let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        dataTask = session.dataTask(with: mutable as URLRequest)
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
    }
}

// MARK: - URLSessionDataDelegate

extension TBNetworkProtocol: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
            reportConnectionError(error, for: task.originalRequest)
        } else {
            if let http = task.response as? HTTPURLResponse, http.statusCode >= 400 {
                reportHTTPError(http, for: task.originalRequest)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    // MARK: - Reporting helpers

    private func reportConnectionError(_ error: Error, for request: URLRequest?) {
        let url = request?.url?.absoluteString ?? "unknown"
        let code = (error as NSError).code
        let event = TesterBuddy.shared.eventSender.makeEvent(
            type: .networkError,
            message: "Network error (\(code)): \(error.localizedDescription)",
            screenName: TesterBuddy.shared.currentScreen,
            metadata: ["url": url, "errorCode": String(code)],
            testerId: TesterBuddy.shared.userId
        )
        TesterBuddy.shared.flush([event])
    }

    private func reportHTTPError(_ response: HTTPURLResponse, for request: URLRequest?) {
        let url = request?.url?.absoluteString ?? "unknown"
        let event = TesterBuddy.shared.eventSender.makeEvent(
            type: .networkError,
            message: "HTTP \(response.statusCode): \(url)",
            screenName: TesterBuddy.shared.currentScreen,
            metadata: ["url": url, "status": String(response.statusCode),
                       "method": request?.httpMethod ?? "GET"],
            testerId: TesterBuddy.shared.userId
        )
        TesterBuddy.shared.flush([event])
    }
}
