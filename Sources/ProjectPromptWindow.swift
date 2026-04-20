import AppKit

class ProjectPromptWindow: NSPanel {
    var onSave: ((String) -> Void)?
    var onBreak: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var comboBox: NSComboBox!
    private var idleContainer: NSView!
    private var inputContainer: NSView!

    private static let W: CGFloat = 400
    private static let H: CGFloat = 58

    init(currentProject: String, recentProjects: [String]) {
        let w = ProjectPromptWindow.W
        let h = ProjectPromptWindow.H

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

        buildUI(currentProject: currentProject, recentProjects: recentProjects)
    }

    override var canBecomeKey: Bool { true }

    private func buildUI(currentProject: String, recentProjects: [String]) {
        let w = ProjectPromptWindow.W
        let h = ProjectPromptWindow.H

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        blur.material = .menu
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 10
        blur.layer?.masksToBounds = true

        // MARK: Input view

        inputContainer = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        let label = NSTextField(labelWithString: "Working on?")
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

        let idleLabel = NSTextField(labelWithString: "What's up?")
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

        blur.addSubview(inputContainer)
        blur.addSubview(idleContainer)
        contentView = blur
    }

    private func activate() {
        idleContainer.isHidden = true
        inputContainer.isHidden = false
        makeKey()
        makeFirstResponder(comboBox)
    }

    func show(startActive: Bool = false) {
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
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let menuBarHeight = screen.frame.height - screen.visibleFrame.maxY
        let x = screen.frame.midX - w / 2
        let y = screen.frame.maxY - menuBarHeight - h - 10
        setFrameOrigin(NSPoint(x: x, y: y))

        orderFrontRegardless()
        if startActive {
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

private class TappableView: NSView {
    var onTap: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onTap?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
