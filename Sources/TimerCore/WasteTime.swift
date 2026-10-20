import Foundation

public enum WasteSite: String, Codable, CaseIterable, Sendable {
    case bilibili, tieba, douyu, xiaohongshu, x

    public var title: String {
        switch self {
        case .bilibili: return "B 站"
        case .tieba: return "贴吧"
        case .douyu: return "斗鱼"
        case .xiaohongshu: return "小红书"
        case .x: return "X"
        }
    }

    public static func match(_ address: String) -> WasteSite? {
        SiteCatalog.entry(for: address)?.waste
    }
}

/// Local aggregates only: no URLs, page titles, or browsing history.
public struct WasteTimeState: Codable, Equatable, Sendable {
    public var secondsByDayAndSite: [String: [String: TimeInterval]] = [:]
    /// Optional for backward compatibility; old daily totals cannot be assigned to hours.
    public var secondsByStudyDayAndHour: [String: [String: TimeInterval]]?
    public func hours(on day: String) -> [String: TimeInterval] {
        secondsByStudyDayAndHour?[day] ?? [:]
    }
    public init() {}
    public var total: TimeInterval { secondsByDayAndSite.values.flatMap { $0.values }.reduce(0, +) }
    public func seconds(on day: String, site: WasteSite? = nil) -> TimeInterval {
        let values = secondsByDayAndSite[day] ?? [:]
        if let site { return values[site.rawValue, default: 0] }
        return values.values.reduce(0, +)
    }

    fileprivate mutating func adjust(from start: Date, to end: Date, site: WasteSite,
                                     multiplier: Double, calendar: Calendar) {
        var cursor = start
        while cursor < end {
            let dayStart = StudyDay.start(for: cursor, calendar: calendar)
            let next = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let hourEnd = calendar.dateInterval(of: .hour, for: cursor)!.end
            let until = min(end, next, hourEnd)
            let key = StudyDay.key(for: cursor, calendar: calendar)
            let value = secondsByDayAndSite[key]?[site.rawValue] ?? 0
            secondsByDayAndSite[key, default: [:]][site.rawValue] = max(0, value + multiplier * until.timeIntervalSince(cursor))
            let hour = String(calendar.component(.hour, from: cursor))
            if secondsByStudyDayAndHour == nil { secondsByStudyDayAndHour = [:] }
            let hourlyValue = secondsByStudyDayAndHour?[key]?[hour] ?? 0
            secondsByStudyDayAndHour![key, default: [:]][hour] = max(0, hourlyValue + multiplier * until.timeIntervalSince(cursor))
            cursor = until
        }
    }
}

/// Short-lived credit receipts allow exact rollback across site and study-day switches.
/// Receipts are bounded to the current five-minute idle window and never saved as history.
public struct WasteTimeTracker {
    private struct Credit {
        let start: Date
        let end: Date
        let site: WasteSite
    }
    private var credits: [Credit] = []
    private var previousDate: Date?
    private var previousSite: WasteSite?
    private var previousInput: Date?
    public private(set) var activeSite: WasteSite?
    public init() {}

    public mutating func observe(at now: Date, site: WasteSite?, idle: TimeInterval,
                                 state: inout WasteTimeState, calendar: Calendar = .current) {
        guard idle.isFinite, idle >= 0 else {
            previousDate = nil
            previousSite = nil
            activeSite = nil
            return
        }
        let lastInput = now.addingTimeInterval(-idle)
        // Input can arrive just before the next poll at the five-minute boundary.
        // Detect that gap before treating older provisional credit as active use.
        let returnedAfterIdle = previousInput.map { lastInput.timeIntervalSince($0) >= 300 } ?? false
        let rollbackStart = returnedAfterIdle ? previousInput! : lastInput
        previousInput = max(previousInput ?? lastInput, lastInput)
        if idle >= 300 || returnedAfterIdle {
            for credit in credits {
                state.adjust(from: max(credit.start, rollbackStart), to: credit.end,
                             site: credit.site, multiplier: -1, calendar: calendar)
            }
            credits.removeAll()
            previousDate = nil
            previousSite = nil
            activeSite = nil
            if idle >= 300 { return }
        }
        // New input validates older provisional time. Keep only receipts that may be rolled back.
        credits = credits.compactMap { credit in
            guard credit.end > lastInput else { return nil }
            return Credit(start: max(credit.start, lastInput), end: credit.end, site: credit.site)
        }
        if let previousDate, let site, site == previousSite {
            let delta = now.timeIntervalSince(previousDate)
            // Unknown gaps, sleep and a changed/failed tab observation are not guessed.
            if delta > 0 && delta <= 5 {
                state.adjust(from: previousDate, to: now, site: site, multiplier: 1, calendar: calendar)
                credits.append(Credit(start: previousDate, end: now, site: site))
            }
        }
        previousDate = now
        previousSite = site
        activeSite = site
    }
}
