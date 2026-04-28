# TesterBuddy iOS SDK

Capture crashes, ANRs, network errors, and tester feedback directly from your iOS app — all visible in your [TesterBuddy](https://testerbuddy.app) dashboard.

> **Dashboard support:** Crash and feedback events require TesterBuddy iOS app **version 2.1.1+**.

---

## Requirements

| | |
|---|---|
| Platform | iOS 16+ |
| Language | Swift 5.9+ |
| Account | [TesterBuddy](https://testerbuddy.app) — free |

---

## Installation

**File → Add Package Dependencies** in Xcode, paste the URL:

```
https://github.com/DavidTereba/testerbuddy-ios-sdk
```

Select **1.2.0** or later, add `TesterBuddy` to your target.

---

## Quick Start

Call `configure` as early as possible — `App.init()` or `application(_:didFinishLaunchingWithOptions:)`.

```swift
import TesterBuddy

@main
struct MyApp: App {
    init() {
        TesterBuddy.configure(apiKey: "your_sdk_key")
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

Your **SDK key** is shown in the TesterBuddy dashboard → App detail → iOS SDK Setup.

### All configure options

```swift
TesterBuddy.configure(
    apiKey: "your_sdk_key",
    userId: nil,                    // optional: set tester ID manually
    enableANRDetection: true,       // detect frozen main thread (≥ 5 s)
    enableNetworkMonitoring: false, // intercept failed URLSession requests (opt-in)
    enableSessionTracking: true,    // track launch count & session duration
    enableAnnouncements: true       // show developer banners inside the app
)
```

---

## Features

### 💥 Crash Reporting

Automatically installed. Captures uncaught exceptions via `NSUncaughtExceptionHandler`. Crash data is saved to disk and sent on the **next launch** so nothing is lost even if the network was offline.

Chain-calls any previously registered handler, so it's compatible with Firebase Crashlytics, Sentry, etc.

---

### 📳 Shake to Report

Tester shakes the device → feedback sheet slides up with:
- Screenshot of the current screen
- Bug / Idea / Other selector
- Description field

The report is sent to your dashboard immediately **and** posted as a message to the tester's feedback thread — you get a push notification.

No view modifications needed. Works out of the box after `configure()`.

---

### 🔴 ANR Detection

Monitors the main thread with a background watchdog. If the main thread is unresponsive for **≥ 5 seconds**, an `anr` event is logged with the duration and current screen name.

Enabled by default. To disable:

```swift
TesterBuddy.configure(apiKey: "...", enableANRDetection: false)
```

---

### 🌐 Network Monitoring *(opt-in)*

Intercepts all `URLSession.shared` and default-configuration sessions. Reports failed connections and HTTP 4xx/5xx responses as `network_error` events.

```swift
TesterBuddy.configure(apiKey: "...", enableNetworkMonitoring: true)
```

> Covers requests through `URLSession.shared` and `.default` configuration. Sessions with custom configurations are not intercepted.

You can also log network errors manually:

```swift
TesterBuddy.logNetworkError(url: "https://api.example.com/items", statusCode: 503)
```

---

### 📊 Session Tracking

Tracks launch count, session duration, and whether the previous session ended in a crash. Sends a `session` event on each launch and when the app goes to background.

Visible in the dashboard under the **Custom** events filter.

To disable:

```swift
TesterBuddy.configure(apiKey: "...", enableSessionTracking: false)
```

---

### 📣 Developer Announcements

Send a message from the TesterBuddy dashboard directly into your app. The message appears as a **non-blocking banner** at the top of the screen for any tester who opens the app.

- Types: **Info** (dark), **Warning** (orange), **Update** (blue)
- Optional expiry (e.g. auto-hide after 24 hours)
- Each announcement is shown once per device
- Tap to dismiss or auto-dismisses after 8 seconds

Create announcements from the iOS developer dashboard → App detail → Announcements section.

To disable:

```swift
TesterBuddy.configure(apiKey: "...", enableAnnouncements: false)
```

---

### 📦 Offline Queue

Events captured while the device is offline (no network, server unreachable) are stored in the app's cache directory and automatically flushed on the next successful send. Capacity is capped at **500 events** (oldest dropped first).

No setup required — works transparently for all event types.

---

### ✏️ Manual Logging

```swift
// Custom event
TesterBuddy.log(message: "User completed onboarding")

// With metadata
TesterBuddy.log(message: "Feature flag evaluated", metadata: [
    "flag": "new_checkout",
    "result": "enabled"
])

// Network error (when networkMonitoring is disabled)
TesterBuddy.logNetworkError(url: "https://api.example.com/data", statusCode: 503)
```

---

### 👤 Tester Identification

**Automatic (TestFlight):** When a tester taps "Start Testing" in the TesterBuddy app, a one-time token is placed in the clipboard. On first launch of your app, the SDK reads and exchanges it automatically — no manual code needed.

> iOS 16+ shows a brief *"App pasted from TesterBuddy"* banner. This is expected in a beta testing context and declared in the SDK's privacy manifest.

**Manual:**

```swift
TesterBuddy.setUserId(currentUser.tbTesterId)  // on sign-in
TesterBuddy.setUserId(nil)                     // on sign-out
```

---

### 🗺️ Screen Tracking

Set the current screen so all events include context:

```swift
.onAppear {
    TesterBuddy.setScreen("CheckoutView")
}
```

---

## Privacy & App Store

The SDK ships with a **`PrivacyInfo.xcprivacy`** manifest (required by Apple since May 2024).

| API | Reason code | Why |
|-----|-------------|-----|
| `NSUserDefaults` | `CA92.1` | Store crash queue, tester ID, session counters |
| `UIPasteboard` | `C56D.1` | Read one-time tester token placed by TesterBuddy |
| File timestamp | `C617.1` | Write offline event queue to caches directory |

**Data collected** (declared in manifest, not linked to user identity, not used for tracking):
- Crash data
- Performance / diagnostic data

**What the SDK does NOT do:**
- No IDFA / ATT usage → no tracking prompt required
- No keylogger, no view content reading, no microphone / camera
- No data sold or shared beyond testerbuddy.app

### App Store privacy nutrition label

When submitting to the App Store, declare in **App Privacy**:
- **Crash Data** → App Functionality → Not linked to user
- **Performance Data** → App Functionality → Not linked to user

If you use `setUserId()`, add:
- **User ID** → Developer's Advertising or Developer's App Functionality → Linked to user

---

## License

MIT
