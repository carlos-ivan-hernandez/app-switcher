import AppKit

private enum WheelLayout {
    static let iconSize: CGFloat = 64
    static let minIconSize: CGFloat = 32
    /// Space around each icon for the selection highlight.
    static let highlightPadding: CGFloat = 8
    /// Space between neighbouring highlights along the ring.
    static let gap: CGFloat = 8
    static let minRadius: CGFloat = 110
    /// Space between the outer icons and the edge of the wheel.
    static let rim: CGFloat = 14
    /// Empty space between the disc and the view's edge, so the glass edge and
    /// shadow aren't cut off.
    static let margin: CGFloat = 24
}

/// Floating, non-activating window that shows the wheel in the middle of the screen.
final class WheelPanel: NSPanel {
    var onHover: ((Int) -> Void)? {
        get { wheel.onHover }
        set { wheel.onHover = newValue }
    }
    var onClick: ((Int) -> Void)? {
        get { wheel.onClick }
        set { wheel.onClick = newValue }
    }

    private let wheel = WheelView(blending: .behindWindow)

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        contentView = wheel
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(apps: [NSRunningApplication], selected: Int) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        wheel.reload(apps: apps, selected: selected, maxSide: min(visible.width, visible.height) * 0.85)

        let side = wheel.frame.width
        setFrame(NSRect(x: visible.midX - side / 2, y: visible.midY - side / 2, width: side, height: side), display: false)
        hasShadow = Appearance.wantsWindowShadow
        orderFrontRegardless()
        invalidateShadow()
    }

    func setSelected(_ index: Int) {
        wheel.setSelected(index)
    }
}

/// Apps on a ring, starting at the top and going clockwise, with the selected
/// app's name in the middle. Used by the floating panel and the settings preview.
final class WheelView: NSView {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let blending: NSVisualEffectView.BlendingMode
    private var background: NSView?
    private let nameLabel = NSTextField(labelWithString: "")
    private var icons: [WheelIconView] = []
    private var names: [String] = []

    init(blending: NSVisualEffectView.BlendingMode) {
        self.blending = blending
        super.init(frame: .zero)
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Lays out the wheel for these apps, only as large as needed but no wider than
    /// `maxSide`, and resizes the view to fit. The background uses the saved appearance.
    func reload(apps: [NSRunningApplication], selected: Int, maxSide: CGFloat) {
        let maxDiameter = maxSide - WheelLayout.margin * 2

        // The ring grows with the number of apps; icons shrink if it would no longer fit.
        var iconSize = WheelLayout.iconSize
        var radius = Self.radius(count: apps.count, iconSize: iconSize)
        while iconSize > WheelLayout.minIconSize && Self.diameter(radius: radius, iconSize: iconSize) > maxDiameter {
            iconSize -= 4
            radius = Self.radius(count: apps.count, iconSize: iconSize)
        }
        let cellSize = iconSize + WheelLayout.highlightPadding * 2
        radius = min(radius, maxDiameter / 2 - cellSize / 2 - WheelLayout.rim)
        let diameter = Self.diameter(radius: radius, iconSize: iconSize)
        let side = diameter + WheelLayout.margin * 2
        setFrameSize(NSSize(width: side, height: side))

        background?.removeFromSuperview()
        let newBackground = Appearance.makeBackground(shape: .circle, size: NSSize(width: diameter, height: diameter),
                                                      blending: blending)
        newBackground.frame.origin = NSPoint(x: WheelLayout.margin, y: WheelLayout.margin)
        addSubview(newBackground, positioned: .below, relativeTo: nil)
        background = newBackground

        icons.forEach { $0.removeFromSuperview() }
        names = apps.map { $0.localizedName ?? $0.bundleIdentifier ?? "Unknown" }
        let center = CGPoint(x: side / 2, y: side / 2)
        icons = apps.enumerated().map { index, app in
            let angle = CGFloat.pi / 2 - 2 * CGFloat.pi * CGFloat(index) / CGFloat(apps.count)
            let view = WheelIconView(app: app, padding: WheelLayout.highlightPadding)
            view.frame = NSRect(x: center.x + radius * cos(angle) - cellSize / 2,
                                y: center.y + radius * sin(angle) - cellSize / 2,
                                width: cellSize, height: cellSize)
            view.onHover = { [weak self] in self?.onHover?(index) }
            view.onClick = { [weak self] in self?.onClick?(index) }
            addSubview(view)
            return view
        }

        // The name fits inside the ring of icons.
        let labelWidth = max(2 * (radius - cellSize / 2) - 16, 60)
        nameLabel.frame = NSRect(x: center.x - labelWidth / 2, y: center.y - 12, width: labelWidth, height: 24)

        setSelected(selected)
    }

    func setSelected(_ index: Int) {
        for (i, icon) in icons.enumerated() { icon.isSelected = (i == index) }
        nameLabel.stringValue = names.indices.contains(index) ? names[index] : ""
    }

    /// Smallest ring radius that keeps neighbouring icons from overlapping.
    private static func radius(count: Int, iconSize: CGFloat) -> CGFloat {
        let cell = iconSize + WheelLayout.highlightPadding * 2 + WheelLayout.gap
        return max(WheelLayout.minRadius, CGFloat(count) * cell / (2 * .pi))
    }

    private static func diameter(radius: CGFloat, iconSize: CGFloat) -> CGFloat {
        2 * (radius + iconSize / 2 + WheelLayout.highlightPadding + WheelLayout.rim)
    }
}

/// One app icon on the wheel, with a rounded highlight behind it when selected.
private final class WheelIconView: NSView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?

    var isSelected = false {
        didSet { layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor }
    }

    init(app: NSRunningApplication, padding: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        toolTip = app.localizedName

        let icon = NSImageView()
        icon.image = app.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            icon.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
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
