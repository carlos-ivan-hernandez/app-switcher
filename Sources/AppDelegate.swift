import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tracker = AppTracker()
    private lazy var switcher = SwitcherController(tracker: tracker)
    private lazy var hotkeys = HotkeyMonitor { [weak self] event in self?.handle(event) }
    private lazy var settings = SettingsWindowController(tracker: tracker, mode: switcher.mode)
    private var statusItem: NSStatusItem?
    private var shownSettingsForPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        settings.onModeChange = { [weak self] mode in self?.setMode(mode) }

        // Ask for Accessibility access (needed to intercept Cmd+Tab).
        Permission.accessibility.request()
        startHotkeys()
    }

    /// Keeps retrying until the event tap starts, showing which permission is missing.
    private func startHotkeys() {
        if hotkeys.start() {
            setStatus("Cmd+Tab is active", detail: nil)
            return
        }

        switch Permission.blocking() {
        case .accessibility:
            setStatus("Missing permission: Accessibility",
                      detail: "Settings → Privacy & Security → Accessibility. If App Switcher is already on, it's an old build: remove it (−), then add this one.")
        case .inputMonitoring:
            if !requestedInputMonitoring {
                requestedInputMonitoring = true
                Permission.inputMonitoring.request()
            }
            setStatus("Missing permission: Input Monitoring",
                      detail: "Settings → Privacy & Security → Input Monitoring")
        case nil:
            setStatus("Can't capture Cmd+Tab",
                      detail: "Accessibility and Input Monitoring are both granted. Try quitting and reopening App Switcher.")
        }

        // The status now lives in the settings window, so open it once to show what's missing.
        if !shownSettingsForPermission {
            shownSettingsForPermission = true
            settings.show()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startHotkeys() }
    }

    private var requestedInputMonitoring = false

    private func setStatus(_ title: String, detail: String?) {
        statusItem?.button?.toolTip = title
        settings.setStatus(title, detail: detail, missing: hotkeys.isRunning ? nil : Permission.blocking())
    }

    private func handle(_ event: HotkeyMonitor.Event) {
        switch event {
        case .next: switcher.next()
        case .previous: switcher.previous()
        case .commit: switcher.commit()
        case .cancel: switcher.cancel()
        case .commandReleased: switcher.commandReleased()
        case .type(let text): switcher.type(text)
        case .deleteBackward: switcher.deleteBackward()
        }
        hotkeys.isSwitching = switcher.isActive
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "App Switcher")
        item.button?.target = self
        item.button?.action = #selector(showSettings)
        statusItem = item
    }

    @objc private func showSettings() {
        settings.show()
    }

    private func setMode(_ mode: SwitcherMode) {
        switcher.cancel()
        hotkeys.isSwitching = false
        switcher.mode = mode
    }
}
