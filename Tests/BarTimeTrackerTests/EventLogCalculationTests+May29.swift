import XCTest
@testable import BarTimeTrackerCore

// May 29 — full workday: apps.qamcom.se, Librixer, Stena sälj, decarb. Morning break chaos.
// Expected: 15 spans (all closed), 8h 36m 19s worked.

extension EventLogCalculationTests {

    private static let now_may29 = EventLogCalculationTests().date("2026-05-29 23:59:59")

    private static let csv_may29 = """
    date,time,event_type,event_source,project_name
    2026-05-29,06:35:00,on,computer,-
    2026-05-29,06:35:00,screensaverOff,computer,-
    2026-05-29,06:50:00,entry,user,Librixer
    2026-05-29,07:05:00,entry,user,Librixer
    2026-05-29,07:05:00,screensaverOn,computer,-
    2026-05-29,07:20:00,screensaverOff,computer,-
    2026-05-29,07:25:00,entry,user,Break
    2026-05-29,07:25:00,off,computer,-
    2026-05-29,07:40:00,on,computer,-
    2026-05-29,07:40:00,off,computer,-
    2026-05-29,07:55:00,on,computer,-
    2026-05-29,08:00:00,entry,user,Break
    2026-05-29,08:00:00,off,computer,-
    2026-05-29,08:00:00,on,computer,-
    2026-05-29,08:15:00,entry,user,Break
    2026-05-29,08:15:00,screensaverOn,computer,-
    2026-05-29,08:25:00,screensaverOff,computer,-
    2026-05-29,08:25:00,entry,user,apps.qamcom.se
    2026-05-29,08:40:00,entry,user,apps.qamcom.se
    2026-05-29,08:55:00,entry,user,apps.qamcom.se
    2026-05-29,09:20:00,entry,user,Librixer
    2026-05-29,09:35:00,entry,user,Librixer
    2026-05-29,09:50:00,entry,user,Librixer
    2026-05-29,10:05:00,entry,user,Librixer
    2026-05-29,10:20:00,entry,user,Librixer
    2026-05-29,10:35:00,entry,user,decarb
    2026-05-29,10:50:00,off,computer,-
    2026-05-29,11:05:00,on,computer,-
    2026-05-29,11:25:00,entry,user,Stena sälj
    2026-05-29,11:40:00,entry,user,Stena sälj
    2026-05-29,11:50:00,entry,user,Stena sälj
    2026-05-29,11:50:00,screensaverOn,computer,-
    2026-05-29,11:55:00,off,computer,-
    2026-05-29,11:55:00,on,computer,-
    2026-05-29,11:55:00,screensaverOff,computer,-
    2026-05-29,12:00:00,entry,user,Stena sälj
    2026-05-29,12:00:00,screensaverOn,computer,-
    2026-05-29,12:00:00,screensaverOff,computer,-
    2026-05-29,12:15:00,entry,user,Stena sälj
    2026-05-29,12:25:00,entry,user,Stena sälj
    2026-05-29,12:25:00,screensaverOn,computer,-
    2026-05-29,12:25:00,screensaverOff,computer,-
    2026-05-29,12:30:00,entry,user,Stena sälj
    2026-05-29,12:30:00,screensaverOn,computer,-
    2026-05-29,12:30:00,screensaverOff,computer,-
    2026-05-29,12:40:00,entry,user,Stena sälj
    2026-05-29,12:40:00,screensaverOn,computer,-
    2026-05-29,12:45:00,off,computer,-
    2026-05-29,13:00:00,on,computer,-
    2026-05-29,13:00:00,screensaverOff,computer,-
    2026-05-29,13:20:00,on,computer,-
    2026-05-29,13:35:00,entry,user,Librixer
    2026-05-29,13:50:00,entry,user,apps.qamcom.se
    2026-05-29,14:05:00,entry,user,apps.qamcom.se
    2026-05-29,14:20:00,entry,user,apps.qamcom.se
    2026-05-29,14:35:00,entry,user,apps.qamcom.se
    2026-05-29,14:45:00,entry,user,apps.qamcom.se
    2026-05-29,14:45:00,screensaverOn,computer,-
    2026-05-29,14:45:00,screensaverOff,computer,-
    2026-05-29,15:05:00,entry,user,apps.qamcom.se
    2026-05-29,15:20:00,entry,user,apps.qamcom.se
    2026-05-29,15:35:00,entry,user,apps.qamcom.se
    2026-05-29,15:50:00,entry,user,apps.qamcom.se
    2026-05-29,16:05:00,entry,user,apps.qamcom.se
    2026-05-29,16:20:00,entry,user,apps.qamcom.se
    2026-05-29,16:40:00,off,computer,-
    2026-05-29,22:35:00,on,computer,-
    2026-05-29,22:35:00,off,computer,-
    2026-05-29,23:30:00,on,computer,-
    2026-05-29,23:30:00,off,computer,-
    2026-05-29,23:30:00,entry,user,Break
    """

    func test_may29_spans() {
        let result = analyze(csv: Self.csv_may29, now: Self.now_may29)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = Self.tz
        let actual = result.spans.map { s in
            let start = fmt.string(from: s.start)
            let end = s.end.map { fmt.string(from: $0) } ?? "?"
            let durations = TimeCalculations.projectDurations(
                entries: result.entries, firstOnTime: result.firstOn,
                spanStart: s.start, spanEnd: s.end ?? Self.now_may29
            )
            let project = durations.first?.project ?? "-"
            return "\(start) - \(end)  \(project)"
        }.joined(separator: "\n")
        XCTAssertEqual(actual, """
            06:35 - 07:05  Librixer
            07:05 - 08:15  Break
            08:15 - 08:55  apps.qamcom.se
            08:55 - 10:20  Librixer
            10:20 - 10:50  decarb
            10:50 - 12:45  Stena sälj
            12:45 - 13:35  Librixer
            13:35 - 16:40  apps.qamcom.se
            16:40 - 23:30  Break
            """.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func test_may29_allClosed() {
        XCTAssertTrue(analyze(csv: Self.csv_may29, now: Self.now_may29).spans.allSatisfy { !$0.isActive })
    }

    func test_may29_workedTime() {
        // 8h 36m 19s
        XCTAssertDuration(analyze(csv: Self.csv_may29, now: Self.now_may29).worked, 30979)
    }

    func test_may29_projectDurations() {
        let projects = analyze(csv: Self.csv_may29, now: Self.now_may29).projects
        XCTAssertDuration(projects["apps.qamcom.se"] ?? 0, 12341)
        XCTAssertDuration(projects["Librixer"] ?? 0, 9092)
        XCTAssertDuration(projects["Stena sälj"] ?? 0, 8632)
        XCTAssertDuration(projects["decarb"] ?? 0, 914)
        XCTAssertNil(projects["Break"])
    }
}
