import UIKit

// MARK: - Model

struct TBAnnouncement: Codable {
    let id: Int
    let title: String
    let message: String
    let type: String   // "info" | "warning" | "update"
}

// MARK: - Manager

/// Polls `/api/sdk/announcements` for developer-sent messages and shows
/// a non-intrusive banner at the top of the screen.
///
/// Announcements are shown once per device (seen IDs stored in UserDefaults).
/// Polling happens on app foreground so developers get near-real-time delivery.
final class AnnouncementManager {

    private static let seenKey = "TBSeenAnnouncements"
    private var apiKey: String = ""

    func start(apiKey: String) {
        self.apiKey = apiKey
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        // If the app is already active (e.g. configure() called from onAppear),
        // didBecomeActiveNotification already fired — fetch immediately.
        // Otherwise the observer above will trigger it on next foreground.
        let alreadyActive = UIApplication.shared.applicationState == .active
        Task {
            // Delay so UIWindowScene is attached before we try to show a banner.
            // Use a longer delay on first launch to ensure the scene is ready.
            try? await Task.sleep(nanoseconds: alreadyActive ? 1_000_000_000 : 500_000_000)
            await fetch()
        }
    }

    @objc private func appDidBecomeActive() {
        Task {
            // Small delay so the scene is ready after returning to foreground.
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 s
            await fetch()
        }
    }

    // MARK: - Private

    private func reportSeen(ids: [Int], apiKey: String) {
        guard !ids.isEmpty,
              let url = URL(string: "https://testerbuddy.app/api/sdk/announcements/seen"),
              let body = try? JSONSerialization.data(withJSONObject: ["ids": ids])
        else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-tb-key")
        req.httpBody = body
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req).resume()
    }

    private func fetch() async {
        guard !apiKey.isEmpty,
              let url = URL(string: "https://testerbuddy.app/api/sdk/announcements")
        else { return }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-tb-key")
        request.timeoutInterval = 5

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let announcements = try? JSONDecoder().decode([TBAnnouncement].self, from: data)
        else { return }

        // Keep only IDs from the last 60 days to prevent unbounded accumulation.
        let seenRaw = UserDefaults.standard.array(forKey: Self.seenKey) as? [Int] ?? []
        let validIds = Set(announcements.map(\.id))
        let seen = seenRaw.filter { validIds.contains($0) }

        let unseen = announcements.filter { !seen.contains($0.id) }
        guard let first = unseen.first else { return }

        // Try to show the banner; retry once if the scene isn't ready yet.
        var shown = await MainActor.run { AnnouncementBannerWindow.show(first) }
        if !shown {
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 s retry
            shown = await MainActor.run { AnnouncementBannerWindow.show(first) }
        }
        guard shown else { return }

        // Mark all unseen IDs as seen so they don't repeat.
        // Only keep IDs that are still active (returned by the server) to stay lean.
        let updated = seen + unseen.map(\.id)
        UserDefaults.standard.set(updated, forKey: Self.seenKey)

        // Report viewed IDs to backend so view_count is incremented
        reportSeen(ids: unseen.map(\.id), apiKey: apiKey)
    }
}

// MARK: - Banner Window

final class AnnouncementBannerWindow {

    private static var window: UIWindow?

    /// Returns `true` if the banner was successfully attached to a window scene.
    @discardableResult
    static func show(_ announcement: TBAnnouncement) -> Bool {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        else { return false }

        let w = UIWindow(windowScene: scene)
        w.windowLevel = .statusBar + 1
        w.backgroundColor = .clear
        w.isUserInteractionEnabled = true

        let vc = UIViewController()
        vc.view.backgroundColor = .clear

        let banner = AnnouncementBannerView(announcement: announcement) { dismiss() }
        vc.view.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 6),
            banner.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 12),
            banner.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -12),
        ])

        w.rootViewController = vc
        w.makeKeyAndVisible()
        window = w

        // Animate in
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: -20)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 0.5) {
            banner.alpha = 1
            banner.transform = .identity
        }

        // Auto-dismiss after 8 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { dismiss() }

        return true
    }

    static func dismiss() {
        guard let w = window else { return }
        UIView.animate(withDuration: 0.25, animations: {
            w.alpha = 0
            w.rootViewController?.view.subviews.first?.transform = CGAffineTransform(translationX: 0, y: -20)
        }) { _ in
            w.isHidden = true
            window = nil
        }
    }
}

// MARK: - Banner View (UIKit)

private final class AnnouncementBannerView: UIView {

    init(announcement: TBAnnouncement, onDismiss: @escaping () -> Void) {
        super.init(frame: .zero)

        backgroundColor = bannerColor(for: announcement.type)
        layer.cornerRadius = 14
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)

        let icon = UIImageView(image: UIImage(systemName: iconName(for: announcement.type)))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = announcement.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1

        let messageLabel = UILabel()
        messageLabel.text = announcement.message
        messageLabel.font = .systemFont(ofSize: 12, weight: .regular)
        messageLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        messageLabel.numberOfLines = 3

        let textStack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.8)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        closeButton.addAction(UIAction { _ in onDismiss() }, for: .touchUpInside)

        let hStack = UIStackView(arrangedSubviews: [icon, textStack, closeButton])
        hStack.axis = .horizontal
        hStack.spacing = 10
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hStack)

        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])

        // Tap whole banner to dismiss
        addGestureRecognizer(UITapGestureRecognizer(target: nil, action: nil))
        let tap = UITapGestureRecognizer()
        tap.addTarget(self, action: #selector(tapped))
        addGestureRecognizer(tap)
        _dismiss = onDismiss
    }

    required init?(coder: NSCoder) { fatalError() }

    private var _dismiss: (() -> Void)?
    @objc private func tapped() { _dismiss?() }

    // MARK: - Helpers

    private func bannerColor(for type: String) -> UIColor {
        switch type {
        case "warning": return UIColor(red: 0.85, green: 0.45, blue: 0.10, alpha: 1)
        case "update":  return UIColor(red: 0.20, green: 0.45, blue: 0.90, alpha: 1)
        default:        return UIColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 0.95)
        }
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "warning": return "exclamationmark.triangle.fill"
        case "update":  return "arrow.down.circle.fill"
        default:        return "megaphone.fill"
        }
    }
}
