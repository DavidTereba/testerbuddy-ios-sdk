import Foundation
import UIKit
#if canImport(CoreTelephony)
import CoreTelephony
#endif

enum DeviceInfoCollector {

    /// Cached snapshot of hardware/OS properties that never change at runtime.
    private static let staticInfo: [String: Any] = collectStatic()

    /// Full device info dictionary — merges static hardware data with volatile
    /// runtime state (battery, memory, thermal, network).
    static func collect() -> [String: Any] {
        var info = staticInfo
        mergeVolatile(into: &info)
        return info
    }

    // MARK: - Static (collected once)

    private static func collectStatic() -> [String: Any] {
        var info: [String: Any] = [:]

        info["manufacturer"] = "Apple"
        info["model"] = marketingModelName()
        info["machine"] = machineName()
        info["os"] = UIDevice.current.systemName
        info["os_version"] = UIDevice.current.systemVersion

        let proc = ProcessInfo.processInfo
        info["processor_count"] = proc.processorCount

        // Screen
        let screen = UIScreen.main
        let bounds = screen.bounds
        let scale = screen.scale
        info["screen"] = [
            "width": Int(bounds.width),
            "height": Int(bounds.height),
            "scale": scale,
            "pixels_w": Int(bounds.width * scale),
            "pixels_h": Int(bounds.height * scale)
        ]

        // Memory — total
        let totalBytes = proc.physicalMemory
        info["memory"] = [
            "total_mb": Int(totalBytes / (1024 * 1024))
        ]

        // Storage
        if let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ) {
            let total = (attrs[.systemSize] as? Int64) ?? 0
            let free = (attrs[.systemFreeSize] as? Int64) ?? 0
            info["storage"] = [
                "total_gb": Int(total / (1024 * 1024 * 1024)),
                "available_gb": Int(free / (1024 * 1024 * 1024))
            ]
        }

        // Locale
        let locale = Locale.current
        info["locale"] = locale.identifier
        info["language"] = locale.language.languageCode?.identifier
        info["country"] = locale.region?.identifier

        // Timezone
        let tz = TimeZone.current
        info["timezone"] = tz.identifier
        info["timezone_offset_minutes"] = tz.secondsFromGMT() / 60

        // App info
        if let bundleInfo = Bundle.main.infoDictionary {
            info["app_version"] = bundleInfo["CFBundleShortVersionString"] as? String
            info["app_build"] = bundleInfo["CFBundleVersion"] as? String
            info["bundle_id"] = Bundle.main.bundleIdentifier
        }

