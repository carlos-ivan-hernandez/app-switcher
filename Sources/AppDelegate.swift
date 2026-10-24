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
        let wheelBackground = NSMenuItem(title: "Wheel Background", action: nil, keyEquivalent: "")
        wheelBackground.submenu = makeWheelBackgroundMenu()
        menu.addItem(wheelBackground)
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

    private static let opacityLabelTag = 10

    /// Style choices, then an opacity slider.
    private func makeWheelBackgroundMenu() -> NSMenu {
        let menu = NSMenu()
        for style in WheelBackground.allCases {
            // Unavailable styles get no action, so the menu greys them out.
            let item = NSMenuItem(title: style.title,
                                  action: style.isAvailable ? #selector(selectWheelBackground(_:)) : nil,
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == WheelBackground.saved ? .on : .off
            if !style.isAvailable { item.toolTip = "Needs macOS 26 or later" }
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let label = NSMenuItem(title: Self.opacityTitle(WheelBackground.opacity), action: nil, keyEquivalent: "")
        label.tag = Self.opacityLabelTag
        label.isEnabled = false
        menu.addItem(label)

        let slider = NSSlider(value: WheelBackground.opacity * 100, minValue: 0, maxValue: 100,
                              target: self, action: #selector(wheelOpacityChanged(_:)))
        slider.isContinuous = true
        slider.numberOfTickMarks = 21 // 5% steps
        slider.allowsTickMarkValuesOnly = true
        slider.frame = NSRect(x: 18, y: 2, width: 184, height: 24)
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        sliderView.addSubview(slider)
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        return menu
    }

    private static func opacityTitle(_ opacity: Double) -> String {
        "Opacity: \(Int((opacity * 100).rounded()))%"
    }

    @objc private func selectWheelBackground(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = WheelBackground(rawValue: raw) else { return }
        WheelBackground.saved = style
        for item in sender.menu?.items ?? [] where item.action == #selector(selectWheelBackground(_:)) {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
    }

    @objc private func wheelOpacityChanged(_ sender: NSSlider) {
        WheelBackground.opacity = sender.doubleValue / 100
        sender.enclosingMenuItem?.menu?.item(withTag: Self.opacityLabelTag)?.title =
            Self.opacityTitle(WheelBackground.opacity)
    }

    @objc private func openAccessibilitySettings() {
        Permission.accessibility.openSettings()
    }

    @objc private func openInputMonitoringSettings() {
        Permission.inputMonitoring.openSettings()
    }
}
