import XCTest
@testable import StudyPlanner

final class BraindumpTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.locale = Locale(identifier: "en_US")
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 8))!
    }

    func testMorningDumpSeparatesWorkFromMoodAndPlanning() throws {
        let reading = BraindumpOrganizer.read("""
        tired
        need coffee
        chem quiz Thursday
        study in the morning, 25 minute blocks
        I'm anxious about the exam
        """, now: now, calendar: calendar)

        XCTAssertEqual(reading.tasks.map(\.title), ["chem quiz"])
        let due = try XCTUnwrap(reading.tasks.first?.dueDate)
        XCTAssertEqual(calendar.component(.month, from: due), 10)
        XCTAssertEqual(calendar.component(.day, from: due), 1)
        XCTAssertEqual(calendar.component(.hour, from: due), 23)
        XCTAssertEqual(reading.plan.studyTime, .morning)
        XCTAssertEqual(reading.plan.blockMinutes, 25)
        XCTAssertNil(reading.plan.remindersEnabled)
        XCTAssertFalse(reading.usedAI)
    }

    func testDueLineWithoutASchoolNounStillBecomesATask() throws {
        let reading = BraindumpOrganizer.read("Spanish vocab due Friday", now: now, calendar: calendar)
        let draft = try XCTUnwrap(reading.tasks.first)
        XCTAssertEqual(draft.title, "Spanish vocab")
        let due = try XCTUnwrap(draft.dueDate)
        XCTAssertEqual(calendar.component(.month, from: due), 10)
        XCTAssertEqual(calendar.component(.day, from: due), 2)
    }

    func testNegationAndInvalidClockAreSkipped() throws {
        let reading = BraindumpOrganizer.read("""
        I don't have a quiz today
        Chem quiz at 99 pm
        Essay due Friday
        """, now: now, calendar: calendar)
        XCTAssertEqual(reading.tasks.map(\.title), ["Essay"])
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(reading.tasks.first?.dueDate)), 2)
    }

    func testDuplicateTitlesCollapseAndEightIsTheCap() {
        var lines = (1...9).map { "quiz \($0) due Friday" }
        lines.append("quiz 1 due Friday")
        let reading = BraindumpOrganizer.read(lines.joined(separator: "\n"), now: now, calendar: calendar)
        XCTAssertEqual(reading.tasks.count, 8)
        XCTAssertEqual(reading.tasks.first?.title, "quiz 1")
        XCTAssertEqual(Set(reading.tasks.map(\.title)).count, 8)
    }

    func testRemindersOffDoesNotInventATask() {
        let reading = BraindumpOrganizer.read("Don't send notifications.", now: now, calendar: calendar)
        XCTAssertTrue(reading.tasks.isEmpty)
        XCTAssertEqual(reading.plan.remindersEnabled, false)
    }

    func testDaysIncludeTodayAndSortNewestFirst() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let days = BraindumpOrganizer.days(from: [yesterday, tomorrow], now: now, calendar: calendar)
        XCTAssertEqual(days, [tomorrow, now, yesterday].map { calendar.startOfDay(for: $0) })
    }

    func testApplyChangesOnlyTheRulesTheNoteMentioned() {
        let settings = UserSettings(workdayStartMinutes: 9 * 60, workdayEndMinutes: 22 * 60, sleepTargetHours: 8)
        settings.remindersEnabled = true
        settings.reminderLeadMinutes = 60
        var reading = PlanReading()
        reading.studyTime = .morning
        reading.blockMinutes = 25
        BraindumpOrganizer.apply(reading, to: settings)
        XCTAssertEqual(settings.studyTime, StudyTime.morning.rawValue)
        XCTAssertEqual(settings.blockMinutes, 25)
        XCTAssertTrue(settings.usesCustomBlockLength)
        XCTAssertTrue(settings.remindersEnabled)
        XCTAssertEqual(settings.reminderLeadMinutes, 60)
        XCTAssertEqual(BraindumpOrganizer.describedChanges(reading), ["Mornings", "25-minute blocks"])
    }

    func testSchedulePreviewStaysInsideTheRequestedMorning() {
        let reading = BraindumpOrganizer.read("History essay due Friday. Study in the morning.", now: now, calendar: calendar)
        XCTAssertEqual(reading.tasks.map(\.title), ["History essay"])
        XCTAssertEqual(reading.plan.studyTime, .morning)
        let settings = UserSettings(workdayStartMinutes: 9 * 60, workdayEndMinutes: 22 * 60, sleepTargetHours: 8)
        let blocks = BraindumpOrganizer.scheduledBlocks(
            existing: [],
            drafts: reading.tasks,
            courses: [],
            grades: [],
            busy: [],
            settings: settings,
            plan: reading.plan,
            applyPlan: true,
            now: now,
            calendar: calendar
        )
        let block = blocks.first { $0.title == "History essay" }
        XCTAssertNotNil(block)
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(block).start), 9)
        XCTAssertLessThanOrEqual(try XCTUnwrap(block).end, noon)
    }

    func testEmptyNoteAddsNothing() {
        let reading = BraindumpOrganizer.read("   \n", now: now, calendar: calendar)
        XCTAssertTrue(reading.isEmpty)
    }
}
