import Foundation

/// A study day runs from local 01:00 to the following day's 01:00.
public enum StudyDay {
    public static func start(for date: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: date)
        let boundary = calendar.date(bySettingHour: 1, minute: 0, second: 0, of: midnight)!
        if date >= boundary { return boundary }
        let previous = calendar.date(byAdding: .day, value: -1, to: midnight)!
        return calendar.date(bySettingHour: 1, minute: 0, second: 0, of: previous)!
    }

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        FocusState.dayKey(start(for: date, calendar: calendar), calendar: calendar)
    }
}
