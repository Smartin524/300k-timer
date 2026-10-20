import Foundation

public struct FocusSettings: Codable, Equatable, Sendable {
    public var idleMinutes: Int = 5
    public init() {}
}

public enum FocusPhase: Equatable, Sendable {
    case idle, running, paused
    public var title: String {
        switch self {
        case .idle: return "未开始"
        case .running: return "计时中"
        case .paused: return "已暂停"
        }
    }
}

public struct FocusState: Codable, Equatable, Sendable {
    public var secondsByDay: [String: TimeInterval] = [:]
    // Optional so pre-hourly records decode without inventing a time distribution.
    public var secondsByHour: [String: [String: TimeInterval]]?
    public var wasteTime: WasteTimeState?
    public var sessionSeconds: TimeInterval = 0
    public private(set) var sessionDay: String?
    public private(set) var resumeWhenActive: Bool?
    public var pauseCount: Int = 0
    public var pauseDay: String = ""
    public var isRunning: Bool = false
    // Optional for compatibility with records saved before explicit session tracking.
    public var sessionHasStarted: Bool?
    /// Coarse last-input time (about a minute's resolution), used only for sleep detection.
    public private(set) var lastInputAt: Date?
    public private(set) var lastSleep: SleepInterval?
    public var phase: FocusPhase {
        if isRunning { return .running }
        return (sessionHasStarted ?? (sessionSeconds > 0)) ? .paused : .idle
    }
    // Only intervals credited during the current run can be removed for idle time.
    private struct CreditedInterval: Codable, Equatable, Sendable {
        var start: Date
        var end: Date
    }
    private var runCredits: [CreditedInterval]?
    public var lastTick: Date?
    public var lastReason: String = "未开始"
    public var settings = FocusSettings()
    public init() {}

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public func todaySeconds(at now: Date = Date()) -> TimeInterval {
        let start = StudyDay.start(for: now)
        let day = Self.dayKey(start)
        let next = Self.dayKey(Calendar.current.date(byAdding: .day, value: 1, to: start)!)
        return max(0, secondsByDay[day, default: 0] - (secondsByHour?[day]?["0"] ?? 0))
            + (secondsByHour?[next]?["0"] ?? 0)
    }

    /// Keep the stored calendar-day ledger unchanged, and regroup known midnight hours.
    /// Older totals without hourly detail are preserved rather than guessed.
    public func studySecondsByDay(calendar: Calendar = .current) -> [String: TimeInterval] {
        var totals = secondsByDay
        for (day, hours) in secondsByHour ?? [:] {
            let components = day.split(separator: "-").compactMap { Int($0) }
            guard components.count == 3,
                  let date = calendar.date(from: DateComponents(year: components[0], month: components[1], day: components[2])),
                  let previous = calendar.date(byAdding: .day, value: -1, to: date) else { continue }
            let midnight = min(hours["0", default: 0], secondsByDay[day, default: 0])
            totals[day, default: 0] -= midnight
            totals[Self.dayKey(previous, calendar: calendar), default: 0] += midnight
        }
        return totals
    }

    public func studyHours(at date: Date, calendar: Calendar = .current) -> [String: TimeInterval] {
        let start = StudyDay.start(for: date, calendar: calendar)
        let next = calendar.date(byAdding: .day, value: 1, to: start)!
        var hours = secondsByHour?[Self.dayKey(start, calendar: calendar)] ?? [:]
        hours["0"] = secondsByHour?[Self.dayKey(next, calendar: calendar)]?["0"] ?? 0
        return hours
    }

    /// The session normally ends with a detected night's sleep (see `observeInput`).
    /// The study-day boundary resets it only without input history, or when no sleep
    /// was seen for two study days. Returns true when the session was reset.
    @discardableResult
    public mutating func refreshStudyDay(at now: Date, calendar: Calendar = .current) -> Bool {
        let day = StudyDay.key(for: now, calendar: calendar)
        guard sessionDay != day else { return false }
        let previousDay = sessionDay ?? lastTick.map { StudyDay.key(for: $0, calendar: calendar) }
            ?? secondsByDay.filter { $0.value > 0 }.keys.max()
        guard let previousDay, previousDay != day else {
            sessionDay = day
            return false
        }
        let yesterday = StudyDay.key(for: calendar.date(byAdding: .day, value: -1, to: now)!, calendar: calendar)
        guard lastInputAt == nil || previousDay < yesterday else { return false }
        resetSession()
        sessionDay = day
        return true
    }

    /// Feed the latest input time. Returns true when the gap since the previous input
    /// looks like a night's sleep; the session is then cleared and not auto-resumed.
    @discardableResult
    public mutating func observeInput(at input: Date, calendar: Calendar = .current) -> Bool {
        guard let previous = lastInputAt else {
            lastInputAt = input
            return false
        }
        // Coarse updates keep frequent pointer events from rewriting state.
        guard input.timeIntervalSince(previous) >= 60 else { return false }
        lastInputAt = input
        guard SleepPolicy.isNightSleep(from: previous, to: input, calendar: calendar) else { return false }
        lastSleep = SleepInterval(start: previous, end: input)
        resetSession()
        resumeWhenActive = false
        sessionDay = StudyDay.key(for: input, calendar: calendar)
        return true
    }

