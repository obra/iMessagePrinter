import Foundation

enum DateFormatting {
    /// Convert Apple's nanosecond timestamp (nanoseconds since 2001-01-01) to Date
    static func dateFromAppleTimestamp(_ nanoseconds: Int64?) -> Date? {
        guard let nanoseconds, nanoseconds > 0 else { return nil }
        let seconds = Double(nanoseconds) / 1_000_000_000.0
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd h:mm:ss a"
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static func formatDateTime(_ date: Date?) -> String {
        guard let date else { return "" }
        return dateTimeFormatter.string(from: date)
    }

    static func formatDateOnly(_ date: Date?) -> String {
        guard let date else { return "" }
        return dateOnlyFormatter.string(from: date)
    }

    static func formatTimeOnly(_ date: Date?) -> String {
        guard let date else { return "" }
        return timeOnlyFormatter.string(from: date)
    }

    /// Returns true if two dates are on the same calendar day
    static func isSameDay(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }
}
