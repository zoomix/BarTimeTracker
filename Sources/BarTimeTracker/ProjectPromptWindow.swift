import AppKit

class ProjectPromptWindow: NSPanel {
    var onSave: ((String) -> Void)?
    var onBreak: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var comboBox: NSComboBox!
    private var idleContainer: NSView!
    private var inputContainer: NSView!
    private var glassContainer: NSGlassEffectContainerView!
    private var mainGlass: NSGlassEffectView!
    private var tailView: TriangleView!
    private var body: NSView!

    private static let W: CGFloat = 400
    private static let H: CGFloat = 58
    private static let tailWidth: CGFloat = 16
    private static let tailHeight: CGFloat = 8
    private static let cornerRadius: CGFloat = 10

    init(currentProject: String, recentProjects: [String]) {
        let w = ProjectPromptWindow.W
        let h = ProjectPromptWindow.H + ProjectPromptWindow.tailHeight

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        syncAppearance()

        buildUI(currentProject: currentProject, recentProjects: recentProjects)
    }

    override var canBecomeKey: Bool { true }

    /// This borderless, nonactivating panel doesn't reliably inherit the app's
    /// effective (dark/light) appearance, so read the real system setting directly.
    private func syncAppearance() {
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func buildUI(currentProject: String, recentProjects: [String]) {
        let w = ProjectPromptWindow.W
        let h = ProjectPromptWindow.H
        let fullH = h + ProjectPromptWindow.tailHeight

        // Speech-bubble body: a rounded glass panel. The tail is a plain flat-color triangle, not
        // glass — NSGlassEffectView's compositing didn't preserve a rotated square as a crisp
        // diamond (it kept collapsing to a plain rounded stub), and it's a 16pt sliver where the
        // backdrop is nearly uniform anyway, so a solid triangle in the same tint reads as one piece.
        let root = NSView(frame: NSRect(x: 0, y: 0, width: w, height: fullH))

        // Tint rather than leaving it purely backdrop-driven — otherwise a dark wallpaper renders
        // the glass dark even in Light mode, clashing with the (light-mode) control colors on top.
        // Kept fairly opaque since macOS also dims translucent materials when the window isn't key.
        let tint = NSColor.windowBackgroundColor.withAlphaComponent(0.9)

        let tw = ProjectPromptWindow.tailWidth
        let th = ProjectPromptWindow.tailHeight
        tailView = TriangleView(frame: NSRect(x: w / 2 - tw / 2, y: h - 1, width: tw, height: th + 1))
        tailView.fillColor = tint
        root.addSubview(tailView)

        // NSGlassEffectView composites its material in its own layer and draws nothing into the
        // window's backing store, so every pixel that isn't a glyph or control has alpha 0 — and the
        // WindowServer passes clicks straight through transparent regions of a non-opaque window.
        // A nearly-invisible fill in the bubble's own shape gives the backing store real alpha, so
        // clicks land, without squaring off the shadow the way an opaque window background would.
        let backdrop = BubbleBackdropView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        backdrop.cornerRadius = ProjectPromptWindow.cornerRadius
        root.addSubview(backdrop)

        glassContainer = ClickThroughGlassContainerView(frame: NSRect(x: 0, y: 0, width: w, height: fullH))
        body = NSView(frame: glassContainer.bounds)
        glassContainer.contentView = body

        mainGlass = ClickThroughGlassEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        mainGlass.cornerRadius = ProjectPromptWindow.cornerRadius
        mainGlass.tintColor = tint
        body.addSubview(mainGlass)

        // Sits above tailView so only the tip poking out past the top edge is visible.
        root.addSubview(glassContainer)

        // MARK: Input view

        inputContainer = ClickCatchingView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        let label = ClickThroughLabel(labelWithString: "Working on?")
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 12, y: 38, width: 200, height: 12)

        comboBox = NSComboBox(frame: NSRect(x: 10, y: 10, width: 200, height: 26))
        comboBox.placeholderString = "Project name…"
        comboBox.font = .systemFont(ofSize: 13)
        comboBox.isBordered = false
        comboBox.drawsBackground = false
        comboBox.focusRingType = .none
        comboBox.completes = true
        comboBox.numberOfVisibleItems = 10
        comboBox.hasVerticalScroller = true
        comboBox.target = self
        comboBox.action = #selector(saveAction)

        if !recentProjects.isEmpty { comboBox.addItems(withObjectValues: recentProjects) }
        if !currentProject.isEmpty { comboBox.stringValue = currentProject }

        let skipBtn = NSButton(title: "Skip", target: self, action: #selector(skipAction))
        skipBtn.bezelStyle = .recessed
        skipBtn.controlSize = .small
        skipBtn.font = .systemFont(ofSize: 11)
        skipBtn.frame = NSRect(x: 216, y: 14, width: 52, height: 18)
        skipBtn.keyEquivalent = "\u{1b}"

        let breakBtn = NSButton(title: "Break", target: self, action: #selector(breakAction))
        breakBtn.bezelStyle = .recessed
        breakBtn.controlSize = .small
        breakBtn.font = .systemFont(ofSize: 11)
        breakBtn.frame = NSRect(x: 274, y: 14, width: 52, height: 18)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveBtn.bezelStyle = .recessed
        saveBtn.controlSize = .small
        saveBtn.font = .systemFont(ofSize: 11)
        saveBtn.frame = NSRect(x: 332, y: 14, width: 52, height: 18)
        saveBtn.keyEquivalent = "\r"

        inputContainer.addSubview(label)
        inputContainer.addSubview(comboBox)
        inputContainer.addSubview(skipBtn)
        inputContainer.addSubview(breakBtn)
        inputContainer.addSubview(saveBtn)

        // MARK: Idle view

        let tappable = TappableView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        tappable.onTap = { [weak self] in self?.activate() }

        let idleLabel = ClickThroughLabel(labelWithString: "What's up?")
        idleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        idleLabel.textColor = .labelColor
        idleLabel.frame = NSRect(x: 14, y: (h - 16) / 2, width: 250, height: 16)
        tappable.addSubview(idleLabel)

        let idleSkip = NSButton(title: "Skip", target: self, action: #selector(skipAction))
        idleSkip.bezelStyle = .recessed
        idleSkip.controlSize = .small
        idleSkip.font = .systemFont(ofSize: 11)
        idleSkip.frame = NSRect(x: 274, y: 14, width: 52, height: 18)
        tappable.addSubview(idleSkip)

        let idleSame = NSButton(title: "Same", target: self, action: #selector(saveAction))
        idleSame.bezelStyle = .recessed
        idleSame.controlSize = .small
        idleSame.font = .systemFont(ofSize: 11)
        idleSame.frame = NSRect(x: 332, y: 14, width: 52, height: 18)
        tappable.addSubview(idleSame)

        idleContainer = tappable

        root.addSubview(inputContainer)
        root.addSubview(idleContainer)

        contentView = root
    }

    /// Repositions `tailView` under the given screen-icon x, in body-local coordinates.
    private func positionTail(apexX: CGFloat) {
        let w = ProjectPromptWindow.W
        let tw = ProjectPromptWindow.tailWidth
        let margin = ProjectPromptWindow.cornerRadius + tw / 2
        let clampedX = min(max(apexX, margin), w - margin)
        tailView.frame.origin.x = clampedX - tw / 2
    }

    private func activate() {
        idleContainer.isHidden = true
        inputContainer.isHidden = false
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
        makeFirstResponder(comboBox)
    }

    func show(startActive: Bool = false, anchor: NSRect? = nil) {
        syncAppearance()

        if startActive {
            idleContainer.isHidden = true
            inputContainer.isHidden = false
        } else {
            idleContainer.isHidden = false
            inputContainer.isHidden = true
        }

        // Recalculate position each time — screen layout may have changed (e.g. after screensaver)
        let w = ProjectPromptWindow.W
        let h = ProjectPromptWindow.H
        let th = ProjectPromptWindow.tailHeight
        let screen = (anchor.flatMap { a in NSScreen.screens.first { $0.frame.contains(NSPoint(x: a.midX, y: a.midY)) } })
            ?? NSScreen.main ?? NSScreen.screens[0]

        let iconCenterX = anchor?.midX ?? screen.frame.midX
        let iconBottomY = anchor?.minY ?? (screen.frame.maxY - (screen.frame.height - screen.visibleFrame.maxY))

        let margin: CGFloat = 8
        var x = iconCenterX - w / 2
        x = min(max(x, screen.visibleFrame.minX + margin), screen.visibleFrame.maxX - w - margin)
        let y = iconBottomY - h - th - 4
        setFrameOrigin(NSPoint(x: x, y: y))

        positionTail(apexX: iconCenterX - x)

        orderFrontRegardless()
        if startActive {
            NSApp.activate(ignoringOtherApps: true)
            makeKey()
            makeFirstResponder(comboBox)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "a" {
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc private func saveAction() {
        let val = comboBox.stringValue.trimmingCharacters(in: .whitespaces)
        if !val.isEmpty { onSave?(val) }
        dismiss()
    }

    @objc private func breakAction() {
        onBreak?()
        dismiss()
    }

    @objc private func skipAction() {
        dismiss()
    }

    private func dismiss() {
        close()
        onDismiss?()
    }
}

private class TriangleView: NSView {
    var fillColor: NSColor = .clear { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: bounds.width, y: 0))
        path.line(to: NSPoint(x: bounds.width / 2, y: bounds.height))
        path.close()
        fillColor.setFill()
        path.fill()
    }
}

private class TappableView: NSView {
    var onTap: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onTap?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Nearly-invisible fill in the bubble's shape, purely so the window backing store has non-zero
/// alpha there and the WindowServer stops treating those pixels as click-through.
private class BubbleBackdropView: NSView {
    var cornerRadius: CGFloat = 10

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.005).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }
}

/// NSGlassEffectContainerView's hitTest claims any point within its bounds, even where a sibling view
/// sits in front of it. Returning nil when it would claim itself lets clicks reach the real view.
private class ClickThroughGlassContainerView: NSGlassEffectContainerView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
}

private class ClickThroughGlassEffectView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
}

/// A non-interactive label that never claims a hit, so clicks reach the view behind it.
private class ClickThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Swallows clicks on empty space so this nonactivating panel doesn't leak them to the window behind.
private class ClickCatchingView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
}
