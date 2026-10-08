import SwiftUI
import SwiftData

struct CoursesView: View {
    @Query(sort: \StudyCourse.name) private var courses: [StudyCourse]
    @Query private var grades: [GradeEntry]
    @State private var showingReview = false
    @State private var addingCourse = false

    var body: some View {
        NavigationStack {
            List {
                if courses.isEmpty {
                    ContentUnavailableView("Your courses", systemImage: "books.vertical",
                        description: Text("Tag classes from your calendars or add a course here to track grades."))
                    Button("Add Course") { addingCourse = true }
                    Button("Review Calendar Tags") { showingReview = true }
                } else {
                    Section {
                        ForEach(courses.filter { !$0.isArchived }) { course in courseLink(course) }
                    } footer: {
                        Text("Courses stay saved when their calendar events end. Tap a course to add grades, set a target, and see your study time.")
                    }
                    if courses.contains(where: \.isArchived) {
                        Section("Archived") {
                            ForEach(courses.filter(\.isArchived)) { course in courseLink(course) }
                        }
                    }
                }
            }
            .navigationTitle("Courses")

            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingReview = true } label: { Image(systemName: "tag") }
                        .accessibilityLabel("Review event tags")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addingCourse = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add course")
                }
            }
            .sheet(isPresented: $showingReview) { ReviewTagsView() }
            .sheet(isPresented: $addingCourse) { CourseEditorView() }
        }
    }

    private func courseLink(_ course: StudyCourse) -> some View {
        NavigationLink { CourseDetailView(course: course) } label: {
            CourseProgressRow(course: course, summary: AcademicProgress.summary(course: course, grades: grades))
        }
        .accessibilityIdentifier("course.\(course.name)")
    }
}

struct CourseProgressRow: View {
    let course: StudyCourse
    let summary: AcademicProgress.Summary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: summary.belowTarget ? "book.closed" : "graduationcap")
                .foregroundStyle(summary.belowTarget ? .orange : AppTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name).font(.body.weight(.medium))
                if let calendar = course.calendarName { Text(calendar).font(.caption).foregroundStyle(.secondary) }
                Text(summary.average == nil ? "No grades entered" : summary.belowTarget ? "Below \(GradeNumber.text(course.targetPercentage))% target" : "Meeting your target")
                    .font(.caption).foregroundStyle(summary.belowTarget ? .orange : .secondary)
            }
            Spacer()
            if let average = summary.average {
                Text("\(average, specifier: "%.1f")%")
                    .font(.headline).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}
