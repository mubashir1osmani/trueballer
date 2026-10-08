import Foundation
import SwiftData

/// What a day's stickies contained. Tasks are drafts until the student confirms.
/// Planning rules are the same shape Plan my way already stores. The week
/// planner places study blocks after that confirmation; this type never does.
struct BraindumpReading: Equatable {
    var tasks: [TaskDraft] = []
    var plan: PlanReading = PlanReading()
    var usedAI = false

    var isEmpty: Bool { tasks.isEmpty && !plan.recognized }
}

enum BraindumpOrganizer {
    static let maximumCharacters = 4_000
    static let maximumTasks = 8

    /// Newest day first. Today is always present so the morning has a place to write.
    static func days(from noteDays: [Date], now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        var unique = Set(noteDays.map { calendar.startOfDay(for: $0) })
        unique.insert(today)
        return unique.sorted(by: >)
    }

    /// Phrase-parser fallback used when Apple Intelligence is off or fails.
    /// Mood and planning lines stay out of the task list. PlanStyle reads the
    /// whole note for hours, block length, and reminders.
    static func read(_ text: String, courses: [StudyCourse] = [], now: Date = .now, calendar: Calendar = .current) -> BraindumpReading {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return BraindumpReading() }
        let clipped = String(trimmed.prefix(maximumCharacters))
        var tasks: [TaskDraft] = []
        var seen = Set<String>()
        for line in lines(in: clipped) where tasks.count < maximumTasks {
            guard isTaskLine(line) else { continue }
            guard let draft = try? BasicTaskParser.parse(line, courses: courses, now: now, calendar: calendar).first else { continue }
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsefulTitle(title) else { continue }
            let key = title.lowercased()
            guard seen.insert(key).inserted else { continue }
            var copy = draft
            copy.title = title
            tasks.append(copy)
        }
        return BraindumpReading(tasks: tasks, plan: PlanStyle.parse(clipped), usedAI: false)
    }

    static func describedChanges(_ reading: PlanReading) -> [String] {
        var lines: [String] = []
        if let time = reading.studyTime {
            lines.append(time == .any ? "Study whenever there's open time" : time.label)
        }
        if let minutes = reading.blockMinutes {
            lines.append("\(minutes)-minute blocks")
        }
        if let cap = reading.dailyCapMinutes {
            lines.append(cap == 0 ? "No daily limit" : "Up to \(PlanStyle.span(cap)) a day")
        }
        if let enabled = reading.remindersEnabled {
            lines.append(PlanStyle.reminderPhrase(enabled: enabled, lead: reading.reminderLeadMinutes ?? 120))
        } else if let lead = reading.reminderLeadMinutes {
            lines.append(PlanStyle.reminderPhrase(enabled: true, lead: lead))
        }
        if let start = reading.dayStartMinutes {
            lines.append("Day starts \(PlanStyle.clockLabel(start))")
        }
        if let end = reading.dayEndMinutes {
            lines.append("Day ends \(PlanStyle.clockLabel(end))")
        }
        if let sleep = reading.sleepHours {
            lines.append(String(format: "Sleep %.1f h", sleep))
        }
        return lines
    }

    static func copy(of settings: UserSettings) -> UserSettings {
        let copy = UserSettings(
            workdayStartMinutes: settings.workdayStartMinutes,
            workdayEndMinutes: settings.workdayEndMinutes,
            sleepTargetHours: settings.sleepTargetHours,
            selectedCalendarIDs: settings.selectedCalendarIDs
        )
        copy.remindersEnabled = settings.remindersEnabled
        copy.reminderLeadMinutes = settings.reminderLeadMinutes
        copy.planNote = settings.planNote
        copy.studyTime = settings.studyTime
        copy.blockMinutes = settings.blockMinutes
        copy.usesCustomBlockLength = settings.usesCustomBlockLength
        copy.dailyCapMinutes = settings.dailyCapMinutes
        copy.dismissedSuggestionIDs = settings.dismissedSuggestionIDs
        return copy
    }

    /// Writes only the rules the note actually mentioned.
    static func apply(_ reading: PlanReading, to settings: UserSettings) {
        if let time = reading.studyTime { settings.studyTime = time.rawValue }
        if let minutes = reading.blockMinutes {
            settings.blockMinutes = min(90, max(25, minutes))
            settings.usesCustomBlockLength = true
        }
        if let cap = reading.dailyCapMinutes { settings.dailyCapMinutes = cap }
        if let enabled = reading.remindersEnabled { settings.remindersEnabled = enabled }
        if let lead = reading.reminderLeadMinutes { settings.reminderLeadMinutes = lead }
        if let start = reading.dayStartMinutes { settings.workdayStartMinutes = start }
        if let end = reading.dayEndMinutes { settings.workdayEndMinutes = end }
        if let sleep = reading.sleepHours { settings.sleepTargetHours = sleep }
    }

    /// Preview of where confirmed tasks would sit. Existing tasks stay in the
    /// ranking. Drafts are not inserted into the student's store.
    static func scheduledBlocks(
        existing: [StudyTask],
        drafts: [TaskDraft],
        courses: [StudyCourse],
        grades: [GradeEntry],
        busy: [WeekPlanner.BusyInterval],
        settings: UserSettings,
        plan: PlanReading,
        applyPlan: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WeekPlanner.Block] {
        let previewSettings = copy(of: settings)
        if applyPlan { apply(plan, to: previewSettings) }
        let proposed = drafts.compactMap { draft -> StudyTask? in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let course = courses.first { $0.id == draft.courseID }
            return StudyTask(
                title: title,
                dueDate: draft.dueDate,
                courseName: course?.name,
                estimatedMinutes: draft.estimatedMinutes,
                courseID: course?.id
            )
        }
        return WeekPlanner.suggest(
            tasks: existing + proposed,
            courses: courses,
            grades: grades,
            busy: busy,
            settings: previewSettings,
            now: now,
            calendar: calendar
        )
    }

    private static func lines(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isNewline || $0 == ";" })
            .flatMap { chunk in String(chunk).components(separatedBy: ". ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// A deliverable with a date or an action, or an explicit "due Friday" line.
    /// "Study in the morning" and "I'm anxious about the exam" are not tasks.
    private static func isTaskLine(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return false }
        let hasDeliverable = text.range(of: deliverable, options: .regularExpression) != nil
        let hasAction = text.range(of: action, options: .regularExpression) != nil
        let hasDate = text.range(of: dated, options: .regularExpression) != nil
        let hasDue = text.range(of: #"\b(due|deadline)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let negated = text.range(of: #"(?i)\b(don't|do not|dont)\b"#, options: .regularExpression) != nil
        if negated && !hasDue { return false }
        if hasDue && hasDate { return true }
        return hasDeliverable && (hasAction || hasDate || hasDue)
    }

    private static func isUsefulTitle(_ title: String) -> Bool {
        let stripped = title.replacingOccurrences(
            of: #"(?i)\b(due|by|on|at|today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|the|a|an|for|my)\b"#,
            with: "",
            options: .regularExpression
        )
        return stripped.filter(\.isLetter).count >= 2
    }

    private static let deliverable = #"(?i)\b(quizzes|quiz|exams|exam|midterms|midterm|finals|final|essays|essay|homework|assignments|assignment|chapters|chapter|problem sets|problem set|psets|pset|labs|lab|papers|paper|presentations|presentation|worksheets|worksheet|projects|project|readings|reading)\b"#
    private static let action = #"(?i)\b(finish|complete|write|read|review|practice|submit|study for|start|do|prepare)\b"#
    private static let dated = #"(?i)\b(today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
}
