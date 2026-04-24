# TesterBuddy iOS SDK

Capture crashes, errors, and tester feedback directly from your iOS app — visible in your [TesterBuddy](https://testerbuddy.app) dashboard alongside web SDK events.

## Requirements

- iOS 16+
- Swift 5.9+
- A TesterBuddy account with an active app (Web/iOS platform)

> **Note:** Crash and feedback events are visible in the TesterBuddy iOS app starting from **version 2.1.1**.

---

## Installation

In Xcode: **File → Add Package Dependencies**

Enter the repository URL:

```
https://github.com/DavidTereba/testerbuddy-ios-sdk
```

Select version **1.0.0** or later, then add the `TesterBuddy` library to your target.

---

## Quick Start

### 1. Configure the SDK

Call `configure` as early as possible — in your `App.init()` or `application(_:didFinishLaunchingWithOptions:)`.

```swift
import TesterBuddy

@main
struct MyApp: App {
    init() {
        TesterBuddy.configure(apiKey: "your_web_api_key")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Your **API key** is the `web_api_key` shown in your app's settings on TesterBuddy.

### 2. Identify the tester (optional but recommended)

Call after the user signs in so feedback is linked to their TesterBuddy profile:

```swift
TesterBuddy.setUserId(currentUser.id)
```

Call with `nil` on logout:

```swift
TesterBuddy.setUserId(nil)
```

### 3. Track screens (optional)

Set the current screen name so all events include context:

```swift
.onAppear {
    TesterBuddy.setScreen("HomeView")
}
```

---

## Features

### Crash Reporting

Automatically captures uncaught exceptions via `NSUncaughtExceptionHandler`. Crash details are saved to disk and sent on the next app launch so nothing is lost.

No additional setup required.

### Shake to Report

When a tester shakes the device, a feedback sheet appears with:
- A screenshot of the current screen
- Bug / Idea / Other type selector
- A description field

The report is sent to your TesterBuddy dashboard immediately.

Works automatically after `configure()` — no view modifications needed.

### Manual Event Logging

```swift
// Custom event
TesterBuddy.log(message: "User reached onboarding step 3")

// Network error
TesterBuddy.logNetworkError(url: "https://api.example.com/data", statusCode: 503)

// With metadata
TesterBuddy.log(message: "Feature flag evaluated", metadata: [
    "flag": "new_checkout",
    "value": "enabled"
])
```

---

## Dashboard

Events appear in the **Web Events** tab of your app in TesterBuddy. Use the **Crashes** filter to see iOS crash reports separately from JS errors.

Feedback submitted via shake includes an inline screenshot preview.

---

## Privacy

The SDK does not collect any personally identifiable information unless you call `setUserId()`. It never reads view content, keystrokes, or user data. All events are associated only with the TesterBuddy tester who is actively testing your app.

---

## License

MIT