    private mutating func resetSession() {
        sessionSeconds = 0
        sessionHasStarted = isRunning
        if !isRunning { lastReason = "未开始" }
    }

    public mutating func cancelAutomaticResume() { resumeWhenActive = false }

    /// Persist intent, but never credit time while the process is not running.
    public mutating func prepareForShutdown(at now: Date) {
        let shouldResume = isRunning || resumeWhenActive == true
        pause(at: now, reason: "计时已保存", automatic: false)
        resumeWhenActive = shouldResume
    }

    public mutating func start(at now: Date, calendar: Calendar = .current) {
        guard !isRunning else { return }
        refreshStudyDay(at: now, calendar: calendar)
        resumeWhenActive = false
        runCredits = []
        isRunning = true
        sessionHasStarted = true
        lastTick = now
        lastReason = "计时中"
    }

    // Wall-clock dates make midnight allocation exact; long unobserved gaps are never credited.
    public mutating func tick(at now: Date, calendar: Calendar = .current) {
        guard isRunning, let previous = lastTick else { return }
        let reset = refreshStudyDay(at: now, calendar: calendar)
        lastTick = now
        let delta = now.timeIntervalSince(previous)
        guard delta > 0, delta <= 15 else { return }
        var cursor = previous
        while cursor < now {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))!
            let nextHour = calendar.dateInterval(of: .hour, for: cursor)!.end
            let end = min(now, nextDay, nextHour)
            let day = Self.dayKey(cursor, calendar: calendar)
            let hour = String(calendar.component(.hour, from: cursor))
            let credited = end.timeIntervalSince(cursor)
            secondsByDay[day, default: 0] += credited
            if secondsByHour == nil { secondsByHour = [:] }
            secondsByHour![day, default: [:]][hour, default: 0] += credited
            cursor = end
        }
        let sessionStart = reset ? max(previous, StudyDay.start(for: now, calendar: calendar)) : previous
        sessionSeconds += max(0, now.timeIntervalSince(sessionStart))
        if runCredits == nil { runCredits = [] }
        if let last = runCredits?.last, last.end == previous {
            runCredits![runCredits!.count - 1].end = now
        } else {
            runCredits!.append(CreditedInterval(start: previous, end: now))
        }
    }

    /// Removes only recorded time after the last input, including hour/day boundaries.
    public mutating func discardIdleTime(since cutoff: Date, calendar: Calendar = .current) {
        guard isRunning else { return }
        var retained: [CreditedInterval] = []
        for interval in runCredits ?? [] {
            var cursor = max(interval.start, cutoff)
            while cursor < interval.end {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))!
                let nextHour = calendar.dateInterval(of: .hour, for: cursor)!.end
                let end = min(interval.end, nextDay, nextHour)
                let day = Self.dayKey(cursor, calendar: calendar)
                let hour = String(calendar.component(.hour, from: cursor))
                let removed = end.timeIntervalSince(cursor)
                secondsByDay[day] = max(0, (secondsByDay[day] ?? 0) - removed)
                if secondsByHour?[day]?[hour] != nil {
                    secondsByHour![day]![hour] = max(0, secondsByHour![day]![hour]! - removed)
                }
                sessionSeconds = max(0, sessionSeconds - removed)
                cursor = end
            }
            if interval.start < cutoff {
                retained.append(CreditedInterval(start: interval.start, end: min(interval.end, cutoff)))
            }
        }
        runCredits = retained
    }

    public mutating func pause(at now: Date, reason: String, automatic: Bool, creditUntilPause: Bool = true, resumeOnActivity: Bool = false, calendar: Calendar = .current) {
        if !automatic { resumeWhenActive = false }
        guard isRunning else { return }
        resumeWhenActive = resumeOnActivity
        if creditUntilPause { tick(at: now, calendar: calendar) }
        else { refreshStudyDay(at: now, calendar: calendar) }
        isRunning = false
        lastTick = nil
        runCredits = nil
        lastReason = reason
        if automatic {
            let key = StudyDay.key(for: now, calendar: calendar)
            if pauseDay != key { pauseCount = 0; pauseDay = key }
            pauseCount += 1
        }
    }

    public mutating func recoverAfterLaunch(at now: Date = Date(), calendar: Calendar = .current) {
        if isRunning { resumeWhenActive = true }
        refreshStudyDay(at: now, calendar: calendar)
        if isRunning { lastReason = "已暂停"; sessionHasStarted = true }
        isRunning = false
        lastTick = nil
        runCredits = nil
    }
}

public enum TimeText {
    public static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    public static func compact(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds)) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

public enum IdlePolicy {
    // Starting via accessibility or a deep link need not generate a hardware input event.
    public static func shouldPause(systemIdle: TimeInterval, runDuration: TimeInterval, threshold: TimeInterval) -> Bool {
        threshold > 0 && min(systemIdle, runDuration) >= threshold
    }
}

/// Only a fresh input after an eligible pause may restart the clock.
public enum AutomaticResumePolicy {
    public static func shouldResume(waiting: Bool, sessionAvailable: Bool, idle: TimeInterval,
                                    now: Date, eligibleAfter: Date) -> Bool {
        waiting && sessionAvailable && idle.isFinite && idle >= 0 && idle < 3
            && now.addingTimeInterval(-idle) > eligibleAfter
    }
}
