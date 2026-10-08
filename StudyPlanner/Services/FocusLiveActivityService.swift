import ActivityKit
import Foundation

@MainActor
protocol FocusActivityManaging {
    func synchronize(session: FocusSession?, now: Date) async -> String?
}

@MainActor
final class FocusLiveActivityService: FocusActivityManaging {
    func synchronize(session: FocusSession?, now: Date) async -> String? {
        let activities = Activity<FocusActivityAttributes>.activities
        let active = session.flatMap { session in
            activities.first {
                $0.attributes.sessionID == session.id &&
                ($0.activityState == .active || $0.activityState == .stale)
            }
        }
        for activity in activities where activity.id != active?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let session else { return nil }
        let elapsed = session.elapsed(at: now)
        let state = FocusActivityAttributes.ContentState(
            phase: session.isPaused ? .paused : .running,
            timerStart: session.isPaused ? nil : now.addingTimeInterval(-elapsed),
            elapsedSeconds: elapsed
        )
        let content = ActivityContent(state: state, staleDate: nil)
        if let active {
            await active.update(content)
            return nil
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Your focus session is saved in the app. Enable Live Activities for StudyPlanner in iOS Settings to see it on the Lock Screen."
        }
        do {
            _ = try Activity.request(
                attributes: FocusActivityAttributes(
                    sessionID: session.id, taskTitle: session.taskTitle,
                    courseName: session.courseName, estimatedMinutes: session.estimatedMinutes
                ),
                content: content, pushType: nil
            )
            return nil
        } catch {
            return "Your session is saved. The Lock Screen timer is unavailable right now; you can keep using Focus in the app."
        }
    }
}
