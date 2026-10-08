import XCTest
import EventKit
@testable import StudyPlanner

final class ScheduleParserTests: XCTestCase {
    func testReminderExtractsLocalTomorrowAndTitle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12))!
        let draft = try BasicScheduleParser.parse("Remind me to submit my essay tomorrow at 5 pm", now: now, calendar: calendar)
        XCTAssertEqual(draft.kind, .reminder)
        XCTAssertEqual(draft.title, "submit my essay")
        let date = try XCTUnwrap(draft.date)
        XCTAssertEqual(calendar.component(.day, from: date), 27)
        XCTAssertEqual(calendar.component(.hour, from: date), 17)
        XCTAssertFalse(draft.usedAI)
        let meetingReminder = try BasicScheduleParser.parse("Remind me tomorrow to prepare for the meeting", now: now, calendar: calendar)
        XCTAssertEqual(meetingReminder.kind, .reminder)
        XCTAssertEqual(meetingReminder.title, "prepare for the meeting")
    }

    func testEventDurationMissingDateAndUnsupportedRecurrence() throws {
        let draft = try BasicScheduleParser.parse("Schedule a study session tomorrow at 3 pm for 45 minutes")
        XCTAssertEqual(draft.kind, .event)
        XCTAssertEqual(draft.title, "study session")
        XCTAssertEqual(draft.durationMinutes, 45)
        XCTAssertNil(draft.validationError)
        XCTAssertThrowsError(try BasicScheduleParser.parse("Remind me every day to read"))
        XCTAssertThrowsError(try BasicScheduleParser.parse(""))
        let undated = try BasicScheduleParser.parse("Schedule a study session")
        XCTAssertNotNil(undated.validationError)
        XCTAssertNotNil(ScheduleDraft(kind: .event, title: "Test", date: .now, durationMinutes: 0).validationError)
    }
}
