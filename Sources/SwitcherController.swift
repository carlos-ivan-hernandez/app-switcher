import AppKit

enum SwitcherMode: String, CaseIterable {
    /// Hold Cmd, press Tab to move, release Cmd to switch.
    case classic
    /// List stays open; type to filter, arrows to move, Enter to switch.
    case search
    /// Like classic, but the icons are arranged in a wheel.
    case wheel

    var title: String {
        switch self {
        case .classic: return "Classic: release ⌘ to switch"
        case .search: return "Search: type to filter, Enter to switch"
        case .wheel: return "Wheel: icons in a circle, release ⌘ to switch"
        }
    }

    private static let defaultsKey = "SwitcherMode"

    static var saved: SwitcherMode {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(SwitcherMode.init) ?? .classic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// Holds switcher state and decides what to show and activate.
final class SwitcherController {
    var mode: SwitcherMode = .saved {
        didSet { SwitcherMode.saved = mode }
    }

    private let tracker: AppTracker
    private let panel = SwitcherPanel()
    private let wheel = WheelPanel()
    private var allApps: [NSRunningApplication] = []
    private var apps: [NSRunningApplication] = []
    private var query = ""
    private var selected = 0
    private var pendingShow: DispatchWorkItem?
    private var clickOutsideMonitor: Any?

    private(set) var isActive = false

    init(tracker: AppTracker) {
        self.tracker = tracker
        panel.onHover = { [weak self] index in self?.select(index) }
        panel.onClick = { [weak self] index in
            self?.select(index)
            self?.commit()
        }
        wheel.onHover = panel.onHover
        wheel.onClick = panel.onClick
    }

    func next() {
        if begin() { select(apps.count > 1 ? 1 : 0) } else { select(selected + 1) }
    }

    func previous() {
        if begin() { select(apps.count - 1) } else { select(selected - 1) }
    }

    func commandReleased() {
        if mode != .search { commit() }
    }

    func type(_ text: String) {
        guard isActive, mode == .search else { return }
        query += text
        applyFilter()
    }

    func deleteBackward() {
        guard isActive, mode == .search, !query.isEmpty else { return }
        query.removeLast()
        applyFilter()
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
        allApps = tracker.apps()
        apps = allApps
        query = ""
        guard !apps.isEmpty else { return false }
        isActive = true

        switch mode {
        case .classic, .wheel:
            // Like the system switcher, a quick Cmd+Tab flips apps without flashing the UI.
            let show = DispatchWorkItem { [weak self] in
                guard let self, self.isActive else { return }
                if self.mode == .wheel {
                    self.wheel.show(apps: self.apps, selected: self.selected)
                } else {
                    self.panel.show(apps: self.apps, selected: self.selected, searching: false)
                }
            }
            pendingShow = show
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: show)

        case .search:
            // Show right away (after the caller sets the selection) and close on clicks elsewhere.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                self.panel.show(apps: self.apps, selected: self.selected, searching: true)
            }
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.cancel()
            }
        }
        return true
    }

    private func end() {
        isActive = false
        pendingShow?.cancel()
        pendingShow = nil
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        panel.orderOut(nil)
        wheel.orderOut(nil)
    }

    private func applyFilter() {
        apps = Self.filter(allApps, by: query)
        selected = 0
        panel.reload(apps: apps, selected: selected, query: query)
    }

    private func select(_ index: Int) {
        guard !apps.isEmpty else { return }
        selected = (index % apps.count + apps.count) % apps.count
        if mode == .wheel { wheel.setSelected(selected) } else { panel.setSelected(selected) }
    }

    /// Keeps apps whose name matches the query, best matches first
    /// (name prefix, then word prefix, then substring, then letters in order).
    private static func filter(_ apps: [NSRunningApplication], by query: String) -> [NSRunningApplication] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return apps }

        func score(_ app: NSRunningApplication) -> Int? {
            let name = (app.localizedName ?? "").lowercased()
            if name.hasPrefix(needle) { return 0 }
            let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            if words.contains(where: { $0.hasPrefix(needle) }) { return 1 }
            if name.contains(needle) { return 2 }
            var rest = Substring(needle)
            for char in name where char == rest.first { rest.removeFirst() }
            return rest.isEmpty ? 3 : nil
        }

        return apps.enumerated()
            .compactMap { index, app in score(app).map { (score: $0, index: index, app: app) } }
            .sorted { ($0.score, $0.index) < ($1.score, $1.index) }
            .map(\.app)
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
