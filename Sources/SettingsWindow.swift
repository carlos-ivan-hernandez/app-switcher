import AppKit

/// The window the menu bar icon opens: permission status, mode, appearance and a
/// live preview built from the apps that are open right now.
final class SettingsWindowController: NSWindowController {
    var onModeChange: ((SwitcherMode) -> Void)?

    private let tracker: AppTracker
    private var mode: SwitcherMode
    private var apps: [NSRunningApplication] = []

    private let statusLabel = NSTextField(labelWithString: "")
    private let statusDetail = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: "", target: nil, action: nil)
    private var missingPermission: Permission?

    private let modeControl = NSSegmentedControl()
    private let modeSummary = NSTextField(wrappingLabelWithString: "")

    private let stylePopup = NSPopUpButton()
    private let opacitySlider = NSSlider()
    private let opacityValue = NSTextField(labelWithString: "")
    private let transparencyNote = NSTextField(wrappingLabelWithString:
        "Reduce Transparency is on in System Settings → Accessibility → Display, so glass and blur look solid.")

    private let backdropPopup = NSPopUpButton()
    private let preview = PreviewView()

    private static let controlsWidth: CGFloat = 300
    private static let previewSide: CGFloat = 460

    init(tracker: AppTracker, mode: SwitcherMode) {
        self.tracker = tracker
        self.mode = mode
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: true)
        window.title = "App Switcher"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        observeChanges()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        apps = tracker.apps()
        syncControls()
        guard let window else { return }
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        refreshPreview()

        // A menu bar app can be refused activation on newer macOS, which leaves the
        // window behind the frontmost app. Asking Launch Services to open the app
        // brings the running copy to the front instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard !NSApp.isActive else { return }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
        }
    }

    func setStatus(_ title: String, detail: String?, missing: Permission?) {
        statusLabel.stringValue = title
        statusDetail.stringValue = detail ?? ""
        statusDetail.isHidden = detail == nil
        missingPermission = missing
        permissionButton.isHidden = missing == nil
        if let missing { permissionButton.title = "Open \(missing.name) Settings…" }
    }

    // MARK: - Layout

    private func buildContent() {
        statusLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        statusDetail.textColor = .secondaryLabelColor
        statusDetail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusDetail.isHidden = true
        permissionButton.target = self
        permissionButton.action = #selector(openPermissionSettings)
        permissionButton.isHidden = true

        modeControl.segmentCount = SwitcherMode.allCases.count
        for (i, mode) in SwitcherMode.allCases.enumerated() {
            modeControl.setLabel(mode.title, forSegment: i)
        }
        modeControl.segmentDistribution = .fillEqually
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeSummary.textColor = .secondaryLabelColor

        for style in BackgroundStyle.allCases {
            stylePopup.addItem(withTitle: style.title)
            stylePopup.lastItem?.representedObject = style.rawValue
            if !style.isAvailable {
                stylePopup.lastItem?.isEnabled = false
                stylePopup.lastItem?.toolTip = "Needs macOS 26 or later"
            }
        }
        stylePopup.autoenablesItems = false
        stylePopup.target = self
        stylePopup.action = #selector(styleChanged)

        opacitySlider.minValue = 0
        opacitySlider.maxValue = 100
        opacitySlider.numberOfTickMarks = 21 // 5% steps
        opacitySlider.allowsTickMarkValuesOnly = true
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        opacityValue.alignment = .right
        opacityValue.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        opacityValue.widthAnchor.constraint(equalToConstant: 40).isActive = true

        transparencyNote.textColor = .secondaryLabelColor
        transparencyNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        for backdrop in PreviewBackdrop.allCases {
            backdropPopup.addItem(withTitle: backdrop.title)
            backdropPopup.lastItem?.representedObject = backdrop.rawValue
        }
        backdropPopup.target = self
        backdropPopup.action = #selector(backdropChanged)

        let opacityRow = NSStackView(views: [opacitySlider, opacityValue])
        opacityRow.spacing = 8
        let grid = NSGridView(views: [
            [Self.label("Background:"), stylePopup],
            [Self.label("Opacity:"), opacityRow],
        ])
        grid.rowSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline

        let quit = NSButton(title: "Quit App Switcher", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .vertical)

        let controls = NSStackView(views: [
            statusLabel, statusDetail, permissionButton,
            Self.separator(),
            Self.header("Mode"), modeControl, modeSummary,
            Self.separator(),
            Self.header("Appearance"), grid, transparencyNote,
            Self.separator(),
            Self.header("Preview"), NSStackView(views: [Self.label("Behind switcher:"), backdropPopup]),
            spacer, quit,
        ])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 10
        controls.setCustomSpacing(4, after: statusLabel)
        controls.setCustomSpacing(16, after: permissionButton)
        controls.setCustomSpacing(16, after: modeSummary)
        controls.setCustomSpacing(16, after: transparencyNote)
        controls.translatesAutoresizingMaskIntoConstraints = false
        for view in [statusDetail, modeControl, modeSummary, transparencyNote] {
            view.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        }
        for view in controls.arrangedSubviews where view is NSBox {
            view.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        }

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.onHover = { [weak self] index in self?.preview.setSelected(index) }

        let content = NSView()
        content.addSubview(controls)
        content.addSubview(preview)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            controls.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            controls.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            controls.widthAnchor.constraint(equalToConstant: Self.controlsWidth),
            preview.leadingAnchor.constraint(equalTo: controls.trailingAnchor, constant: 20),
            preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            preview.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            preview.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            preview.widthAnchor.constraint(equalToConstant: Self.previewSide),
            preview.heightAnchor.constraint(equalToConstant: Self.previewSide),
        ])
        window?.contentView = content
    }

    private static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private static func header(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    private static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    // MARK: - State

    private func syncControls() {
        modeControl.selectedSegment = SwitcherMode.allCases.firstIndex(of: mode) ?? 0
        modeSummary.stringValue = mode.summary
        if let index = BackgroundStyle.allCases.firstIndex(of: Appearance.style) {
            stylePopup.selectItem(at: index)
        }
        opacitySlider.doubleValue = Appearance.opacity * 100
        opacityValue.stringValue = "\(Int((Appearance.opacity * 100).rounded()))%"
        if let index = PreviewBackdrop.allCases.firstIndex(of: PreviewBackdrop.saved) {
            backdropPopup.selectItem(at: index)
        }
        transparencyNote.isHidden = !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private func refreshPreview() {
        preview.show(mode: mode, apps: apps, backdrop: PreviewBackdrop.saved)
    }

    /// Keeps the preview's app list and the transparency note current while the window is open.
    private func observeChanges() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.window?.isVisible == true else { return }
                self.apps = self.tracker.apps()
                self.refreshPreview()
            }
        }
        workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                              object: nil, queue: .main) { [weak self] _ in
            self?.syncControls()
            self?.refreshPreview()
        }
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        mode = SwitcherMode.allCases[modeControl.selectedSegment]
        onModeChange?(mode)
        syncControls()
        refreshPreview()
    }

    @objc private func styleChanged() {
        guard let raw = stylePopup.selectedItem?.representedObject as? String,
              let style = BackgroundStyle(rawValue: raw) else { return }
        Appearance.style = style
        refreshPreview()
    }

    @objc private func opacityChanged() {
        Appearance.opacity = opacitySlider.doubleValue / 100
        syncControls()
        refreshPreview()
    }

    @objc private func backdropChanged() {
        guard let raw = backdropPopup.selectedItem?.representedObject as? String,
              let backdrop = PreviewBackdrop(rawValue: raw) else { return }
        PreviewBackdrop.saved = backdrop
        refreshPreview()
    }

    @objc private func openPermissionSettings() {
        missingPermission?.openSettings()
    }
}

