import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tracker = AppTracker()
    private lazy var switcher = SwitcherController(tracker: tracker)
    private lazy var hotkeys = HotkeyMonitor { [weak self] event in self?.handle(event) }
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        // Ask for Accessibility access (needed to intercept Cmd+Tab).
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        startHotkeys()
    }

    /// Keeps retrying until the user grants Accessibility permission.
    private func startHotkeys() {
        if hotkeys.start() {
            statusItem?.menu?.item(withTag: 1)?.title = "Cmd+Tab is active"
            return
        }
        statusItem?.menu?.item(withTag: 1)?.title = "Waiting for Accessibility permission…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startHotkeys() }
    }

    private func handle(_ event: HotkeyMonitor.Event) {
        switch event {
        case .next: switcher.next()
        case .previous: switcher.previous()
        case .commit: switcher.commit()
        case .cancel: switcher.cancel()
        }
        hotkeys.isSwitching = switcher.isActive
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "App Switcher")

        let menu = NSMenu()
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.tag = 1
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit App Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
