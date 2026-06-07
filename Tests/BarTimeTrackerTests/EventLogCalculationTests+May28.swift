import XCTest
@testable import BarTimeTrackerCore

// May 28 — short afternoon session: Librixer only, then a break-only evening span.
// Expected: 2 spans (both closed), 54m 38s worked, Librixer 54m 38s.

extension EventLogCalculationTests {

    private static let now_may28 = EventLogCalculationTests().date("2026-05-28 20:40:27")

    private static let csv_may28 = """
    date,time,event_type,event_source,project_name
    2026-05-28,16:00:00,on,computer,-
    2026-05-28,16:20:00,entry,user,Librixer
    2026-05-28,16:30:00,entry,user,Librixer
    2026-05-28,16:50:00,entry,user,Librixer
    2026-05-28,17:00:00,entry,user,Librixer
    2026-05-28,17:00:00,screensaverOn,computer,-
    2026-05-28,18:00:00,off,computer,-
    2026-05-28,19:40:00,on,computer,-
    2026-05-28,19:40:00,screensaverOff,computer,-
    2026-05-28,19:45:00,entry,user,Break
    2026-05-28,19:45:00,screensaverOn,computer,-
    2026-05-28,20:40:00,off,computer,-
    """

    func test_may28_spanCount() {
        XCTAssertEqual(analyze(csv: Self.csv_may28, now: Self.now_may28).spans.count, 2)
    }

    func test_may28_spans() {
        let result = analyze(csv: Self.csv_may28, now: Self.now_may28)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = Self.tz
        let actual = result.spans.map { s in
            let start = fmt.string(from: s.start)
            let end = s.end.map { fmt.string(from: $0) } ?? "?"
            let durations = TimeCalculations.projectDurations(
                entries: result.entries, firstOnTime: result.firstOn,
                spanStart: s.start, spanEnd: s.end ?? Self.now_may28
            )
            let project = durations.first?.project ?? "-"
            return "\(start) - \(end)  \(project)"
        }.joined(separator: "\n")
        XCTAssertEqual(actual, """
            16:00 - 17:00  Librixer
            17:00 - 20:40  Break
            """.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func test_may28_allClosed() {
        XCTAssertTrue(analyze(csv: Self.csv_may28, now: Self.now_may28).spans.allSatisfy { !$0.isActive })
    }

    func test_may28_workedTime() {
        XCTAssertDuration(analyze(csv: Self.csv_may28, now: Self.now_may28).worked, 3600)
    }

    func test_may28_projectDurations() {
        let projects = analyze(csv: Self.csv_may28, now: Self.now_may28).projects
        XCTAssertDuration(projects["Librixer"] ?? 0, 3600)
        XCTAssertNil(projects["Break"])
    }
}
