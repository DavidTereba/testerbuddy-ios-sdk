import UIKit

enum ScreenshotHelper {

    static func capture() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?
            .windows
            .first(where: { $0.isKeyWindow }) else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    // Compress to JPEG for network upload (~100–300 KB)
    static func toBase64(_ image: UIImage, quality: CGFloat = 0.3) -> String? {
        image.jpegData(compressionQuality: quality)?.base64EncodedString()
    }
}
