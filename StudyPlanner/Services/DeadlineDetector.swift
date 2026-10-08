import EventKit
import Foundation

/// Finds calendar events that look like deadlines. These become *suggestions*
/// the user confirms — never auto-created tasks (plan.md, Phase 1c).
enum DeadlineDetector {
    private static let patterns: [String] = [
        "due", "deadline", "submit", "submission", "exam", "quiz", "test",
        "midterm", "final", "essay", "assignment", "homework", "hw", "turn in"
    ]

    static func isDeadlineLike(_ event: EKEvent) -> Bool {
        guard let title = event.title?.lowercased() else { return false }
        let titleMatches = patterns.contains { title.contains($0) }

        // 11:45pm–midnight starts are the classic "due at 11:59" shape.
        let parts = Calendar.current.dateComponents([.hour, .minute], from: event.startDate)
        let lateNight = (parts.hour == 23 && (parts.minute ?? 0) >= 45)

        return titleMatches || (event.isAllDay && titleMatches) || (lateNight && titleMatches)
            || (titleMatches && event.endDate.timeIntervalSince(event.startDate) <= 60 * 15)
    }

    static func isDeadlineTitle(_ title: String) -> Bool {
        patterns.contains { title.lowercased().contains($0) }
    }

    /// Deadline-like events with no existing task and not previously dismissed.
    static func suggestions(events: [EKEvent],
                            existingTasks: [StudyTask],
                            dismissedEventIDs: [String]) -> [EKEvent] {
        let taskEventIDs = Set(existingTasks.compactMap(\.sourceEventID))
        let dismissed = Set(dismissedEventIDs)
        return events.filter { event in
            guard let id = event.eventIdentifier else { return false }
            return isDeadlineLike(event) && !taskEventIDs.contains(id) && !dismissed.contains(id)
        }
    }
}
