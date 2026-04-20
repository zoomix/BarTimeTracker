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

    /// Merge raw screen-on intervals into logical work spans.
    /// Gaps < `mergeThreshold` are always merged.
    /// Larger gaps are merged if the first project entry after the gap is not a Break
    /// (i.e. the user was doing tracked work during the gap, e.g. a meeting).
    public static func buildTimeSpans(
        from events: [ScreenEvent],
        projectEntries: [ProjectEntry] = [],
        mergeThreshold: TimeInterval = 3 * 60,
        now: Date
    ) -> [TimeSpan] {
        var rawSpans: [(start: Date, end: Date)] = []
        var spanStart: Date?

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
        let activeStart = spanStart

        func gapCoveredByWork(gapEnd: Date) -> Bool {
            guard let first = projectEntries.first(where: { $0.time >= gapEnd }) else { return false }
            return first.project != "Break"
        }

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
