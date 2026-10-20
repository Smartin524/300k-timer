import Foundation

public struct SleepInterval: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A night's sleep: at least four hours without input, at least one of them
/// inside local 00:00–08:00. Long afternoon or evening absences do not qualify.
public enum SleepPolicy {
    public static let minimumGap: TimeInterval = 4 * 3600
    public static let minimumNightOverlap: TimeInterval = 3600

    public static func isNightSleep(from start: Date, to end: Date, calendar: Calendar = .current) -> Bool {
        let gap = end.timeIntervalSince(start)
        guard gap >= minimumGap else { return false }
        if gap >= 86400 { return true }
        var overlap: TimeInterval = 0
        var midnight = calendar.startOfDay(for: start)
        while midnight < end {
            let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: midnight)!
            overlap += max(0, min(end, morning).timeIntervalSince(max(start, midnight)))
            midnight = calendar.date(byAdding: .day, value: 1, to: midnight)!
        }
        return overlap >= minimumNightOverlap
    }
}
