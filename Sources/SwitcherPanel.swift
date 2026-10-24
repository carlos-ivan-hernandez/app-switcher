import AppKit

private enum Layout {
    static let width: CGFloat = 320
    static let rowHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 2
    static let iconSize: CGFloat = 28
    static let padding: CGFloat = 8
    static let searchHeight: CGFloat = 32
    static let sectionSpacing: CGFloat = 6
}

/// Floating, non-activating window that shows the app list in the middle of the screen.
final class SwitcherPanel: NSPanel {
    var onHover: ((Int) -> Void)? {
        get { list.onHover }
        set { list.onHover = newValue }
    }
    var onClick: ((Int) -> Void)? {
        get { list.onClick }
        set { list.onClick = newValue }
    }

    private let list = SwitcherListView(blending: .behindWindow)

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        contentView = list
    }

    // Glass draws its flat, inactive look unless its window is key. The panel is
    // non-activating, so becoming key doesn't take focus from the frontmost app,
    // and the event tap swallows every key press while the switcher is open.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Sizes and shows the panel for the full list. Filtering later keeps this size.
    func show(apps: [NSRunningApplication], selected: Int, searching: Bool) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = SwitcherListView.preferredSize(appCount: apps.count, searching: searching,
                                                  maxHeight: visible.height * 0.8)
        setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                        width: size.width, height: size.height), display: false)

        list.configure(searching: searching)
        list.reload(apps: apps, selected: selected, query: "")
        hasShadow = Appearance.wantsWindowShadow
        orderFrontRegardless()
        makeKey()
        invalidateShadow()
    }

    func reload(apps: [NSRunningApplication], selected: Int, query: String) {
        list.reload(apps: apps, selected: selected, query: query)
    }

    func setSelected(_ index: Int) {
        list.setSelected(index)
    }
}

/// Apps listed vertically, with an optional search bar on top. Used by the floating
/// panel and the settings preview.
final class SwitcherListView: NSView {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let blending: NSVisualEffectView.BlendingMode
    private var background: NSView?
    private let searchBar = SearchBarView()
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No matching apps")
    private var rows: [AppRowView] = []

    init(blending: NSVisualEffectView.BlendingMode) {
        self.blending = blending
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.spacing = Layout.rowSpacing
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        scrollView.documentView = document
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        scrollView.addSubview(emptyLabel)

        // Search bar on top (hidden in classic mode), list below.
        let column = NSStackView(views: [searchBar, scrollView])
        column.orientation = .vertical
        column.spacing = Layout.sectionSpacing
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        let p = Layout.padding
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: p),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -p),
            column.topAnchor.constraint(equalTo: topAnchor, constant: p),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -p),
            searchBar.widthAnchor.constraint(equalTo: column.widthAnchor),
            searchBar.heightAnchor.constraint(equalToConstant: Layout.searchHeight),
            scrollView.widthAnchor.constraint(equalTo: column.widthAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The size that fits every app, but no taller than `maxHeight`.
    static func preferredSize(appCount: Int, searching: Bool, maxHeight: CGFloat) -> NSSize {
        let listHeight = CGFloat(appCount) * Layout.rowHeight + CGFloat(max(appCount - 1, 0)) * Layout.rowSpacing
        let searchHeight = searching ? Layout.searchHeight + Layout.sectionSpacing : 0
        return NSSize(width: Layout.width, height: min(listHeight + searchHeight + Layout.padding * 2, maxHeight))
    }

    /// Shows or hides the search bar and applies the saved appearance. Call after sizing the view.
    func configure(searching: Bool) {
        searchBar.isHidden = !searching
        searchBar.query = ""

        background?.removeFromSuperview()
        let newBackground = Appearance.makeBackground(shape: .roundedRect(radius: 14), size: bounds.size,
                                                      blending: blending)
        newBackground.autoresizingMask = [.width, .height]
        addSubview(newBackground, positioned: .below, relativeTo: nil)
        background = newBackground
    }

    /// Replaces the rows, e.g. after the filter changes.
    func reload(apps: [NSRunningApplication], selected: Int, query: String) {
        searchBar.query = query
        rows.forEach { $0.removeFromSuperview() }
        rows = apps.enumerated().map { index, app in
            let row = AppRowView(app: app)
            row.onHover = { [weak self] in self?.onHover?(index) }
            row.onClick = { [weak self] in self?.onClick?(index) }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return row
        }
        emptyLabel.isHidden = !apps.isEmpty
        setSelected(selected)
    }

    func setSelected(_ index: Int) {
        for (i, row) in rows.enumerated() { row.isSelected = (i == index) }
        if rows.indices.contains(index) {
            layoutSubtreeIfNeeded()
            rows[index].scrollToVisible(rows[index].bounds)
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Shows what the user has typed. It is a plain label: keys arrive through the
/// event tap, so the panel never needs keyboard focus.
private final class SearchBarView: NSView {
    private let label = NSTextField(labelWithString: "")

    var query = "" {
        didSet { update() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")!)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingHead
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func update() {
        if query.isEmpty {
            label.stringValue = "Type to filter apps"
            label.textColor = .tertiaryLabelColor
        } else {
            label.stringValue = query
            label.textColor = .labelColor
        }
    }
}

/// One row: icon on the left, app name on the right.
private final class AppRowView: NSView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?

    var isSelected = false {
        didSet {
            layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
            label.textColor = isSelected ? .white : .labelColor
        }
    }

    private let label: NSTextField

    init(app: NSRunningApplication) {
        label = NSTextField(labelWithString: app.localizedName ?? app.bundleIdentifier ?? "Unknown")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = app.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Layout.rowHeight),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Layout.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Layout.iconSize),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }
}