        return info
    }

    // MARK: - Volatile (refreshed every event)

    private static func mergeVolatile(into info: inout [String: Any]) {
        // Available memory
        if var mem = info["memory"] as? [String: Any] {
            if let avail = availableMemoryMB() {
                mem["available_mb"] = avail
            }
            info["memory"] = mem
        }

        // Battery
        let wasBatteryEnabled = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        if !wasBatteryEnabled { UIDevice.current.isBatteryMonitoringEnabled = false }

        var battery: [String: Any] = [:]
        if level >= 0 {
            battery["level"] = Int(level * 100)
        }
        switch state {
        case .charging:  battery["state"] = "charging"
        case .full:      battery["state"] = "full"
        case .unplugged: battery["state"] = "unplugged"
        default:         battery["state"] = "unknown"
        }
        info["battery"] = battery

        // Thermal state
        let thermal = ProcessInfo.processInfo.thermalState
        switch thermal {
        case .nominal:  info["thermal_state"] = "nominal"
        case .fair:     info["thermal_state"] = "fair"
        case .serious:  info["thermal_state"] = "serious"
        case .critical: info["thermal_state"] = "critical"
        @unknown default: info["thermal_state"] = "unknown"
        }

        // Brightness
        info["screen_brightness"] = Int(UIScreen.main.brightness * 100)

        // Network
        info["network"] = collectNetwork()

        // Accessibility
        info["accessibility"] = collectAccessibility()

        // Font scale (Dynamic Type)
        let category = UIApplication.shared.preferredContentSizeCategory
        info["font_scale"] = contentSizeName(category)

        // Orientation
        let orientation = UIDevice.current.orientation
        switch orientation {
        case .portrait, .portraitUpsideDown:
            info["orientation"] = "portrait"
        case .landscapeLeft, .landscapeRight:
            info["orientation"] = "landscape"
        default:
            info["orientation"] = "unknown"
        }

        // Low Power Mode
        info["low_power_mode"] = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Jailbreak (basic heuristic)
        info["is_jailbroken"] = detectJailbreak()
    }

    // MARK: - Network

    private static func collectNetwork() -> [String: Any] {
        var net: [String: Any] = [:]

        #if canImport(CoreTelephony)
        let telephony = CTTelephonyNetworkInfo()

        if let carriers = telephony.serviceSubscriberCellularProviders,
           let carrier = carriers.values.first {
            if let name = carrier.carrierName, !name.isEmpty {
                net["carrier"] = name
            }
            if let iso = carrier.isoCountryCode, !iso.isEmpty {
                net["carrier_country"] = iso
            }
        }

        if let radios = telephony.serviceCurrentRadioAccessTechnology,
           let radio = radios.values.first {
            net["radio"] = radioName(radio)
        }
        #endif

        return net
    }

    // MARK: - Accessibility

    private static func collectAccessibility() -> [String: Any] {
        return [
            "voiceover": UIAccessibility.isVoiceOverRunning,
            "bold_text": UIAccessibility.isBoldTextEnabled,
            "reduce_motion": UIAccessibility.isReduceMotionEnabled,
            "switch_control": UIAccessibility.isSwitchControlRunning,
            "invert_colors": UIAccessibility.isInvertColorsEnabled,
            "grayscale": UIAccessibility.isGrayscaleEnabled
        ]
    }

    // MARK: - Hardware identification

    private static func machineName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }

    private static func marketingModelName() -> String {
        let machine = machineName()
        let map: [String: String] = [
            // iPhone 16 series
            "iPhone17,3": "iPhone 16 Pro", "iPhone17,4": "iPhone 16 Pro Max",
            "iPhone17,1": "iPhone 16", "iPhone17,2": "iPhone 16 Plus",
            // iPhone 15 series
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            // iPhone 14 series
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            // iPhone 13 series
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,5": "iPhone 13", "iPhone14,4": "iPhone 13 mini",
            // iPhone 12 series
            "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone13,2": "iPhone 12", "iPhone13,1": "iPhone 12 mini",
            // iPhone SE
            "iPhone14,6": "iPhone SE (3rd gen)", "iPhone12,8": "iPhone SE (2nd gen)",
            // iPad Pro
            "iPad16,3": "iPad Pro 13\" (M4)", "iPad16,4": "iPad Pro 13\" (M4)",
            "iPad16,5": "iPad Pro 11\" (M4)", "iPad16,6": "iPad Pro 11\" (M4)",
            "iPad14,5": "iPad Pro 12.9\" (6th gen)", "iPad14,6": "iPad Pro 12.9\" (6th gen)",
            "iPad14,3": "iPad Pro 11\" (4th gen)", "iPad14,4": "iPad Pro 11\" (4th gen)",
            // iPad Air
            "iPad14,8": "iPad Air 13\" (M2)", "iPad14,9": "iPad Air 13\" (M2)",
            "iPad14,10": "iPad Air 11\" (M2)", "iPad14,11": "iPad Air 11\" (M2)",
            // iPad mini
            "iPad14,1": "iPad mini (6th gen)", "iPad14,2": "iPad mini (6th gen)",
            // Simulator
            "x86_64": "Simulator", "arm64": "Simulator",
        ]
        return map[machine] ?? machine
    }

    // MARK: - Radio access technology

    private static func radioName(_ tech: String) -> String {
        switch tech {
        case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge,
             CTRadioAccessTechnologyCDMA1x:
            return "2G"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA, CTRadioAccessTechnologyeHRPD,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB:
            return "3G"
        case CTRadioAccessTechnologyLTE:
            return "LTE"
        default:
            if #available(iOS 14.1, *), tech == CTRadioAccessTechnologyNRNSA || tech == CTRadioAccessTechnologyNR {
                return "5G"
            }
            return tech
        }
    }

    // MARK: - Available memory

    private static func availableMemoryMB() -> Int? {
        if #available(iOS 13.0, *) {
            let bytes = os_proc_available_memory()
            return bytes > 0 ? Int(bytes / (1024 * 1024)) : nil
        }
        return nil
    }

    // MARK: - Dynamic Type category name

    private static func contentSizeName(_ category: UIContentSizeCategory) -> String {
        switch category {
        case .extraSmall:                         return "XS"
        case .small:                              return "S"
        case .medium:                             return "M"
        case .large:                              return "L (Default)"
        case .extraLarge:                         return "XL"
        case .extraExtraLarge:                    return "XXL"
        case .extraExtraExtraLarge:               return "XXXL"
        case .accessibilityMedium:                return "Accessibility M"
        case .accessibilityLarge:                 return "Accessibility L"
        case .accessibilityExtraLarge:            return "Accessibility XL"
        case .accessibilityExtraExtraLarge:       return "Accessibility XXL"
        case .accessibilityExtraExtraExtraLarge:  return "Accessibility XXXL"
        default:                                  return category.rawValue
        }
    }

    // MARK: - Jailbreak detection (basic)

    private static func detectJailbreak() -> Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) { return true }
        }
        if let _ = try? String(contentsOfFile: "/private/jailbreak.txt", encoding: .utf8) {
            return true
        }
        return false
    }
}
