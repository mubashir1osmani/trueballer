import Foundation
import SwiftData

@Model
final class StudyTask {
    var title: String
    var dueDate: Date?
    /// Display title of the course group this belongs to, if any.
    var courseName: String?
    /// Stable link for grades and priority; old name-only tasks are backfilled.
    var courseID: UUID?
    /// EKEvent identifier when this task was confirmed from a calendar suggestion.
    var sourceEventID: String?
    var isCompleted: Bool
    var createdAt: Date
    /// Hidden from Next up until this passes (Phase 2 snooze).
    var snoozedUntil: Date?
    /// Total expected effort; optional so existing tasks migrate unchanged.
    var estimatedMinutes: Int?

    init(title: String,
         dueDate: Date? = nil,
         courseName: String? = nil,
         sourceEventID: String? = nil,
         estimatedMinutes: Int? = nil,
         courseID: UUID? = nil) {
        self.title = title
        self.dueDate = dueDate
        self.courseName = courseName
        self.courseID = courseID
        self.sourceEventID = sourceEventID
        self.estimatedMinutes = estimatedMinutes
        self.isCompleted = false
        self.createdAt = .now
    }
}
