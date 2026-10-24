import AppKit

/// How the switcher's background is drawn. Applies to every mode.
enum BackgroundStyle: String, CaseIterable {
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

    /// Glass sets its own transparency (Clear Glass is the see-through one), and
    /// fading it with alpha leaves a flat tint instead of glass.
    var supportsOpacity: Bool {
        self == .blur || self == .solid
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
}

/// The saved look of the switcher, shared by the floating panels and the settings preview.
enum Appearance {
    private static let styleKey = "BackgroundStyle"
    private static let opacityKey = "BackgroundOpacity"

    static var style: BackgroundStyle {
        get {
            let style = UserDefaults.standard.string(forKey: styleKey).flatMap(BackgroundStyle.init) ?? .blur
            return style.isAvailable ? style : .blur
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: styleKey) }
    }

    /// How opaque the background is, from 0 (invisible) to 1. Icons and text are not affected.
    /// Glass ignores it: fading a glass view turns off its refraction and blur.
    static var opacity: Double {
        get { UserDefaults.standard.object(forKey: opacityKey) as? Double ?? 1 }
        set { UserDefaults.standard.set(min(max(newValue, 0), 1), forKey: opacityKey) }
    }

    /// Whether a window showing the background should draw its own shadow.
    /// Glass draws one itself, and an invisible background has nothing to cast one.
    static var wantsWindowShadow: Bool {
        style.supportsOpacity && opacity > 0
    }
}

enum BackgroundShape {
    case circle
    case roundedRect(radius: CGFloat)

    func cornerRadius(for size: NSSize) -> CGFloat {
        switch self {
        case .circle: return min(size.width, size.height) / 2
        case .roundedRect(let radius): return radius
        }
    }

    func path(in rect: NSRect) -> NSBezierPath {
        switch self {
        case .circle: return NSBezierPath(ovalIn: rect)
        case .roundedRect(let radius): return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        }
    }

    /// Mask for the blur, which ignores a layer corner radius. The rounded rectangle
    /// stretches to any size; the circle is drawn at its final size.
    func maskImage(size: NSSize) -> NSImage {
        switch self {
        case .circle:
            return NSImage(size: size, flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
        case .roundedRect(let radius):
            let side = radius * 2 + 1
            let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                return true
            }
            image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
            image.resizingMode = .stretch
            return image
        }
    }
}

extension Appearance {
    /// Builds a background view in the saved style and opacity.
    /// `blending` is `.behindWindow` for the floating panels (they blur the desktop)
    /// and `.withinWindow` for the settings preview (it blurs the preview's wallpaper).
    static func makeBackground(shape: BackgroundShape, size: NSSize,
                               blending: NSVisualEffectView.BlendingMode) -> NSView {
        let view = makeView(style: style, shape: shape, size: size, blending: blending)
        view.frame = NSRect(origin: .zero, size: size)
        if style.supportsOpacity { view.alphaValue = opacity }
        return view
    }

    private static func makeView(style: BackgroundStyle, shape: BackgroundShape, size: NSSize,
                                 blending: NSVisualEffectView.BlendingMode) -> NSView {
        switch style {
        case .glass, .clearGlass:
            if #available(macOS 26, *) {
                let glass = NSGlassEffectView()
                glass.style = style == .clearGlass ? .clear : .regular
                glass.cornerRadius = shape.cornerRadius(for: size)
                return glass
            }
            return makeView(style: .blur, shape: shape, size: size, blending: blending)
        case .solid:
            return ShapeFillView(shape: shape)
        case .blur:
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = blending
            blur.state = .active
            blur.maskImage = shape.maskImage(size: size)
            return blur
        }
    }
}

/// The shape filled with the window background color (follows light and dark mode).
private final class ShapeFillView: NSView {
    private let shape: BackgroundShape

    init(shape: BackgroundShape) {
        self.shape = shape
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        shape.path(in: bounds).fill()
    }
}
