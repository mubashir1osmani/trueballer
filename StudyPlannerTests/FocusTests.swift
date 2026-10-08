import XCTest
import SwiftData
@testable import StudyPlanner

@MainActor
private final class ActivitySpy: FocusActivityManaging {
    var sessionIDs: [UUID?] = []
    func synchronize(session: FocusSession?, now: Date) async -> String? {
        sessionIDs.append(session?.id)
        return nil
    }
}

@MainActor
final class FocusTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func container(inMemory: Bool = true, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([StudyTask.self, FocusSession.self])
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func testBackgroundElapsedUsesDatesAndExcludesPauses() async throws {
        let store = try container()
        let context = store.mainContext
        let task = StudyTask(title: "Essay")
        context.insert(task)
        let manager = FocusManager(activities: ActivitySpy())
        await manager.restore(context: context, now: start)
        await manager.start(task: task, estimateMinutes: 25, now: start)
        let session = try XCTUnwrap(manager.activeSession)
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(120)), 120)
        await manager.togglePause(now: start.addingTimeInterval(120))
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(900)), 120)
        await manager.togglePause(now: start.addingTimeInterval(900))
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(960)), 180)
        await manager.finish(completeTask: false, now: start.addingTimeInterval(960))
        XCTAssertEqual(session.accumulatedSeconds, 180)
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(task.estimatedMinutes, 25)
    }

    func testRunningSessionSurvivesDiskReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("focus.store")
        var sessionID: UUID?
        do {
            let store = try container(url: url)
            let task = StudyTask(title: "Lab", courseName: "Chemistry")
            store.mainContext.insert(task)
            let manager = FocusManager(activities: ActivitySpy())
            await manager.restore(context: store.mainContext, now: start)
            await manager.start(task: task, estimateMinutes: 45, now: start)
            sessionID = manager.activeSession?.id
        }
        let reloaded = try container(url: url)
        let manager = FocusManager(activities: ActivitySpy())
        await manager.restore(context: reloaded.mainContext, now: start.addingTimeInterval(300))
        let session = try XCTUnwrap(manager.activeSession)
        XCTAssertEqual(session.id, sessionID)
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(300)), 300)
        XCTAssertEqual(session.task?.courseName, "Chemistry")
        await manager.finish(completeTask: true, now: start.addingTimeInterval(360))
        let readContext = ModelContext(reloaded)
        let saved = try XCTUnwrap(readContext.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertEqual(saved.accumulatedSeconds, 360)
        XCTAssertNotNil(saved.endedAt)
        XCTAssertTrue(saved.task?.isCompleted == true)
    }

    func testPausedSessionRestoresWithoutCountingTimeAway() async throws {
        let store = try container()
        let task = StudyTask(title: "Reading")
        store.mainContext.insert(task)
        let original = FocusManager(activities: ActivitySpy())
        await original.restore(context: store.mainContext, now: start)
        await original.start(task: task, estimateMinutes: 15, now: start)
        await original.togglePause(now: start.addingTimeInterval(33))
        let restored = FocusManager(activities: ActivitySpy())
        await restored.restore(context: ModelContext(store), now: start.addingTimeInterval(600))
        XCTAssertTrue(restored.activeSession?.isPaused == true)
        XCTAssertEqual(restored.activeSession?.elapsed(at: start.addingTimeInterval(600)), 33)
        await restored.finish(completeTask: false, now: start.addingTimeInterval(800))
        let sessions = try ModelContext(store).fetch(FetchDescriptor<FocusSession>())
        XCTAssertEqual(sessions.first?.accumulatedSeconds, 33)
    }

    func testCannotOverlapOrLogTwiceAndCompletionEndsActivity() async throws {
        let store = try container()
        let first = StudyTask(title: "First")
        let second = StudyTask(title: "Second")
        store.mainContext.insert(first)
        store.mainContext.insert(second)
        let activities = ActivitySpy()
        let manager = FocusManager(activities: activities)
        await manager.restore(context: store.mainContext, now: start)
        await manager.start(task: first, estimateMinutes: 25, now: start)
        await manager.start(task: second, estimateMinutes: 25, now: start)
        XCTAssertEqual(manager.activeSession?.taskTitle, "First")
        await manager.finish(completeTask: true, now: start.addingTimeInterval(90))
        await manager.finish(completeTask: true, now: start.addingTimeInterval(120))
        let sessions = try store.mainContext.fetch(FetchDescriptor<FocusSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.accumulatedSeconds, 90)
        XCTAssertTrue(first.isCompleted)
        XCTAssertFalse(second.isCompleted)
        XCTAssertNil(activities.sessionIDs.last!)
        await manager.start(task: first, estimateMinutes: 25, now: start)
        XCTAssertNil(manager.activeSession)
    }

    func testMultipleSessionsKeepTaskAssociationAndEstimate() async throws {
        let store = try container()
        let task = StudyTask(title: "Project")
        store.mainContext.insert(task)
        let manager = FocusManager(activities: ActivitySpy())
        await manager.restore(context: store.mainContext, now: start)
        await manager.start(task: task, estimateMinutes: 60, now: start)
        await manager.finish(completeTask: false, now: start.addingTimeInterval(900))
        await manager.start(task: task, estimateMinutes: 60, now: start.addingTimeInterval(1000))
        await manager.finish(completeTask: true, now: start.addingTimeInterval(2200))
        let sessions = try store.mainContext.fetch(FetchDescriptor<FocusSession>())
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.reduce(0) { $0 + $1.accumulatedSeconds }, 2100)
        XCTAssertTrue(sessions.allSatisfy { $0.task == task && $0.estimatedMinutes == 60 })
        XCTAssertEqual(sessions.filter(\.completedTask).count, 1)
    }

    func testClockDoesNotGoNegativeAndFormatsLongSessions() {
        let task = StudyTask(title: "Reading")
        let session = FocusSession(task: task, estimatedMinutes: 30, now: start)
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(-10)), 0)
        XCTAssertEqual(FocusTimeFormat.clock(3661), "1:01:01")
        XCTAssertEqual(FocusTimeFormat.clock(59), "00:59")
        XCTAssertEqual(FocusTimeFormat.duration(2100), "35m")
    }
}
