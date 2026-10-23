import Foundation
import TimerCore

// A dependency-free executable so the same checks run with Command Line Tools or Xcode.
@main
struct FocusStateTests {
    static func main() throws {
        let tests = FocusStateTests()
        tests.testStartPauseResumeOnlyCountsRunningTime()
        tests.testMidnightSplitsCreditIntoCorrectDays()
        tests.testSleepGapAndBackwardClockAreNotCredited()
        try tests.testAutomaticPauseIsIdempotentAndRecoversPaused()
        try tests.testLegacyWebsiteSettingsPreserveHistory()
        tests.testIdleStartsAtCurrentRunAndHonorsInput()
        try tests.testSessionPhasesAndOldRecords()
        try tests.testHourlyCreditAndPersistence()
        tests.testDistractionSites()
        try tests.testIdleRollback()
        try tests.testStudyDayAndRelaunch()
        tests.testAutomaticResumePolicy()
        tests.testStudyDayGroupingAndBoundaryRollback()
        tests.testWasteDomains()
        try tests.testWasteTrackingAndPersistence()
        tests.testWasteIdleAndDayBoundary()
        try tests.testWasteHourlyStorage()
        tests.testSleepPolicy()
        try tests.testSleepClearsSessionInsteadOfStudyDayBoundary()
        print("PASS: 19 core checks")
    }
    func testSleepPolicy() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 86400) // Jan 2, 00:00 UTC
        func night(_ from: Double, _ to: Double) -> Bool {
            SleepPolicy.isNightSleep(from: day.addingTimeInterval(from * 3600),
                                     to: day.addingTimeInterval(to * 3600), calendar: calendar)
        }
        expectEqual(night(-1, 7), true)       // 23:00–07:00
        expectEqual(night(2, 10), true)       // 02:00–10:00
        expectEqual(night(7, 12), true)       // 07:00–12:00, one night hour
        expectEqual(night(1, 4.5), false)     // too short
        expectEqual(night(13, 19), false)     // afternoon absence
        expectEqual(night(-4, 0.5), false)    // evening, only 30 night minutes
        expectEqual(night(0, 50), true)       // away for days
    }

    func testSleepClearsSessionInsteadOfStudyDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let evening = Date(timeIntervalSince1970: 86400 - 3600) // Jan 1, 23:00
        var state = FocusState()
        state.observeInput(at: evening, calendar: calendar)
        state.start(at: evening, calendar: calendar)
        // Studying past the study-day boundary keeps the session once input history exists.
        for second in stride(from: 10, through: 3 * 3600, by: 10) {
            state.tick(at: evening.addingTimeInterval(Double(second)), calendar: calendar)
        }
        expectEqual(state.sessionSeconds, 3 * 3600)
        let bedtime = evening.addingTimeInterval(3 * 3600) // 02:00
        expectEqual(state.observeInput(at: bedtime, calendar: calendar), false)
        state.pause(at: bedtime, reason: "locked", automatic: true, resumeOnActivity: true, calendar: calendar)
        expectEqual(state.resumeWhenActive, true)
        // A short break keeps it.
        expectEqual(state.observeInput(at: bedtime.addingTimeInterval(1800), calendar: calendar), false)
        expectEqual(state.sessionSeconds, 3 * 3600)
        // Waking after a night clears it and does not auto-start.
        let wake = bedtime.addingTimeInterval(1800 + 7 * 3600) // 09:30
        expectEqual(state.observeInput(at: wake, calendar: calendar), true)
        expectEqual(state.sessionSeconds, 0)
        expectEqual(state.resumeWhenActive, false)
        expectEqual(state.phase, .idle)
        expectEqual(state.secondsByDay.values.reduce(0, +), 3 * 3600)
        let restored = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(state))
        expectEqual(restored, state)
        // Without any detected sleep, a session older than yesterday still resets.
        state.start(at: wake, calendar: calendar)
        state.tick(at: wake.addingTimeInterval(5), calendar: calendar)
        state.pause(at: wake.addingTimeInterval(5), reason: "manual", automatic: false, calendar: calendar)
        expectEqual(state.refreshStudyDay(at: wake.addingTimeInterval(86400), calendar: calendar), false)
        expectEqual(state.sessionSeconds, 5)
        expectEqual(state.refreshStudyDay(at: wake.addingTimeInterval(2 * 86400), calendar: calendar), true)
        expectEqual(state.sessionSeconds, 0)
    }
    func testWasteHourlyStorage() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for boundary in [86400.0, 104400.0, 93600.0] {
            var tracker = WasteTimeTracker()
            var ledger = WasteTimeState()
            let start = Date(timeIntervalSince1970: boundary - 2)
            let end = start.addingTimeInterval(4)
            tracker.observe(at: start, site: .douyu, idle: 0, state: &ledger, calendar: calendar)
            tracker.observe(at: end, site: .douyu, idle: 4, state: &ledger, calendar: calendar)
            let firstDay = StudyDay.key(for: start, calendar: calendar)
            let lastDay = StudyDay.key(for: end, calendar: calendar)
            let firstHour = String(calendar.component(.hour, from: start))
            let lastHour = String(calendar.component(.hour, from: end))
            expectEqual(ledger.hours(on: firstDay)[firstHour], 2)
            expectEqual(ledger.hours(on: lastDay)[lastHour], 2)
            let restored = try JSONDecoder().decode(WasteTimeState.self, from: JSONEncoder().encode(ledger))
            expectEqual(restored, ledger)
            tracker.observe(at: start.addingTimeInterval(300), site: .douyu, idle: 300, state: &ledger, calendar: calendar)
            expectEqual(ledger.hours(on: firstDay)[firstHour], 0)
            expectEqual(ledger.hours(on: lastDay)[lastHour], 0)
            expectEqual(ledger.total, 0)
        }
        let legacy = Data(#"{"secondsByDayAndSite":{"2026-10-07":{"douyu":120}}}"#.utf8)
        let restored = try JSONDecoder().decode(WasteTimeState.self, from: legacy)
        expectEqual(restored.total, 120)
        expectEqual(restored.hours(on: "2026-10-07"), [:])
    }

    func testWasteDomains() {
        for (url, site) in [("https://live.bilibili.com/1", WasteSite.bilibili),
                            ("https://b23.tv/a", .bilibili), ("https://tieba.baidu.com/p/a", .tieba),
                            ("https://www.douyu.com/1", .douyu), ("https://xhslink.com/a", .xiaohongshu),
                            ("https://www.xiaohongshu.com/explore/a", .xiaohongshu),
                            ("https://x.com/home", .x), ("https://mobile.twitter.com/a", .x),
                            ("https://lol.fandom.com/wiki/LCK", .leaguepedia)] {
            // Every distracting site both counts as 摸鱼 and pauses study.
            expectEqual(DistractionPolicy.siteName(for: url), site.title)
            expectEqual(WasteSite.match(url), site)
        }
        for url in ["https://x.com.evil.com", "https://notdouyu.com", "https://baidu.com",
                    "https://example.com/?next=x.com", "file:///x.com", "https://other.fandom.com"] {
            expectNil(WasteSite.match(url))
        }
    }

    func testWasteTrackingAndPersistence() throws {
        var tracker = WasteTimeTracker()
        var ledger = WasteTimeState()
        let start = Date(timeIntervalSince1970: 100000)
        tracker.observe(at: start, site: .bilibili, idle: 0, state: &ledger)
        tracker.observe(at: start.addingTimeInterval(2), site: .bilibili, idle: 0, state: &ledger)
        expectEqual(ledger.total, 2)
        // Background, unknown tab and site transitions do not invent credit.
        tracker.observe(at: start.addingTimeInterval(4), site: nil, idle: 0, state: &ledger)
        tracker.observe(at: start.addingTimeInterval(6), site: .x, idle: 0, state: &ledger)
        tracker.observe(at: start.addingTimeInterval(8), site: .x, idle: 0, state: &ledger)
        expectEqual(ledger.total, 4)
        tracker.observe(at: start.addingTimeInterval(100), site: .x, idle: 0, state: &ledger)
        expectEqual(ledger.total, 4)
        var focus = FocusState()
        focus.wasteTime = ledger
        let restored = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(focus))
        expectEqual(restored.wasteTime, ledger)
        expectEqual(focus.sessionSeconds, 0) // Runs while learning is stopped.
        let legacy = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(FocusState()))
        expectNil(legacy.wasteTime)
        tracker.observe(at: start.addingTimeInterval(102), site: .x, idle: .infinity, state: &ledger)
        expectNil(tracker.activeSite)
        expectEqual(ledger.total, 4)
    }

    func testWasteIdleAndDayBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var tracker = WasteTimeTracker()
        var ledger = WasteTimeState()
        let start = Date(timeIntervalSince1970: 104390) // 04:59:50
        for second in stride(from: 0, through: 20, by: 2) {
            tracker.observe(at: start.addingTimeInterval(Double(second)), site: .douyu,
                idle: 0, state: &ledger, calendar: calendar)
        }
        expectEqual(ledger.seconds(on: "1970-01-01"), 10)
        expectEqual(ledger.seconds(on: "1970-01-02"), 10)
        // No further input: roll back all sites, even when the idle cutoff crosses 05:00.
        tracker = WasteTimeTracker()
        ledger = WasteTimeState()
        for second in stride(from: 0, through: 304, by: 2) {
            tracker.observe(at: start.addingTimeInterval(Double(second)), site: second < 100 ? .douyu : .x,
                idle: Double(max(0, second - 4)), state: &ledger, calendar: calendar)
        }
        expectEqual(ledger.total, 4)
        expectEqual(ledger.seconds(on: "1970-01-01"), 4)
        expectEqual(ledger.seconds(on: "1970-01-02"), 0)
        expectNil(tracker.activeSite)
        tracker.observe(at: start.addingTimeInterval(306), site: .x, idle: 0, state: &ledger, calendar: calendar)
        tracker.observe(at: start.addingTimeInterval(308), site: .x, idle: 2, state: &ledger, calendar: calendar)
        expectEqual(ledger.total, 6)
        expectEqual(tracker.activeSite, .x)
        // Return just after the threshold, before a poll observes idle >= 300.
        tracker = WasteTimeTracker()
        ledger = WasteTimeState()
        for second in stride(from: 0, through: 298, by: 2) {
            tracker.observe(at: start.addingTimeInterval(Double(second)), site: .x,
                idle: Double(second), state: &ledger, calendar: calendar)
        }
        tracker.observe(at: start.addingTimeInterval(301), site: .x, idle: 0, state: &ledger, calendar: calendar)
        expectEqual(ledger.total, 0)
    }

    func testStudyDayAndRelaunch() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let before = Date(timeIntervalSince1970: 104398) // Jan 2, 04:59:58 UTC
        let after = before.addingTimeInterval(5)
        expectEqual(StudyDay.key(for: before, calendar: calendar), "1970-01-01")
        expectEqual(StudyDay.key(for: after, calendar: calendar), "1970-01-02")
        var state = FocusState()
        state.start(at: before, calendar: calendar)
        state.tick(at: after, calendar: calendar)
        expectEqual(state.sessionSeconds, 3)
        expectEqual(state.studySecondsByDay(calendar: calendar)["1970-01-01"], 2)
        expectEqual(state.studySecondsByDay(calendar: calendar)["1970-01-02"], 3)
        state.pause(at: after, reason: "idle", automatic: true, creditUntilPause: false, resumeOnActivity: true, calendar: calendar)
        expectEqual(state.resumeWhenActive, true)
        state.recoverAfterLaunch(at: after.addingTimeInterval(86400), calendar: calendar)
        expectEqual(state.sessionSeconds, 0)
        expectEqual(state.resumeWhenActive, true)
        expectEqual(state.isRunning, false)
        expectEqual(state.secondsByDay.values.reduce(0, +), 5)
        state.cancelAutomaticResume()
        expectEqual(state.resumeWhenActive, false)

        // Exit/reopen intent persists, without adding the closed interval.
        state = FocusState()
        let now = Date()
        state.start(at: now)
        state.prepareForShutdown(at: now.addingTimeInterval(5))
        state = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(state))
        state.recoverAfterLaunch(at: now.addingTimeInterval(100))
        expectEqual(state.resumeWhenActive, true)
        expectEqual(state.sessionSeconds, 5)
        state.start(at: now.addingTimeInterval(100))
        state.tick(at: now.addingTimeInterval(102))
        expectEqual(state.sessionSeconds, 7)
        state.pause(at: now.addingTimeInterval(102), reason: "manual", automatic: false)
        state.prepareForShutdown(at: now.addingTimeInterval(103))
        state.recoverAfterLaunch(at: now.addingTimeInterval(200))
        expectEqual(state.resumeWhenActive, false)
        state.start(at: now.addingTimeInterval(200))
        state.pause(at: now.addingTimeInterval(200), reason: "website", automatic: true)
        expectEqual(state.resumeWhenActive, false)

        // A legacy session last used yesterday must not survive into this morning.
        var legacy = FocusState()
        legacy.sessionSeconds = 500
        legacy.secondsByDay = ["1970-01-01": 500]
        legacy.recoverAfterLaunch(at: after, calendar: calendar)
        expectEqual(legacy.sessionSeconds, 0)
        expectEqual(legacy.secondsByDay["1970-01-01"], 500)
    }

    func testAutomaticResumePolicy() {
        let paused = Date(timeIntervalSince1970: 100000)
        func eligible(_ idle: Double, waiting: Bool = true, available: Bool = true) -> Bool {
            AutomaticResumePolicy.shouldResume(waiting: waiting, sessionAvailable: available,
                idle: idle, now: paused.addingTimeInterval(10), eligibleAfter: paused)
        }
        expectEqual(eligible(0.2), true)
        expectEqual(eligible(600), false)
        expectEqual(eligible(0.2, waiting: false), false)
        expectEqual(eligible(0.2, available: false), false)
        expectEqual(eligible(.infinity), false)
        expectEqual(AutomaticResumePolicy.shouldResume(waiting: true, sessionAvailable: true,
            idle: 1, now: paused.addingTimeInterval(0.5), eligibleAfter: paused), false)
    }

    func testStudyDayGroupingAndBoundaryRollback() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var state = FocusState()
        state.secondsByDay = ["1970-01-01": 150, "1970-01-02": 100]
        state.secondsByHour = ["1970-01-01": ["23": 100], "1970-01-02": ["2": 30, "4": 10, "5": 60]]
        expectEqual(state.studySecondsByDay(calendar: calendar)["1970-01-01"], 190)
        expectEqual(state.studySecondsByDay(calendar: calendar)["1970-01-02"], 60)
        expectEqual(state.studySecondsByDay(calendar: calendar).values.reduce(0, +), 250)
        expectEqual(state.studyHours(at: Date(timeIntervalSince1970: 86400), calendar: calendar)["2"], 30)
        expectEqual(state.studyHours(at: Date(timeIntervalSince1970: 86400), calendar: calendar)["5"], nil)
        // Cramming until 02:00 counts toward the previous day.
        expectEqual(StudyDay.key(for: Date(timeIntervalSince1970: 86400 + 7200), calendar: calendar), "1970-01-01")
        state = FocusState()
        let start = Date(timeIntervalSince1970: 104220) // 04:57:00
        state.start(at: start, calendar: calendar)
        for second in 1...360 { state.tick(at: start.addingTimeInterval(Double(second)), calendar: calendar) }
        expectEqual(state.sessionSeconds, 180)
        state.discardIdleTime(since: start.addingTimeInterval(60), calendar: calendar)
        expectEqual(state.sessionSeconds, 0)
        expectEqual(state.studySecondsByDay(calendar: calendar)["1970-01-01"], 60)
        expectEqual(state.studySecondsByDay(calendar: calendar)["1970-01-02"], 0)
        expectEqual(state.secondsByHour!.values.flatMap { $0.values }.reduce(0, +), 60)
    }

    func testIdleRollback() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for boundary in [7200.0, 86400.0] {
            var state = FocusState()
            let start = Date(timeIntervalSince1970: boundary - 180)
            state.start(at: start, calendar: calendar)
            for second in 1...359 { state.tick(at: start.addingTimeInterval(Double(second)), calendar: calendar) }
            // At 360 seconds the last 300 seconds were idle; only 299 were credited.
            state.discardIdleTime(since: start.addingTimeInterval(60), calendar: calendar)
            expectEqual(state.sessionSeconds, 60)
            expectEqual(state.secondsByDay.values.reduce(0, +), 60)
            expectEqual(state.secondsByHour!.values.flatMap { $0.values }.reduce(0, +), 60)
            state.discardIdleTime(since: start.addingTimeInterval(60), calendar: calendar)
            expectEqual(state.sessionSeconds, 60)
            state.pause(at: start.addingTimeInterval(360), reason: "idle", automatic: true, creditUntilPause: false, calendar: calendar)
            let restored = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(state))
            expectEqual(restored, state)
            // Resuming must never remove time from an earlier run.
            state.start(at: start.addingTimeInterval(400), calendar: calendar)
            state.tick(at: start.addingTimeInterval(405), calendar: calendar)
            state.discardIdleTime(since: start, calendar: calendar)
            expectEqual(state.sessionSeconds, 60)
        }
        var state = FocusState()
        let start = Date(timeIntervalSince1970: 100000)
        state.start(at: start, calendar: calendar)
        state.tick(at: start.addingTimeInterval(5))
        state.tick(at: start.addingTimeInterval(100)) // Uncredited gap.
        state.tick(at: start.addingTimeInterval(105))
        state.discardIdleTime(since: start.addingTimeInterval(3))
        expectEqual(state.sessionSeconds, 3)
    }
    func testDistractionSites() {
        for address in ["https://www.bilibili.com/video/a", "https://live.bilibili.com/6", "https://b23.tv/a",
                        "https://www.xiaohongshu.com/explore/a", "https://xhslink.com/a",
                        "https://lol.fandom.com/wiki/LCK", "https://leaguepedia.com/", "https://tieba.baidu.com/p/1"] {
            precondition(DistractionPolicy.siteName(for: address) != nil)
        }
        for address in ["https://bilibili.com.evil.com", "https://example.com/?q=tieba.baidu.com",
                        "https://www.baidu.com", "https://other.fandom.com", "file:///bilibili.com"] {
            expectNil(DistractionPolicy.siteName(for: address))
        }
    }
    func testHourlyCreditAndPersistence() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var state = FocusState()
        let start = Date(timeIntervalSince1970: 3598)
        state.start(at: start)
        state.tick(at: start.addingTimeInterval(5), calendar: calendar)
        expectEqual(state.secondsByHour?["1970-01-01"]?["0"], 2)
        expectEqual(state.secondsByHour?["1970-01-01"]?["1"], 3)
        let restored = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(state))
        expectEqual(restored.secondsByHour, state.secondsByHour)
        state = FocusState()
        state.start(at: Date(timeIntervalSince1970: 86398))
        state.tick(at: Date(timeIntervalSince1970: 86403), calendar: calendar)
        expectEqual(state.secondsByHour?["1970-01-01"]?["23"], 2)
        expectEqual(state.secondsByHour?["1970-01-02"]?["0"], 3)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        json.removeValue(forKey: "secondsByHour")
        let legacy = try JSONDecoder().decode(FocusState.self, from: JSONSerialization.data(withJSONObject: json))
        expectNil(legacy.secondsByHour)
        expectEqual(legacy.secondsByDay, state.secondsByDay)
    }
    func testSessionPhasesAndOldRecords() throws {
        var state = FocusState()
        expectEqual(state.phase, .idle)
        let now = Date()
        state.start(at: now)
        expectEqual(state.phase, .running)
        state.pause(at: now, reason: "pause", automatic: false)
        expectEqual(state.sessionSeconds, 0)
        expectEqual(state.phase, .paused)
        state.sessionHasStarted = false
        expectEqual(state.phase, .idle)
        state.sessionSeconds = 30
        state.sessionHasStarted = nil
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        json.removeValue(forKey: "sessionHasStarted")
        let old = try JSONDecoder().decode(FocusState.self, from: JSONSerialization.data(withJSONObject: json))
        expectEqual(old.phase, .paused)
    }
    func testIdleStartsAtCurrentRunAndHonorsInput() {
        expectEqual(IdlePolicy.shouldPause(systemIdle: 600, runDuration: 600, threshold: 0), false)
        expectEqual(IdlePolicy.shouldPause(systemIdle: 600, runDuration: 1, threshold: 300), false)
        expectEqual(IdlePolicy.shouldPause(systemIdle: 300, runDuration: 300, threshold: 300), true)
        expectEqual(IdlePolicy.shouldPause(systemIdle: 1, runDuration: 600, threshold: 300), false)
    }
    func testStartPauseResumeOnlyCountsRunningTime() {
        let start = Date(timeIntervalSince1970: 100000)
        var state = FocusState()
        state.start(at: start)
        state.tick(at: start.addingTimeInterval(10))
        state.pause(at: start.addingTimeInterval(12), reason: "break", automatic: false)
        state.tick(at: start.addingTimeInterval(30))
        state.start(at: start.addingTimeInterval(60))
        state.tick(at: start.addingTimeInterval(65))
        expectEqual(state.sessionSeconds, 17)
    }
    func testMidnightSplitsCreditIntoCorrectDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 86398)
        var state = FocusState()
        state.start(at: start)
        state.tick(at: start.addingTimeInterval(5), calendar: calendar)
        expectEqual(state.secondsByDay["1970-01-01"], 2)
        expectEqual(state.secondsByDay["1970-01-02"], 3)
    }
    func testSleepGapAndBackwardClockAreNotCredited() {
        var state = FocusState()
        let date = Date()
        state.start(at: date)
        state.tick(at: date.addingTimeInterval(3600))
        state.tick(at: date.addingTimeInterval(3500))
        expectEqual(state.sessionSeconds, 0)
    }
    func testAutomaticPauseIsIdempotentAndRecoversPaused() throws {
        var state = FocusState()
        state.start(at: Date())
        state.pause(at: Date(), reason: "idle", automatic: true)
        state.pause(at: Date(), reason: "idle", automatic: true)
        expectEqual(state.pauseCount, 1)
        state.start(at: Date())
        var restored = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(state))
        restored.recoverAfterLaunch()
        expectEqual(restored.isRunning, false)
        expectNil(restored.lastTick)
    }
    func testLegacyWebsiteSettingsPreserveHistory() throws {
        var state = FocusState()
        state.secondsByDay = ["2026-09-08": 231]
        state.settings.idleMinutes = 10
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        var settings = json["settings"] as! [String: Any]
        settings["watchChrome"] = true
        settings["watchMode"] = "anyTab"
        json["settings"] = settings
        let restored = try JSONDecoder().decode(FocusState.self, from: JSONSerialization.data(withJSONObject: json))
        expectEqual(restored.secondsByDay, state.secondsByDay)
        expectEqual(restored.settings.idleMinutes, 10)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored.settings)) as! [String: Any]
        expectNil(encoded["watchChrome"])
        expectNil(encoded["watchMode"])
    }
}

private func expectEqual<T: Equatable>(_ value: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    precondition(value == expected, "Expected \(expected), got \(value)", file: file, line: line)
}
private func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value == nil, "Expected nil", file: file, line: line)
}
