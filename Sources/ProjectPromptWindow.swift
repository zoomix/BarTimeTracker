import AppKit

class ProjectPromptWindow: NSPanel {
    var onSave: ((String) -> Void)?
    var onBreak: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var comboBox: NSComboBox!

    private static let W: CGFloat = 400
    private static let H: CGFloat = 58

    init(currentProject: String, recentProjects: [String]) {
        let w = ProjectPromptWindow.W
        let h = ProjectPromptWindow.H

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let menuBarHeight = screen.frame.height - screen.visibleFrame.maxY
        let x = screen.frame.midX - w / 2
        let y = screen.frame.maxY - menuBarHeight - h - 10

        super.init(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
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

        // Label
        let label = NSTextField(labelWithString: "Working on?")
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 12, y: 38, width: 200, height: 12)

        // Combo box
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

        if !recentProjects.isEmpty {
            comboBox.addItems(withObjectValues: recentProjects)
        }
        if !currentProject.isEmpty {
            comboBox.stringValue = currentProject
        }

        // Skip button
        let skipBtn = NSButton(title: "Skip", target: self, action: #selector(skipAction))
        skipBtn.bezelStyle = .recessed
        skipBtn.controlSize = .small
        skipBtn.font = .systemFont(ofSize: 11)
        skipBtn.frame = NSRect(x: 216, y: 14, width: 52, height: 18)
        skipBtn.keyEquivalent = "\u{1b}"

        // Break button
        let breakBtn = NSButton(title: "Break", target: self, action: #selector(breakAction))
        breakBtn.bezelStyle = .recessed
        breakBtn.controlSize = .small
        breakBtn.font = .systemFont(ofSize: 11)
        breakBtn.frame = NSRect(x: 274, y: 14, width: 52, height: 18)

        // Save button
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveBtn.bezelStyle = .recessed
        saveBtn.controlSize = .small
        saveBtn.font = .systemFont(ofSize: 11)
        saveBtn.frame = NSRect(x: 332, y: 14, width: 52, height: 18)
        saveBtn.keyEquivalent = "\r"

        blur.addSubview(label)
        blur.addSubview(comboBox)
        blur.addSubview(skipBtn)
        blur.addSubview(breakBtn)
        blur.addSubview(saveBtn)
        contentView = blur
    }

    /// Show without stealing keyboard focus from whatever the user is doing.
    func show() {
        orderFront(nil)
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
