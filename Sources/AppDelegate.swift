import AppKit
import Foundation

struct ScreenEvent: Codable {
    enum Kind: String, Codable {
        case on, off
        case screensaverOn, screensaverOff

        /// True when this event means user is away from screen
        var isAway: Bool { self == .off || self == .screensaverOn }
    }
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
    var lastPromptShown: Date?
    var nextPromptDate: Date?
    var promptInterval: TimeInterval = 15 * 60

    let intervalKey = "promptInterval"
    let logoutDateKey = "logoutDate"

    var isLoggedOut: Bool {
        guard let date = UserDefaults.standard.object(forKey: logoutDateKey) as? Date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    let intervalOptions: [(label: String, seconds: TimeInterval)] = [
        ("5 min",  5  * 60),
        ("15 min", 15 * 60),
        ("30 min", 30 * 60),
        ("60 min", 60 * 60),
    ]

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

        let saved = UserDefaults.standard.double(forKey: intervalKey)
        if saved > 0 { promptInterval = saved }

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

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screensaverStarted),
                        name: .init("com.apple.screensaver.didstart"), object: nil)
        dnc.addObserver(self, selector: #selector(screensaverStopped),
                        name: .init("com.apple.screensaver.didstop"), object: nil)
    }

    @objc func screenWoke()        { recordScreenEvent(.on) }
    @objc func screenSlept()       { recordScreenEvent(.off) }
    @objc func screensaverStarted(){ recordScreenEvent(.screensaverOn) }
    @objc func screensaverStopped(){ recordScreenEvent(.screensaverOff) }

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
            if event.kind == .on || event.kind == .screensaverOff {
                lastOn = event.time
            } else if event.kind.isAway, let on = lastOn {
                total += event.time.timeIntervalSince(on)
                lastOn = nil
            }
        }
        if let on = lastOn { total += Date().timeIntervalSince(on) }
        return total
    }

    struct TimeSpan {
        let start: Date
        let end: Date?   // nil = still active
        let isActive: Bool
    }

    func buildTimeSpans(from events: [ScreenEvent], mergeThreshold: TimeInterval = 3 * 60) -> [TimeSpan] {
        // Build raw completed spans
        var rawSpans: [(start: Date, end: Date)] = []
        var spanStart: Date? = nil

        for event in events {
            switch event.kind {
            case .on, .screensaverOff:
                if spanStart == nil { spanStart = event.time }
            case .off, .screensaverOn:
                if let s = spanStart {
                    rawSpans.append((start: s, end: event.time))
                    spanStart = nil
                }
            }
        }
        let activeStart = spanStart  // non-nil if screen still on

        // Merge completed spans whose gap is < threshold
        var merged: [(start: Date, end: Date)] = []
        for span in rawSpans {
            if let last = merged.last, span.start.timeIntervalSince(last.end) < mergeThreshold {
                merged[merged.count - 1] = (start: last.start, end: span.end)
            } else {
                merged.append(span)
            }
        }

        // Attach or append active span
        var result = merged.map { TimeSpan(start: $0.start, end: $0.end, isActive: false) }
        if let active = activeStart {
            if let last = merged.last, active.timeIntervalSince(last.end) < mergeThreshold {
                result[result.count - 1] = TimeSpan(start: last.start, end: nil, isActive: true)
            } else {
                result.append(TimeSpan(start: active, end: nil, isActive: true))
            }
        }
        return result
    }

    func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    func screensaverTimeout() -> TimeInterval {
        // idleTime first (active setting), lastDelayTime as fallback (last known before disabled)
        for key in ["idleTime", "lastDelayTime"] {
            if let val = CFPreferencesCopyValue(
                key as CFString,
                "com.apple.screensaver" as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            ) as? NSNumber, val.intValue > 0 {
                return val.doubleValue
            }
        }
        return 0
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

        menu.addItem(NSMenuItem.separator())

        // Time spans
        let spans = buildTimeSpans(from: todayScreenEvents)
        let todayProjects = appData.projectEntries.filter {
            Calendar.current.isDateInToday($0.time) && !$0.project.hasPrefix("~")
        }

        if spans.isEmpty {
            let item = NSMenuItem(title: "No events yet", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for span in spans {
                let startStr = timeFmt.string(from: span.start)
                let endStr   = span.isActive ? "now" : timeFmt.string(from: span.end!)
                let dur      = formatDuration((span.end ?? Date()).timeIntervalSince(span.start))
                let title    = "\(startStr) – \(endStr)  (\(dur))"

                let spanEnd = span.end ?? Date()
                let projects = todayProjects.filter { $0.time >= span.start && $0.time <= spanEnd }

                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

                if !projects.isEmpty {
                    let submenu = NSMenu()
                    var seen = Set<String>()
                    for entry in projects {
                        guard seen.insert(entry.project).inserted else { continue }
                        let pItem = NSMenuItem(title: entry.project, action: nil, keyEquivalent: "")
                        pItem.isEnabled = false
                        submenu.addItem(pItem)
                    }
                    item.submenu = submenu
                } else {
                    item.isEnabled = false
                }
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Current project
        let projLabel = currentProject.isEmpty ? "No project set" : "Project: \(currentProject)"
        let projItem = NSMenuItem(title: projLabel, action: nil, keyEquivalent: "")
        projItem.isEnabled = false
        menu.addItem(projItem)

        // Last / next prompt times
        let lastLabel = lastPromptShown.map { "Last check: \(timeAgo(from: $0))" } ?? "Last check: not yet"
        let lastItem = NSMenuItem(title: lastLabel, action: nil, keyEquivalent: "")
        lastItem.isEnabled = false
        menu.addItem(lastItem)

        let nextLabel: String
        if isLoggedOut {
            nextLabel = "Next check: logged out for today"
        } else {
            nextLabel = nextPromptDate.map { "Next check: \(timeUntil($0))" } ?? "Next check: —"
        }
        let nextItem = NSMenuItem(title: nextLabel, action: nil, keyEquivalent: "")
        nextItem.isEnabled = false
        menu.addItem(nextItem)

        let setItem = NSMenuItem(title: "Set project…", action: #selector(askForProjectManually), keyEquivalent: "p")
        setItem.target = self
        menu.addItem(setItem)

        // Interval submenu
        let intervalItem = NSMenuItem(title: "Check every…", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for option in intervalOptions {
            let item = NSMenuItem(title: option.label, action: #selector(setInterval(_:)), keyEquivalent: "")
            item.representedObject = option.seconds
            item.state = option.seconds == promptInterval ? .on : .off
            item.target = self
            submenu.addItem(item)
        }
        intervalItem.submenu = submenu
        menu.addItem(intervalItem)

        menu.addItem(NSMenuItem.separator())
        if isLoggedOut {
            let item = NSMenuItem(title: "Resume tracking", action: #selector(resumeTracking), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Log out for the day", action: #selector(logoutForDay), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Project Timer

    @objc func logoutForDay() {
        projectTimer?.invalidate()
        projectTimer = nil
        nextPromptDate = nil
        UserDefaults.standard.set(Date(), forKey: logoutDateKey)
        recordProjectEntry("~logged out~")
        promptWindow?.close()
        promptWindow = nil
    }

    @objc func resumeTracking() {
        UserDefaults.standard.removeObject(forKey: logoutDateKey)
        recordProjectEntry("~resumed~")
        scheduleProjectTimer()
    }

    func scheduleProjectTimer() {
        guard !isLoggedOut else { return }
        projectTimer?.invalidate()
        nextPromptDate = Date().addingTimeInterval(promptInterval)
        projectTimer = Timer.scheduledTimer(withTimeInterval: promptInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            let data = self.loadData()
            let userActive = !(data.screenEvents.filter { Calendar.current.isDateInToday($0.time) }.last?.kind.isAway ?? false)
            if userActive {
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

            window.onBreak = { [weak self] in
                guard let self else { return }
                self.recordProjectEntry("Break")
            }

            window.onDismiss = { [weak self] in
                guard let self else { return }
                self.promptWindow = nil
                if isAutoPrompt { self.scheduleProjectTimer() }
            }

            self.lastPromptShown = Date()
            window.show()
        }
    }

    @objc func setInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        promptInterval = interval
        UserDefaults.standard.set(interval, forKey: intervalKey)
        scheduleProjectTimer()
    }

    func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60   { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return m > 0 ? "\(h)h \(m)m ago" : "\(h)h ago"
    }

    func timeUntil(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return "soon" }
        let timeFmt = DateFormatter()
        timeFmt.timeStyle = .short
        timeFmt.dateStyle = .none
        let clock = timeFmt.string(from: date)
        if seconds < 60   { return "in \(seconds)s (\(clock))" }
        if seconds < 3600 { return "in \(seconds / 60) min (\(clock))" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let dur = m > 0 ? "\(h)h \(m)m" : "\(h)h"
        return "in \(dur) (\(clock))"
    }
}
