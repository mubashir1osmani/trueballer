import Foundation

/// Claude through the StudyPlanner API. Callers fall back to the on-device
/// model or the date parser when this returns nil, so a network problem or a
/// used-up quota never blocks capturing work.
@MainActor
enum CloudAI {
    struct Notice: Equatable, Sendable {
        var message: String
        var offersUpgrade = false
    }

    static func captureTasks(_ note: String, courses: [StudyCourse], account: AccountStore) async throws -> [TaskDraft]? {
        guard account.canUseCloudAI else { return nil }
        let active = courses.filter { !$0.isArchived }
        do {
            let (result, _) = try await account.client.capture(.init(note: note, courses: active.map(\.name)))
            guard result.supported else {
                throw DraftError.message(result.clarification.isEmpty ? "Describe an assignment, exam, or reading to add." : result.clarification)
            }
            let drafts = drafts(from: result.tasks, courses: active, limit: 5)
            guard !drafts.isEmpty else { throw DraftError.message("No tasks were found in that note. Try one assignment per line.") }
            return drafts
        } catch let failure as APIClient.Failure {
            await record(failure, account: account)
            return nil
        }
    }

    static func readBraindump(_ text: String, courses: [StudyCourse], account: AccountStore) async -> BraindumpReading? {
        guard account.canUseCloudAI else { return nil }
        let active = courses.filter { !$0.isArchived }
        do {
            let (result, _) = try await account.client.braindump(.init(note: text, courses: active.map(\.name)))
            var plan = PlanStyle.parse(text)
            plan.fillGaps(from: AskAIService.recognizedPlan(
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
            let tasks = drafts(from: result.tasks, courses: active, limit: BraindumpOrganizer.maximumTasks)
                .filter { $0.title.count >= 2 }
            return BraindumpReading(tasks: tasks, plan: plan, usedAI: true)
        } catch let failure as APIClient.Failure {
            await record(failure, account: account)
            return nil
        } catch {
            return nil
        }
    }

    /// Same validation the on-device path applies: known courses only,
    /// plausible estimates, and dates the parser can read.
    nonisolated static func drafts(from tasks: [APIClient.CloudTask], courses: [StudyCourse], limit: Int) -> [TaskDraft] {
        let formatter = ISO8601DateFormatter()
        return tasks.prefix(limit).compactMap { item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let course = courses.first { $0.name.compare(item.courseName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            let minutes = (1...1_440).contains(item.estimatedMinutes) ? item.estimatedMinutes : nil
            return TaskDraft(title: title, courseID: course?.id, dueDate: formatter.date(from: item.dateTime), estimatedMinutes: minutes, usedAI: true)
        }
    }

    private static func record(_ failure: APIClient.Failure, account: AccountStore) async {
        switch failure {
        case .unauthorized: account.signOut()
        case .consentRequired: await account.refresh()
        case .quotaExceeded, .upgradeRequired, .declined, .unavailable, .offline: break
        }
        account.lastNotice = notice(for: failure)
    }

    nonisolated static func notice(for failure: APIClient.Failure) -> Notice? {
        switch failure {
        case .quotaExceeded(let limit):
            return Notice(message: "You've used today's \(limit) Claude reads. This draft came from the on-device reader instead.", offersUpgrade: true)
        case .upgradeRequired:
            return Notice(message: "That feature is part of Plus. This draft came from the on-device reader.", offersUpgrade: true)
        case .offline:
            return Notice(message: "You're offline, so this draft came from the on-device reader.")
        case .declined, .unavailable:
            return Notice(message: "Claude couldn't read that one, so the on-device reader filled in the draft.")
        case .unauthorized, .consentRequired:
            return nil
        }
    }
}