/// What the preview shows behind the switcher, to judge how it reads over real content.
enum PreviewBackdrop: String, CaseIterable {
    case wallpaper
    case document
    case photos
    case webPage

    var title: String {
        switch self {
        case .wallpaper: return "Desktop Wallpaper"
        case .document: return "Text Document"
        case .photos: return "Photos"
        case .webPage: return "Web Page"
        }
    }

    private static let key = "PreviewBackdrop"

    static var saved: PreviewBackdrop {
        get { UserDefaults.standard.string(forKey: key).flatMap(PreviewBackdrop.init) ?? .wallpaper }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// The desktop wallpaper (or a mock window) with the switcher drawn on top, as it would appear on Cmd+Tab.
private final class PreviewView: NSView {
    var onHover: ((Int) -> Void)? {
        didSet {
            wheel.onHover = onHover
            list.onHover = onHover
        }
    }

    // Blur samples the wallpaper inside this window rather than whatever is behind it.
    private let wheel = WheelView(blending: .withinWindow)
    private let list = SwitcherListView(blending: .withinWindow)
    private let fallback = CAGradientLayer()
    private let backdrop = BackdropView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill

        fallback.colors = [NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor]
        fallback.startPoint = CGPoint(x: 0, y: 0)
        fallback.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(fallback)

        list.translatesAutoresizingMaskIntoConstraints = true
        addSubview(backdrop)
        addSubview(wheel)
        addSubview(list)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        fallback.frame = bounds
        backdrop.frame = bounds
    }

    func show(mode: SwitcherMode, apps: [NSRunningApplication], backdrop kind: PreviewBackdrop) {
        loadWallpaper()
        backdrop.kind = kind
        backdrop.isHidden = kind == .wallpaper
        let selected = apps.count > 1 ? 1 : 0 // what the first Tab press selects
        wheel.isHidden = mode != .wheel
        list.isHidden = mode == .wheel

        if mode == .wheel {
            wheel.reload(apps: apps, selected: selected, maxSide: min(bounds.width, bounds.height))
            wheel.setFrameOrigin(NSPoint(x: (bounds.width - wheel.frame.width) / 2,
                                         y: (bounds.height - wheel.frame.height) / 2))
        } else {
            let searching = mode == .search
            var size = SwitcherListView.preferredSize(appCount: apps.count, searching: searching,
                                                      maxHeight: bounds.height - 40)
            size.width = min(size.width, bounds.width - 40)
            list.frame = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                width: size.width, height: size.height)
            list.configure(searching: searching)
            list.reload(apps: apps, selected: selected, query: "")
        }
    }

