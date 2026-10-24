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
        window.layoutIfNeeded()
        refreshPreview()
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
            spacer, quit,
        ])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 10
        controls.setCustomSpacing(4, after: statusLabel)
        controls.setCustomSpacing(16, after: permissionButton)
        controls.setCustomSpacing(16, after: modeSummary)
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
        transparencyNote.isHidden = !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private func refreshPreview() {
        preview.show(mode: mode, apps: apps)
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

    @objc private func openPermissionSettings() {
        missingPermission?.openSettings()
    }
}

/// The desktop wallpaper with the switcher drawn on top, as it would appear on Cmd+Tab.
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
        addSubview(wheel)
        addSubview(list)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        fallback.frame = bounds
    }

    func show(mode: SwitcherMode, apps: [NSRunningApplication]) {
        loadWallpaper()
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
