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

/// Floating, non-activating window that lists apps vertically.
final class SwitcherPanel: NSPanel {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let searchBar = SearchBarView()
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No matching apps")
    private var rows: [AppRowView] = []

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        contentView = background

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
        background.addSubview(column)

        let p = Layout.padding
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: p),
            column.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -p),
            column.topAnchor.constraint(equalTo: background.topAnchor, constant: p),
            column.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -p),
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Sizes and shows the panel for the full list. Filtering later keeps this size.
    func show(apps: [NSRunningApplication], selected: Int, searching: Bool) {
        searchBar.isHidden = !searching
        searchBar.query = ""

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let listHeight = CGFloat(apps.count) * Layout.rowHeight + CGFloat(max(apps.count - 1, 0)) * Layout.rowSpacing
        let searchHeight = searching ? Layout.searchHeight + Layout.sectionSpacing : 0
        let height = min(listHeight + searchHeight + Layout.padding * 2, visible.height * 0.8)
        setFrame(NSRect(x: visible.midX - Layout.width / 2, y: visible.midY - height / 2,
                        width: Layout.width, height: height), display: false)

        reload(apps: apps, selected: selected, query: "")
        orderFrontRegardless()
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
            layoutIfNeeded()
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
