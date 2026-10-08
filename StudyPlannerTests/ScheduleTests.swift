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

@MainActor
final class ScheduleIntegrationTests: XCTestCase {
    func testSavesAppleReminderAndCalendarEventOnce() async throws {
        #if targetEnvironment(simulator)
        let store = EKEventStore()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            throw XCTSkip("Grant simulator Calendar and Reminders access before this integration test.")
        }
        let source = try XCTUnwrap(store.sources.first { $0.sourceType == .local })
        let eventCalendar = EKCalendar(for: .event, eventStore: store)
        eventCalendar.title = "StudyPlanner Calendar Test \(UUID())"; eventCalendar.source = source
        let reminderList = EKCalendar(for: .reminder, eventStore: store)
        reminderList.title = "StudyPlanner Reminders Test \(UUID())"; reminderList.source = source
        try store.saveCalendar(eventCalendar, commit: true)
        defer { try? store.removeCalendar(eventCalendar, commit: true) }
        try store.saveCalendar(reminderList, commit: true)
        defer { try? store.removeCalendar(reminderList, commit: true) }
        let service = PersonalScheduleService()
        let date = Calendar.current.date(bySettingHour: 15, minute: 30, second: 0, of: Date.now.addingTimeInterval(86400))!
        let reminder = ScheduleDraft(kind: .reminder, title: "Submit test essay", date: date)
        try service.save(reminder, destinationID: reminderList.calendarIdentifier)
        try service.save(reminder, destinationID: reminderList.calendarIdentifier)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: [reminderList])) { continuation.resume(returning: $0 ?? []) }
        }
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.title, reminder.title)
        XCTAssertEqual(reminders.first?.dueDateComponents?.hour, 15)
        XCTAssertEqual(reminders.first?.alarms?.first?.absoluteDate, date)
        let event = ScheduleDraft(kind: .event, title: "Study test", date: date, durationMinutes: 45)
        try service.save(event, destinationID: eventCalendar.calendarIdentifier)
        try service.save(event, destinationID: eventCalendar.calendarIdentifier)
        let events = store.events(matching: store.predicateForEvents(withStart: date.addingTimeInterval(-60), end: date.addingTimeInterval(3600), calendars: [eventCalendar]))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.endDate.timeIntervalSince(date), 2700)
        #else
        throw XCTSkip("This test writes disposable simulator data only.")
        #endif
    }
}
