import Foundation
import SwiftData

enum CourseCatalog {
    static func matching(name: String?, in courses: [StudyCourse]) -> StudyCourse? {
        guard let name else { return nil }
        let matches = courses.filter { normalizeEventTitle($0.name) == normalizeEventTitle(name) }
        // Never silently assign grades/effort to one of two identically named courses.
        return matches.count == 1 ? matches[0] : nil
    }

    static func course(for task: StudyTask, in courses: [StudyCourse]) -> StudyCourse? {
        if let id = task.courseID { return courses.first { $0.id == id } }
        return matching(name: task.courseName, in: courses)
    }

    static func course(for session: FocusSession, in courses: [StudyCourse]) -> StudyCourse? {
        if let id = session.courseID { return courses.first { $0.id == id } }
        if let task = session.task { return course(for: task, in: courses) }
        return matching(name: session.courseName, in: courses)
    }

    @MainActor
    static func synchronize(groups: [EventGroup], tasks: [StudyTask], sessions: [FocusSession], context: ModelContext) throws {
        var courses = try context.fetch(FetchDescriptor<StudyCourse>())
        for group in groups where group.tag == .course && !DeadlineDetector.isDeadlineTitle(group.displayTitle) {
            guard !courses.contains(where: { $0.sourceGroupID == group.id }) else { continue }
            let course = StudyCourse(name: group.displayTitle, sourceGroupID: group.id, calendarName: group.calendarTitle)
            context.insert(course)
            courses.append(course)
        }
        // Preserve courses from old tasks/history even without calendar permission.
        let oldNames = tasks.filter { $0.courseID == nil }.compactMap(\.courseName)
            + sessions.filter { $0.courseID == nil }.compactMap(\.courseName)
        for name in oldNames where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard !courses.contains(where: { normalizeEventTitle($0.name) == normalizeEventTitle(name) }) else { continue }
            let course = StudyCourse(name: name)
            context.insert(course)
            courses.append(course)
        }
        for task in tasks where task.courseID == nil {
            if let course = matching(name: task.courseName, in: courses) { task.courseID = course.id }
        }
        for session in sessions where session.courseID == nil {
            if let course = course(for: session, in: courses) { session.courseID = course.id }
        }
        if context.hasChanges { try context.save() }
    }
}
