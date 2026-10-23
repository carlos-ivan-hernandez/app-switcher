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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startHotkeys() }
    }

    private var requestedInputMonitoring = false

    private func setStatus(_ title: String, detail: String?) {
        guard let menu = statusItem?.menu else { return }
        menu.item(withTag: 1)?.title = title
        if let detailItem = menu.item(withTag: 2) {
            detailItem.isHidden = detail == nil
            detailItem.attributedTitle = NSAttributedString(string: detail ?? "", attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
        // Only offer the settings link that matters right now.
        let missing = Permission.blocking()
        menu.item(withTag: 3)?.isHidden = hotkeys.isRunning || missing == .inputMonitoring
        menu.item(withTag: 4)?.isHidden = hotkeys.isRunning || missing != .inputMonitoring
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

        let menu = NSMenu()
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.tag = 1
        status.isEnabled = false
        menu.addItem(status)
        let detail = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        detail.tag = 2
        detail.isEnabled = false
        detail.isHidden = true
        menu.addItem(detail)
        menu.addItem(.separator())
        let modeHeader = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)
        for mode in SwitcherMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == switcher.mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let accessibility = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibility.target = self
        accessibility.tag = 3
        menu.addItem(accessibility)
        let inputMonitoring = NSMenuItem(title: "Open Input Monitoring Settings…", action: #selector(openInputMonitoringSettings), keyEquivalent: "")
        inputMonitoring.target = self
        inputMonitoring.tag = 4
        inputMonitoring.isHidden = true
        menu.addItem(inputMonitoring)
        menu.addItem(NSMenuItem(title: "Quit App Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = SwitcherMode(rawValue: raw) else { return }
        switcher.cancel()
        hotkeys.isSwitching = false
        switcher.mode = mode
        for item in sender.menu?.items ?? [] where item.action == #selector(selectMode(_:)) {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
    }

    @objc private func openAccessibilitySettings() {
        Permission.accessibility.openSettings()
    }

    @objc private func openInputMonitoringSettings() {
        Permission.inputMonitoring.openSettings()
    }
}
