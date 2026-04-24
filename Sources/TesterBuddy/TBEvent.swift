import Foundation

public enum TBEventType: String {
    case error
    case crash
    case networkError = "network_error"
    case feedback
    case custom
}

struct TBEvent: Codable {
    let type: String
    let pageUrl: String?
    let message: String?
    let stack: String?
    let metadata: [String: String]?
    let testerId: Int?
    let sessionId: String
    let userAgent: String
}