    func setSelected(_ index: Int) {
        wheel.setSelected(index)
        list.setSelected(index)
    }

    /// Uses the wallpaper of the screen the window is on; dynamic wallpapers that
    /// can't be read as an image fall back to a gradient.
    private func loadWallpaper() {
        let url = (window?.screen ?? NSScreen.main).flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        guard url != wallpaperURL else { return } // already loaded; the slider refreshes often
        wallpaperURL = url
        let image = url.flatMap { NSImage(contentsOf: $0) }
        layer?.contents = image
        fallback.isHidden = image != nil
    }

    private var wallpaperURL: URL?
}

/// Hand-drawn stand-ins for what's usually behind the switcher: a page of text,
/// a photo grid, or a browser window with both. Follows light and dark mode.
private final class BackdropView: NSView {
    var kind: PreviewBackdrop = .wallpaper {
        didSet { if kind != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        switch kind {
        case .wallpaper: break
        case .document: drawDocument()
        case .photos: drawPhotos()
        case .webPage: drawWebPage()
        }
    }

    // MARK: Content

    private static let headline = "The Quiet Art of Switching Tasks"
    private static let paragraphs = [
        "Most of us move between a dozen apps an hour. A mail client, a browser, an editor, a chat window, a calendar that never seems to have a free afternoon. Every jump costs a moment of reorientation, and those moments add up over a day.",
        "A good switcher keeps that cost low. It shows what you expect, in the order you expect it, and gets out of the way the instant you let go of the keys. The best ones feel less like a tool and more like a reflex.",
        "Legibility matters more than decoration. Whatever sits behind the switcher — a busy photo, a dense spreadsheet, a page of small type — the app names and icons should still read at a glance.",
        "Translucent materials help the switcher feel connected to the work beneath it, but too much transparency turns text into noise. Finding the balance is mostly a matter of trying it against real content.",
    ]

    /// Sky and ground colors for the generated "photos".
    private static let palettes: [(NSColor, NSColor)] = [
        (.systemOrange, .systemPink), (.systemTeal, .systemBlue), (.systemYellow, .systemGreen),
        (.systemPurple, .systemIndigo), (.systemPink, .systemPurple), (.systemCyan, .systemMint),
        (.systemRed, .systemOrange), (.systemBlue, .systemIndigo), (.systemGreen, .systemTeal),
    ]

    // MARK: Layouts

    private func drawDocument() {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        var y: CGFloat = 28
        y = drawText(Self.headline, font: .boldSystemFont(ofSize: 22), color: .labelColor,
                     x: 32, y: y, width: bounds.width - 64) + 6
        y = drawText("October 24 · 6 min read", font: .systemFont(ofSize: 12), color: .secondaryLabelColor,
                     x: 32, y: y, width: bounds.width - 64) + 14
        drawParagraphs(x: 32, y: y, width: bounds.width - 64, size: 14)
    }

    private func drawPhotos() {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let gap: CGFloat = 6, columns = 3
        let side = (bounds.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
        var index = 0
        var y = gap
        while y < bounds.height {
            for column in 0..<columns {
                let rect = NSRect(x: gap + CGFloat(column) * (side + gap), y: y, width: side, height: side)
                drawPhoto(in: rect, seed: index, radius: 4)
                index += 1
            }
            y += side + gap
        }
    }

    private func drawWebPage() {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        // Browser toolbar: window buttons and an address field.
        let toolbar = NSRect(x: 0, y: 0, width: bounds.width, height: 44)
        NSColor.windowBackgroundColor.setFill()
        toolbar.fill()
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 14 + CGFloat(i) * 20, y: 16, width: 12, height: 12)).fill()
        }
        let address = NSRect(x: 90, y: 10, width: bounds.width - 180, height: 24)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: address, xRadius: 7, yRadius: 7).fill()
        drawText("example.com/articles/switching", font: .systemFont(ofSize: 12), color: .secondaryLabelColor,
                 x: address.minX + 10, y: address.minY + 4, width: address.width - 20)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: toolbar.maxY - 1, width: bounds.width, height: 1).fill()

        // Site navigation.
        var y = toolbar.maxY + 12
        drawText("The Daily Desk", font: .boldSystemFont(ofSize: 15), color: .labelColor,
                 x: 20, y: y, width: 160)
        var x = bounds.width - 20
        for item in ["Subscribe", "Design", "Tech", "News"] {
            let width = (item as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
            x -= width
            drawText(item, font: .systemFont(ofSize: 12), color: item == "Subscribe" ? .controlAccentColor : .secondaryLabelColor,
                     x: x, y: y + 2, width: width + 2)
            x -= 16
        }
        y += 30

        // Hero image with the headline over it.
        let hero = NSRect(x: 20, y: y, width: bounds.width - 40, height: 140)
        drawPhoto(in: hero, seed: 0, radius: 8)
        drawText(Self.headline, font: .boldSystemFont(ofSize: 20), color: .white,
                 x: hero.minX + 16, y: hero.maxY - 36, width: hero.width - 32)
        y = hero.maxY + 16

        // Article text beside a column of thumbnails.
        let sideWidth: CGFloat = 120
        let textWidth = bounds.width - 40 - sideWidth - 16
        drawParagraphs(x: 20, y: y, width: textWidth, size: 12)
        let sideX = bounds.maxX - 20 - sideWidth
        drawText("Related", font: .boldSystemFont(ofSize: 12), color: .labelColor, x: sideX, y: y, width: sideWidth)
        var thumbY = y + 22
        for seed in 1... {
            guard thumbY < bounds.height else { break }
            drawPhoto(in: NSRect(x: sideX, y: thumbY, width: sideWidth, height: 70), seed: seed * 2, radius: 5)
            thumbY = drawText(["Keyboard habits", "Fewer windows", "Glass, explained", "Focus modes"][seed % 4],
                              font: .systemFont(ofSize: 11), color: .secondaryLabelColor,
                              x: sideX, y: thumbY + 74, width: sideWidth) + 12
        }
    }

    // MARK: Drawing helpers

    /// Draws wrapped text and returns the y just below it.
    @discardableResult
    private func drawText(_ text: String, font: NSFont, color: NSColor,
                          x: CGFloat, y: CGFloat, width: CGFloat, lineSpacing: CGFloat = 0) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        let size = string.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        string.draw(with: NSRect(x: x, y: y, width: width, height: ceil(size.height)),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
        return y + ceil(size.height)
    }

    /// Repeats the sample paragraphs until the view is full.
    private func drawParagraphs(x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat) {
        var y = y
        var i = 0
        while y < bounds.height {
            y = drawText(Self.paragraphs[i % Self.paragraphs.count], font: .systemFont(ofSize: size),
                         color: .labelColor, x: x, y: y, width: width, lineSpacing: size * 0.3) + size
            i += 1
        }
    }

    /// A simple landscape — gradient sky, sun and hills — so blur and glass have
    /// bright shapes and edges to work on.
    private func drawPhoto(in rect: NSRect, seed: Int, radius: CGFloat) {
        let (top, bottom) = Self.palettes[seed % Self.palettes.count]
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: 90)

        let sun = rect.height * 0.22
        let sunX = rect.minX + rect.width * (0.2 + 0.6 * CGFloat((seed * 37) % 10) / 10)
        NSColor.white.withAlphaComponent(0.75).setFill()
        NSBezierPath(ovalIn: NSRect(x: sunX - sun / 2, y: rect.minY + rect.height * 0.18, width: sun, height: sun)).fill()

        for (layer, alpha) in [(0, 0.25), (1, 0.45)] {
            let hills = NSBezierPath()
            let baseY = rect.minY + rect.height * (0.55 + 0.15 * CGFloat(layer))
            hills.move(to: NSPoint(x: rect.minX, y: rect.maxY))
            hills.line(to: NSPoint(x: rect.minX, y: baseY))
            let peaks = 3
            for p in 0..<peaks {
                let step = rect.width / CGFloat(peaks)
                let peakX = rect.minX + step * (CGFloat(p) + 0.5)
                let lift = rect.height * (0.12 + 0.1 * CGFloat((seed + p + layer) % 3))
                hills.curve(to: NSPoint(x: rect.minX + step * CGFloat(p + 1), y: baseY),
                            controlPoint1: NSPoint(x: peakX - step * 0.2, y: baseY - lift),
                            controlPoint2: NSPoint(x: peakX + step * 0.2, y: baseY - lift))
            }
            hills.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            hills.close()
            NSColor.black.withAlphaComponent(alpha).setFill()
            hills.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
