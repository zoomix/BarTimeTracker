import XCTest

// June 2 — partial day, still in progress at snapshot time.
// apps.qamcom.se heavy, Librixer, Stena sälj, Meeting.
// Expected: 18 spans (1 active), 7h 11m 11s worked.

extension EventLogCalculationTests {

    private static let now_jun2 = EventLogCalculationTests().date("2026-06-02 19:13:54")

    private static let csv_jun2 = """
    date,time,event_type,event_source,project_name
    2026-06-02,00:33:41,on,computer,-
    2026-06-02,00:33:41,off,computer,-
    2026-06-02,00:51:26,on,computer,-
    2026-06-02,00:51:26,off,computer,-
    2026-06-02,02:11:19,on,computer,-
    2026-06-02,02:11:19,off,computer,-
    2026-06-02,03:51:00,on,computer,-
    2026-06-02,03:51:00,off,computer,-
    2026-06-02,04:30:25,on,computer,-
    2026-06-02,04:30:55,off,computer,-
    2026-06-02,06:09:00,on,computer,-
    2026-06-02,06:09:00,off,computer,-
    2026-06-02,06:31:31,on,computer,-
    2026-06-02,06:31:31,off,computer,-
    2026-06-02,06:48:08,on,computer,-
    2026-06-02,06:48:08,off,computer,-
    2026-06-02,07:16:07,on,computer,-
    2026-06-02,07:16:07,off,computer,-
    2026-06-02,07:32:16,on,computer,-
    2026-06-02,07:47:24,off,computer,-
    2026-06-02,08:05:48,on,computer,-
    2026-06-02,08:19:07,entry,user,Break
    2026-06-02,08:19:07,off,computer,-
    2026-06-02,08:19:16,on,computer,-
    2026-06-01,22:47:29,entry,user,Break
    2026-06-02,08:34:36,entry,user,Meeting
    2026-06-02,08:49:46,entry,user,apps.qamcom.se
    2026-06-02,09:05:19,entry,user,apps.qamcom.se
    2026-06-02,09:20:36,entry,user,apps.qamcom.se
    2026-06-02,09:35:47,entry,user,apps.qamcom.se
    2026-06-02,09:50:50,entry,user,apps.qamcom.se
    2026-06-02,10:09:16,entry,user,apps.qamcom.se
    2026-06-02,10:25:07,entry,user,apps.qamcom.se
    2026-06-02,10:40:40,entry,user,apps.qamcom.se
    2026-06-02,10:55:56,entry,user,apps.qamcom.se
    2026-06-02,11:11:11,entry,user,apps.qamcom.se
    2026-06-02,11:28:31,entry,user,apps.qamcom.se
    2026-06-02,11:42:14,entry,user,apps.qamcom.se
    2026-06-02,11:42:14,screensaverOn,computer,-
    2026-06-02,12:24:41,screensaverOff,computer,-
    2026-06-02,11:42:14,entry,user,Break
    2026-06-02,12:40:41,entry,user,Librixer
    2026-06-02,12:59:02,entry,user,Librixer
    2026-06-02,13:18:22,entry,user,apps.qamcom.se
    2026-06-02,13:34:35,entry,user,apps.qamcom.se
    2026-06-02,13:34:35,screensaverOn,computer,-
    2026-06-02,14:05:39,screensaverOff,computer,-
    2026-06-02,14:05:39,entry,user,Stena sälj
    2026-06-02,14:20:45,entry,user,apps.qamcom.se
    2026-06-02,14:30:00,entry,user,apps.qamcom.se
    2026-06-02,14:30:00,screensaverOn,computer,-
    2026-06-02,14:35:41,screensaverOff,computer,-
    2026-06-02,14:35:41,entry,user,apps.qamcom.se
    2026-06-02,14:55:17,entry,user,apps.qamcom.se
    2026-06-02,14:55:17,screensaverOn,computer,-
    2026-06-02,14:59:54,screensaverOff,computer,-
    2026-06-02,14:50:45,entry,user,apps.qamcom.se
    2026-06-02,15:14:59,entry,user,apps.qamcom.se
    2026-06-02,15:30:18,entry,user,apps.qamcom.se
    2026-06-02,15:39:49,off,computer,-
    2026-06-02,15:53:53,on,computer,-
    2026-06-02,15:54:23,off,computer,-
    2026-06-02,16:11:16,on,computer,-
    2026-06-02,16:29:33,entry,user,Break
    2026-06-02,16:47:04,entry,user,Break
    2026-06-02,16:58:12,entry,user,Break
    2026-06-02,16:58:12,off,computer,-
    2026-06-02,17:15:26,on,computer,-
    2026-06-02,17:17:26,off,computer,-
    2026-06-02,18:24:13,on,computer,-
    2026-06-02,18:24:13,off,computer,-
    2026-06-02,18:34:58,on,computer,-
    2026-06-02,18:41:40,off,computer,-
    2026-06-02,18:59:37,on,computer,-
    2026-06-02,18:59:37,off,computer,-
    2026-06-02,19:13:53,on,computer,-
    2026-06-02,16:58:12,entry,user,Break
    2026-06-02,19:29:06,entry,user,Break
    2026-06-02,19:29:13,entry,user,~logged out~
    """

    func test_jun2_spanCount() {
        XCTAssertEqual(analyze(csv: Self.csv_jun2, now: Self.now_jun2).spans.count, 9)
    }

    func test_jun2_lastSpanActive() {
        XCTAssertTrue(analyze(csv: Self.csv_jun2, now: Self.now_jun2).spans.last?.isActive ?? false)
    }

    func test_jun2_workedTime() {
        // 7h 11m 11s
        XCTAssertDuration(analyze(csv: Self.csv_jun2, now: Self.now_jun2).worked, 25871)
    }

    func test_jun2_projectDurations() {
        let projects = analyze(csv: Self.csv_jun2, now: Self.now_jun2).projects
        XCTAssertDuration(projects["apps.qamcom.se"] ?? 0, 18470)
        XCTAssertDuration(projects["Librixer"] ?? 0, 4608)
        XCTAssertDuration(projects["Stena sälj"] ?? 0, 1864)
        XCTAssertDuration(projects["Meeting"] ?? 0, 929)
        XCTAssertNil(projects["Break"])
    }
}
