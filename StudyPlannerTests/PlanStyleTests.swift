import XCTest
@testable import StudyPlanner

final class PlanStyleTests: XCTestCase {
    func testMorningBlocksAndNightBeforeReminder() {
        let reading = PlanStyle.parse("Mornings only, 25-minute blocks. Remind me the night before.")
        XCTAssertEqual(reading.studyTime, .morning)
        XCTAssertEqual(reading.blockMinutes, 25)
        XCTAssertEqual(reading.remindersEnabled, true)
        XCTAssertEqual(reading.reminderLeadMinutes, 24 * 60)
        XCTAssertNil(reading.dailyCapMinutes)
    }

    func testEveningCapAndNoNotifications() {
        let reading = PlanStyle.parse("Evenings, no more than 2 hours. Don't send notifications.")
        XCTAssertEqual(reading.studyTime, .evening)
        XCTAssertEqual(reading.dailyCapMinutes, 120)
        XCTAssertEqual(reading.remindersEnabled, false)
        XCTAssertNil(reading.reminderLeadMinutes)
    }

    func testDoneByNineAndAnHourReminderLeavesStudyTimeAlone() {
        let reading = PlanStyle.parse("Done by 9 pm. Remind me an hour before.")
        XCTAssertEqual(reading.dayEndMinutes, 21 * 60)
        XCTAssertEqual(reading.remindersEnabled, true)
        XCTAssertEqual(reading.reminderLeadMinutes, 60)
        XCTAssertNil(reading.studyTime)
        XCTAssertNil(reading.blockMinutes)
    }

    func testEveningsFreeDoesNotScheduleEvenings() {
        let reading = PlanStyle.parse("Leave my evenings free and remind me 30 minutes before.")
        XCTAssertEqual(reading.dayEndMinutes, 17 * 60)
        XCTAssertNil(reading.studyTime)
        XCTAssertEqual(reading.reminderLeadMinutes, 30)
    }

    func testUnrecognizedNoteChangesNothing() {
        let reading = PlanStyle.parse("I want to be more intentional this semester.")
        XCTAssertFalse(reading.recognized)
    }

    func testMorningPlanPlacesShortBlocksBeforeNoonAndHonorsTheCap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 8))!
        let settings = UserSettings(workdayStartMinutes: 9 * 60, workdayEndMinutes: 22 * 60, sleepTargetHours: 8)
        settings.studyTime = StudyTime.morning.rawValue
        settings.blockMinutes = 25
        settings.usesCustomBlockLength = true
        settings.dailyCapMinutes = 30
        let first = StudyTask(title: "Essay", dueDate: now.addingTimeInterval(3 * 86_400), estimatedMinutes: 60)
        let second = StudyTask(title: "Lab", dueDate: now.addingTimeInterval(4 * 86_400), estimatedMinutes: 60)
        let blocks = WeekPlanner.suggest(tasks: [first, second], courses: [], grades: [], busy: [], settings: settings, now: now, calendar: calendar)
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertEqual(calendar.component(.hour, from: blocks[0].start), 9)
        let byDay = Dictionary(grouping: blocks, by: { calendar.startOfDay(for: $0.start) })
        for dayBlocks in byDay.values {
            XCTAssertLessThanOrEqual(dayBlocks.reduce(0) { $0 + $1.minutes }, 30)
            for block in dayBlocks {
                XCTAssertEqual(block.minutes, 25)
                XCTAssertLessThan(calendar.component(.hour, from: block.start), 12)
            }
        }
    }
}
