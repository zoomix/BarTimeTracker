import AppKit
#if canImport(BarTimeTrackerCore)
import BarTimeTrackerCore
#endif

// MARK: - Data protocol

protocol TimeDataStore: AnyObject {
    func loadData() -> AppData
    func saveData(_ data: AppData)
}

// MARK: - File-private constants & helpers

private let cal = Calendar.current
private let timeColW: CGFloat = 52
private let activityStripW: CGFloat = 6   // left strip for screen activity
private let pxPerMin: CGFloat = 1.5
private let visibleStartHour = 0
private let visibleEndHour = 24
private let defaultScrollHour = 7
private let visibleStartMin = visibleStartHour * 60
private let visibleEndMin   = visibleEndHour * 60
private let dayH: CGFloat = CGFloat(visibleEndMin - visibleStartMin) * pxPerMin

private func minsOfDay(_ date: Date) -> Int {
    cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
}

private func minsOfDay(_ date: Date, relativeTo day: Date) -> Int {
    let startOfDay = cal.startOfDay(for: day)
    let comps = cal.dateComponents([.hour, .minute], from: startOfDay, to: date)
    return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
}

private func yFor(min m: Int) -> CGFloat { CGFloat(m - visibleStartMin) * pxPerMin }
private func yFor(date d: Date) -> CGFloat { yFor(min: minsOfDay(d)) }

private func mondayOf(weekOffset: Int) -> Date {
    var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
    comps.weekday = 2
    let monday = cal.date(from: comps)!
    return cal.date(byAdding: .weekOfYear, value: weekOffset, to: monday)!
}

// MARK: - Project color palette

private let projectPalette: [NSColor] = [
    NSColor(red: 0.95, green: 0.72, blue: 0.72, alpha: 1),  // rose
    NSColor(red: 0.98, green: 0.86, blue: 0.60, alpha: 1),  // peach
    NSColor(red: 0.93, green: 0.93, blue: 0.58, alpha: 1),  // yellow
    NSColor(red: 0.64, green: 0.91, blue: 0.68, alpha: 1),  // mint
    NSColor(red: 0.60, green: 0.84, blue: 0.97, alpha: 1),  // sky
    NSColor(red: 0.78, green: 0.70, blue: 0.97, alpha: 1),  // lavender
    NSColor(red: 0.97, green: 0.70, blue: 0.91, alpha: 1),  // pink
    NSColor(red: 0.62, green: 0.95, blue: 0.91, alpha: 1),  // teal
    NSColor(red: 0.92, green: 0.78, blue: 0.60, alpha: 1),  // tan
    NSColor(red: 0.74, green: 0.96, blue: 0.80, alpha: 1),  // seafoam
    NSColor(red: 0.84, green: 0.74, blue: 0.97, alpha: 1),  // purple
    NSColor(red: 0.97, green: 0.87, blue: 0.74, alpha: 1),  // apricot
]

private func projectColor(_ project: String) -> NSColor {
    if project == "Break" { return NSColor(red: 0.97, green: 0.84, blue: 0.58, alpha: 1) }
    var h = 5381
    for c in project.unicodeScalars { h = ((h << 5) &+ h) &+ Int(c.value) }
    return projectPalette[abs(h) % projectPalette.count]
}

/// Format a time interval as decimal hours, suitable for pasting into a
/// time-reporting tool. Always two decimals (e.g. "2.50", "6.75", "0.25").
private func decimalHours(_ interval: TimeInterval) -> String {
    String(format: "%.2f", interval / 3600)
}

// MARK: - Data models

private struct VisualSpan {
    enum Kind { case working, afk }
    let kind: Kind
    let start: Date
    let end: Date
}

private struct ProjectTimespan {
    let project: String
    let start: Date
    let end: Date
}

private struct DayColumnData {
    let date: Date
    let visualSpans: [VisualSpan]
    let logicalSpans: [TimeSpan]
    let projects: [ProjectEntry]
    let projectTimespans: [ProjectTimespan]
}

private func buildVisualSpans(events: [ScreenEvent], cap: Date) -> [VisualSpan] {
    var spans: [VisualSpan] = []
    var kind: VisualSpan.Kind? = nil
    var spanStart: Date? = nil
    for e in events {
        switch e.kind {
        case .on:
            if kind == nil { kind = .working; spanStart = e.time }
        case .screensaverOn:
            if let s = spanStart, kind == .working { spans.append(.init(kind: .working, start: s, end: e.time)) }
            kind = .afk; spanStart = e.time
        case .screensaverOff:
            if let s = spanStart, kind == .afk { spans.append(.init(kind: .afk, start: s, end: e.time)) }
            kind = .working; spanStart = e.time
        case .off:
            if let s = spanStart, let k = kind { spans.append(.init(kind: k, start: s, end: e.time)) }
            kind = nil; spanStart = nil
        }
    }
    if let s = spanStart, let k = kind {
        spans.append(.init(kind: k, start: s, end: min(cap, Date())))
    }
    return spans
}

