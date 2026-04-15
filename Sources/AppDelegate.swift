import AppKit
import Foundation

struct ScreenEvent: Codable {
    enum Kind: String, Codable { case on, off }
    let kind: Kind
    let time: Date
}

struct ProjectEntry: Codable {
    let project: String
    let time: Date
}

struct AppData: Codable {
    var screenEvents: [ScreenEvent] = []
    var projectEntries: [ProjectEntry] = []
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var projectTimer: Timer?
    var currentProject: String = ""
    var promptWindow: ProjectPromptWindow?
    var isFocusActive: Bool = false

    // MARK: - Storage

    lazy var dataFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("BarTimeTracker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.json")
    }()

    let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .prettyPrinted
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func loadData() -> AppData {
        guard let data = try? Data(contentsOf: dataFileURL),
              let appData = try? decoder.decode(AppData.self, from: data) else {
            return AppData()
        }
        return appData
    }

    func saveData(_ data: AppData) {
        if let encoded = try? encoder.encode(data) {
            try? encoded.write(to: dataFileURL, options: .atomic)
        }
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let data = loadData()
        currentProject = data.projectEntries.last?.project ?? ""

        setupStatusItem()
        setupScreenMonitoring()
        setupFocusMonitoring()
        recordScreenEvent(.on)
        scheduleProjectTimer()
    }

    // MARK: - Screen Events

    func setupScreenMonitoring() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(screenWoke),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(screenSlept),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
    }

    @objc func screenWoke() { recordScreenEvent(.on) }
    @objc func screenSlept() { recordScreenEvent(.off) }

    func recordScreenEvent(_ kind: ScreenEvent.Kind) {
        var data = loadData()
        let todayEvents = data.screenEvents.filter { Calendar.current.isDateInToday($0.time) }
        if let last = todayEvents.last, last.kind == kind { return }
        data.screenEvents.append(ScreenEvent(kind: kind, time: Date()))
        saveData(data)
    }

    // MARK: - Focus Monitoring

    func setupFocusMonitoring() {
        // Read current state (works for DND and Focus modes on macOS 12+)
        isFocusActive = UserDefaults(suiteName: "com.apple.notificationcenterui")?
            .bool(forKey: "doNotDisturb") ?? false

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(focusDidStart),
                        name: .init("com.apple.notificationcenterui.dndstart"), object: nil)
        dnc.addObserver(self, selector: #selector(focusDidEnd),
                        name: .init("com.apple.notificationcenterui.dndend"), object: nil)
    }

    @objc func focusDidStart() { isFocusActive = true }
    @objc func focusDidEnd()   { isFocusActive = false }

    // MARK: - Project Entries

    func recordProjectEntry(_ project: String) {
        var data = loadData()
        data.projectEntries.append(ProjectEntry(project: project, time: Date()))
        saveData(data)
    }

    // MARK: - Time Calculation

    func totalOnTime(events: [ScreenEvent]) -> TimeInterval {
        var total: TimeInterval = 0
        var lastOn: Date?

        for event in events {
            switch event.kind {
            case .on:  lastOn = event.time
            case .off:
                if let on = lastOn {
                    total += event.time.timeIntervalSince(on)
                    lastOn = nil
                }
            }
        }
        if let on = lastOn { total += Date().timeIntervalSince(on) }
        return total
    }

    func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: - Status Item

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⏱"
            button.action = #selector(showMenu)
            button.target = self
        }
    }

    @objc func showMenu() {
        let appData = loadData()
        let todayScreenEvents = appData.screenEvents.filter { Calendar.current.isDateInToday($0.time) }

        let menu = NSMenu()
        let timeFmt = DateFormatter()
        timeFmt.timeStyle = .short
        timeFmt.dateStyle = .none

        // Total on-time
        let total = totalOnTime(events: todayScreenEvents)
        let totalItem = NSMenuItem(title: "Total on today: \(formatDuration(total))", action: nil, keyEquivalent: "")
        totalItem.isEnabled = false
        menu.addItem(totalItem)

        if let first = todayScreenEvents.first(where: { $0.kind == .on }) {
            let item = NSMenuItem(title: "First on: \(timeFmt.string(from: first.time))", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Screen events
        if todayScreenEvents.isEmpty {
            let item = NSMenuItem(title: "No events yet", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for event in todayScreenEvents {
                let label = event.kind == .on ? "▶ on   \(timeFmt.string(from: event.time))"
                                              : "■ off  \(timeFmt.string(from: event.time))"
                let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Current project
        let projLabel = currentProject.isEmpty ? "No project set" : "Project: \(currentProject)"
        let projItem = NSMenuItem(title: projLabel, action: nil, keyEquivalent: "")
        projItem.isEnabled = false
        menu.addItem(projItem)

        let setItem = NSMenuItem(title: "Set project…", action: #selector(askForProjectManually), keyEquivalent: "p")
        setItem.target = self
        menu.addItem(setItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Project Timer

    func scheduleProjectTimer() {
        projectTimer?.invalidate()
        projectTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: false) { [weak self] _ in
            guard let self else { return }
            let data = self.loadData()
            let screenIsOn = data.screenEvents.filter { Calendar.current.isDateInToday($0.time) }.last?.kind != .off
            if screenIsOn {
                self.askForProject(isAutoPrompt: true)
            } else {
                // Screen off — skip popup but still schedule next
                self.scheduleProjectTimer()
            }
        }
        RunLoop.main.add(projectTimer!, forMode: .common)
    }

    func recentProjects() -> [String] {
        let entries = loadData().projectEntries
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries.reversed() {
            if seen.insert(entry.project).inserted {
                result.append(entry.project)
                if result.count >= 100 { break }
            }
        }
        return result
    }

    @objc func askForProjectManually() {
        askForProject(isAutoPrompt: false)
    }

    func askForProject(isAutoPrompt: Bool) {
        DispatchQueue.main.async {
            // Skip if Focus/DND is active — reschedule and try again later
            if isAutoPrompt && self.isFocusActive {
                self.scheduleProjectTimer()
                return
            }

            // Don't stack prompts
            guard self.promptWindow == nil else { return }

            let window = ProjectPromptWindow(
                currentProject: self.currentProject,
                recentProjects: self.recentProjects()
            )
            self.promptWindow = window

            window.onSave = { [weak self] val in
                guard let self else { return }
                self.currentProject = val
                self.recordProjectEntry(val)
            }

            window.onDismiss = { [weak self] in
                guard let self else { return }
                self.promptWindow = nil
                if isAutoPrompt { self.scheduleProjectTimer() }
            }

            window.show()
        }
    }
}
