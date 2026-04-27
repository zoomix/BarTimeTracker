import AppKit
import Foundation
import IOKit.pwr_mgt
#if canImport(BarTimeTrackerCore)
import BarTimeTrackerCore
#endif

class AppDelegate: NSObject, NSApplicationDelegate, TimeDataStore {
    var statusItem: NSStatusItem!
    var projectTimer: Timer?
    var currentProject: String = ""
    var promptWindow: ProjectPromptWindow?
    var weekTimelineWindow: WeekTimelineWindow?
    var isFocusActive: Bool = false
    var lastPromptShown: Date?
    var nextPromptDate: Date?
    var promptInterval: TimeInterval = 15 * 60
    var screensaverStartTime: Date?
    var pendingPromptEntryTime: Date?

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
        DispatchQueue.main.async { [weak self] in
            self?.weekTimelineWindow?.refresh()
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
        DispatchQueue.main.async { [weak self] in
            self?.openWeekView()
        }
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
        if sinceLastPrompt > promptInterval {
            pendingPromptEntryTime = loadData().screenEvents.last(where: { $0.kind.isAway })?.time
            askForProject(isAutoPrompt: true)
        }
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
            if absence > 60 {
                pendingPromptEntryTime = start
                // Delay slightly — screen layout isn't stable the instant the screensaver ends
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.askForProject(isAutoPrompt: true)
                }
            }
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
        // Legacy DND (macOS ≤11 only — no longer fires on 12+)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(focusDidStart),
                        name: .init("com.apple.notificationcenterui.dndstart"), object: nil)
        dnc.addObserver(self, selector: #selector(focusDidEnd),
                        name: .init("com.apple.notificationcenterui.dndend"), object: nil)
    }

    @objc func focusDidStart() { isFocusActive = true }
    @objc func focusDidEnd()   { isFocusActive = false }

    // Returns true when Keynote/Zoom/Teams/etc. is holding a display-sleep prevention
    // assertion — the reliable cross-version signal that a presentation is in progress.
    func isPresentationActive() -> Bool {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let dict = byProcess?.takeRetainedValue() as? [String: [[String: Any]]] else {
            return false
        }
        return dict.values.contains { assertions in
            assertions.contains { ($0["AssertType"] as? String) == "PreventUserIdleDisplaySleep" }
        }
    }

    // MARK: - Project Entries

    func recordProjectEntry(_ project: String, at time: Date = Date()) {
        var data = loadData()
        data.projectEntries.append(ProjectEntry(project: project, time: time))
        saveData(data)
        scheduleProjectTimer()
    }

    // MARK: - Time Calculation (delegated to BarTimeTrackerCore)

    func formatDuration(_ interval: TimeInterval) -> String {
        TimeCalculations.formatDuration(interval)
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
        statusItem.isVisible = true
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "timer", accessibilityDescription: "BarTimeTracker") {
                img.isTemplate = true
                button.image = img
                button.imagePosition = .imageOnly
            } else {
                button.title = "⏱"
            }
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

        let weekViewItem = NSMenuItem(title: "Week View…", action: #selector(openWeekView), keyEquivalent: "w")
        weekViewItem.target = self
        menu.addItem(weekViewItem)

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

        let exportItem = NSMenuItem(title: "Export CSV…", action: #selector(exportCSV), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

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

        let now = Date()
        let spans = TimeCalculations.buildTimeSpans(from: dayScreenEvents, projectEntries: dayProjects, now: now)
        let worked = TimeCalculations.workedTime(spans: spans, entries: dayProjects, firstOnTime: firstOnTime, now: now)

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

                let durations = TimeCalculations.projectDurations(
                    entries: dayProjects,
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
            // Skip if Focus/DND or a presentation is active — reschedule and try again later
            if isAutoPrompt && (self.isFocusActive || self.isPresentationActive()) {
                self.scheduleProjectTimer()
                return
            }

            // Don't stack prompts — but resurface existing window if manually triggered
            guard self.promptWindow == nil else {
                if !isAutoPrompt { self.promptWindow?.show() }
                else { self.scheduleProjectTimer() }
                return
            }

            let window = ProjectPromptWindow(
                currentProject: self.currentProject,
                recentProjects: self.recentProjects()
            )
            self.promptWindow = window
            let entryTime = self.pendingPromptEntryTime ?? Date()

            window.onSave = { [weak self] val in
                guard let self else { return }
                self.currentProject = val
                self.recordProjectEntry(val, at: entryTime)
            }

            window.onBreak = { [weak self] in
                guard let self else { return }
                self.recordProjectEntry("Break", at: entryTime)
            }

            window.onDismiss = { [weak self] in
                guard let self else { return }
                self.pendingPromptEntryTime = nil
                self.promptWindow = nil
                if isAutoPrompt { self.scheduleProjectTimer() }
            }

            self.lastPromptShown = Date()
            window.show(startActive: !isAutoPrompt)
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

    // MARK: - CSV Export

    @objc func exportCSV() {
        let csv = buildCSV()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "BarTimeTracker_export.csv"
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                try? csv.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    func buildCSV() -> String {
        let appData = loadData()
        let cal = Calendar.current
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        func csvField(_ s: String) -> String {
            s.contains(";") || s.contains("\"") || s.contains("\n")
                ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
        }

        struct RawRow {
            let date: String
            var start: Date
            var end: Date
            let project: String
        }

        var rows: [RawRow] = []

        let allDates = (appData.screenEvents.map(\.time) + appData.projectEntries.map(\.time))
            .map { cal.startOfDay(for: $0) }
        let days = Array(Set(allDates)).sorted()

        for day in days {
            let dayScreenEvents = appData.screenEvents.filter { cal.isDate($0.time, inSameDayAs: day) }
            let dayProjects = appData.projectEntries
                .filter { cal.isDate($0.time, inSameDayAs: day) && !$0.project.hasPrefix("~") }
                .sorted { $0.time < $1.time }
            let firstOnTime = dayScreenEvents.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
            let dayStart = firstOnTime ?? day
            let spans = TimeCalculations.buildTimeSpans(from: dayScreenEvents, projectEntries: dayProjects, now: Date())
            let dateStr = dateFmt.string(from: day)

            func addRow(_ start: Date, _ end: Date, _ project: String) {
                guard end > start, Int(end.timeIntervalSince(start) / 60) > 0 else { return }
                rows.append(RawRow(date: dateStr, start: start, end: end, project: project))
            }

            for span in spans {
                let spanEnd = span.end ?? Date()
                let indicesInSpan = dayProjects.indices.filter {
                    dayProjects[$0].time > span.start && dayProjects[$0].time <= spanEnd
                }

                if indicesInSpan.isEmpty {
                    addRow(span.start, spanEnd, "")
                    continue
                }

                var coveredUpTo = span.start

                for idx in indicesInSpan {
                    let entry = dayProjects[idx]
                    let claimFrom = idx == 0 ? dayStart : dayProjects[idx - 1].time
                    let rowStart = max(claimFrom, span.start)
                    let rowEnd = entry.time

                    if rowStart > coveredUpTo { addRow(coveredUpTo, rowStart, "") }
                    if entry.project != "Break" { addRow(rowStart, rowEnd, entry.project) }
                    coveredUpTo = rowEnd
                }

                if let lastIdx = indicesInSpan.last {
                    let lastEntry = dayProjects[lastIdx]
                    let rowStart = max(lastEntry.time, span.start)
                    if rowStart > coveredUpTo { addRow(coveredUpTo, rowStart, "") }
                    if lastEntry.project != "Break" { addRow(rowStart, spanEnd, lastEntry.project) }
                }
            }
        }

        // Merge consecutive rows with the same date and project
        var merged: [RawRow] = []
        for row in rows {
            if var last = merged.last,
               last.date == row.date,
               last.project == row.project,
               last.end == row.start {
                last.end = row.end
                merged[merged.count - 1] = last
            } else {
                merged.append(row)
            }
        }

        var lines = ["Date;Start time;End time;Duration (minutes);Project/Description"]
        for row in merged {
            let durMin = Int(row.end.timeIntervalSince(row.start) / 60)
            lines.append("\(row.date);\(timeFmt.string(from: row.start));\(timeFmt.string(from: row.end));\(durMin);\(csvField(row.project))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Week view

    @objc func openWeekView() {
        if weekTimelineWindow == nil {
            weekTimelineWindow = WeekTimelineWindow(dataStore: self)
        }
        weekTimelineWindow?.refresh()
        weekTimelineWindow?.center()
        weekTimelineWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
