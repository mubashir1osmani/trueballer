import EventKit
import Foundation

/// Ranks open tasks into "next actions" and measures today's free time.
/// Plan.md Phase 2: due × weight × available time.
enum Planner {

    // MARK: - Ranking

    /// Deadline windows protect overdue and next-day work. Below-target
    /// courses receive a bounded, credit-sensitive boost within later windows.
    /// Snoozed/completed tasks are hidden; undated tasks remain last.
    static func rankedTasks(_ tasks: [StudyTask], courses: [StudyCourse] = [], grades: [GradeEntry] = [], now: Date = .now) -> [StudyTask] {
        func tier(_ task: StudyTask) -> Int {
            guard let due = task.dueDate else { return 4 }
            let hours = due.timeIntervalSince(now) / 3600
            return hours < 0 ? 0 : hours <= 24 ? 1 : hours <= 168 ? 2 : 3
        }
        func boost(_ task: StudyTask) -> Double {
            guard let course = CourseCatalog.course(for: task, in: courses) else { return 1 }
            return AcademicProgress.priorityBoost(course: course, grades: grades)
        }
        return tasks
            .filter { !$0.isCompleted && !isSnoozed($0, now: now) }
            .sorted {
                let firstTier = tier($0), secondTier = tier($1)
                if firstTier != secondTier { return firstTier < secondTier }
                // Keep overdue and next-24-hour deadlines in chronological order.
                if firstTier <= 1, $0.dueDate != $1.dueDate { return $0.dueDate! < $1.dueDate! }
                let firstScore = firstTier == 4 ? boost($0) : score($0, now: now) * boost($0)
                let secondScore = firstTier == 4 ? boost($1) : score($1, now: now) * boost($1)
                if firstScore != secondScore { return firstScore > secondScore }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.title < $1.title
            }
    }

    static func isSnoozed(_ task: StudyTask, now: Date) -> Bool {
        guard let until = task.snoozedUntil else { return false }
        return until > now
    }

    private static func score(_ task: StudyTask, now: Date) -> Double {
        guard let due = task.dueDate else {
            // Dateless: below any dated task; older entries first.
            return -1_000_000 - now.timeIntervalSince(task.createdAt) / 86_400
        }
        let hoursLeft = due.timeIntervalSince(now) / 3600
        if hoursLeft < 0 {
            // Overdue: top of the list, most-overdue first.
            return 1_000_000 + abs(hoursLeft)
        }
        // Sooner due = higher score. +1 avoids divide-by-zero.
        return 10_000 / (hoursLeft + 1)
    }

    // MARK: - Free time

    struct DaySummary {
        var freeMinutes: Int
        /// Today's remaining timed events, sorted by start.
        var lockedEvents: [EKEvent]
    }

    /// Free minutes left in today's study window, after timed events.
    /// The window is working hours clipped by the sleep target. All-day events
    /// stay on the schedule but do not use clock time.
    static func daySummary(events: [EKEvent], settings: UserSettings, now: Date = .now) -> DaySummary {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let todaysEvents = events
            .filter { !$0.isAllDay && calendar.isDate($0.startDate, inSameDayAs: now) && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        guard let window = WeekPlanner.availabilityWindow(on: dayStart, settings: settings, now: now, calendar: calendar, clampToNow: true) else {
            return DaySummary(freeMinutes: 0, lockedEvents: todaysEvents)
        }
        let busy = todaysEvents.map { WeekPlanner.BusyInterval(start: $0.startDate, end: $0.endDate, isAllDay: false) }
        return DaySummary(freeMinutes: WeekPlanner.freeMinutes(from: window.start, to: window.end, busy: busy), lockedEvents: todaysEvents)
    }
}
