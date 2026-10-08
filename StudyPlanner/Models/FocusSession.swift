import Foundation
import SwiftData

/// An unfinished record is the durable timer. Finishing updates this same
/// record, so restoring or tapping twice cannot log a session twice.
@Model
final class FocusSession {
    var id: UUID = UUID()
    var task: StudyTask?
    var taskTitle: String
    var courseName: String?
    var courseID: UUID?
    var estimatedMinutes: Int
    var startedAt: Date
    var endedAt: Date?
    var accumulatedSeconds: Double = 0
    var runningSince: Date?
    var completedTask: Bool = false

    init(task: StudyTask, estimatedMinutes: Int, now: Date) {
        self.task = task
        self.taskTitle = task.title
        self.courseName = task.courseName
        self.courseID = task.courseID
        self.estimatedMinutes = estimatedMinutes
        self.startedAt = now
        self.runningSince = now
    }

    var isPaused: Bool { runningSince == nil && endedAt == nil }

    func elapsed(at now: Date) -> TimeInterval {
        accumulatedSeconds + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}
