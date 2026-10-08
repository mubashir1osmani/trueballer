import Foundation
import SwiftData

/// Places open tasks into free time for the next week.
/// Calendar events, working hours, and the sleep target are hard limits.
/// Task order comes from Planner, which already prefers overdue work and
/// below-target courses. This type only decides *when* those tasks fit.
enum WeekPlanner {
    struct BusyInterval: Equatable {
        var start: Date
        var end: Date
        var isAllDay: Bool = false
    }

    struct Block: Identifiable, Equatable {
        var taskID: PersistentIdentifier
        var title: String
        var courseName: String?
        var protectsGPA: Bool
        var start: Date
        var end: Date

        var id: String { "\(taskID)-\(start.timeIntervalSinceReferenceDate)" }
        var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
    }

    static let horizonDays = 7
    static let minimumMinutes = 25
    static let maximumMinutes = 90
    /// One task cannot fill the whole week and hide everything else.
    static let maximumTaskMinutes = 240
    static let maximumBlocks = 12
    static let defaultMinutes = 45
    static let atRiskDefaultMinutes = 60

    /// Working hours clipped so the window ends at least `sleepTargetHours`
    /// before the next day's start. Nil when the window is shorter than a block
    /// or the day has already ended.
    static func availabilityWindow(on dayStart: Date, settings: UserSettings, now: Date, calendar: Calendar, clampToNow: Bool) -> DateInterval? {
        let wake = dayStart.addingTimeInterval(TimeInterval(settings.workdayStartMinutes * 60))
        var end = dayStart.addingTimeInterval(TimeInterval(settings.workdayEndMinutes * 60))
        guard end > wake else { return nil }
        let nextWake = calendar.date(byAdding: .day, value: 1, to: wake) ?? wake.addingTimeInterval(86_400)
        let bedtime = nextWake.addingTimeInterval(-settings.sleepTargetHours * 3_600)
        if bedtime < end { end = bedtime }
        var start = wake
        if clampToNow { start = max(start, now) }
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func freeMinutes(from start: Date, to end: Date, busy: [BusyInterval]) -> Int {
        guard end > start else { return 0 }
        let occupied = mergedBusy(from: start, to: end, busy: busy)
            .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        return max(0, Int((end.timeIntervalSince(start) - occupied) / 60))
    }

    static func suggest(
        tasks: [StudyTask],
        courses: [StudyCourse],
        grades: [GradeEntry],
        busy: [BusyInterval],
        settings: UserSettings,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Block] {
        let ranked = Planner.rankedTasks(tasks, courses: courses, grades: grades, now: now)
        guard !ranked.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        var slots: [DateInterval] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  var window = availabilityWindow(on: day, settings: settings, now: now, calendar: calendar, clampToNow: offset == 0)
            else { continue }
            if offset == 0 {
                let rounded = roundedUp(window.start, calendar: calendar)
                guard rounded < window.end else { continue }
                window = DateInterval(start: rounded, end: window.end)
            }
            guard let preferred = clip(window, to: StudyTime(rawValue: settings.studyTime) ?? .any, dayStart: day) else { continue }
            slots.append(contentsOf: openSlots(from: preferred.start, to: preferred.end, busy: busy))
        }

        let chunkLimit = settings.usesCustomBlockLength
            ? min(maximumMinutes, max(minimumMinutes, settings.blockMinutes))
            : maximumMinutes
        var placedByDay: [Date: Int] = [:]
        var blocks: [Block] = []
        for task in ranked where blocks.count < maximumBlocks {
            let course = CourseCatalog.course(for: task, in: courses)
            let protects = course.map { !$0.isArchived && AcademicProgress.summary(course: $0, grades: grades).belowTarget } ?? false
            var remaining = minutesToPlace(task, protectsGPA: protects, settings: settings)
            let floor = remaining < minimumMinutes ? remaining : minimumMinutes
            let deadline: Date? = task.dueDate.flatMap { $0 > now ? $0 : nil }
            var placed = 0
            while remaining >= floor, placed < 4, blocks.count < maximumBlocks {
                guard let chunk = take(minutes: remaining, before: deadline, chunkLimit: chunkLimit, cap: settings.dailyCapMinutes, placedByDay: placedByDay, calendar: calendar, from: &slots) else { break }
                blocks.append(Block(
                    taskID: task.persistentModelID,
                    title: task.title,
                    courseName: task.courseName ?? course?.name,
                    protectsGPA: protects,
                    start: chunk.start,
                    end: chunk.end
                ))
                let dayKey = calendar.startOfDay(for: chunk.start)
                placedByDay[dayKey, default: 0] += chunk.minutes
                remaining -= chunk.minutes
                placed += 1
                if remaining < minimumMinutes { break }
            }
        }
        return blocks.sorted { $0.start < $1.start }
    }

