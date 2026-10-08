import Foundation
import SwiftData

/// Singleton-style settings record. Fetch the first instance or create one.
@Model
final class UserSettings {
    /// Minutes from midnight, e.g. 9 * 60 = 9:00 AM.
    var workdayStartMinutes: Int
    var workdayEndMinutes: Int
    /// Target hours of sleep per night.
    var sleepTargetHours: Double
    /// Device calendar IDs the user chose to include. nil = all calendars.
    var selectedCalendarIDs: [String]?
    /// Event IDs of deadline suggestions the user dismissed on Today.
    var dismissedSuggestionIDs: [String]?
    /// Phase 2: local reminders for task due dates.
    var remindersEnabled: Bool = false
    /// How long before the due date the reminder fires.
    var reminderLeadMinutes: Int = 120
    /// The student's own words for how they want the day to work.
    var planNote: String = ""
    /// any, morning, afternoon, or evening. Study blocks stay inside this part of the day.
    var studyTime: String = "any"
    /// Used when the student chooses a block length. Otherwise the planner keeps its own defaults.
    var blockMinutes: Int = 45
    var usesCustomBlockLength: Bool = false
    /// 0 means no daily cap. A cap keeps the day from filling every open minute.
    var dailyCapMinutes: Int = 0

    init(workdayStartMinutes: Int = 9 * 60,
         workdayEndMinutes: Int = 22 * 60,
         sleepTargetHours: Double = 8,
         selectedCalendarIDs: [String]? = nil) {
        self.workdayStartMinutes = workdayStartMinutes
        self.workdayEndMinutes = workdayEndMinutes
        self.sleepTargetHours = sleepTargetHours
        self.selectedCalendarIDs = selectedCalendarIDs
    }

    var workdayStart: Date {
        get { Self.date(fromMinutes: workdayStartMinutes) }
        set { workdayStartMinutes = Self.minutes(from: newValue) }
    }

    var workdayEnd: Date {
        get { Self.date(fromMinutes: workdayEndMinutes) }
        set { workdayEndMinutes = Self.minutes(from: newValue) }
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