private func buildProjectTimespans(
    entries: [ProjectEntry],
    firstOnTime: Date?,
    spanEndTime: Date?
) -> [ProjectTimespan] {
    let visible = entries.filter { !$0.project.hasPrefix("~") }.sorted { $0.time < $1.time }
    guard !visible.isEmpty else { return [] }

    var raw: [ProjectTimespan] = []
    for (i, entry) in visible.enumerated() {
        let start = i == 0 ? (firstOnTime ?? entry.time) : visible[i - 1].time
        raw.append(.init(project: entry.project, start: start, end: entry.time))
    }
    if let last = visible.last, let end = spanEndTime, end > last.time {
        raw.append(.init(project: last.project, start: last.time, end: end))
    }

    // Merge consecutive same-project spans
    var merged: [ProjectTimespan] = []
    for span in raw {
        if let prev = merged.last, prev.project == span.project {
            merged[merged.count - 1] = .init(project: prev.project, start: prev.start, end: span.end)
        } else {
            merged.append(span)
        }
    }
    return merged.filter { $0.end > $0.start }
}

// MARK: - Window

class WeekTimelineWindow: NSWindow {

    private weak var dataStore: TimeDataStore?
    private var weekOffset = 0
    private var timelineView: TimelineContentView!
    private var dayHeaderView: DayNameHeaderView!
    private var daySummaryView: DaySummaryView!
    private var weekLabel: NSTextField!
    private var nextBtn: NSButton!
    private var scrollView: NSScrollView!

    private let topBarH: CGFloat = 48
    private let namesH: CGFloat = 28

