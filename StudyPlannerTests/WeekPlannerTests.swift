import XCTest
@testable import StudyPlanner

final class WeekPlannerTests: XCTestCase {
    private var calendar: Calendar!
    private var settings: UserSettings!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.locale = Locale(identifier: "en_US")
        self.calendar = calendar
        settings = UserSettings(workdayStartMinutes: 9 * 60, workdayEndMinutes: 22 * 60, sleepTargetHours: 8)
        now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 8))!
        XCTAssertEqual(calendar.component(.weekday, from: now), 2)
    }

    func testAtRiskTaskTakesTheEarlierGapAndClassTimeIsLeftAlone() {
        let math = StudyCourse(name: "Math")
        math.targetPercentage = 80
        let grade = GradeEntry(courseID: math.id, title: "Quiz", percentage: 50, weight: 20)
        let due = calendar.date(byAdding: .day, value: 3, to: now)!
        let healthy = StudyTask(title: "Reading", dueDate: due.addingTimeInterval(-86_400), estimatedMinutes: 45)
        let risk = StudyTask(title: "Problem set", dueDate: due, estimatedMinutes: 45, courseID: math.id)
        let blocks = WeekPlanner.suggest(
            tasks: [healthy, risk],
            courses: [math],
            grades: [grade],
            busy: [busy(hour: 10, minute: 0, duration: 60)],
            settings: settings,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(blocks.map(\.title), ["Problem set", "Reading"])
        XCTAssertTrue(blocks[0].protectsGPA)
        XCTAssertFalse(blocks[1].protectsGPA)
        expect(blocks[0].start, hour: 9, minute: 0)
        XCTAssertEqual(blocks[0].minutes, 45)
        expect(blocks[1].start, hour: 11, minute: 0)
        XCTAssertTrue(blocks.allSatisfy { block in
            let classStart = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)!
            return block.end <= classStart || block.start >= classStart.addingTimeInterval(3_600)
        })
    }

    func testSleepClipsTheEveningAndAllDayEventsDoNotBlockStudy() {
        settings.workdayStartMinutes = 7 * 60
        settings.workdayEndMinutes = 23 * 60 + 30
        now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 22))!
        let task = StudyTask(title: "Lab writeup", dueDate: calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now), estimatedMinutes: 180)
        let blocks = WeekPlanner.suggest(
            tasks: [task],
            courses: [],
            grades: [],
            busy: [WeekPlanner.BusyInterval(start: calendar.startOfDay(for: now), end: calendar.date(byAdding: .day, value: 1, to: now)!, isAllDay: true)],
            settings: settings,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(blocks.count, 1)
        expect(blocks[0].start, hour: 22, minute: 0)
        expect(blocks[0].end, hour: 23, minute: 0)
    }

    func testDeadlineClipsABlockAndATooSmallGapIsSkipped() throws {
        let soon = StudyTask(title: "Quiz prep", dueDate: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now), estimatedMinutes: 60)
        let impossible = StudyTask(title: "Too soon", dueDate: calendar.date(bySettingHour: 9, minute: 10, second: 0, of: now), estimatedMinutes: 45)
        let soonBlocks = WeekPlanner.suggest(tasks: [soon], courses: [], grades: [], busy: [], settings: settings, now: now, calendar: calendar)
        XCTAssertEqual(soonBlocks.count, 1)
        XCTAssertEqual(soonBlocks[0].minutes, 30)
        expect(soonBlocks[0].end, hour: 9, minute: 30)
        let skipped = WeekPlanner.suggest(tasks: [impossible], courses: [], grades: [], busy: [], settings: settings, now: now, calendar: calendar)
        XCTAssertTrue(skipped.isEmpty)
    }

    func testOverdueWorkIsPlacedNowAndPastMorningGapsAreNotReused() {
        let overdue = StudyTask(title: "Late essay", dueDate: now.addingTimeInterval(-86_400), estimatedMinutes: 45)
        let morning = WeekPlanner.suggest(tasks: [overdue], courses: [], grades: [], busy: [], settings: settings, now: now, calendar: calendar)
        expect(morning[0].start, hour: 9, minute: 0)

        now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 15, minute: 7))!
        let later = WeekPlanner.suggest(tasks: [overdue], courses: [], grades: [], busy: [], settings: settings, now: now, calendar: calendar)
        expect(later[0].start, hour: 15, minute: 10)
        XCTAssertTrue(later.allSatisfy { $0.start >= now })
    }

    func testFreeMinutesIncludeShortGapsThatAreTooSmallForABlock() throws {
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let end = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)!
        let busy = [
            WeekPlanner.BusyInterval(start: start.addingTimeInterval(20 * 60), end: start.addingTimeInterval(40 * 60))
        ]
        XCTAssertEqual(WeekPlanner.freeMinutes(from: start, to: end, busy: busy), 40)
        let window = try XCTUnwrap(WeekPlanner.availabilityWindow(on: calendar.startOfDay(for: now), settings: settings, now: now, calendar: calendar, clampToNow: true))
        expect(window.start, hour: 9, minute: 0)
        expect(window.end, hour: 22, minute: 0)
    }

    private func busy(hour: Int, minute: Int, duration: Int) -> WeekPlanner.BusyInterval {
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
        return WeekPlanner.BusyInterval(start: start, end: start.addingTimeInterval(TimeInterval(duration * 60)))
    }

    private func expect(_ date: Date, hour: Int, minute: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(calendar.component(.hour, from: date), hour, file: file, line: line)
        XCTAssertEqual(calendar.component(.minute, from: date), minute, file: file, line: line)
    }
}
