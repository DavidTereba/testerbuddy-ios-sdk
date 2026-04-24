import UIKit
import ObjectiveC

enum ShakeDetector {

    private static var feedbackWindow: UIWindow?

    static func install() {
        swizzleSendEvent()
        NotificationCenter.default.addObserver(
            forName: .TBShakeDetected,
            object: nil,
            queue: .main
        ) { _ in
            handleShake()
        }
    }

    static func handleShake() {
        guard feedbackWindow == nil else { return }
        let screenshot = ScreenshotHelper.capture()
        presentFeedback(screenshot: screenshot)
    }

    private static func presentFeedback(screenshot: UIImage?) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        let vc = FeedbackHostingController(screenshot: screenshot) {
            feedbackWindow?.isHidden = true
            feedbackWindow = nil
        }
        window.rootViewController = vc
        window.makeKeyAndVisible()
        feedbackWindow = window
    }

    // MARK: - UIApplication.sendEvent swizzle

    private static func swizzleSendEvent() {
        guard let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
              let swizzled = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.tb_sendEvent(_:))) else { return }
        method_exchangeImplementations(original, swizzled)
    }
}

extension NSNotification.Name {
    static let TBShakeDetected = NSNotification.Name("TBShakeDetected")
}

extension UIApplication {
    @objc func tb_sendEvent(_ event: UIEvent) {
        if event.type == .motion && event.subtype == .motionShake {
            NotificationCenter.default.post(name: .TBShakeDetected, object: nil)
        }
        tb_sendEvent(event)
    }
}
