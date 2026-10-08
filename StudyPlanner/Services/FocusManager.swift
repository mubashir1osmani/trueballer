import Foundation
import SwiftData

@MainActor
final class FocusManager: ObservableObject {
    @Published private(set) var activeSession: FocusSession?
    @Published private(set) var isBusy = false
    @Published private(set) var activityNotice: String?
    @Published var errorMessage: String?
    private var context: ModelContext?
    private let activities: any FocusActivityManaging

    init(activities: any FocusActivityManaging) {
        self.activities = activities
    }

    func restore(context: ModelContext, now: Date = .now) async {
        guard !isBusy else { return }
        self.context = context
        isBusy = true
        defer { isBusy = false }
        do {
            var request = FetchDescriptor<FocusSession>(
                predicate: #Predicate { $0.endedAt == nil },
                sortBy: [SortDescriptor(\FocusSession.startedAt, order: .reverse)]
            )
            request.fetchLimit = 1
            activeSession = try context.fetch(request).first
            activityNotice = await activities.synchronize(session: activeSession, now: now)
        } catch {
            errorMessage = "Your focus session couldn't be loaded. Please try reopening the app."
        }
    }

    func start(task: StudyTask, estimateMinutes: Int, now: Date = .now) async {
        guard !isBusy, activeSession == nil, !task.isCompleted, let context else { return }
        isBusy = true
        defer { isBusy = false }
        let estimate = max(1, min(estimateMinutes, 1440))
        let oldEstimate = task.estimatedMinutes
        let session = FocusSession(task: task, estimatedMinutes: estimate, now: now)
        context.insert(session)
        task.estimatedMinutes = estimate
        do {
            try context.save()
            activeSession = session
            activityNotice = await activities.synchronize(session: session, now: now)
        } catch {
            context.delete(session)
            task.estimatedMinutes = oldEstimate
            errorMessage = "The session couldn't be saved. Please try again."
        }
    }

    func togglePause(now: Date = .now) async {
        guard !isBusy, let session = activeSession, let context else { return }
        isBusy = true
        defer { isBusy = false }
        let previousSeconds = session.accumulatedSeconds
        let previousStart = session.runningSince
        if session.isPaused {
            session.runningSince = now
        } else {
            session.accumulatedSeconds = session.elapsed(at: now)
            session.runningSince = nil
        }
        do {
            try context.save()
            activityNotice = await activities.synchronize(session: session, now: now)
        } catch {
            session.accumulatedSeconds = previousSeconds
            session.runningSince = previousStart
            errorMessage = "The timer change couldn't be saved. Please try again."
        }
    }

    func finish(completeTask: Bool, now: Date = .now) async {
        guard !isBusy, let session = activeSession, let context else { return }
        isBusy = true
        defer { isBusy = false }
        let previousSeconds = session.accumulatedSeconds
        let previousStart = session.runningSince
        let wasCompleted = session.task?.isCompleted ?? false
        session.accumulatedSeconds = session.elapsed(at: now)
        session.runningSince = nil
        session.endedAt = now
        session.completedTask = completeTask
        if completeTask { session.task?.isCompleted = true }
        do {
            try context.save()
            activeSession = nil
            activityNotice = await activities.synchronize(session: nil, now: now)
        } catch {
            session.accumulatedSeconds = previousSeconds
            session.runningSince = previousStart
            session.endedAt = nil
            session.completedTask = false
            session.task?.isCompleted = wasCompleted
            errorMessage = "Your time couldn't be logged. The session is still open; please try again."
        }
    }
}
