import XCTest
import SwiftData
@testable import StudyPlanner

@MainActor
final class AcademicProgressTests: XCTestCase {
    func testWeightedAverageCoverageAndRemainingTarget() throws {
        let course = StudyCourse(name: "Math")
        course.targetPercentage = 80
        let first = GradeEntry(courseID: course.id, title: "Quiz", percentage: 60, weight: 10)
        let second = GradeEntry(courseID: course.id, title: "Exam", percentage: 90, weight: 30)
        let summary = AcademicProgress.summary(course: course, grades: [first, second])
        XCTAssertEqual(try XCTUnwrap(summary.average), 82.5, accuracy: 0.001)
        XCTAssertEqual(summary.gradedWeight, 40)
        XCTAssertEqual(try XCTUnwrap(summary.requiredOnRemaining), 78.333333, accuracy: 0.001)
        XCTAssertFalse(summary.belowTarget)
        XCTAssertNil(AcademicProgress.summary(course: StudyCourse(name: "Empty"), grades: [first]).average)
    }

    func testZeroGradeIsIncludedAndWeightsAreValidated() throws {
        let course = StudyCourse(name: "Math")
        let zero = GradeEntry(courseID: course.id, title: "Quiz", percentage: 0, weight: 50)
        let full = GradeEntry(courseID: course.id, title: "Exam", percentage: 100, weight: 50)
        let summary = AcademicProgress.summary(course: course, grades: [zero, full])
        XCTAssertEqual(summary.average, 50)
        XCTAssertTrue(summary.belowTarget)
        XCTAssertNil(summary.requiredOnRemaining)
        XCTAssertNil(AcademicProgress.gradeError(title: "Zero", percentage: 0, weight: 10, otherWeight: 90))
        XCTAssertNotNil(AcademicProgress.gradeError(title: "Bad", percentage: 80, weight: 11, otherWeight: 90))
        XCTAssertNotNil(AcademicProgress.gradeError(title: "Bad", percentage: .nan, weight: 10, otherWeight: 0))
        XCTAssertNotNil(AcademicProgress.gradeError(title: "Bad", percentage: 101, weight: 10, otherWeight: 0))
        XCTAssertNotNil(AcademicProgress.gradeError(title: "Bad", percentage: 70, weight: 0, otherWeight: 0))
        XCTAssertNil(GradeNumber.parse("80abc"))
    }

    func testTrendUsesReceivedDateAndRespondsToCorrections() {
        let course = StudyCourse(name: "History")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let early = GradeEntry(courseID: course.id, title: "First", percentage: 80, weight: 20, receivedAt: date)
        let late = GradeEntry(courseID: course.id, title: "Second", percentage: 40, weight: 20, receivedAt: date.addingTimeInterval(100))
        var summary = AcademicProgress.summary(course: course, grades: [late, early])
        XCTAssertEqual(summary.trend.map(\.average), [80, 60])
        XCTAssertEqual(summary.trendChange, -20)
        late.percentage = 100
        summary = AcademicProgress.summary(course: course, grades: [late, early])
        XCTAssertEqual(summary.trendChange, 10)
        XCTAssertFalse(summary.belowTarget)
    }

