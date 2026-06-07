import XCTest

// June 1 — long apps.qamcom.se day with Fineasity morning, brief Stena sälj and Librixer.
// Expected: 20 spans (all closed), 9h 31m 35s worked.

extension EventLogCalculationTests {

    private static let now_jun1 = EventLogCalculationTests().date("2026-06-01 23:49:45")

    private static let csv_jun1 = """
    date,time,event_type,event_source,project_name
    2026-06-01,01:17:51,on,computer,-
    2026-06-01,01:17:51,off,computer,-
    2026-06-01,02:13:47,on,computer,-
    2026-06-01,02:13:47,off,computer,-
    2026-06-01,03:51:42,on,computer,-
    2026-06-01,03:51:42,off,computer,-
    2026-06-01,05:13:58,on,computer,-
    2026-06-01,05:13:58,off,computer,-
    2026-06-01,06:53:44,on,computer,-
    2026-06-01,07:14:27,screensaverOff,computer,-
    2026-05-31,23:11:50,entry,user,Break
    2026-06-01,06:53:44,off,computer,-
    2026-06-01,07:14:45,on,computer,-
    2026-06-01,07:15:17,entry,user,Break
    2026-06-01,07:15:17,off,computer,-
    2026-06-01,07:51:33,on,computer,-
    2026-06-01,07:54:40,entry,user,Break
    2026-06-01,07:54:40,off,computer,-
    2026-06-01,07:54:54,on,computer,-
    2026-06-01,07:15:17,entry,user,Break
    2026-06-01,08:10:04,entry,user,Fineasity
    2026-06-01,08:25:10,entry,user,Fineasity
    2026-06-01,08:40:34,entry,user,apps.qamcom.se
    2026-06-01,08:55:52,entry,user,Librixer
    2026-06-01,09:14:43,entry,user,apps.qamcom.se
    2026-06-01,09:29:49,entry,user,apps.qamcom.se
    2026-06-01,09:44:56,entry,user,Fineasity
    2026-06-01,10:00:42,entry,user,Stena sälj
    2026-06-01,10:16:58,entry,user,Fineasity
    2026-06-01,10:32:23,entry,user,Fineasity
    2026-06-01,10:46:29,entry,user,Fineasity
    2026-06-01,11:01:32,entry,user,Fineasity
    2026-06-01,11:16:47,entry,user,apps.qamcom.se
    2026-06-01,11:32:43,entry,user,apps.qamcom.se
    2026-06-01,11:47:57,entry,user,apps.qamcom.se
    2026-06-01,11:47:57,screensaverOn,computer,-
    2026-06-01,11:50:37,screensaverOff,computer,-
    2026-06-01,11:47:45,entry,user,apps.qamcom.se
    2026-06-01,12:21:12,entry,user,apps.qamcom.se
    2026-06-01,12:37:08,entry,user,apps.qamcom.se
    2026-06-01,12:44:23,entry,user,apps.qamcom.se
    2026-06-01,12:44:23,screensaverOn,computer,-
    2026-06-01,12:56:19,screensaverOff,computer,-
    2026-06-01,12:44:23,entry,user,Break
    2026-06-01,13:11:28,entry,user,Break
    2026-06-01,13:26:45,entry,user,apps.qamcom.se
    2026-06-01,13:42:22,entry,user,apps.qamcom.se
    2026-06-01,13:57:37,entry,user,apps.qamcom.se
    2026-06-01,14:12:47,entry,user,apps.qamcom.se
    2026-06-01,14:27:58,entry,user,apps.qamcom.se
    2026-06-01,14:43:00,entry,user,apps.qamcom.se
    2026-06-01,14:58:36,entry,user,apps.qamcom.se
    2026-06-01,15:13:44,entry,user,apps.qamcom.se
    2026-06-01,15:29:35,entry,user,apps.qamcom.se
    2026-06-01,15:44:37,entry,user,apps.qamcom.se
    2026-06-01,15:59:48,entry,user,apps.qamcom.se
    2026-06-01,16:15:03,entry,user,apps.qamcom.se
    2026-06-01,16:30:06,entry,user,apps.qamcom.se
    2026-06-01,16:48:42,entry,user,apps.qamcom.se
    2026-06-01,16:48:42,screensaverOn,computer,-
    2026-06-01,17:07:42,screensaverOff,computer,-
    2026-06-01,16:45:11,entry,user,apps.qamcom.se
    2026-06-01,17:22:47,entry,user,apps.qamcom.se
    2026-06-01,17:37:55,entry,user,apps.qamcom.se
    2026-06-01,17:53:20,entry,user,apps.qamcom.se
    2026-06-01,18:10:12,off,computer,-
    2026-06-01,18:40:45,on,computer,-
    2026-06-01,18:59:18,entry,user,Break
    2026-06-01,18:47:25,off,computer,-
    2026-06-01,18:59:26,on,computer,-
    2026-06-01,19:01:04,entry,user,Break
    2026-06-01,19:01:04,off,computer,-
    2026-06-01,19:51:39,on,computer,-
    2026-06-01,19:51:39,off,computer,-
    2026-06-01,20:05:40,on,computer,-
    2026-06-01,19:01:04,entry,user,Break
    2026-06-01,20:05:40,off,computer,-
    2026-06-01,20:17:02,on,computer,-
    2026-06-01,20:30:24,entry,user,Break
    2026-06-01,20:30:24,off,computer,-
    2026-06-01,20:47:06,on,computer,-
    2026-06-01,20:49:16,off,computer,-
    2026-06-01,21:22:15,on,computer,-
    2026-06-01,21:37:14,off,computer,-
    2026-06-01,21:48:35,on,computer,-
    2026-06-01,22:05:18,off,computer,-
    2026-06-01,22:18:13,on,computer,-
    2026-06-01,22:49:49,off,computer,-
    2026-06-01,23:05:49,on,computer,-
    2026-06-01,23:05:49,off,computer,-
    2026-06-01,23:26:29,on,computer,-
    2026-06-01,23:32:44,off,computer,-
    2026-06-01,23:49:44,on,computer,-
    2026-06-01,23:49:44,off,computer,-
    2026-06-01,22:47:29,entry,user,Break
    """

    func test_jun1_spanCount() {
        XCTAssertEqual(analyze(csv: Self.csv_jun1, now: Self.now_jun1).spans.count, 20)
    }

    func test_jun1_allClosed() {
        XCTAssertTrue(analyze(csv: Self.csv_jun1, now: Self.now_jun1).spans.allSatisfy { !$0.isActive })
    }

    func test_jun1_workedTime() {
        // 9h 31m 35s
        XCTAssertDuration(analyze(csv: Self.csv_jun1, now: Self.now_jun1).worked, 34295)
    }

    func test_jun1_projectDurations() {
        let projects = analyze(csv: Self.csv_jun1, now: Self.now_jun1).projects
        XCTAssertDuration(projects["apps.qamcom.se"] ?? 0, 26044)
        XCTAssertDuration(projects["Fineasity"] ?? 0, 6387)
        XCTAssertDuration(projects["Stena sälj"] ?? 0, 946)
        XCTAssertDuration(projects["Librixer"] ?? 0, 918)
        XCTAssertNil(projects["Break"])
    }
}
