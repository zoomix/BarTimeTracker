import XCTest
import Foundation
@testable import BarTimeTrackerCore

final class LogoutTests: XCTestCase {
    private typealias T = TimeCalculatorTests

    func testNothingCountsAfterLogout() {
        let events = [T.se(.on, "2026-10-08T07:00:00Z"), T.se(.on, "2026-10-08T20:00:00Z")]
        let entries = [T.pe("Dev", "2026-10-08T07:00:00Z"), T.pe("~logged out~", "2026-10-08T16:00:00Z"), T.pe("Dev", "2026-10-08T18:00:00Z")]
        let day = TimeCalculations.applyLogouts(events: events, entries: entries)
        let now = T.d("2026-10-08T23:00:00Z")
        let spans = TimeCalculations.buildTimeSpans(from: day.events, projectEntries: day.entries, now: now)
        let worked = TimeCalculations.workedTime(spans: spans, entries: day.entries, firstOnTime: day.events.first?.time, now: now)
        XCTAssertEqual(worked, 9 * 3600, accuracy: 1)
    }

    func testResumeRestartsCounting() {
        let events = [T.se(.on, "2026-10-08T07:00:00Z")]
        let entries = [T.pe("Dev", "2026-10-08T07:00:00Z"), T.pe("~logged out~", "2026-10-08T16:00:00Z"), T.pe("~resumed~", "2026-10-08T20:00:00Z"), T.pe("Dev", "2026-10-08T20:00:05Z")]
        let day = TimeCalculations.applyLogouts(events: events, entries: entries)
        let now = T.d("2026-10-08T21:00:00Z")
        let spans = TimeCalculations.buildTimeSpans(from: day.events, projectEntries: day.entries, now: now)
        let worked = TimeCalculations.workedTime(spans: spans, entries: day.entries, firstOnTime: day.events.first?.time, now: now)
        XCTAssertEqual(worked, 10 * 3600, accuracy: 6)
    }
}