    func testGPAUsesCreditsAndSeparatesScalesAndExcludesMissingAndArchived() throws {
        let a = StudyCourse(name: "A"); a.credits = 3; a.gpaPoints = 4
        let b = StudyCourse(name: "B"); b.credits = 1; b.gpaPoints = 0
        let c = StudyCourse(name: "C"); c.gpaPoints = 4.3; c.gpaScale = 4.3
        let d = StudyCourse(name: "D"); d.gpaPoints = 0; d.isArchived = true
        let result = AcademicProgress.gpa(courses: [a, b, c, d, StudyCourse(name: "Missing")])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].value, 3)
        XCTAssertEqual(result[0].courseCount, 2)
        XCTAssertEqual(result[1].value, 4.3)
    }

    func testPriorityBoostPreservesUrgencySnoozeAndCompletion() {
        let now = Date.now
        let course = StudyCourse(name: "Math")
        let grade = GradeEntry(courseID: course.id, title: "Exam", percentage: 20, weight: 30)
        let overdue = StudyTask(title: "Overdue", dueDate: now.addingTimeInterval(-60))
        let imminent = StudyTask(title: "Imminent", dueDate: now.addingTimeInterval(3600))
        let normal = StudyTask(title: "Normal", dueDate: now.addingTimeInterval(2 * 86400))
        let risk = StudyTask(title: "Risk", dueDate: now.addingTimeInterval(3 * 86400), courseID: course.id)
        let dateless = StudyTask(title: "No date", courseID: course.id)
        let hidden = StudyTask(title: "Snoozed", courseID: course.id); hidden.snoozedUntil = now.addingTimeInterval(60)
        let done = StudyTask(title: "Done"); done.isCompleted = true
        let inputs = [normal, risk, dateless, imminent, overdue, hidden, done]
        XCTAssertEqual(Planner.rankedTasks(inputs, courses: [course], grades: [grade], now: now).map(\.title),
                       ["Overdue", "Imminent", "Risk", "Normal", "No date"])
        course.isArchived = true
        XCTAssertEqual(Planner.rankedTasks([normal, risk], courses: [course], grades: [grade], now: now).first?.title, "Normal")
    }

    func testDuplicateCourseNamesNeverMixGradesOrEffort() {
        let a = StudyCourse(name: "Math", sourceGroupID: "one")
        let b = StudyCourse(name: "Math", sourceGroupID: "two")
        let old = StudyTask(title: "Old", courseName: "Math")
        XCTAssertNil(CourseCatalog.course(for: old, in: [a, b]))
        old.courseID = a.id
        let session = FocusSession(task: old, estimatedMinutes: 25, now: .now.addingTimeInterval(-300))
        session.accumulatedSeconds = 180; session.runningSince = nil; session.endedAt = .now.addingTimeInterval(-1)
        let unfinished = FocusSession(task: old, estimatedMinutes: 25, now: .now)
        XCTAssertEqual(AcademicProgress.focusSeconds(course: a, courses: [a, b], sessions: [session, unfinished]), 180)
        XCTAssertEqual(AcademicProgress.focusSeconds(course: b, courses: [a, b], sessions: [session]), 0)
    }

    func testCatalogIsIdempotentAndGradesSurviveReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([StudyCourse.self, GradeEntry.self, StudyTask.self, FocusSession.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("grades.store"), cloudKitDatabase: .none)
        let store = try ModelContainer(for: schema, configurations: configuration)
        let task = StudyTask(title: "Old task", courseName: "Biology")
        store.mainContext.insert(task)
        try CourseCatalog.synchronize(groups: [], tasks: [task], sessions: [], context: store.mainContext)
        try CourseCatalog.synchronize(groups: [], tasks: [task], sessions: [], context: store.mainContext)
        let courses = try store.mainContext.fetch(FetchDescriptor<StudyCourse>())
        XCTAssertEqual(courses.count, 1)
        let course = try XCTUnwrap(courses.first)
        XCTAssertEqual(task.courseID, course.id)
        course.name = "Biology 101"
        try CourseCatalog.synchronize(groups: [], tasks: [task], sessions: [], context: store.mainContext)
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<StudyCourse>()), 1)
        store.mainContext.insert(GradeEntry(courseID: course.id, title: "Lab", percentage: 75, weight: 20))
        try store.mainContext.save()
        let reload = try ModelContainer(for: schema, configurations: configuration)
        let savedCourse = try XCTUnwrap(reload.mainContext.fetch(FetchDescriptor<StudyCourse>()).first)
        let savedGrades = try reload.mainContext.fetch(FetchDescriptor<GradeEntry>())
        XCTAssertEqual(AcademicProgress.summary(course: savedCourse, grades: savedGrades).average, 75)
    }
}