    init(dataStore: TimeDataStore) {
        self.dataStore = dataStore
        super.init(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        title = "Week View"
        minSize = NSSize(width: 640, height: 460)
        isReleasedWhenClosed = false
        center()
        buildUI()
        reload()
    }

    private func buildUI() {
        let cv = contentView!
        let w = cv.bounds.width
        let h = cv.bounds.height

        let topBar = NSView(frame: NSRect(x: 0, y: h - topBarH, width: w, height: topBarH))
        topBar.autoresizingMask = [.width, .minYMargin]

        let prevBtn = barButton("◀", #selector(prevWeek), NSRect(x: 12, y: 9, width: 36, height: 30))
        nextBtn = barButton("▶", #selector(nextWeek), NSRect(x: w - 48, y: 9, width: 36, height: 30))
        nextBtn.autoresizingMask = .minXMargin
        nextBtn.isEnabled = false

        weekLabel = NSTextField(labelWithString: "")
        weekLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        weekLabel.alignment = .center
        weekLabel.frame = NSRect(x: 56, y: 13, width: w - 112, height: 22)
        weekLabel.autoresizingMask = .width
        topBar.addSubview(prevBtn); topBar.addSubview(nextBtn); topBar.addSubview(weekLabel)

        let sep = NSBox(frame: NSRect(x: 0, y: 0, width: w, height: 1))
        sep.boxType = .separator; sep.autoresizingMask = .width
        topBar.addSubview(sep)
        cv.addSubview(topBar)

        dayHeaderView = DayNameHeaderView(frame: NSRect(x: 0, y: h - topBarH - namesH, width: w, height: namesH))
        dayHeaderView.autoresizingMask = [.width, .minYMargin]
        cv.addSubview(dayHeaderView)

        // Summary view is placed (and sized) in layoutSummaryAndScroll(); start with a
        // sensible default so the initial layout is stable.
        let initialSummaryH: CGFloat = DaySummaryView.minHeight
        daySummaryView = DaySummaryView(frame: NSRect(
            x: 0,
            y: h - topBarH - namesH - initialSummaryH,
            width: w,
            height: initialSummaryH
        ))
        daySummaryView.autoresizingMask = [.width, .minYMargin]
        cv.addSubview(daySummaryView)

        let scrollH = h - topBarH - namesH - initialSummaryH
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: w, height: scrollH))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        timelineView = TimelineContentView(frame: NSRect(x: 0, y: 0, width: w, height: dayH))
        timelineView.autoresizingMask = .width
        timelineView.onAdd = { [weak self] date in self?.presentAddSheet(for: date) }
        timelineView.onMerge = { [weak self] date, project in self?.addEntry(date: date, project: project) }
        timelineView.onEdit = { [weak self] entry in self?.presentEditSheet(for: entry) }

        scrollView.documentView = timelineView
        cv.addSubview(scrollView)

        DispatchQueue.main.async { [weak self] in
            guard let sv = self?.scrollView else { return }
            sv.contentView.scroll(to: NSPoint(x: 0, y: yFor(min: defaultScrollHour * 60)))
            sv.reflectScrolledClipView(sv.contentView)
        }
    }

    private func barButton(_ title: String, _ action: Selector, _ frame: NSRect) -> NSButton {
        let b = NSButton(frame: frame)
        b.title = title; b.target = self; b.action = action; b.bezelStyle = .rounded
        return b
    }

    @objc private func prevWeek() { weekOffset -= 1; nextBtn.isEnabled = true; reload() }
    @objc private func nextWeek() {
        guard weekOffset < 0 else { return }
        weekOffset += 1; nextBtn.isEnabled = weekOffset < 0; reload()
    }

    func refresh() {
        reload()
    }

    private func reload() {
        guard let store = dataStore else { return }
        let data = store.loadData()
        let monday = mondayOf(weekOffset: weekOffset)
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
        let now = Date()

        let columns: [DayColumnData] = days.map { day in
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let isToday = cal.isDateInToday(day)
            let events   = data.screenEvents.filter { $0.time >= dayStart && $0.time < dayEnd }
            let projects = data.projectEntries.filter { $0.time >= dayStart && $0.time < dayEnd }.sorted { $0.time < $1.time }
            let cap      = isToday ? now : dayEnd
            let visual   = buildVisualSpans(events: events, cap: cap)
            let logical  = TimeCalculations.buildTimeSpans(from: events, projectEntries: projects, now: now)
            let firstOn  = visual.first?.start
            let spanEnd  = visual.last?.end
            let projTS   = buildProjectTimespans(entries: projects, firstOnTime: firstOn, spanEndTime: spanEnd)
            return DayColumnData(date: day, visualSpans: visual, logicalSpans: logical, projects: projects, projectTimespans: projTS)
        }

        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        let a = fmt.string(from: days[0]); fmt.dateFormat = "d, yyyy"
        weekLabel.stringValue = "\(a) – \(fmt.string(from: days[6]))"

        dayHeaderView.days = days; dayHeaderView.needsDisplay = true
        daySummaryView.update(columns: columns, now: now)
        timelineView.columns = columns; timelineView.showNow = weekOffset == 0
        timelineView.needsDisplay = true

        layoutSummaryAndScroll()
    }

    /// Resize the summary band to fit the week's tallest day, and adjust the
    /// scroll view below it to fill the remaining space.
    private func layoutSummaryAndScroll() {
        let cv = contentView!
        let w = cv.bounds.width
        let h = cv.bounds.height
        let summaryH = daySummaryView.preferredHeight()

        daySummaryView.frame = NSRect(
            x: 0,
            y: h - topBarH - namesH - summaryH,
            width: w,
            height: summaryH
        )
        scrollView.frame = NSRect(
            x: 0,
            y: 0,
            width: w,
            height: h - topBarH - namesH - summaryH
        )
        daySummaryView.needsDisplay = true
    }

    func addEntry(date: Date, project: String) {
        guard let store = dataStore else { return }
        var data = store.loadData()
        data.projectEntries.append(ProjectEntry(project: project, time: date))
        data.projectEntries.sort { $0.time < $1.time }
        store.saveData(data)
        reload()
    }

    private func updateEntry(_ entry: ProjectEntry, project: String) {
        guard let store = dataStore else { return }
        var data = store.loadData()
        guard let idx = data.projectEntries.firstIndex(where: { $0.time == entry.time && $0.project == entry.project }) else {
            return
        }
        data.projectEntries[idx] = ProjectEntry(project: project, time: entry.time)
        data.projectEntries.sort { $0.time < $1.time }
        store.saveData(data)
        reload()
    }

    private func deleteEntry(_ entry: ProjectEntry) {
        guard let store = dataStore else { return }
        var data = store.loadData()
        guard let idx = data.projectEntries.firstIndex(where: { $0.time == entry.time && $0.project == entry.project }) else {
            return
        }
        data.projectEntries.remove(at: idx)
        store.saveData(data)
        reload()
    }

    private func recentProjectNames() -> [String] {
        let entries = (dataStore?.loadData().projectEntries ?? []).reversed()
        var seen = Set<String>()
        return entries.compactMap { e -> String? in
            guard !e.project.hasPrefix("~") else { return nil }
            return seen.insert(e.project).inserted ? e.project : nil
        }.prefix(30).map { $0 }
    }

    private func presentAddSheet(for date: Date) {
        guard date <= Date() else { return }
        let fmt = DateFormatter(); fmt.timeStyle = .short
        let alert = NSAlert()
        alert.messageText = "Add entry at \(fmt.string(from: date))"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let combo = NSComboBox(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        combo.placeholderString = "Project name…"
        combo.addItems(withObjectValues: recentProjectNames())
        combo.completes = true
        alert.accessoryView = combo
        alert.window.initialFirstResponder = combo
        alert.beginSheetModal(for: self) { [weak self] resp in
            guard resp == .alertFirstButtonReturn else { return }
            let project = combo.stringValue.trimmingCharacters(in: .whitespaces)
            guard !project.isEmpty else { return }
            self?.addEntry(date: date, project: project)
        }
    }

    private func presentEditSheet(for entry: ProjectEntry) {
        guard entry.time <= Date() else { return }
        let fmt = DateFormatter(); fmt.timeStyle = .short
        let alert = NSAlert()
        alert.messageText = "Edit entry at \(fmt.string(from: entry.time))"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete")
        let combo = NSComboBox(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        combo.placeholderString = "Project name…"
        combo.addItems(withObjectValues: recentProjectNames())
        combo.completes = true
        combo.stringValue = entry.project
        alert.accessoryView = combo
        alert.window.initialFirstResponder = combo
        alert.beginSheetModal(for: self) { [weak self] resp in
            if resp == .alertThirdButtonReturn {
                self?.deleteEntry(entry)
                return
            }
            guard resp == .alertFirstButtonReturn else { return }
            let project = combo.stringValue.trimmingCharacters(in: .whitespaces)
            guard !project.isEmpty else { return }
            self?.updateEntry(entry, project: project)
        }
    }
}

// MARK: - Day name header

private class DayNameHeaderView: NSView {
    var days: [Date] = []
    private let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d"; return f }()

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); dirtyRect.fill()
        let colW = (bounds.width - timeColW) / 7
        for (i, day) in days.enumerated() {
            let x = timeColW + CGFloat(i) * colW
            let isToday = cal.isDateInToday(day)
            if isToday {
                NSColor.controlAccentColor.withAlphaComponent(0.1).setFill()
                NSRect(x: x, y: 0, width: colW, height: bounds.height).fill()
            }
            NSColor.separatorColor.withAlphaComponent(0.25).setFill()
            NSRect(x: x, y: 4, width: 0.5, height: bounds.height - 8).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: isToday ? .bold : .medium),
                .foregroundColor: isToday ? NSColor.controlAccentColor : NSColor.labelColor
            ]
            let str = NSAttributedString(string: fmt.string(from: day), attributes: attrs)
            let sz = str.size()
            str.draw(at: NSPoint(x: x + (colW - sz.width) / 2, y: (bounds.height - sz.height) / 2))
        }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
    }
}

