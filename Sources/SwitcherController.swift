import AppKit

/// Holds switcher state and decides what to show and activate.
final class SwitcherController {
    private let tracker: AppTracker
    private let panel = SwitcherPanel()
    private var apps: [NSRunningApplication] = []
    private var selected = 0
    private var pendingShow: DispatchWorkItem?

    private(set) var isActive = false

    init(tracker: AppTracker) {
        self.tracker = tracker
        panel.onHover = { [weak self] index in self?.select(index) }
        panel.onClick = { [weak self] index in
            self?.select(index)
            self?.commit()
        }
    }

    func next() {
        if begin() { select(apps.count > 1 ? 1 : 0) } else { select(selected + 1) }
    }

    func previous() {
        if begin() { select(apps.count - 1) } else { select(selected - 1) }
    }

    func commit() {
        guard isActive else { return }
        let app = apps.indices.contains(selected) ? apps[selected] : nil
        end()
        if let app { activate(app) }
    }

    func cancel() {
        end()
    }

    /// Starts a switch session. Returns true if one was just started.
    private func begin() -> Bool {
        guard !isActive else { return false }
        apps = tracker.apps()
        guard !apps.isEmpty else { return false }
        isActive = true

        // Like the system switcher, a quick Cmd+Tab flips apps without flashing the UI.
        let show = DispatchWorkItem { [weak self] in
            guard let self, self.isActive else { return }
            self.panel.show(apps: self.apps, selected: self.selected)
        }
        pendingShow = show
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: show)
        return true
    }

    private func end() {
        isActive = false
        pendingShow?.cancel()
        pendingShow = nil
        panel.orderOut(nil)
    }

    private func select(_ index: Int) {
        guard !apps.isEmpty else { return }
        selected = (index % apps.count + apps.count) % apps.count
        panel.setSelected(selected)
    }

    private func activate(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        app.activate(options: [.activateAllWindows])

        // Background apps can be refused activation on newer macOS; fall back to Launch Services.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier,
                  let url = app.bundleURL else { return }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }
}
