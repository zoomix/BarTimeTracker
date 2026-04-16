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
    var screensaverStartTime: Date?

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

    @objc func screenWoke() {
        recordScreenEvent(.on)
        if projectTimer == nil { scheduleProjectTimer() }
        // Prompt on lid-open return if absent long enough (screensaver path handles its own)
        let sinceLastPrompt = Date().timeIntervalSince(lastPromptShown ?? .distantPast)
        if sinceLastPrompt > promptInterval { askForProject(isAutoPrompt: true) }
    }
    @objc func screenSlept() {
        screensaverStartTime = nil  // lid-close voids any pending screensaver absence
        recordScreenEvent(.off)
    }
    @objc func screensaverStarted() {
        screensaverStartTime = Date()
        recordScreenEvent(.screensaverOn)
    }
    @objc func screensaverStopped() {
        recordScreenEvent(.screensaverOff)
        if let start = screensaverStartTime {
            let absence = Date().timeIntervalSince(start)
            screensaverStartTime = nil
            if absence > 60 { askForProject(isAutoPrompt: true) }
        }
    }

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
        scheduleProjectTimer()
    }

    // MARK: - Time Calculation

    func totalOnTime(events: [ScreenEvent]) -> TimeInterval {
        var total: TimeInterval = 0
        var lastOn: Date?

        for event in events {
            if event.kind == .on || event.kind == .screensaverOff {
                if lastOn == nil { lastOn = event.time }  // don't overwrite — keep earliest start
            } else if event.kind.isAway, let on = lastOn {
                total += event.time.timeIntervalSince(on)
                lastOn = nil
            }
        }
        if let on = lastOn { total += Date().timeIntervalSince(on) }
        return total
    }

    /// Worked time = sum of span durations minus break-attributed time within each span.
    /// This counts project-attributed offline time (meetings etc.) as worked, unlike raw screen-on time.
    func workedTime(spans: [TimeSpan], allEntries: [ProjectEntry], firstOnTime: Date?) -> TimeInterval {
        spans.reduce(0.0) { total, span in
            let spanEnd = span.end ?? Date()
            let spanDur = spanEnd.timeIntervalSince(span.start)
            let d = computeProjectDurations(allEntries: allEntries, firstOnTime: firstOnTime,
                                            spanStart: span.start, spanEnd: spanEnd)
            let breakDur = d.first(where: { $0.project == "Break" })?.duration ?? 0
            return total + max(0, spanDur - breakDur)
        }
    }

    struct TimeSpan {
        let start: Date
        let end: Date?   // nil = still active
        let isActive: Bool
    }

    func buildTimeSpans(from events: [ScreenEvent],
                        projectEntries: [ProjectEntry] = [],
                        mergeThreshold: TimeInterval = 3 * 60) -> [TimeSpan] {
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

        // Gap covered by a project (not Break) = spans should be merged regardless of duration.
        // The first entry at or after gapEnd tells us what the user was doing during the gap.
        func gapCoveredByWork(gapEnd: Date) -> Bool {
            guard let first = projectEntries.first(where: { $0.time >= gapEnd }) else { return false }
            return first.project != "Break"
        }

        // Merge completed spans whose gap is < threshold OR covered by non-Break project
        var merged: [(start: Date, end: Date)] = []
        for span in rawSpans {
            if let last = merged.last {
                let gap = span.start.timeIntervalSince(last.end)
                if gap < mergeThreshold || gapCoveredByWork(gapEnd: span.start) {
                    merged[merged.count - 1] = (start: last.start, end: span.end)
                    continue
                }
            }
            merged.append(span)
        }

        // Attach or append active span
        var result = merged.map { TimeSpan(start: $0.start, end: $0.end, isActive: false) }
        if let active = activeStart {
            if let last = merged.last {
                let gap = active.timeIntervalSince(last.end)
                if gap < mergeThreshold || gapCoveredByWork(gapEnd: active) {
                    result[result.count - 1] = TimeSpan(start: last.start, end: nil, isActive: true)
                } else {
                    result.append(TimeSpan(start: active, end: nil, isActive: true))
                }
            } else {
                result.append(TimeSpan(start: active, end: nil, isActive: true))
            }
        }
        return result
    }

    /// For each project whose entry falls inside [spanStart, spanEnd], compute how much
    /// time within that span is attributed to it.
    ///
    /// Attribution rule: entry[i] claims the interval [entry[i-1].time, entry[i].time]
    /// (or [firstOnTime, entry[0].time] for the first entry of the day).
    /// The last entry additionally claims [entry.last.time, spanEnd] (still working on it).
    /// Each claim is intersected with [spanStart, spanEnd].
    func computeProjectDurations(
        allEntries: [ProjectEntry],
        firstOnTime: Date?,
        spanStart: Date,
        spanEnd: Date
    ) -> [(project: String, duration: TimeInterval)] {
        guard !allEntries.isEmpty else { return [] }

        let dayStart = firstOnTime ?? allEntries[0].time
        var durations: [String: TimeInterval] = [:]

        for i in 0..<allEntries.count {
            let entry = allEntries[i]
            let claimStart = i == 0 ? dayStart : allEntries[i - 1].time
            let intStart = max(claimStart, spanStart)
            let intEnd   = min(entry.time, spanEnd)
            if intEnd > intStart {
                durations[entry.project, default: 0] += intEnd.timeIntervalSince(intStart)
            }
        }

        // Last entry also claims forwards to spanEnd
        if let last = allEntries.last {
            let intStart = max(last.time, spanStart)
            if spanEnd > intStart {
                durations[last.project, default: 0] += spanEnd.timeIntervalSince(intStart)
            }
        }

        return durations
            .map { (project: $0.key, duration: $0.value) }
            .filter { $0.duration >= 30 }
            .sorted { $0.duration > $1.duration }
    }

    /// Same pairing logic as totalOnTime — must stay in sync.
    func screenOnIntervals(from events: [ScreenEvent]) -> [(start: Date, end: Date)] {
        var intervals: [(start: Date, end: Date)] = []
        var lastOn: Date?
        for event in events {
            if event.kind == .on || event.kind == .screensaverOff {
                lastOn = event.time
            } else if event.kind.isAway, let on = lastOn {
                intervals.append((on, event.time))
                lastOn = nil
            }
        }
        if let on = lastOn { intervals.append((on, Date())) }
        return intervals
    }

    /// Break time = only the screen-ON portion of break claim intervals.
    /// Prevents over-subtracting when screen was already off during the break period.
    func effectiveBreakTime(allEntries: [ProjectEntry], firstOnTime: Date?,
                            onIntervals: [(start: Date, end: Date)]) -> TimeInterval {
        guard !allEntries.isEmpty else { return 0 }
        let dayStart = firstOnTime ?? allEntries[0].time

        func intersect(_ claimStart: Date, _ claimEnd: Date) -> TimeInterval {
            onIntervals.reduce(0) { sum, iv in
                let s = max(claimStart, iv.start), e = min(claimEnd, iv.end)
                return e > s ? sum + e.timeIntervalSince(s) : sum
            }
        }

        var total: TimeInterval = 0
        for i in 0..<allEntries.count {
            guard allEntries[i].project == "Break" else { continue }
            let claimStart = i == 0 ? dayStart : allEntries[i - 1].time
            total += intersect(claimStart, allEntries[i].time)
        }
        if allEntries.last?.project == "Break" {
            total += intersect(allEntries.last!.time, Date())
        }
        return total
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
        let menu = NSMenu()
        let timeFmt = DateFormatter()
        timeFmt.timeStyle = .short
        timeFmt.dateStyle = .none

        // Today
        addDayItems(to: menu, date: Date(), appData: appData, timeFmt: timeFmt)

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
        let intervalSubmenu = NSMenu()
        for option in intervalOptions {
            let item = NSMenuItem(title: option.label, action: #selector(setInterval(_:)), keyEquivalent: "")
            item.representedObject = option.seconds
            item.state = option.seconds == promptInterval ? .on : .off
            item.target = self
            intervalSubmenu.addItem(item)
        }
        intervalItem.submenu = intervalSubmenu
        menu.addItem(intervalItem)

        // Previous days submenu
        let cal = Calendar.current
        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"
        let allDates = appData.screenEvents.map(\.time) + appData.projectEntries.map(\.time)
        let prevDays = Array(Set(allDates
            .filter { !cal.isDateInToday($0) }
            .map { cal.startOfDay(for: $0) }))
            .sorted(by: >)
        if !prevDays.isEmpty {
            let prevItem = NSMenuItem(title: "Previous days", action: nil, keyEquivalent: "")
            let prevSubmenu = NSMenu()
            for day in prevDays {
                let dayItem = NSMenuItem(title: isoFmt.string(from: day), action: nil, keyEquivalent: "")
                let dayMenu = NSMenu()
                addDayItems(to: dayMenu, date: day, appData: appData, timeFmt: timeFmt)
                dayItem.submenu = dayMenu
                prevSubmenu.addItem(dayItem)
            }
            prevItem.submenu = prevSubmenu
            menu.addItem(prevItem)
        }

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

    func addDayItems(to menu: NSMenu, date: Date, appData: AppData, timeFmt: DateFormatter) {
        let cal = Calendar.current
        let dayScreenEvents = appData.screenEvents.filter { cal.isDate($0.time, inSameDayAs: date) }
        let dayProjects = appData.projectEntries
            .filter { cal.isDate($0.time, inSameDayAs: date) && !$0.project.hasPrefix("~") }
            .sorted { $0.time < $1.time }
        let firstOnTime = dayScreenEvents.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time

        let spans = buildTimeSpans(from: dayScreenEvents, projectEntries: dayProjects)
        let worked = workedTime(spans: spans, allEntries: dayProjects, firstOnTime: firstOnTime)

        let totalItem = NSMenuItem(title: "Worked: \(formatDuration(worked))", action: nil, keyEquivalent: "")
        totalItem.isEnabled = false
        menu.addItem(totalItem)
        menu.addItem(.separator())
        if spans.isEmpty {
            let item = NSMenuItem(title: "No events yet", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for span in spans {
                let spanEnd = span.end ?? Date()
                let startStr = timeFmt.string(from: span.start)
                let endStr   = span.isActive ? "now" : timeFmt.string(from: span.end!)
                let dur      = formatDuration(spanEnd.timeIntervalSince(span.start))
                let title    = "\(startStr) – \(endStr)  (\(dur))"

                let reportedInSpan = Set(dayProjects
                    .filter { $0.time >= span.start && $0.time <= spanEnd }
                    .map { $0.project })

                let durations = computeProjectDurations(
                    allEntries: dayProjects,
                    firstOnTime: firstOnTime,
                    spanStart: span.start,
                    spanEnd: spanEnd
                ).filter { reportedInSpan.contains($0.project) }

                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let totalAttributed = durations.reduce(0.0) { $0 + $1.duration }
                let diff = spanEnd.timeIntervalSince(span.start) - totalAttributed

                if !durations.isEmpty || diff > 60 {
                    let submenu = NSMenu()
                    for pd in durations {
                        let pItem = NSMenuItem(title: "\(pd.project)  \(formatDuration(pd.duration))", action: nil, keyEquivalent: "")
                        pItem.isEnabled = false
                        submenu.addItem(pItem)
                    }
                    if diff > 60 {
                        if !durations.isEmpty { submenu.addItem(.separator()) }
                        let diffItem = NSMenuItem(title: "diff  \(formatDuration(diff))", action: nil, keyEquivalent: "")
                        diffItem.isEnabled = false
                        submenu.addItem(diffItem)
                    }
                    item.submenu = submenu
                } else {
                    item.isEnabled = false
                }
                menu.addItem(item)
            }
        }
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

            // Don't stack prompts — but ensure timer survives
            guard self.promptWindow == nil else {
                if isAutoPrompt { self.scheduleProjectTimer() }
                return
            }

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