// MARK: - Day summary (per-day project hour totals, always visible)

/// Always-visible band above the scrolling timeline that shows, per day,
/// a pill per project with the day's decimal hour total — designed to be
/// copy-pasted into a time-reporting tool.
private class DaySummaryView: NSView {
    static let minHeight: CGFloat = 72
    static let maxHeight: CGFloat = 220

    /// Per-day project totals. Parallel to the 7 day columns.
    private var dayTotals: [[ProjectDuration]] = Array(repeating: [], count: 7)
    private var dates: [Date] = []

    private let rowH: CGFloat = 19
    private let rowSpacing: CGFloat = 3
    private let topPadding: CGFloat = 6
    private let totalRowH: CGFloat = 20
    private let totalGap: CGFloat = 4
    private let sidePadding: CGFloat = 5

    override var isFlipped: Bool { true }

    func update(columns: [DayColumnData], now: Date) {
        dates = columns.map { $0.date }
        dayTotals = columns.map { col in
            let firstOn = col.visualSpans.first?.start
            return TimeCalculations.dailyProjectTotals(
                spans: col.logicalSpans,
                entries: col.projects,
                firstOnTime: firstOn,
                now: now
            ).filter { !$0.project.hasPrefix("~") }
        }
    }

    /// Height needed to show every project for the week without clipping,
    /// clamped so the timeline below never disappears.
    func preferredHeight() -> CGFloat {
        let maxRows = dayTotals.map(\.count).max() ?? 0
        guard maxRows > 0 else { return Self.minHeight }
        let projectsArea = CGFloat(maxRows) * rowH + CGFloat(max(0, maxRows - 1)) * rowSpacing
        let needed = topPadding + projectsArea + totalGap + totalRowH + 4
        return min(Self.maxHeight, max(Self.minHeight, needed))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        let colW = (bounds.width - timeColW) / 7
        guard colW > 0 else { return }

        // Left gutter label ("hours") so the column is never unexplained
        let gutterAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let gutterStr = NSAttributedString(string: "hours", attributes: gutterAttrs)
        let gsz = gutterStr.size()
        gutterStr.draw(at: NSPoint(
            x: timeColW - gsz.width - 5,
            y: topPadding + 2
        ))

        let totalRowY = bounds.height - totalRowH - 2

        for i in 0..<7 {
            let x = timeColW + CGFloat(i) * colW
            let isToday = i < dates.count && cal.isDateInToday(dates[i])

            if isToday {
                NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
                NSRect(x: x, y: 0, width: colW, height: bounds.height).fill()
            }

            // Column separator (matches the header/timeline)
            NSColor.separatorColor.withAlphaComponent(0.18).setFill()
            NSRect(x: x, y: 4, width: 0.5, height: bounds.height - 8).fill()

            let totals = i < dayTotals.count ? dayTotals[i] : []
            drawPills(in: CGRect(x: x + sidePadding,
                                 y: topPadding,
                                 width: colW - sidePadding * 2,
                                 height: totalRowY - totalGap - topPadding),
                     totals: totals)

            let grandTotal = totals.reduce(0.0) { $0 + $1.duration }
            drawDayTotal(in: CGRect(x: x, y: totalRowY, width: colW, height: totalRowH),
                        seconds: grandTotal,
                        isToday: isToday)
        }

        // Divider above total row (subtle rule tying all day totals together)
        NSColor.separatorColor.withAlphaComponent(0.25).setFill()
        NSRect(x: timeColW, y: totalRowY - 1, width: bounds.width - timeColW, height: 0.5).fill()

        // Bottom separator aligning with the scroll view
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5).fill()
    }

    private func drawPills(in rect: CGRect, totals: [ProjectDuration]) {
        guard !totals.isEmpty else { return }

        let availableH = rect.height
        // How many pills actually fit?
        var maxFit = 0
        var used: CGFloat = 0
        for _ in totals {
            let next = used + (maxFit == 0 ? rowH : rowH + rowSpacing)
            if next > availableH { break }
            used = next
            maxFit += 1
        }
        if maxFit == 0 { return }

        let overflow = totals.count - maxFit
        // If truncating, reserve the last slot for an overflow indicator.
        let pillsToShow = overflow > 0 ? max(0, maxFit - 1) : maxFit

        var y = rect.minY
        for i in 0..<pillsToShow {
            drawPill(CGRect(x: rect.minX, y: y, width: rect.width, height: rowH),
                    project: totals[i].project,
                    seconds: totals[i].duration)
            y += rowH + rowSpacing
        }

        if overflow > 0 {
            // +N more, with the summed hours — still useful for reporting
            let rest = totals.dropFirst(pillsToShow).reduce(0.0) { $0 + $1.duration }
            drawOverflowPill(
                CGRect(x: rect.minX, y: y, width: rect.width, height: rowH),
                count: totals.count - pillsToShow,
                seconds: rest
            )
        }
    }

    private func drawPill(_ rect: CGRect, project: String, seconds: TimeInterval) {
        let color = projectColor(project)
        color.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        color.withAlphaComponent(0.75).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        border.lineWidth = 0.5
        border.stroke()

        let hoursAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let hoursStr = NSAttributedString(string: decimalHours(seconds), attributes: hoursAttrs)
        let hsz = hoursStr.size()
        hoursStr.draw(at: NSPoint(
            x: rect.maxX - hsz.width - 5,
            y: rect.minY + (rect.height - hsz.height) / 2 - 0.5
        ))

        let label = project == "Break" ? "⏸ Break" : project
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.9)
        ]
        let nameStr = NSAttributedString(string: label, attributes: nameAttrs)
        let nameMaxX = rect.maxX - hsz.width - 10
        let nameRect = CGRect(x: rect.minX + 6,
                              y: rect.minY,
                              width: max(0, nameMaxX - rect.minX - 6),
                              height: rect.height)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: nameRect).setClip()
        nameStr.draw(at: NSPoint(
            x: nameRect.minX,
            y: rect.minY + (rect.height - nameStr.size().height) / 2 - 0.5
        ))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawOverflowPill(_ rect: CGRect, count: Int, seconds: TimeInterval) {
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()

        let text = "+\(count) more · \(decimalHours(seconds))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(
            x: rect.minX + (rect.width - sz.width) / 2,
            y: rect.minY + (rect.height - sz.height) / 2 - 0.5
        ))
    }

    private func drawDayTotal(in rect: CGRect, seconds: TimeInterval, isToday: Bool) {
        guard seconds > 0 else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: NSColor.quaternaryLabelColor
            ]
            let dash = NSAttributedString(string: "—", attributes: attrs)
            let sz = dash.size()
            dash.draw(at: NSPoint(
                x: rect.minX + (rect.width - sz.width) / 2,
                y: rect.minY + (rect.height - sz.height) / 2
            ))
            return
        }

        let text = decimalHours(seconds) + "h"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: isToday ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(
            x: rect.minX + (rect.width - sz.width) / 2,
            y: rect.minY + (rect.height - sz.height) / 2
        ))
    }
}

