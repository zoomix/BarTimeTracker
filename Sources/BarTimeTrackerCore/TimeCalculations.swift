import Foundation

// MARK: - Data types

public struct ScreenEvent: Codable {
    public enum Kind: String, Codable {
        case on, off, screensaverOn, screensaverOff
        public var isAway: Bool { self == .off || self == .screensaverOn }
    }
    public let kind: Kind
    public let time: Date

    public init(kind: Kind, time: Date) {
        self.kind = kind
        self.time = time
    }
}

public struct ProjectEntry: Codable {
    public let project: String
    public let time: Date

    public init(project: String, time: Date) {
        self.project = project
        self.time = time
    }
}

public struct AppData: Codable {
    public var screenEvents: [ScreenEvent]
    public var projectEntries: [ProjectEntry]

    public init(screenEvents: [ScreenEvent] = [], projectEntries: [ProjectEntry] = []) {
        self.screenEvents = screenEvents
        self.projectEntries = projectEntries
    }
}

public struct TimeSpan {
    public let start: Date
    public let end: Date?   // nil = still active
    public let isActive: Bool

    public init(start: Date, end: Date?, isActive: Bool) {
        self.start = start
        self.end = end
        self.isActive = isActive
    }
}

public struct ProjectDuration {
    public let project: String
    public let duration: TimeInterval
}

// MARK: - Calculations

public enum TimeCalculations {

    /// Build logical work spans driven by project-entry transitions.
    /// Each run of consecutive same-project entries forms one span.
    /// Span start = end of previous span (or first screen-on for the first span).
    /// Span end = first away event (off/screensaverOn) at or after the last entry of the
    /// group but before the next group starts; falls back to the last entry time if none.
    /// The last span is active when no away event follows its last entry.
    public static func buildTimeSpans(
        from events: [ScreenEvent],
        projectEntries: [ProjectEntry] = [],
        mergeThreshold: TimeInterval = 3 * 60,
        now: Date
    ) -> [TimeSpan] {
        guard !projectEntries.isEmpty else { return [] }

        let firstOn = events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time

        // Group consecutive same-project entries into (project, firstTime, lastTime)
        var groupProjects: [String] = []
        var groupFirsts:   [Date]   = []
        var groupLasts:    [Date]   = []
        for entry in projectEntries {
            if groupProjects.isEmpty || groupProjects[groupProjects.count - 1] != entry.project {
                groupProjects.append(entry.project)
                groupFirsts.append(entry.time)
                groupLasts.append(entry.time)
            } else {
                groupLasts[groupLasts.count - 1] = entry.time
            }
        }

        let awayEvents  = events.filter { $0.kind == .off || $0.kind == .screensaverOn }
        let hardOffs    = events.filter { $0.kind == .off }

        // First away event (screensaverOn or off) in [from, before)
        func firstAway(from: Date, before: Date?) -> ScreenEvent? {
            awayEvents.first(where: { e in
                e.time >= from && (before == nil || e.time < before!)
            })
        }

        // First hard off in [from, before)
        func firstHardOff(from: Date, before: Date?) -> Date? {
            hardOffs.first(where: { e in
                e.time >= from && (before == nil || e.time < before!)
            })?.time
        }

        // Span end for non-last groups: if screensaverOn is first, promote to a subsequent
        // hard off when it arrives quickly (< 30 min) and still before the next group.
        let screensaverOffThreshold: TimeInterval = 30 * 60

        var spans: [TimeSpan] = []
        var spanStart = firstOn ?? groupFirsts[0]

        for i in 0..<groupProjects.count {
            let last      = groupLasts[i]
            let nextFirst: Date? = i + 1 < groupProjects.count ? groupFirsts[i + 1] : nil
            let isLast    = nextFirst == nil

            if isLast {
                // For the last group only hard off counts; screensaverOn means still active.
                if let hardOff = firstHardOff(from: last, before: nil) {
                    spans.append(TimeSpan(start: spanStart, end: hardOff, isActive: false))
                } else {
                    spans.append(TimeSpan(start: spanStart, end: nil, isActive: true))
                }
            } else {
                if let away = firstAway(from: last, before: nextFirst) {
                    var spanEnd = away.time
                    if away.kind == .screensaverOn,
                       let hardOff = firstHardOff(from: away.time, before: nextFirst),
                       hardOff.timeIntervalSince(away.time) <= screensaverOffThreshold {
                        spanEnd = hardOff
                    }
                    spans.append(TimeSpan(start: spanStart, end: spanEnd, isActive: false))
                    spanStart = spanEnd
                } else {
                    spans.append(TimeSpan(start: spanStart, end: last, isActive: false))
                    spanStart = last
                }
            }
        }

        return spans
    }

    /// Time attributed to each project within [spanStart, spanEnd].
    /// Entry[i] claims [entry[i-1].time, entry[i].time], intersected with the span.
    /// The last entry additionally claims forward to spanEnd.
    /// Results with < 30 s are dropped (noise).
    public static func projectDurations(
        entries: [ProjectEntry],
        firstOnTime: Date?,
        spanStart: Date,
        spanEnd: Date
    ) -> [ProjectDuration] {
        guard !entries.isEmpty else { return [] }

        let dayStart = firstOnTime ?? entries[0].time
        var durations: [String: TimeInterval] = [:]

        for i in 0..<entries.count {
            let entry = entries[i]
            let claimStart = i == 0 ? dayStart : entries[i - 1].time
            let intStart = max(claimStart, spanStart)
            let intEnd   = min(entry.time, spanEnd)
            if intEnd > intStart {
                durations[entry.project, default: 0] += intEnd.timeIntervalSince(intStart)
            }
        }

        if let last = entries.last {
            let intStart = max(last.time, spanStart)
            if spanEnd > intStart {
                durations[last.project, default: 0] += spanEnd.timeIntervalSince(intStart)
            }
        }

        return durations
            .map { ProjectDuration(project: $0.key, duration: $0.value) }
            .filter { $0.duration >= 30 }
            .sorted { $0.duration > $1.duration }
    }

    /// Worked time = span duration minus break-attributed time within each span.
    public static func workedTime(
        spans: [TimeSpan],
        entries: [ProjectEntry],
        firstOnTime: Date?,
        now: Date
    ) -> TimeInterval {
        spans.reduce(0.0) { total, span in
            let spanEnd = span.end ?? now
            let d = projectDurations(entries: entries, firstOnTime: firstOnTime,
                                     spanStart: span.start, spanEnd: spanEnd)
            let breakDur = d.first(where: { $0.project == "Break" })?.duration ?? 0
            return total + max(0, spanEnd.timeIntervalSince(span.start) - breakDur)
        }
    }

    /// Sum project durations across all spans for a day.
    /// Excludes Break and ~system entries.
    public static func dailyProjectTotals(
        spans: [TimeSpan],
        entries: [ProjectEntry],
        firstOnTime: Date?,
        now: Date
    ) -> [ProjectDuration] {
        var totals: [String: TimeInterval] = [:]
        for span in spans {
            let spanEnd = span.end ?? now
            for d in projectDurations(entries: entries, firstOnTime: firstOnTime,
                                       spanStart: span.start, spanEnd: spanEnd)
            where d.project != "Break" {
                totals[d.project, default: 0] += d.duration
            }
        }
        return totals
            .map { ProjectDuration(project: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
    }

    public static func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
