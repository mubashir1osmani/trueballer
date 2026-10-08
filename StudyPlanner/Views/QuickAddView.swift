import SwiftUI
import SwiftData

/// The primary way tasks enter the app (plan.md 1c): title, optional due
/// date, optional course — fast enough to use mid-lecture.
struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyCourse.name) private var courses: [StudyCourse]

    @State private var title = ""
    @State private var hasDueDate = true
    @State private var dueDate = defaultDueDate()
    @State private var courseID: UUID?
    @State private var hasEstimate = false
    @State private var estimateMinutes = 25
    @FocusState private var titleFocused: Bool

    private var activeCourses: [StudyCourse] { courses.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What's due?", text: $title)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(saveIfValid)

                Section {
                    Toggle("Due date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate)
                    }
                }

                if !activeCourses.isEmpty {
                    Section {
                        Picker("Course", selection: $courseID) {
                            Text("None").tag(UUID?.none)
                            ForEach(activeCourses) { course in
                                Text(course.pickerLabel).tag(UUID?.some(course.id))
                            }
                        }
                    }
                }
                Section {
                    Toggle("Estimate time", isOn: $hasEstimate)
                    if hasEstimate {
                        Stepper("\(estimateMinutes) minutes", value: $estimateMinutes, in: 5...1440, step: 5)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { saveIfValid() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { titleFocused = true }
        }
        .presentationDetents([.large])
    }

    private func saveIfValid() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(StudyTask(
            title: trimmed,
            dueDate: hasDueDate ? dueDate : nil,
            courseName: courses.first { $0.id == courseID }?.name,
            estimatedMinutes: hasEstimate ? estimateMinutes : nil,
            courseID: courseID
        ))
        dismiss()
    }

    /// Tomorrow 11:59 PM — the most common real deadline shape.
    private static func defaultDueDate() -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow)!
    }
}
