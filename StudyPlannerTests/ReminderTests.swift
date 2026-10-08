import XCTest
@testable import StudyPlanner

final class ReminderTests: XCTestCase {
    @MainActor
    func testDuplicateTaskIDsAreReassignedOnceAndOldestKeepsItsID() {
        let shared = UUID()
        let older = StudyTask(title: "Essay")
        let newer = StudyTask(title: "Quiz")
        older.createdAt = .now.addingTimeInterval(-60)
        older.id = shared
        newer.id = shared

        XCTAssertTrue(NotificationService.repairDuplicateIDs([newer, older]))
        XCTAssertEqual(older.id, shared)
        XCTAssertNotEqual(newer.id, shared)
        XCTAssertFalse(NotificationService.repairDuplicateIDs([newer, older]))
    }
}
