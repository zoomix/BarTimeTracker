import XCTest
import Foundation
@testable import BarTimeTrackerCore

// Tests are based on a snapshot of events.json captured 2026-04-20.
// Each day uses a fixed "now" = last screen event of that day + 1s so results are deterministic.
// Tolerance: ±1s on durations (rounding).

final class TimeCalculatorTests: XCTestCase {

    // MARK: - Helpers

    private static let iso = ISO8601DateFormatter()

    static func d(_ s: String) -> Date {
        iso.date(from: s)!
    }

    static func se(_ kind: ScreenEvent.Kind, _ s: String) -> ScreenEvent {
        ScreenEvent(kind: kind, time: d(s))
    }

    static func pe(_ project: String, _ s: String) -> ProjectEntry {
        ProjectEntry(project: project, time: d(s))
    }

    private func XCTAssertDuration(
        _ actual: TimeInterval,
        _ expected: TimeInterval,
        tolerance: TimeInterval = 1,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual, expected, accuracy: tolerance, message, file: file, line: line)
    }

    // MARK: - April 15  (now = 21:18:47 UTC)
    // Long Stena decarb day, brief Interplanetary Sälj, break-only evening.
    // Expected: 4 spans, 8h 43m worked, Stena decarb 8h 28m, Interplanetary Sälj 15m.

    private var apr15Events: [ScreenEvent] { [
        Self.se(.on,            "2026-04-15T05:35:15Z"),
        Self.se(.off,           "2026-04-15T10:36:09Z"),
        Self.se(.on,            "2026-04-15T12:13:16Z"),
        Self.se(.screensaverOn, "2026-04-15T15:15:04Z"),
        Self.se(.screensaverOff,"2026-04-15T15:24:49Z"),
        Self.se(.on,            "2026-04-15T15:28:17Z"),
        Self.se(.screensaverOn, "2026-04-15T15:28:55Z"),
        Self.se(.screensaverOff,"2026-04-15T15:29:04Z"),
        Self.se(.screensaverOn, "2026-04-15T15:34:55Z"),
        Self.se(.off,           "2026-04-15T16:30:06Z"),
        Self.se(.on,            "2026-04-15T18:25:02Z"),
        Self.se(.off,           "2026-04-15T18:25:35Z"),
        Self.se(.on,            "2026-04-15T18:25:47Z"),
        Self.se(.off,           "2026-04-15T18:26:18Z"),
        Self.se(.on,            "2026-04-15T20:13:11Z"),
        Self.se(.screensaverOff,"2026-04-15T20:13:19Z"),
        Self.se(.on,            "2026-04-15T20:40:49Z"),
        Self.se(.off,           "2026-04-15T21:18:46Z"),
    ] }

    private var apr15Projects: [ProjectEntry] { [
        Self.pe("Stena decarb",       "2026-04-15T09:20:30Z"),
        Self.pe("Stena decarb",       "2026-04-15T09:35:58Z"),
        Self.pe("Stena decarb",       "2026-04-15T12:42:24Z"),
        Self.pe("Stena decarb",       "2026-04-15T12:50:52Z"),
        Self.pe("Stena decarb",       "2026-04-15T13:48:02Z"),
        Self.pe("Interplanetary Sälj","2026-04-15T14:03:20Z"),
        Self.pe("Stena decarb",       "2026-04-15T14:18:35Z"),
        Self.pe("Break",              "2026-04-15T20:13:27Z"),
        Self.pe("Break",              "2026-04-15T20:37:18Z"),
    ] }

    private var apr15Now: Date { Self.d("2026-04-15T21:18:47Z") }

    func test_apr15_spanCount() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr15Events, projectEntries: apr15Projects, now: apr15Now)
        XCTAssertEqual(spans.count, 4)
    }

    func test_apr15_allSpansClosed() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr15Events, projectEntries: apr15Projects, now: apr15Now)
        XCTAssertTrue(spans.allSatisfy { !$0.isActive })
    }

    func test_apr15_workedTime() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr15Events, projectEntries: apr15Projects, now: apr15Now)
        let firstOn = apr15Events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let worked = TimeCalculations.workedTime(spans: spans, entries: apr15Projects,
                                                 firstOnTime: firstOn, now: apr15Now)
        // 8h 43m 20s
        XCTAssertDuration(worked, 31400)
    }

    func test_apr15_projectDurations() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr15Events, projectEntries: apr15Projects, now: apr15Now)
        let firstOn = apr15Events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let totals = TimeCalculations.dailyProjectTotals(spans: spans, entries: apr15Projects,
                                                         firstOnTime: firstOn, now: apr15Now)
        let byName = Dictionary(uniqueKeysWithValues: totals.map { ($0.project, $0.duration) })

        // Stena decarb: 8h 28m 2s
        XCTAssertDuration(byName["Stena decarb"] ?? 0, 30482)
        // Interplanetary Sälj: 15m 18s
        XCTAssertDuration(byName["Interplanetary Sälj"] ?? 0, 918)
        // Break must not appear in project totals
        XCTAssertNil(byName["Break"])
    }

    // MARK: - April 16  (now = 20:40:46 UTC)
    // Mix of DGX Spark, Stena decarb, apps.qamcom.se with several breaks.
    // Expected: 5 spans, 7h 18m worked.

    private var apr16Events: [ScreenEvent] { [
        Self.se(.on,            "2026-04-16T06:05:42Z"),
        Self.se(.screensaverOn, "2026-04-16T06:47:35Z"),
        Self.se(.screensaverOff,"2026-04-16T07:04:21Z"),
        Self.se(.on,            "2026-04-16T07:11:21Z"),
        Self.se(.screensaverOn, "2026-04-16T10:00:48Z"),
        Self.se(.off,           "2026-04-16T10:55:58Z"),
        Self.se(.on,            "2026-04-16T11:12:11Z"),
        Self.se(.screensaverOff,"2026-04-16T11:12:15Z"),
        Self.se(.off,           "2026-04-16T12:19:47Z"),
        Self.se(.on,            "2026-04-16T12:20:36Z"),
        Self.se(.off,           "2026-04-16T12:21:06Z"),
        Self.se(.on,            "2026-04-16T12:21:47Z"),
        Self.se(.off,           "2026-04-16T12:28:22Z"),
        Self.se(.on,            "2026-04-16T12:28:29Z"),
        Self.se(.off,           "2026-04-16T12:28:31Z"),
        Self.se(.on,            "2026-04-16T12:29:06Z"),
        Self.se(.off,           "2026-04-16T13:43:47Z"),
        Self.se(.on,            "2026-04-16T14:18:08Z"),
        Self.se(.off,           "2026-04-16T14:18:38Z"),
        Self.se(.on,            "2026-04-16T14:18:44Z"),
        Self.se(.screensaverOn, "2026-04-16T14:42:14Z"),
        Self.se(.off,           "2026-04-16T14:47:24Z"),
        Self.se(.on,            "2026-04-16T16:22:10Z"),
        Self.se(.screensaverOff,"2026-04-16T16:22:17Z"),
        Self.se(.screensaverOn, "2026-04-16T17:44:21Z"),
        Self.se(.off,           "2026-04-16T18:39:32Z"),
        Self.se(.on,            "2026-04-16T19:36:10Z"),
        Self.se(.screensaverOff,"2026-04-16T19:36:11Z"),
        Self.se(.off,           "2026-04-16T20:40:45Z"),
    ] }

    private var apr16Projects: [ProjectEntry] { [
        Self.pe("Stena decarb",  "2026-04-16T06:20:53Z"),
        Self.pe("DGX Spark",     "2026-04-16T07:04:52Z"),
        Self.pe("Stena decarb",  "2026-04-16T07:26:25Z"),
        Self.pe("Stena decarb",  "2026-04-16T07:41:42Z"),
        Self.pe("Stena decarb",  "2026-04-16T07:57:51Z"),
        Self.pe("DGX Spark",     "2026-04-16T08:13:41Z"),
        Self.pe("DGX Spark",     "2026-04-16T08:43:02Z"),
        Self.pe("DGX Spark",     "2026-04-16T08:54:29Z"),
        Self.pe("DGX Spark",     "2026-04-16T08:58:28Z"),
        Self.pe("Stena decarb",  "2026-04-16T09:13:32Z"),
        Self.pe("Stena decarb",  "2026-04-16T09:54:29Z"),
        Self.pe("Break",         "2026-04-16T11:12:18Z"),
        Self.pe("DGX Spark",     "2026-04-16T11:28:02Z"),
        Self.pe("DGX Spark",     "2026-04-16T11:44:23Z"),
        Self.pe("DGX Spark",     "2026-04-16T12:01:29Z"),
        Self.pe("DGX Spark",     "2026-04-16T13:02:27Z"),
        Self.pe("Stena decarb",  "2026-04-16T13:20:55Z"),
        Self.pe("Stena decarb",  "2026-04-16T13:41:53Z"),
        Self.pe("Break",         "2026-04-16T14:21:48Z"),
        Self.pe("Break",         "2026-04-16T14:25:00Z"),
        Self.pe("Break",         "2026-04-16T16:22:24Z"),
        Self.pe("apps.qamcom.se","2026-04-16T16:37:39Z"),
        Self.pe("apps.qamcom.se","2026-04-16T16:52:41Z"),
        Self.pe("Break",         "2026-04-16T17:09:08Z"),
        Self.pe("apps.qamcom.se","2026-04-16T17:24:11Z"),
        Self.pe("apps.qamcom.se","2026-04-16T17:38:42Z"),
        Self.pe("Break",         "2026-04-16T19:36:18Z"),
    ] }

    private var apr16Now: Date { Self.d("2026-04-16T20:40:46Z") }

    func test_apr16_spanCount() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr16Events, projectEntries: apr16Projects, now: apr16Now)
        XCTAssertEqual(spans.count, 5)
    }

    func test_apr16_allSpansClosed() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr16Events, projectEntries: apr16Projects, now: apr16Now)
        XCTAssertTrue(spans.allSatisfy { !$0.isActive })
    }

    func test_apr16_workedTime() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr16Events, projectEntries: apr16Projects, now: apr16Now)
        let firstOn = apr16Events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let worked = TimeCalculations.workedTime(spans: spans, entries: apr16Projects,
                                                 firstOnTime: firstOn, now: apr16Now)
        // 7h 18m 13s
        XCTAssertDuration(worked, 26293)
    }

    func test_apr16_projectDurations() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr16Events, projectEntries: apr16Projects, now: apr16Now)
        let firstOn = apr16Events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let totals = TimeCalculations.dailyProjectTotals(spans: spans, entries: apr16Projects,
                                                         firstOnTime: firstOn, now: apr16Now)
        let byName = Dictionary(uniqueKeysWithValues: totals.map { ($0.project, $0.duration) })

        // DGX Spark: 3h 34m 45s
        XCTAssertDuration(byName["DGX Spark"] ?? 0, 12885)
        // Stena decarb: 2h 43m 37s
        XCTAssertDuration(byName["Stena decarb"] ?? 0, 9817)
        // apps.qamcom.se: 59m 51s
        XCTAssertDuration(byName["apps.qamcom.se"] ?? 0, 3591)
        XCTAssertNil(byName["Break"])
    }

    // MARK: - April 17  (now = 15:33:18 UTC)
    // All events merge into one long span — meetings/offline time covered by project entries.
    // Heavy Fineasity day, Stena decarb morning, afternoon Ment + apps.qamcom.se.
    // Expected: 1 span (active), 9h 19m worked.

    private var apr17Events: [ScreenEvent] { [
        Self.se(.on,            "2026-04-17T06:13:24Z"),
        Self.se(.off,           "2026-04-17T06:13:28Z"),
        Self.se(.on,            "2026-04-17T06:13:50Z"),
        Self.se(.screensaverOn, "2026-04-17T06:41:42Z"),
        Self.se(.screensaverOff,"2026-04-17T06:48:36Z"),
        Self.se(.off,           "2026-04-17T08:03:53Z"),
        Self.se(.on,            "2026-04-17T08:04:08Z"),
        Self.se(.off,           "2026-04-17T08:04:11Z"),
        Self.se(.on,            "2026-04-17T08:04:16Z"),
        Self.se(.off,           "2026-04-17T09:11:05Z"),
        Self.se(.on,            "2026-04-17T09:11:10Z"),
        Self.se(.off,           "2026-04-17T09:11:14Z"),
        Self.se(.on,            "2026-04-17T09:11:18Z"),
        Self.se(.screensaverOn, "2026-04-17T12:45:20Z"),
        Self.se(.screensaverOff,"2026-04-17T12:45:42Z"),
        Self.se(.on,            "2026-04-17T13:46:48Z"),
        Self.se(.screensaverOn, "2026-04-17T15:32:57Z"),
        Self.se(.screensaverOff,"2026-04-17T15:33:17Z"),
    ] }

    private var apr17Projects: [ProjectEntry] { [
        Self.pe("Break",         "2026-04-17T06:14:11Z"),
        Self.pe("Stena decarb",  "2026-04-17T06:48:43Z"),
        Self.pe("Stena decarb",  "2026-04-17T07:04:00Z"),
        Self.pe("Stena decarb",  "2026-04-17T07:19:03Z"),
        Self.pe("Stena decarb",  "2026-04-17T07:34:06Z"),
        Self.pe("Stena decarb",  "2026-04-17T07:49:45Z"),
        Self.pe("Stena decarb",  "2026-04-17T08:03:45Z"),
        Self.pe("Stena decarb",  "2026-04-17T08:19:38Z"),
        Self.pe("Fineasity",     "2026-04-17T09:11:42Z"),
        Self.pe("Fineasity",     "2026-04-17T09:26:59Z"),
        Self.pe("Fineasity",     "2026-04-17T09:43:59Z"),
        Self.pe("Fineasity",     "2026-04-17T10:01:28Z"),
        Self.pe("Fineasity",     "2026-04-17T10:16:37Z"),
        Self.pe("Fineasity",     "2026-04-17T10:31:56Z"),
        Self.pe("Fineasity",     "2026-04-17T10:54:55Z"),
        Self.pe("Fineasity",     "2026-04-17T11:13:52Z"),
        Self.pe("Fineasity",     "2026-04-17T11:29:16Z"),
        Self.pe("Fineasity",     "2026-04-17T11:53:05Z"),
        Self.pe("Stena decarb",  "2026-04-17T12:08:21Z"),
        Self.pe("Ment",          "2026-04-17T13:05:21Z"),
        Self.pe("Ment",          "2026-04-17T13:46:25Z"),
        Self.pe("Fineasity",     "2026-04-17T14:08:01Z"),
        Self.pe("Fineasity",     "2026-04-17T14:15:04Z"),
        Self.pe("apps.qamcom.se","2026-04-17T14:27:31Z"),
        Self.pe("apps.qamcom.se","2026-04-17T14:46:17Z"),
        Self.pe("apps.qamcom.se","2026-04-17T15:01:22Z"),
        Self.pe("apps.qamcom.se","2026-04-17T15:19:00Z"),
    ] }

    private var apr17Now: Date { Self.d("2026-04-17T15:33:18Z") }

    func test_apr17_spanCount() {
        // All gaps covered by non-Break project entries → everything merges into one span
        let spans = TimeCalculations.buildTimeSpans(
            from: apr17Events, projectEntries: apr17Projects, now: apr17Now)
        XCTAssertEqual(spans.count, 1)
    }

    func test_apr17_spanIsActive() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr17Events, projectEntries: apr17Projects, now: apr17Now)
        XCTAssertTrue(spans.first?.isActive ?? false)
    }

    func test_apr17_workedTime() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr17Events, projectEntries: apr17Projects, now: apr17Now)
        let firstOn = apr17Events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let worked = TimeCalculations.workedTime(spans: spans, entries: apr17Projects,
                                                 firstOnTime: firstOn, now: apr17Now)
        // 9h 19m 7s
        XCTAssertDuration(worked, 33547)
    }

    func test_apr17_projectDurations() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr17Events, projectEntries: apr17Projects, now: apr17Now)
        let firstOn = apr17Events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let totals = TimeCalculations.dailyProjectTotals(spans: spans, entries: apr17Projects,
                                                         firstOnTime: firstOn, now: apr17Now)
        let byName = Dictionary(uniqueKeysWithValues: totals.map { ($0.project, $0.duration) })

        // Fineasity: 4h 2m 6s
        XCTAssertDuration(byName["Fineasity"] ?? 0, 14526)
        // Stena decarb: 2h 20m 43s
        XCTAssertDuration(byName["Stena decarb"] ?? 0, 8443)
        // Ment: 1h 38m 4s
        XCTAssertDuration(byName["Ment"] ?? 0, 5884)
        // apps.qamcom.se: 1h 18m 14s
        XCTAssertDuration(byName["apps.qamcom.se"] ?? 0, 4694)
    }

    // MARK: - April 19  (now = 20:39:03 UTC)
    // Evening-only activity, all logged as Break — zero worked time.
    // Expected: 2 spans (both closed), 0s worked, no project entries.

    private var apr19Events: [ScreenEvent] { [
        Self.se(.on,            "2026-04-19T19:47:35Z"),
        Self.se(.screensaverOn, "2026-04-19T19:59:38Z"),
        Self.se(.off,           "2026-04-19T20:04:49Z"),
        Self.se(.on,            "2026-04-19T20:12:04Z"),
        Self.se(.off,           "2026-04-19T20:12:06Z"),
        Self.se(.screensaverOff,"2026-04-19T20:12:17Z"),
        Self.se(.on,            "2026-04-19T20:12:18Z"),
        Self.se(.off,           "2026-04-19T20:39:02Z"),
    ] }

    private var apr19Projects: [ProjectEntry] { [
        Self.pe("Break", "2026-04-19T20:12:24Z"),
    ] }

    private var apr19Now: Date { Self.d("2026-04-19T20:39:03Z") }

    func test_apr19_spanCount() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr19Events, projectEntries: apr19Projects, now: apr19Now)
        XCTAssertEqual(spans.count, 2)
    }

    func test_apr19_workedTime_isZero() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr19Events, projectEntries: apr19Projects, now: apr19Now)
        let firstOn = apr19Events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let worked = TimeCalculations.workedTime(spans: spans, entries: apr19Projects,
                                                 firstOnTime: firstOn, now: apr19Now)
        XCTAssertEqual(worked, 0)
    }

    func test_apr19_noProjectTotals() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr19Events, projectEntries: apr19Projects, now: apr19Now)
        let firstOn = apr19Events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let totals = TimeCalculations.dailyProjectTotals(spans: spans, entries: apr19Projects,
                                                         firstOnTime: firstOn, now: apr19Now)
        XCTAssertTrue(totals.isEmpty)
    }

    // MARK: - April 20  (snapshot: now = 11:23:17 UTC, screen still on)
    // Morning apps.qamcom.se session. Break entries cover the screensaver gaps.
    // Expected: 3 spans (last active), 4h 9m worked, all apps.qamcom.se.

    private var apr20Events: [ScreenEvent] { [
        Self.se(.on,            "2026-04-20T06:05:41Z"),
        Self.se(.off,           "2026-04-20T06:06:12Z"),
        Self.se(.on,            "2026-04-20T06:06:52Z"),
        Self.se(.screensaverOn, "2026-04-20T06:50:20Z"),
        Self.se(.screensaverOff,"2026-04-20T07:01:10Z"),
        Self.se(.screensaverOn, "2026-04-20T07:48:03Z"),
        Self.se(.screensaverOff,"2026-04-20T07:56:43Z"),
        Self.se(.on,            "2026-04-20T07:58:57Z"),
        Self.se(.screensaverOn, "2026-04-20T08:53:12Z"),
        Self.se(.screensaverOff,"2026-04-20T08:55:20Z"),
        Self.se(.screensaverOn, "2026-04-20T09:47:32Z"),
        Self.se(.screensaverOff,"2026-04-20T09:48:19Z"),
        Self.se(.on,            "2026-04-20T10:16:21Z"),
        Self.se(.screensaverOn, "2026-04-20T10:24:20Z"),
        Self.se(.screensaverOff,"2026-04-20T10:42:55Z"),
        Self.se(.screensaverOn, "2026-04-20T10:48:00Z"),
        Self.se(.screensaverOff,"2026-04-20T11:21:11Z"),
        Self.se(.on,            "2026-04-20T11:23:16Z"),
    ] }

    private var apr20Projects: [ProjectEntry] { [
        Self.pe("Break",         "2026-04-20T06:07:22Z"),
        Self.pe("apps.qamcom.se","2026-04-20T06:22:29Z"),
        Self.pe("apps.qamcom.se","2026-04-20T06:38:40Z"),
        Self.pe("apps.qamcom.se","2026-04-20T07:01:14Z"),
        Self.pe("apps.qamcom.se","2026-04-20T07:19:54Z"),
        Self.pe("apps.qamcom.se","2026-04-20T07:59:03Z"),
        Self.pe("apps.qamcom.se","2026-04-20T08:14:36Z"),
        Self.pe("apps.qamcom.se","2026-04-20T08:29:40Z"),
        Self.pe("apps.qamcom.se","2026-04-20T08:46:49Z"),
        Self.pe("apps.qamcom.se","2026-04-20T08:55:35Z"),
        Self.pe("apps.qamcom.se","2026-04-20T09:10:55Z"),
        Self.pe("apps.qamcom.se","2026-04-20T09:28:42Z"),
        Self.pe("apps.qamcom.se","2026-04-20T10:16:28Z"),
        Self.pe("Break",         "2026-04-20T10:42:59Z"),
        Self.pe("Break",         "2026-04-20T11:21:14Z"),
    ] }

    // Snapshot "now": last recorded screen event + 1s (screen still on)
    private var apr20Now: Date { Self.d("2026-04-20T11:23:17Z") }

    func test_apr20_spanCount() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr20Events, projectEntries: apr20Projects, now: apr20Now)
        XCTAssertEqual(spans.count, 3)
    }

    func test_apr20_lastSpanIsActive() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr20Events, projectEntries: apr20Projects, now: apr20Now)
        XCTAssertTrue(spans.last?.isActive ?? false)
    }

    func test_apr20_workedTime() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr20Events, projectEntries: apr20Projects, now: apr20Now)
        let firstOn = apr20Events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let worked = TimeCalculations.workedTime(spans: spans, entries: apr20Projects,
                                                 firstOnTime: firstOn, now: apr20Now)
        // 4h 9m 6s
        XCTAssertDuration(worked, 14946)
    }

    func test_apr20_projectDurations() {
        let spans = TimeCalculations.buildTimeSpans(
            from: apr20Events, projectEntries: apr20Projects, now: apr20Now)
        let firstOn = apr20Events.first(where: { $0.kind == .on || $0.kind == .screensaverOff })?.time
        let totals = TimeCalculations.dailyProjectTotals(spans: spans, entries: apr20Projects,
                                                         firstOnTime: firstOn, now: apr20Now)
        let byName = Dictionary(uniqueKeysWithValues: totals.map { ($0.project, $0.duration) })

        // apps.qamcom.se: 4h 9m 6s — only project logged today
        XCTAssertDuration(byName["apps.qamcom.se"] ?? 0, 14946)
        XCTAssertEqual(totals.count, 1, "only one non-Break project expected")
    }
}
