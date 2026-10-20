import Foundation

/// A study day runs from local 05:00 to the following day's 05:00,
/// so late-night cramming still counts toward the day it belongs to.
public enum StudyDay {
    public static let boundaryHour = 5

    public static func start(for date: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: date)
        let boundary = calendar.date(bySettingHour: boundaryHour, minute: 0, second: 0, of: midnight)!
        if date >= boundary { return boundary }
        let previous = calendar.date(byAdding: .day, value: -1, to: midnight)!
        return calendar.date(bySettingHour: boundaryHour, minute: 0, second: 0, of: previous)!
    }

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        FocusState.dayKey(start(for: date, calendar: calendar), calendar: calendar)
    }

    /// Clock hours (as stored keys) before the boundary, which belong to the previous study day.
    static let earlyHours = (0..<boundaryHour).map(String.init)
}
