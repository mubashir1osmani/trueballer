import SwiftUI
import SwiftData

struct CourseEditorView: View {
    var course: StudyCourse?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var courses: [StudyCourse]
    @State private var name: String
    @State private var credits: String
    @State private var target: String
    @State private var hasGPA: Bool
    @State private var points: String
    @State private var scale: Double
    @State private var archived: Bool
    @State private var error: String?

    init(course: StudyCourse? = nil) {
        self.course = course
        _name = State(initialValue: course?.name ?? "")
        _credits = State(initialValue: GradeNumber.text(course?.credits ?? 3))
        _target = State(initialValue: GradeNumber.text(course?.targetPercentage ?? 70))
        _hasGPA = State(initialValue: course?.gpaPoints != nil)
        _points = State(initialValue: course?.gpaPoints.map(GradeNumber.text) ?? "")
        _scale = State(initialValue: course?.gpaScale ?? 4)
        _archived = State(initialValue: course?.isArchived ?? false)
    }

    private var validation: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a course name." }
        if course == nil, courses.contains(where: { normalizeEventTitle($0.name) == normalizeEventTitle(name) }) { return "That course already exists. Use its settings, or add a term to this name." }
        guard let c = GradeNumber.parse(credits), c > 0, c <= 100 else { return "Enter credits greater than 0 and up to 100." }
        guard let t = GradeNumber.parse(target), (0...100).contains(t) else { return "Enter a target from 0 to 100%." }
        if hasGPA {
            guard let p = GradeNumber.parse(points), (0...scale).contains(p) else { return "Enter GPA points from 0 to \(GradeNumber.text(scale))." }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Course name", text: $name).accessibilityIdentifier("course.name")
                    numericField("Credits", text: $credits, id: "course.credits")
                    numericField("Target (%)", text: $target, id: "course.target")
                } footer: { Text("Your target flags courses for extra study time. Credits weight your entered GPA and the size of the task priority boost.") }
                Section {
                    Toggle("Enter GPA points", isOn: $hasGPA).accessibilityIdentifier("course.hasGPA")
                    if hasGPA {
                        Picker("GPA scale", selection: $scale) {
                            ForEach([4.0, 4.3, 5.0, 10.0], id: \.self) { value in Text(GradeNumber.text(value)).tag(value) }
                        }
                        numericField("GPA points", text: $points, id: "course.points")
                    }
                } footer: { Text("Use the current course grade points from your school's conversion. Update them when grades change; percentages are not automatically converted to GPA.") }
                if course != nil {
                    Section { Toggle("Archive course", isOn: $archived) }
                    footer: { Text("Archived courses keep their grades and focus history, and are excluded from current GPA and task priority boosts.") }
                }
                if let validation { Text(validation).font(.footnote).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(course == nil ? "New Course" : "Course Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(validation != nil).accessibilityIdentifier("course.save") }
            }
        }
    }

    private func save() {
        guard validation == nil, let c = GradeNumber.parse(credits), let t = GradeNumber.parse(target) else { return }
        let record = course ?? StudyCourse(name: name)
        let old = (record.name, record.credits, record.targetPercentage, record.gpaPoints, record.gpaScale, record.isArchived)
        if course == nil { context.insert(record) }
        record.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        record.credits = c; record.targetPercentage = t
        record.gpaPoints = hasGPA ? GradeNumber.parse(points) : nil
        record.gpaScale = scale; record.isArchived = archived
        do { try context.save(); dismiss() } catch {
            if course == nil { context.delete(record) }
            else { (record.name, record.credits, record.targetPercentage, record.gpaPoints, record.gpaScale, record.isArchived) = old }
            self.error = "The course couldn't be saved. Please try again."
        }
    }
}

struct GradeEditorView: View {
    let course: StudyCourse
    var entry: GradeEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var grades: [GradeEntry]
    @State private var title: String
    @State private var percentage: String
    @State private var weight: String
    @State private var date: Date
    @State private var error: String?
    @State private var confirmingDelete = false

    init(course: StudyCourse, entry: GradeEntry? = nil) {
        self.course = course; self.entry = entry
        _title = State(initialValue: entry?.title ?? "")
        _percentage = State(initialValue: entry.map { GradeNumber.text($0.percentage) } ?? "")
        _weight = State(initialValue: entry.map { GradeNumber.text($0.weight) } ?? "")
        _date = State(initialValue: entry?.receivedAt ?? .now)
    }

    private var validation: String? {
        AcademicProgress.gradeError(title: title, percentage: GradeNumber.parse(percentage), weight: GradeNumber.parse(weight),
            otherWeight: grades.filter { $0.courseID == course.id && $0.id != entry?.id }.reduce(0) { $0 + $1.weight })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(course.name) {
                    TextField("Assessment name", text: $title).accessibilityIdentifier("grade.title")
                    numericField("Grade (%)", text: $percentage, id: "grade.percentage")
                    numericField("Course weight (%)", text: $weight, id: "grade.weight")
                    DatePicker("Received", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section {
                    Text("Enter the assessment's share of your final course grade from the syllabus. Leave ungraded work out until you receive a result.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let validation { Text(validation).font(.footnote).foregroundStyle(.orange) }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                if entry != nil {
                    Button("Delete Grade", role: .destructive) { confirmingDelete = true }.accessibilityIdentifier("grade.delete")
                }
            }
            .navigationTitle(entry == nil ? "Add Grade" : "Edit Grade").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(validation != nil).accessibilityIdentifier("grade.save") }
            }
            .confirmationDialog("Delete this grade?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Grade", role: .destructive) {
                    guard let entry else { return }
                    context.delete(entry)
                    do { try context.save(); dismiss() } catch { context.rollback(); self.error = "The grade couldn't be deleted." }
                }
            }
        }
    }

    private func save() {
        guard validation == nil, let percentage = GradeNumber.parse(percentage), let weight = GradeNumber.parse(weight) else { return }
        let record = entry ?? GradeEntry(courseID: course.id, title: title, percentage: percentage, weight: weight)
        let old = (record.title, record.percentage, record.weight, record.receivedAt)
        if entry == nil { context.insert(record) }
        record.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        record.percentage = percentage; record.weight = weight; record.receivedAt = date
        do { try context.save(); dismiss() } catch {
            if entry == nil { context.delete(record) }
            else { (record.title, record.percentage, record.weight, record.receivedAt) = old }
            self.error = "The grade couldn't be saved. Please try again."
        }
    }
}

private func numericField(_ label: String, text: Binding<String>, id: String) -> some View {
    HStack {
        Text(label)
        Spacer()
        TextField(label, text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            .frame(minWidth: 70, maxWidth: 120).accessibilityIdentifier(id)
    }
}
