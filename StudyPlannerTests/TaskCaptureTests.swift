import XCTest
@testable import StudyPlanner

final class TaskCaptureTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.locale = Locale(identifier: "en_US")
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
    }

    func testSingleLineExtractsTitleTomorrowAndClock() throws {
        let drafts = try BasicTaskParser.parse("History essay due tomorrow at 5 pm", now: now, calendar: calendar)
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(draft.title, "History essay")
        XCTAssertFalse(draft.usedAI)
        let due = try XCTUnwrap(draft.dueDate)
        XCTAssertEqual(calendar.component(.day, from: due), 29)
        XCTAssertEqual(calendar.component(.hour, from: due), 17)
        XCTAssertNil(draft.estimatedMinutes)
    }

    func testWeekdayCourseAndDuration() throws {
        let biology = StudyCourse(name: "Biology")
        let drafts = try BasicTaskParser.parse("Read chapter 4 for Biology due Friday for 45 minutes", courses: [biology], now: now, calendar: calendar)
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(draft.title, "Read chapter 4")
        XCTAssertEqual(draft.courseID, biology.id)
        XCTAssertEqual(draft.estimatedMinutes, 45)
        let due = try XCTUnwrap(draft.dueDate)
        XCTAssertEqual(calendar.component(.month, from: due), 10)
        XCTAssertEqual(calendar.component(.day, from: due), 2)
        XCTAssertEqual(calendar.component(.hour, from: due), 23)
        XCTAssertEqual(calendar.component(.minute, from: due), 59)
    }

    func testTwoLinesAndRejectedBatches() throws {
        let drafts = try BasicTaskParser.parse("Chem quiz Thursday at 10 am\nLab report due tomorrow", now: now, calendar: calendar)
        XCTAssertEqual(drafts.map(\.title), ["Chem quiz", "Lab report"])
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(drafts[0].dueDate)), 10)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(drafts[0].dueDate)), 5)
        XCTAssertThrowsError(try BasicTaskParser.parse("", now: now, calendar: calendar))
        let lines = (1...6).map { "Task \($0) due tomorrow" }.joined(separator: "\n")
        XCTAssertThrowsError(try BasicTaskParser.parse(lines, now: now, calendar: calendar))
    }

    func testAmbiguousCourseNamesAreLeftUnset() throws {
        let short = StudyCourse(name: "Math")
        let long = StudyCourse(name: "Math Methods")
        let specific = try BasicTaskParser.parse("Problem set for Math Methods due Friday", courses: [short, long], now: now, calendar: calendar)
        XCTAssertEqual(specific.first?.courseID, long.id)
        XCTAssertEqual(specific.first?.title, "Problem set")
        let ambiguous = StudyCourse(name: "Stats")
        let other = StudyCourse(name: "Stats")
        let unset = try BasicTaskParser.parse("Worksheet for Stats due tomorrow", courses: [ambiguous, other], now: now, calendar: calendar)
        XCTAssertNil(unset.first?.courseID)
    }
}
