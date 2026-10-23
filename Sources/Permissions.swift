import AppKit
import ApplicationServices

/// The macOS privacy permissions the Cmd+Tab event tap can depend on.
enum Permission {
    case accessibility
    case inputMonitoring

    var name: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: return AXIsProcessTrusted()
        case .inputMonitoring: return CGPreflightListenEventAccess()
        }
    }

    /// Shows the system prompt (only the first time macOS allows it).
    func request() {
        switch self {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        }
    }

    var settingsURL: URL? {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }

    func openSettings() {
        if let url = settingsURL { NSWorkspace.shared.open(url) }
    }

    /// Which permission is blocking the event tap. Accessibility alone is enough for it,
    /// so Input Monitoring is only blamed when Accessibility is granted and the tap still fails.
    static func blocking() -> Permission? {
        if !Permission.accessibility.isGranted { return .accessibility }
        if !Permission.inputMonitoring.isGranted { return .inputMonitoring }
        return nil
    }
}
