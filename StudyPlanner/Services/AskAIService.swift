import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AskAIService {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.availability == .available }
        #endif
        return false
    }

    static var availabilityMessage: String {
        isAvailable
            ? "Apple Intelligence reads your note on this iPhone and prepares a draft. Nothing is saved until you confirm it."
            : "Apple Intelligence isn't available on this iPhone. Dates such as tomorrow or Friday still fill in a draft you can correct. On-device AI needs iOS 26 with Apple Intelligence turned on."
    }

    /// School tasks only. Scheduling stays in WeekPlanner so a model cannot
    /// place work on top of a class, a shift, or sleep.
    static func captureTasks(from prompt: String, courses: [StudyCourse]) async throws -> [TaskDraft] {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DraftError.message("Describe an assignment first.") }
        guard trimmed.count <= 2_000 else { throw DraftError.message("Keep your note under 2,000 characters.") }
        let active = courses.filter { !$0.isArchived }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session = LanguageModelSession(instructions: """
                Extract up to 5 school tasks from the user's note: assignments, exams, quizzes, readings, or projects.
                Do not invent tasks they did not mention. Do not create reminders, calendar events, or a study schedule.
                Match courseName to one of the supplied course names only when the note clearly refers to that course. Otherwise leave it empty.
                Do not invent a due date. When a day is given without a clock time, use 23:59 in the supplied timezone.
                Set estimatedMinutes to 0 when they did not mention a duration.
                Resolve relative dates from the supplied current time. Return dateTime as ISO 8601 with a timezone offset, or empty when no day was given.
                If the note is not school work to track, set supported to false and explain briefly in clarification.
                """)
            let names = active.map(\.name).joined(separator: ", ")
            let request = "Current time: \(Date.now.ISO8601Format()). Timezone: \(TimeZone.current.identifier). Courses: \(names.isEmpty ? "None" : names). Note: \(trimmed)"
            let result = try await session.respond(to: request, generating: GeneratedTaskList.self).content
            try Task.checkCancellation()
            guard result.supported else {
                throw DraftError.message(result.clarification.isEmpty ? "Describe an assignment, exam, or reading to add." : result.clarification)
            }
            let formatter = ISO8601DateFormatter()
            let drafts = result.tasks.prefix(5).compactMap { item -> TaskDraft? in
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                let course = active.first { $0.name.compare(item.courseName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                let minutes = (1...1_440).contains(item.estimatedMinutes) ? item.estimatedMinutes : nil
                return TaskDraft(title: title, courseID: course?.id, dueDate: formatter.date(from: item.dateTime), estimatedMinutes: minutes, usedAI: true)
            }
            guard !drafts.isEmpty else { throw DraftError.message("No tasks were found in that note. Try one assignment per line.") }
            return drafts
        }
        #endif
        return try BasicTaskParser.parse(trimmed, courses: active)
    }

    /// Fills in planning rules the phrase parser did not already recognize.
    /// The parser wins when both have an answer, so a clear "25 minutes" cannot be overwritten.
    static func interpretPlan(_ note: String) async -> PlanReading {
        var reading = PlanStyle.parse(note)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return reading }
            do {
                let session = LanguageModelSession(instructions: """
                    Read how this student wants to plan their own time. Extract only rules they explicitly stated.
                    Do not invent tasks, a schedule, or advice.
                    studyTime is morning, afternoon, evening, or an empty string.
                    blockMinutes is one study block in minutes, or 0 if they did not choose a length. Pomodoro means 25.
                    dailyCapMinutes is the most study time they want in a day, or 0 if unstated.
                    Set remindersMentioned only when they mention reminders or notifications.
                    remindersEnabled is false when they do not want them.
                    reminderLeadMinutes is how long before a due time to remind them, or 0 if unstated. The night before is 1440.
                    dayStartMinutes and dayEndMinutes are minutes from midnight, or -1 if unstated.
                    sleepHours is 0 if unstated.
                    """)
                let result = try await session.respond(to: trimmed, generating: GeneratedPlan.self).content
                try Task.checkCancellation()
                reading.fillGaps(from: recognizedPlan(
                    studyTime: result.studyTime,
                    blockMinutes: result.blockMinutes,
                    dailyCapMinutes: result.dailyCapMinutes,
                    remindersMentioned: result.remindersMentioned,
                    remindersEnabled: result.remindersEnabled,
                    reminderLeadMinutes: result.reminderLeadMinutes,
                    dayStartMinutes: result.dayStartMinutes,
                    dayEndMinutes: result.dayEndMinutes,
                    sleepHours: result.sleepHours
                ))
            } catch {
                return reading
            }
        }
        #endif
        return reading
    }

    /// Reads one day's braindump. Tasks and planning rules only. WeekPlanner
    /// places study blocks after the student confirms, so the model cannot
    /// invent a timetable or write to Calendar.
    static func readBraindump(_ text: String, courses: [StudyCourse]) async -> BraindumpReading {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return BraindumpReading() }
        let clipped = String(trimmed.prefix(BraindumpOrganizer.maximumCharacters))
        let fallback = BraindumpOrganizer.read(clipped, courses: courses)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let active = courses.filter { !$0.isArchived }
            do {
                let session = LanguageModelSession(instructions: """
                    Read a student's morning brain dump. Extract only what they explicitly said.
                    tasks: at most 8 school tasks (assignments, exams, quizzes, readings, or projects). Skip moods, worries, and planning preferences that are not a piece of school work. Do not invent tasks.
                    Match courseName to one of the supplied course names only when the note clearly refers to that course. Otherwise leave it empty.
                    Do not invent a due date. When a day is given without a clock time, use 23:59 in the supplied timezone.
                    Set estimatedMinutes to 0 when they did not mention a duration.
                    Resolve relative dates from the supplied current time. Return dateTime as ISO 8601 with a timezone offset, or empty when no day was given.
                    Also extract planning rules they explicitly stated. Do not invent rules.
                    studyTime is morning, afternoon, evening, or an empty string.
                    blockMinutes is one study block in minutes, or 0 if they did not choose a length. Pomodoro means 25.
                    dailyCapMinutes is the most study time they want in a day, or 0 if unstated.
                    Set remindersMentioned only when they mention reminders or notifications.
                    remindersEnabled is false when they do not want them.
                    reminderLeadMinutes is how long before a due time to remind them, or 0 if unstated. The night before is 1440.
                    dayStartMinutes and dayEndMinutes are minutes from midnight, or -1 if unstated.
                    sleepHours is 0 if unstated.
                    Do not create a timetable, reminders, or calendar events. Do not place study blocks.
                    """)
                let names = active.map(\.name).joined(separator: ", ")
                let request = "Current time: \(Date.now.ISO8601Format()). Timezone: \(TimeZone.current.identifier). Courses: \(names.isEmpty ? "None" : names). Notes:\n\(clipped)"
                let result = try await session.respond(to: request, generating: GeneratedBraindump.self).content
                try Task.checkCancellation()
                var plan = PlanStyle.parse(clipped)
                plan.fillGaps(from: recognizedPlan(
                    studyTime: result.studyTime,
                    blockMinutes: result.blockMinutes,
                    dailyCapMinutes: result.dailyCapMinutes,
                    remindersMentioned: result.remindersMentioned,
                    remindersEnabled: result.remindersEnabled,
                    reminderLeadMinutes: result.reminderLeadMinutes,
                    dayStartMinutes: result.dayStartMinutes,
                    dayEndMinutes: result.dayEndMinutes,
                    sleepHours: result.sleepHours
                ))
                let formatter = ISO8601DateFormatter()
                let drafts = result.tasks.prefix(BraindumpOrganizer.maximumTasks).compactMap { item -> TaskDraft? in
                    let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard title.count >= 2 else { return nil }
                    let course = active.first { $0.name.compare(item.courseName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                    let minutes = (1...1_440).contains(item.estimatedMinutes) ? item.estimatedMinutes : nil
                    return TaskDraft(title: title, courseID: course?.id, dueDate: formatter.date(from: item.dateTime), estimatedMinutes: minutes, usedAI: true)
                }
                return BraindumpReading(tasks: drafts, plan: plan, usedAI: true)
            } catch {
                return fallback
            }
        }
        #endif
        return fallback
    }

    private static func recognizedPlan(
        studyTime: String,
        blockMinutes: Int,
        dailyCapMinutes: Int,
        remindersMentioned: Bool,
        remindersEnabled: Bool,
        reminderLeadMinutes: Int,
        dayStartMinutes: Int,
        dayEndMinutes: Int,
        sleepHours: Double
    ) -> PlanReading {
        var extra = PlanReading()
        if let time = StudyTime(rawValue: studyTime), time != .any { extra.studyTime = time }
        if (1...180).contains(blockMinutes) { extra.blockMinutes = min(90, max(25, blockMinutes)) }
        if (30...8 * 60).contains(dailyCapMinutes) { extra.dailyCapMinutes = dailyCapMinutes }
        if remindersMentioned {
            extra.remindersEnabled = remindersEnabled
            if (15...24 * 60).contains(reminderLeadMinutes) { extra.reminderLeadMinutes = reminderLeadMinutes }
        }
        if (0..<24 * 60).contains(dayStartMinutes) { extra.dayStartMinutes = dayStartMinutes }
        if (0..<24 * 60).contains(dayEndMinutes) { extra.dayEndMinutes = dayEndMinutes }
        if (5...12).contains(sleepHours) { extra.sleepHours = sleepHours }
        return extra
    }

    static func draft(from prompt: String) async throws -> ScheduleDraft {
        guard prompt.count <= 2000 else { throw DraftError.message("Keep your request under 2,000 characters.") }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session = LanguageModelSession(instructions: """
                Extract exactly one new reminder or calendar event from the user's request.
                Do not execute actions. No recurrence, invitees, deleting, or editing existing items.
                If the request needs multiple items, recurrence, or is not an actionable creation request,
                set supported to false and give a short clarification.
                Preserve the user's intent. Use a concise title. Do not invent missing dates.
                Resolve relative dates using the supplied current date and timezone.
                Return dateTime as ISO 8601 with timezone offset, or an empty string if unspecified.
                For date-only requests, use 09:00 local time and set allDay true for calendar events.
                Use 60 minutes if an event duration is unspecified.
                """
            )
            let request = "Current time: \(Date.now.ISO8601Format()). Local timezone: \(TimeZone.current.identifier). Request: \(prompt)"
            let result = try await session.respond(to: request, generating: GeneratedSchedule.self).content
            try Task.checkCancellation()
            guard result.supported else { throw DraftError.message(result.clarification.isEmpty ? "Describe one reminder or event to create." : result.clarification) }
            let formatter = ISO8601DateFormatter()
            let date = formatter.date(from: result.dateTime)
            return ScheduleDraft(kind: result.isReminder ? .reminder : .event,
                title: result.title, date: date, durationMinutes: min(1440, max(1, result.durationMinutes)),
                isAllDay: result.allDay, notes: result.notes, usedAI: true)
        }
        #endif
        return try BasicScheduleParser.parse(prompt)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedPlan {
    @Guide(description: "morning, afternoon, evening, or empty.")
    var studyTime: String
    var blockMinutes: Int
    var dailyCapMinutes: Int
    var remindersMentioned: Bool
    var remindersEnabled: Bool
    var reminderLeadMinutes: Int
    @Guide(description: "Minutes from midnight, or -1 if the user did not set a start.")
    var dayStartMinutes: Int
    @Guide(description: "Minutes from midnight, or -1 if the user did not set an end.")
    var dayEndMinutes: Int
    var sleepHours: Double
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedTaskList {
    @Guide(description: "True only when the note describes school work to track.")
    var supported: Bool
    var clarification: String
    @Guide(description: "At most 5 tasks, and only tasks the user actually mentioned.")
    var tasks: [GeneratedTask]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedTask {
    var title: String
    @Guide(description: "A supplied course name, or empty.")
    var courseName: String
    @Guide(description: "ISO 8601 timestamp with offset, or empty when no due day was given.")
    var dateTime: String
    var estimatedMinutes: Int
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedBraindump {
    @Guide(description: "At most 8 school tasks the student actually mentioned. Empty if the notes have none.")
    var tasks: [GeneratedTask]
    @Guide(description: "morning, afternoon, evening, or empty.")
    var studyTime: String
    var blockMinutes: Int
    var dailyCapMinutes: Int
    var remindersMentioned: Bool
    var remindersEnabled: Bool
    var reminderLeadMinutes: Int
    @Guide(description: "Minutes from midnight, or -1 if the user did not set a start.")
    var dayStartMinutes: Int
    @Guide(description: "Minutes from midnight, or -1 if the user did not set an end.")
    var dayEndMinutes: Int
    var sleepHours: Double
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedSchedule {
    @Guide(description: "True only for one supported new non-repeating reminder or calendar event.")
    var supported: Bool
    var clarification: String
    var isReminder: Bool
    var title: String
    @Guide(description: "ISO 8601 timestamp including offset, or empty if no date was specified.")
    var dateTime: String
    var durationMinutes: Int
    var allDay: Bool
    var notes: String
}
#endif