// MARK: - Timeline content view

private class TimelineContentView: NSView {
    var columns: [DayColumnData] = []
    var showNow = true
    var onAdd: ((Date) -> Void)?
    var onMerge: ((Date, String) -> Void)?
    var onEdit: ((ProjectEntry) -> Void)?

    override var isFlipped: Bool { true }
    private var colW: CGFloat { (bounds.width - timeColW) / 7 }

    // Hover state
    private var hoverDayIdx: Int = -1
    private var hoverY: CGFloat = 0
    private var hoverEntry: ProjectEntry? = nil
    private var hoverEntryLabel: String? = nil   // set when within snap distance of an entry line
    private var trackingArea: NSTrackingArea?

    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private func isSameEntry(_ lhs: ProjectEntry?, _ rhs: ProjectEntry?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs.time == rhs.time && lhs.project == rhs.project
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private func hoveredEntry(dayIndex: Int, y: CGFloat) -> ProjectEntry? {
        guard dayIndex >= 0 && dayIndex < columns.count else { return nil }
        let snapPx: CGFloat = 5
        for entry in columns[dayIndex].projects {
            guard !entry.project.hasPrefix("~") else { continue }
            let mins = minsOfDay(entry.time, relativeTo: columns[dayIndex].date)
            guard mins >= visibleStartMin && mins < visibleEndMin else { continue }
            let ey = yFor(min: mins)
            if abs(ey - y) <= snapPx {
                return entry
            }
        }
        return nil
    }

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); dirtyRect.fill()
        drawGrid()
        for (i, col) in columns.enumerated() {
            drawColumn(col, x: timeColW + CGFloat(i) * colW)
        }
        if showNow { drawNowLine() }
        if hoverDayIdx >= 0 && hoverDayIdx < columns.count {
            drawHoverOverlay()
        }
    }

    // MARK: Grid

    private func drawGrid() {
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .light),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        for hour in visibleStartHour...visibleEndHour {
            let y = yFor(min: hour * 60)
            NSColor.separatorColor.withAlphaComponent(hour % 2 == 0 ? 0.18 : 0.09).setFill()
            NSRect(x: timeColW, y: y, width: bounds.width - timeColW, height: 0.5).fill()
            let str = NSAttributedString(string: String(format: "%02d:00", hour), attributes: timeAttrs)
            let sz = str.size()
            str.draw(at: NSPoint(x: timeColW - sz.width - 5, y: y - sz.height / 2))
        }
        for halfMinute in stride(from: visibleStartMin + 30, to: visibleEndMin, by: 60) {
            let y = yFor(min: halfMinute)
            NSColor.separatorColor.withAlphaComponent(0.06).setFill()
            NSRect(x: timeColW, y: y, width: bounds.width - timeColW, height: 0.5).fill()
        }
    }

    // MARK: Day column

    private func drawColumn(_ col: DayColumnData, x: CGFloat) {
        let isToday = cal.isDateInToday(col.date)
        if isToday {
            NSColor.controlAccentColor.withAlphaComponent(0.035).setFill()
            NSRect(x: x, y: 0, width: colW, height: dayH).fill()
        }
        NSColor.separatorColor.withAlphaComponent(0.18).setFill()
        NSRect(x: x, y: 0, width: 0.5, height: dayH).fill()

        // Left strip: screen activity (green = working, blue = AFK)
        for span in col.visualSpans {
            let s = max(minsOfDay(span.start, relativeTo: col.date), visibleStartMin)
            let e = min(minsOfDay(span.end, relativeTo: col.date), visibleEndMin)
            guard s < e else { continue }
            let y1 = yFor(min: s); let y2 = yFor(min: e)
            let stripRect = CGRect(x: x + 1, y: y1, width: activityStripW - 1, height: y2 - y1)
            let stripColor: NSColor = span.kind == .working
                ? NSColor(red: 0.40, green: 0.78, blue: 0.44, alpha: 0.75)
                : NSColor(red: 0.35, green: 0.62, blue: 0.92, alpha: 0.75)
            stripColor.setFill()
            NSBezierPath(roundedRect: stripRect, xRadius: 2, yRadius: 2).fill()
        }

        // Project timespans (rest of column width)
        let projX = x + activityStripW + 2
        let projW = colW - activityStripW - 3

        for span in col.projectTimespans {
            let s = max(minsOfDay(span.start, relativeTo: col.date), visibleStartMin)
            let e = min(minsOfDay(span.end, relativeTo: col.date), visibleEndMin)
            guard s < e else { continue }
            let y1 = yFor(min: s); let y2 = yFor(min: e)
            let h = y2 - y1
            let rect = CGRect(x: projX, y: y1, width: projW, height: h)

            let base = projectColor(span.project)
            base.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            base.withAlphaComponent(0.75).setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            border.lineWidth = 0.6; border.stroke()

            // Project label inside span if tall enough
            if h >= 18 {
                let label = span.project == "Break" ? "⏸ Break" : span.project
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(0.75)
                ]
                let str = NSAttributedString(string: label, attributes: labelAttrs)
                let textY = y1 + (h - str.size().height) / 2
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 1), xRadius: 2, yRadius: 2).setClip()
                str.draw(at: NSPoint(x: projX + 5, y: textY))
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        // Entry lines — thin 1px horizontal rules (no labels; hover reveals text)
        for entry in col.projects {
            guard !entry.project.hasPrefix("~") else { continue }
            let mins = minsOfDay(entry.time, relativeTo: col.date)
            guard mins >= visibleStartMin && mins < visibleEndMin else { continue }
            let y = yFor(min: mins)
            NSColor.labelColor.withAlphaComponent(0.20).setFill()
            NSRect(x: x + 1, y: y - 0.5, width: colW - 2, height: 1).fill()
        }
    }

    // MARK: Now line

    private func drawNowLine() {
        let mins = minsOfDay(Date())
        guard mins >= visibleStartMin && mins < visibleEndMin else { return }
        let y = yFor(min: mins)
        NSColor.systemRed.withAlphaComponent(0.7).setFill()
        NSBezierPath(ovalIn: CGRect(x: timeColW - 8, y: y - 4, width: 8, height: 8)).fill()
        NSRect(x: timeColW, y: y - 0.75, width: bounds.width - timeColW, height: 1.5).fill()
    }

    // MARK: Hover overlay

    private func drawHoverOverlay() {
        let x = timeColW + CGFloat(hoverDayIdx) * colW
        let mins = visibleStartMin + Int(hoverY / pxPerMin)
        guard mins >= visibleStartMin && mins < visibleEndMin else { return }

        // Dashed time line across the hovered column only
        NSGraphicsContext.saveGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.30).setStroke()
        let path = NSBezierPath()
        path.setLineDash([3, 3], count: 2, phase: 0)
        path.lineWidth = 0.75
        path.move(to: NSPoint(x: x, y: hoverY))
        path.line(to: NSPoint(x: x + colW, y: hoverY))
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Time label in left margin at hover Y
        let timeStr = String(format: "%02d:%02d", mins / 60, mins % 60)
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.65)
        ]
        let timeAS = NSAttributedString(string: timeStr, attributes: timeAttrs)
        let tsz = timeAS.size()
        // Small background to cover the existing hour label
        let bgRect = CGRect(x: timeColW - tsz.width - 8, y: hoverY - tsz.height / 2 - 1,
                            width: tsz.width + 6, height: tsz.height + 2)
        NSColor.controlBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 2, yRadius: 2).fill()
        timeAS.draw(at: NSPoint(x: timeColW - tsz.width - 5, y: hoverY - tsz.height / 2))

        // Entry tooltip
        if let label = hoverEntryLabel {
            drawEntryTooltip(label, nearX: x + colW / 2, y: hoverY)
        }
    }

    private func drawEntryTooltip(_ text: String, nearX cx: CGFloat, y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        let pad: CGFloat = 7
        let bw = sz.width + pad * 2
        let bh = sz.height + pad
        var bx = cx - bw / 2
        var by = y - bh - 6
        // Clamp to view bounds
        bx = max(timeColW + 2, min(bx, bounds.width - bw - 2))
        if by < 0 { by = y + 6 }
        let box = CGRect(x: bx, y: by, width: bw, height: bh)
        NSColor.windowBackgroundColor.setFill()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 4
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        border.lineWidth = 0.5; border.stroke()
        str.draw(at: NSPoint(x: bx + pad, y: by + pad / 2))
    }

    // MARK: Tracking area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds,
                                      options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
                                      owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let newDay = loc.x > timeColW ? min(Int((loc.x - timeColW) / colW), columns.count - 1) : -1
        let newY = loc.y

        // Check proximity to entry lines
        let entry = hoveredEntry(dayIndex: newDay, y: newY)
        var entryLabel: String? = nil
        if let entry {
            let name = entry.project == "Break" ? "⏸ Break" : entry.project
            entryLabel = "\(timeFmt.string(from: entry.time))  \(name)"
        }

        if hoverDayIdx != newDay || abs(hoverY - newY) > 0.5 || hoverEntryLabel != entryLabel || !isSameEntry(hoverEntry, entry) {
            hoverDayIdx = newDay
            hoverY = newY
            hoverEntry = entry
            hoverEntryLabel = entryLabel
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverDayIdx = -1
        hoverEntry = nil
        hoverEntryLabel = nil
        needsDisplay = true
    }

    // MARK: Mouse clicks

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard let (date, colIdx) = resolveClick(loc), date <= Date() else { return }
        if let entry = hoveredEntry(dayIndex: colIdx, y: loc.y) {
            onEdit?(entry)
            return
        }
        onAdd?(date)
    }

    override func rightMouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard let (date, colIdx) = resolveClick(loc), date <= Date() else { return }

        let col = columns[colIdx]
        let clickedMins = minsOfDay(date)
        let sorted = col.logicalSpans.sorted { $0.start < $1.start }

        for i in 0..<(sorted.count - 1) {
            let gapStart = sorted[i].end ?? Date()
            let gapEnd   = sorted[i + 1].start
            let gsm = minsOfDay(gapStart); let gem = minsOfDay(gapEnd)
            guard gsm < gem, clickedMins > gsm, clickedMins < gem else { continue }

            let suggestedProject = col.projects
                .filter { !$0.project.hasPrefix("~") && $0.time <= gapStart }
                .last?.project

            let menu = NSMenu()
            let hdr = NSMenuItem(title: "Gap: fill to merge spans", action: nil, keyEquivalent: "")
            hdr.isEnabled = false; menu.addItem(hdr); menu.addItem(.separator())

            if let proj = suggestedProject {
                let item = NSMenuItem(title: "Fill with \"\(proj)\"", action: nil, keyEquivalent: "")
                item.representedObject = ["date": gapStart, "project": proj] as NSDictionary
                item.target = self; item.action = #selector(doFill(_:))
                menu.addItem(item)
            }

            let custom = NSMenuItem(title: "Fill with…", action: nil, keyEquivalent: "")
            custom.representedObject = ["date": gapStart] as NSDictionary
            custom.target = self; custom.action = #selector(doFillCustom(_:))
            menu.addItem(custom)

            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        onAdd?(date)
    }

    @objc private func doFill(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? [String: Any],
              let date = dict["date"] as? Date,
              let project = dict["project"] as? String else { return }
        onMerge?(date, project)
    }

    @objc private func doFillCustom(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? [String: Any],
              let date = dict["date"] as? Date else { return }
        onAdd?(date)
    }

    private func resolveClick(_ loc: CGPoint) -> (Date, Int)? {
        let idx = Int((loc.x - timeColW) / colW)
        guard idx >= 0, idx < columns.count else { return nil }
        let mins = visibleStartMin + Int(loc.y / pxPerMin)
        guard mins >= visibleStartMin, mins < visibleEndMin else { return nil }
        var comps = cal.dateComponents([.year, .month, .day], from: columns[idx].date)
        comps.hour = mins / 60; comps.minute = mins % 60; comps.second = 0
        guard let date = cal.date(from: comps) else { return nil }
        return (date, idx)
    }
}