    /// Rounds up to the next 5 minutes so a suggestion does not start in the past.
    static func roundedUp(_ date: Date, minutes step: Int = 5, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        let minute = parts.minute ?? 0
        let base = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: parts.hour, minute: minute)) ?? date
        let hasSeconds = (parts.second ?? 0) > 0 || (parts.nanosecond ?? 0) > 0
        if minute % step == 0 && !hasSeconds { return base }
        let add = minute % step == 0 ? step : step - (minute % step)
        return calendar.date(byAdding: .minute, value: add, to: base) ?? date
    }

    /// Keeps study blocks inside the part of the day the student asked for.
    static func clip(_ window: DateInterval, to time: StudyTime, dayStart: Date) -> DateInterval? {
        let band: (Int, Int)?
        switch time {
        case .any: return window
        case .morning: band = (0, 12 * 60)
        case .afternoon: band = (12 * 60, 17 * 60)
        case .evening: band = (17 * 60, 24 * 60)
        }
        guard let band else { return window }
        let start = max(window.start, dayStart.addingTimeInterval(TimeInterval(band.0 * 60)))
        let end = min(window.end, dayStart.addingTimeInterval(TimeInterval(band.1 * 60)))
        guard end.timeIntervalSince(start) >= TimeInterval(minimumMinutes * 60) else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func minutesToPlace(_ task: StudyTask, protectsGPA: Bool, settings: UserSettings) -> Int {
        if settings.usesCustomBlockLength {
            let chosen = min(maximumMinutes, max(minimumMinutes, settings.blockMinutes))
            if let estimate = task.estimatedMinutes, estimate > 0 {
                return min(estimate, maximumTaskMinutes)
            }
            return chosen
        }
        if let estimate = task.estimatedMinutes, estimate > 0 {
            return min(estimate, maximumTaskMinutes)
        }
        return protectsGPA ? atRiskDefaultMinutes : defaultMinutes
    }

    private struct Chunk {
        var start: Date
        var end: Date
        var minutes: Int
    }

    private static func take(minutes wanted: Int, before deadline: Date?, chunkLimit: Int, cap: Int, placedByDay: [Date: Int], calendar: Calendar, from slots: inout [DateInterval]) -> Chunk? {
        let floor = wanted < minimumMinutes ? wanted : minimumMinutes
        guard floor > 0 else { return nil }
        for index in slots.indices {
            var start = slots[index].start
            var end = slots[index].end
            if let deadline {
                if start >= deadline { continue }
                if end > deadline { end = deadline }
            }
            var length = min(wanted, Int(end.timeIntervalSince(start) / 60), chunkLimit)
            if cap > 0 {
                let room = cap - (placedByDay[calendar.startOfDay(for: start)] ?? 0)
                if room < floor { continue }
                length = min(length, room)
            }
            guard length >= floor else { continue }
            let blockEnd = start.addingTimeInterval(TimeInterval(length * 60))
            slots[index] = DateInterval(start: blockEnd, end: slots[index].end)
            return Chunk(start: start, end: blockEnd, minutes: length)
        }
        return nil
    }

    private struct Span {
        var start: Date
        var end: Date
    }

    private static func mergedBusy(from start: Date, to end: Date, busy: [BusyInterval]) -> [Span] {
        let clipped = busy
            .filter { !$0.isAllDay && $0.end > start && $0.start < end }
            .map { Span(start: max($0.start, start), end: min($0.end, end)) }
            .sorted { $0.start < $1.start }
        var merged: [Span] = []
        for span in clipped {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1].end = max(last.end, span.end)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    private static func openSlots(from start: Date, to end: Date, busy: [BusyInterval]) -> [DateInterval] {
        guard end > start else { return [] }
        var slots: [DateInterval] = []
        var cursor = start
        for span in mergedBusy(from: start, to: end, busy: busy) {
            if span.start.timeIntervalSince(cursor) >= TimeInterval(minimumMinutes * 60) {
                slots.append(DateInterval(start: cursor, end: span.start))
            }
            cursor = max(cursor, span.end)
        }
        if end.timeIntervalSince(cursor) >= TimeInterval(minimumMinutes * 60) {
            slots.append(DateInterval(start: cursor, end: end))
        }
        return slots
    }
}
