import SwiftUI
import UIKit

// MARK: - UIHostingController wrapper (presented over a UIWindow)

final class FeedbackHostingController: UIViewController {
    private let screenshot: UIImage?
    private let onDismiss: () -> Void

    init(screenshot: UIImage?, onDismiss: @escaping () -> Void) {
        self.screenshot = screenshot
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let feedbackView = FeedbackView(screenshot: screenshot, onDismiss: onDismiss)
        let hosting = UIHostingController(rootView: feedbackView)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }
}

// MARK: - SwiftUI Feedback Sheet

struct FeedbackView: View {

    enum FeedbackType: String, CaseIterable {
        case bug = "Bug"
        case idea = "Idea"
        case other = "Other"

        var icon: String {
            switch self {
            case .bug:   return "ladybug.fill"
            case .idea:  return "lightbulb.fill"
            case .other: return "ellipsis.bubble.fill"
            }
        }
    }

    let screenshot: UIImage?
    let onDismiss: () -> Void

    @State private var type: FeedbackType = .bug
    @State private var description: String = ""
    @State private var isSending = false
    @State private var sent = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { focused = false }

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("Send Feedback")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.title2)
                        }
                    }

                    // Screenshot preview
                    if let img = screenshot {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }

                    // Type picker
                    HStack(spacing: 10) {
                        ForEach(FeedbackType.allCases, id: \.self) { t in
                            Button {
                                type = t
                            } label: {
                                Label(t.rawValue, systemImage: t.icon)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(type == t ? Color.accentColor : Color(UIColor.tertiarySystemFill))
                                    .foregroundStyle(type == t ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                    }

                    // Description
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                        if description.isEmpty {
                            Text("Describe what happened…")
                                .foregroundStyle(.tertiary)
                                .padding(12)
                        }
                        TextEditor(text: $description)
                            .focused($focused)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 90, maxHeight: 140)
                    }
                    .frame(minHeight: 110)

                    // Send button
                    Button {
                        sendFeedback()
                    } label: {
                        Group {
                            if isSending {
                                ProgressView()
                                    .tint(.white)
                            } else if sent {
                                Label("Sent!", systemImage: "checkmark")
                            } else {
                                Text("Send Feedback")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || isSending || sent)
                }
                .padding(20)
                .background(Color(UIColor.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .ignoresSafeArea()
    }

    private func sendFeedback() {
        isSending = true
        focused = false

        var meta: [String: String] = ["feedbackType": type.rawValue]
        if let img = screenshot, let b64 = ScreenshotHelper.toBase64(img) {
            meta["screenshotBase64"] = b64
        }

        let event = TesterBuddy.shared.eventSender.makeEvent(
            type: .feedback,
            message: description.trimmingCharacters(in: .whitespaces),
            screenName: TesterBuddy.shared.currentScreen,
            metadata: meta,
            testerId: TesterBuddy.shared.userId
        )

        TesterBuddy.shared.flush([event])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isSending = false
            sent = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onDismiss()
            }
        }
    }
}
