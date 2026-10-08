import SwiftUI
import SwiftData
import Charts

struct ProgressTabView: View {
    var showsDismiss = false
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StudyCourse.name) private var courses: [StudyCourse]
    @Query private var grades: [GradeEntry]
    @Query private var sessions: [FocusSession]
    @State private var addingCourse = false
    private var active: [StudyCourse] { courses.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            List {
                if active.isEmpty {
                    ContentUnavailableView("Start with a course", systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Add a course or tag one from your calendar. Then enter the grades you get back."))
                    Button("Add Course") { addingCourse = true }
                } else {
                    Section {
                        let gradedCount = active.filter { AcademicProgress.summary(course: $0, grades: grades).average != nil }.count
                        let atRiskCount = active.filter { AcademicProgress.summary(course: $0, grades: grades).belowTarget }.count
                        let focused = active.reduce(0.0) { $0 + AcademicProgress.focusSeconds(course: $1, courses: courses, sessions: sessions) }
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Grades & study time", systemImage: "chart.xyaxis.line")
                                .font(.headline).foregroundStyle(AppTheme.accent)
                            HStack(spacing: 32) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(gradedCount) / \(active.count)").font(.title.bold()).monospacedDigit()
                                    Text("courses with grades").font(.caption).foregroundStyle(.secondary)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(FocusTimeFormat.duration(focused)).font(.title.bold()).monospacedDigit()
                                    Text("course focus time").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if atRiskCount > 0 {
                                Label("\(atRiskCount) \(atRiskCount == 1 ? "course could" : "courses could") use more time", systemImage: "book.closed")
                                    .font(.subheadline).foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    Section {
                        let results = AcademicProgress.gpa(courses: active)
                        if results.isEmpty {
                            Text("Add GPA points in a course's settings to see your GPA here.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(results) { gpa in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(gpa.value, specifier: "%.2f") / \(GradeNumber.text(gpa.scale))")
                                    .font(.largeTitle.bold()).foregroundStyle(AppTheme.accent)
                                    .accessibilityIdentifier("progress.gpa")
                                Text("\(gpa.courseCount) of \(active.count) active courses · \(GradeNumber.text(gpa.credits)) credits")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: { Text("Entered GPA") }
                    footer: { Text("Credit-weighted from the GPA points you enter using your school's scale. Different scales are shown separately. Missing grades are never treated as zero.") }

                    Section("Grades & effort") {
                        ForEach(active) { course in
                            NavigationLink { CourseDetailView(course: course) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    CourseProgressRow(course: course, summary: AcademicProgress.summary(course: course, grades: grades))
                                    let seconds = AcademicProgress.focusSeconds(course: course, courses: courses, sessions: sessions)
                                    Text("\(FocusTimeFormat.duration(seconds)) logged focus time")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("progress.course.\(course.name)")
                        }
                    }
                }
            }
            .navigationTitle("Progress")

            .toolbar {
                if showsDismiss {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("progress.close")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addingCourse = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add course")
                }
            }
            .sheet(isPresented: $addingCourse) { CourseEditorView() }
        }
    }
}

struct CourseDetailView: View {
    let course: StudyCourse
    @Query private var allCourses: [StudyCourse]
    @Query private var allGrades: [GradeEntry]
    @Query private var sessions: [FocusSession]
    @State private var addingGrade = false
    @State private var editingGrade: GradeEntry?
    @State private var editingCourse = false

    private var grades: [GradeEntry] {
        allGrades.filter { $0.courseID == course.id }.sorted { $0.receivedAt > $1.receivedAt }
    }
    private var summary: AcademicProgress.Summary { AcademicProgress.summary(course: course, grades: allGrades) }

    var body: some View {
        List {
            Section {
                if let average = summary.average {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(average, specifier: "%.1f")%")
                            .font(.largeTitle.bold()).foregroundStyle(summary.belowTarget ? .orange : AppTheme.accent)
                            .accessibilityIdentifier("grade.average")
                        Spacer()
                        Text("Target \(GradeNumber.text(course.targetPercentage))%")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("\(GradeNumber.text(summary.gradedWeight))% of course weight entered")
                        .font(.footnote).foregroundStyle(.secondary)
                    if summary.belowTarget {
                        Label("This course could use more study time.", systemImage: "book.closed")
                            .foregroundStyle(.orange).accessibilityIdentifier("grade.belowTarget")
                    }
                    if let required = summary.requiredOnRemaining {
                        Text(required > 100
                             ? "Reaching your target would require more than 100% on the remaining work. Review the weights or adjust your target."
                             : "Average \(required.formatted(.number.precision(.fractionLength(1))))% on the remaining work to reach your target.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text("No grades yet").font(.headline)
                    Text("Add a returned assessment to start your progress record.").foregroundStyle(.secondary)
                }
                Button { addingGrade = true } label: { Label("Add Grade", systemImage: "plus.circle") }
                    .accessibilityIdentifier("grade.add")
            } header: { Text("Current average") }
            footer: { Text("Average of entered assessments, weighted by their share of the course. It is not a predicted final grade.") }

            if !summary.trend.isEmpty {
                Section {
                    Chart {
                        ForEach(summary.trend) { point in
                            LineMark(x: .value("Received", point.date), y: .value("Average", point.average)).foregroundStyle(AppTheme.accent)
                            PointMark(x: .value("Received", point.date), y: .value("Average", point.average)).foregroundStyle(AppTheme.accent)
                        }
                        RuleMark(y: .value("Target", course.targetPercentage))
                            .lineStyle(StrokeStyle(dash: [4])).foregroundStyle(.secondary)
                    }
                    .chartYScale(domain: 0...100).frame(height: 170)
                    .accessibilityLabel("Weighted grade trend")
                    if let change = summary.trendChange {
                        Text("\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1)))) percentage points after your latest assessment")
                            .font(.caption).foregroundStyle(.secondary)
                    } else { Text("Add another grade to see a trend.").font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Grade trend") }
            }

            Section {
                let weeks = AcademicProgress.effortWeeks(course: course, courses: allCourses, sessions: sessions)
                let total = AcademicProgress.focusSeconds(course: course, courses: allCourses, sessions: sessions)
                LabeledContent("Logged total", value: FocusTimeFormat.duration(total)).accessibilityIdentifier("grade.effort")
                Chart(weeks) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Minutes", week.seconds / 60)).foregroundStyle(AppTheme.accent)
                }
                .chartYAxisLabel("Minutes").frame(height: 130)
                .accessibilityLabel("Logged focus time over four weeks")
            } header: { Text("Study effort · last 4 weeks") }
            footer: { Text("Finished Focus sessions, grouped by the week they ended. Use this beside your grades to decide where to spend time; it doesn't measure all studying or prove what caused a result.") }

            if !grades.isEmpty {
                Section("Assessments") {
                    ForEach(grades) { grade in
                        Button { editingGrade = grade } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(grade.title).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(GradeNumber.text(grade.percentage))%").foregroundStyle(.primary).monospacedDigit()
                                }
                                Text("\(GradeNumber.text(grade.weight))% weight · \(grade.receivedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("grade.entry.\(grade.title)")
                    }
                }
            }
        }
        .navigationTitle(course.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editingCourse = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Course settings")
            }
        }
        .sheet(isPresented: $addingGrade) { GradeEditorView(course: course) }
        .sheet(item: $editingGrade) { GradeEditorView(course: course, entry: $0) }
        .sheet(isPresented: $editingCourse) { CourseEditorView(course: course) }
    }
}
