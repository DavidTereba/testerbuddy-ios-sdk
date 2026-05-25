import Foundation

public enum TBEventType: String {
    case error
    case crash
    case networkError = "network_error"
    case feedback
    case custom
    case anr
    case session
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
    let deviceInfo: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, pageUrl, message, stack, metadata, testerId, sessionId, userAgent
        case deviceInfo = "device_info"
    }
}

/// Type-erased Codable wrapper for heterogeneous dictionaries.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:            try container.encodeNil()
        case let b as Bool:        try container.encode(b)
        case let i as Int:         try container.encode(i)
        case let d as Double:      try container.encode(d)
        case let s as String:      try container.encode(s)
        case let arr as [Any]:     try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }
}
