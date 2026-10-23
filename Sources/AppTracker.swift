import AppKit

/// Keeps running apps in most-recently-used order.
final class AppTracker {
    private var order: [pid_t] = []

    init() {
        order = Self.initialOrder()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.bump(app.processIdentifier)
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.order.removeAll { $0 == app.processIdentifier }
        }
    }

    /// Regular (Dock-visible) apps, most recently used first.
    func apps() -> [NSRunningApplication] {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        let byPid = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        var result = order.compactMap { byPid[$0] }
        let known = Set(result.map(\.processIdentifier))
        result += running.filter { !known.contains($0.processIdentifier) }

        // The frontmost app always comes first.
        if let front = NSWorkspace.shared.frontmostApplication,
           let index = result.firstIndex(where: { $0.processIdentifier == front.processIdentifier }) {
            result.insert(result.remove(at: index), at: 0)
        }
        return result
    }

    private func bump(_ pid: pid_t) {
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
    }

    /// Best guess at recency on launch: the front-to-back order of on-screen windows.
    private static func initialOrder() -> [pid_t] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var seen = Set<pid_t>()
        var pids: [pid_t] = []
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  seen.insert(pid).inserted else { continue }
            pids.append(pid)
        }
        return pids
    }
}
