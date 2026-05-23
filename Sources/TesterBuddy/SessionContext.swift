import Foundation
import UIKit

enum SessionContext {

    private static let wasBackgroundedKey = "TBWasBackgrounded"
    private static var foregroundSessionId: String?

    static func beginForegroundSession() {
        foregroundSessionId = UUID().uuidString
        UserDefaults.standard.set(true, forKey: wasBackgroundedKey)
    }

    static func isWarmStart() -> Bool {
        UserDefaults.standard.bool(forKey: wasBackgroundedKey)
    }

    static func baseMetadata(subtype: String) -> [String: String] {
        var meta: [String: String] = [
            "sessionEvent": subtype,
            "installSessionId": TesterBuddy.shared.eventSender.sessionId,
            "deviceModel": UIDevice.current.model,
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier
        ]

        if let fg = foregroundSessionId {
            meta["foregroundSessionId"] = fg
        }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        meta["appVersion"] = version

        let screen = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        meta["screenSize"] = "\(Int(screen.width * scale))x\(Int(screen.height * scale)) @\(Int(scale * 163))dpi"

        if subtype == "start" {
            meta["startType"] = isWarmStart() ? "warm" : "cold"
        }

        if subtype == "end" {
            if let name = TesterBuddy.shared.currentScreen {
                meta["lastScreen"] = name
            }
        }

        return meta
    }
}
