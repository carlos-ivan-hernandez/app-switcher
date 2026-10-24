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
}

/// How the wheel's background is drawn. Picked from the menu bar icon and remembered.
enum WheelBackground: String, CaseIterable {
    case blur
    case glass
    case clearGlass
    case solid

    var title: String {
        switch self {
        case .blur: return "Blur"
        case .glass: return "Liquid Glass"
        case .clearGlass: return "Clear Glass"
        case .solid: return "Solid"
        }
    }

    /// Liquid Glass needs macOS 26 or later.
    var isAvailable: Bool {
        switch self {
        case .glass, .clearGlass:
            if #available(macOS 26, *) { return true }
            return false
        case .blur, .solid:
            return true
        }
    }

    private static let defaultsKey = "WheelBackground"
    private static let opacityKey = "WheelBackgroundOpacity"

    static var saved: WheelBackground {
        get {
            let style = UserDefaults.standard.string(forKey: defaultsKey).flatMap(WheelBackground.init) ?? .blur
            return style.isAvailable ? style : .blur
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// How opaque the background is, from 0 (invisible) to 1. The icons are not affected.
    static var opacity: Double {
        get { UserDefaults.standard.object(forKey: opacityKey) as? Double ?? 1 }
        set { UserDefaults.standard.set(min(max(newValue, 0), 1), forKey: opacityKey) }
    }
}

/// Floating, non-activating window that shows apps on a ring, starting at the top
/// and going clockwise, with the selected app's name in the middle.
final class WheelPanel: NSPanel {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let container = NSView()
    private var background: NSView?
    private let nameLabel = NSTextField(labelWithString: "")
    private var icons: [WheelIconView] = []
    private var names: [String] = []

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        // The background sits in its own view under the icons, so its opacity
        // and style can change without touching them.
        contentView = container

        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(nameLabel)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(apps: [NSRunningApplication], selected: Int) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxDiameter = min(visible.width, visible.height) * 0.85

        // The ring grows with the number of apps; icons shrink if it would no longer fit on screen.
        var iconSize = WheelLayout.iconSize
        var radius = Self.radius(count: apps.count, iconSize: iconSize)
        while iconSize > WheelLayout.minIconSize && Self.diameter(radius: radius, iconSize: iconSize) > maxDiameter {
            iconSize -= 4
            radius = Self.radius(count: apps.count, iconSize: iconSize)
        }
        let cellSize = iconSize + WheelLayout.highlightPadding * 2
        radius = min(radius, maxDiameter / 2 - cellSize / 2 - WheelLayout.rim)
        let diameter = Self.diameter(radius: radius, iconSize: iconSize)

        setFrame(NSRect(x: visible.midX - diameter / 2, y: visible.midY - diameter / 2,
                        width: diameter, height: diameter), display: false)
        installBackground(diameter: diameter)

        icons.forEach { $0.removeFromSuperview() }
        names = apps.map { $0.localizedName ?? $0.bundleIdentifier ?? "Unknown" }
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        icons = apps.enumerated().map { index, app in
            let angle = CGFloat.pi / 2 - 2 * CGFloat.pi * CGFloat(index) / CGFloat(apps.count)
            let view = WheelIconView(app: app, padding: WheelLayout.highlightPadding)
            view.frame = NSRect(x: center.x + radius * cos(angle) - cellSize / 2,
                                y: center.y + radius * sin(angle) - cellSize / 2,
                                width: cellSize, height: cellSize)
            view.onHover = { [weak self] in self?.onHover?(index) }
            view.onClick = { [weak self] in self?.onClick?(index) }
            container.addSubview(view)
            return view
        }

        // The name fits inside the ring of icons.
        let labelWidth = max(2 * (radius - cellSize / 2) - 16, 60)
        nameLabel.frame = NSRect(x: center.x - labelWidth / 2, y: center.y - 12, width: labelWidth, height: 24)

        setSelected(selected)
        orderFrontRegardless()
        invalidateShadow()
    }

    /// Replaces the background with the saved style and opacity.
    private func installBackground(diameter: CGFloat) {
        background?.removeFromSuperview()
        let style = WheelBackground.saved
        let view = Self.makeBackground(style, diameter: diameter)
        view.frame = NSRect(x: 0, y: 0, width: diameter, height: diameter)
        view.autoresizingMask = [.width, .height]
        view.alphaValue = WheelBackground.opacity
        container.addSubview(view, positioned: .below, relativeTo: nil)
        background = view
        // Glass draws its own shadow; with no background there's nothing to cast one.
        hasShadow = (style == .blur || style == .solid) && WheelBackground.opacity > 0
    }

    private static func makeBackground(_ style: WheelBackground, diameter: CGFloat) -> NSView {
        switch style {
        case .glass, .clearGlass:
            if #available(macOS 26, *) {
                let glass = NSGlassEffectView()
                glass.style = style == .clearGlass ? .clear : .regular
                glass.cornerRadius = diameter / 2
                return glass
            }
            return makeBackground(.blur, diameter: diameter)
        case .solid:
            return CircleFillView()
        case .blur:
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            // The behind-window blur ignores a layer corner radius, so clip it with a mask.
            blur.maskImage = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
            return blur
        }
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

/// A plain disc in the window background color (adapts to light and dark mode).
private final class CircleFillView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
