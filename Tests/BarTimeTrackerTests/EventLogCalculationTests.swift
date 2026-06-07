import XCTest
import Foundation
@testable import BarTimeTrackerCore

// Tests use real events.csv data (snapshots embedded per-day in companion files).
// Expected values computed by running the current algorithm against the CSV.
// To update: edit the expected values then fix the algorithm until tests pass.
//
// Timezone: Europe/Stockholm (CEST = UTC+2 in summer)
// "now" per day: last screen event on that day + 1s (makes closed days fully deterministic)

class EventLogCalculationTests: XCTestCase {

    static let tz = TimeZone(identifier: "Europe/Stockholm")!

    func XCTAssertDuration(
        _ actual: TimeInterval, _ expected: TimeInterval,
        tolerance: TimeInterval = 60,
        _ label: String = "",
        file: StaticString = #file, line: UInt = #line
    ) {
        XCTAssertEqual(actual, expected, accuracy: tolerance, label, file: file, line: line)
    }

    func analyze(csv: String, now: Date) -> (
        spans: [TimeSpan], worked: TimeInterval, projects: [String: TimeInterval],
        entries: [ProjectEntry], firstOn: Date?
    ) {
        let (screenEvents, projectEntries) = EventLogParser.parse(csv: csv, timeZone: Self.tz)
        let entries = projectEntries.filter { !$0.project.hasPrefix("~") }
        let firstOn = screenEvents.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let spans = TimeCalculations.buildTimeSpans(from: screenEvents, projectEntries: entries, now: now)
        let worked = TimeCalculations.workedTime(spans: spans, entries: entries, firstOnTime: firstOn, now: now)
        let totals = TimeCalculations.dailyProjectTotals(spans: spans, entries: entries, firstOnTime: firstOn, now: now)
        return (spans, worked, Dictionary(uniqueKeysWithValues: totals.map { ($0.project, $0.duration) }), entries, firstOn)
    }

    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = Self.tz
        return f.date(from: s)!
    }
}
