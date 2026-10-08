import SwiftUI
import SwiftData
import EventKit

/// Morning stickies, one calendar day at a time. Organize reads that day's
/// notes into tasks and planning rules. The student confirms before anything
/// is saved, and the week planner places the study blocks after that.
struct BraindumpView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var calendars: CalendarService
    @Query(sort: \BrainNote.createdAt) private var notes: [BrainNote]
    @Query private var settingsRows: [UserSettings]
    @Query private var tasks: [StudyTask]
    @Query private var courses: [StudyCourse]
    @Query private var grades: [GradeEntry]

    @State private var draft = ""
    @State private var composerDay = Calendar.current.startOfDay(for: .now)
    @State private var editing: BrainNote?
    @State private var organize: OrganizeRequest?
    @FocusState private var composerFocused: Bool

    private var sections: [BraindumpSection] {
        let calendar = Calendar.current
        return BraindumpOrganizer.days(from: notes.map(\.day)).compactMap { day in
            let dayNotes = notes
                .filter { calendar.isDate($0.day, inSameDayAs: day) && !trimmed($0.text).isEmpty }
                .sorted { $0.createdAt < $1.createdAt }
            guard calendar.isDateInToday(day) || !dayNotes.isEmpty else { return nil }
            return BraindumpSection(day: day, notes: dayNotes)
        }
    }

    private var busy: [WeekPlanner.BusyInterval] {
        _ = calendars.storeVersion
        let selected = settingsRows.first?.selectedCalendarIDs.map(Set.init)
        return calendars.upcomingEvents(selectedIDs: selected).map {
            WeekPlanner.BusyInterval(start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    composer
                    ForEach(sections) { section in
                        daySection(section)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(AppTheme.background)
            .navigationTitle("Braindump")
            .toolbar { SettingsToolbarButton() }
            .sheet(item: $editing) { note in
                BrainNoteEditor(note: note)
            }
            .sheet(item: $organize) { request in
                OrganizeBraindumpSheet(
                    request: request,
                    existingTasks: tasks.filter { !$0.isCompleted },
                    courses: courses,
                    grades: grades,
                    busy: busy,
                    settings: settingsRows.first
                )
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One thought per note. Organize reads a day, then you confirm the tasks and the rules for your schedule.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                TextField("Chem quiz Thursday", text: $draft, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($composerFocused)
                    .font(.body.weight(.medium))
                    .foregroundStyle(StickyPalette.ink)
                    .accessibilityIdentifier("braindump.composer")
                    .onSubmit(addNote)
                HStack {
                    DatePicker("Day", selection: $composerDay, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityIdentifier("braindump.day")
                    Spacer()
                    Button(action: addNote) {
                        Label("Add note", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(trimmed(draft).isEmpty)
                    .accessibilityIdentifier("braindump.add")
                }
            }
            .padding(16)
            .background(StickyPalette.papers[0], in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
    }

    private func daySection(_ section: BraindumpSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sectionTitle(section.day))
                        .font(.title3.bold())
                    Text(section.day, format: .dateTime.month(.wide).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !section.notes.isEmpty {
                    Button {
                        openOrganize(section)
                    } label: {
                        Label("Organize", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("braindump.organize.\(Self.dayStamp.string(from: section.day))")
                }
            }
            if section.notes.isEmpty {
                Text("Nothing here yet. Dump the morning before you plan it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(section.notes) { note in
                        StickyNoteCard(note: note) {
                            editing = note
                        } onDelete: {
                            modelContext.delete(note)
                        }
                    }
                }
            }
        }
    }

    private func addNote() {
        let text = trimmed(draft)
        guard !text.isEmpty else { return }
        let day = Calendar.current.startOfDay(for: composerDay)
        modelContext.insert(BrainNote(text: String(text.prefix(500)), day: day, colorIndex: notes.count % StickyPalette.papers.count))
        draft = ""
        composerFocused = false
    }

    private func openOrganize(_ section: BraindumpSection) {
        let pending = section.notes.filter { $0.organizedAt == nil }
        let source = pending.isEmpty ? section.notes : pending
        organize = OrganizeRequest(day: section.day, notes: source, rereading: pending.isEmpty)
    }

    private func sectionTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let dayStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct BraindumpSection: Identifiable {
    var day: Date
    var notes: [BrainNote]
    var id: Date { day }
}

struct OrganizeRequest: Identifiable {
    var day: Date
    var notes: [BrainNote]
    var rereading: Bool
    var id: Date { day }
}

private enum StickyPalette {
    static let papers: [Color] = [
        Color(red: 0.99, green: 0.91, blue: 0.55),
        Color(red: 0.98, green: 0.76, blue: 0.60),
        Color(red: 0.76, green: 0.90, blue: 0.76),
        Color(red: 0.82, green: 0.80, blue: 0.96),
        Color(red: 0.98, green: 0.82, blue: 0.86),
        Color(red: 0.73, green: 0.87, blue: 0.93)
    ]
    static let ink = Color(red: 0.22, green: 0.16, blue: 0.08)
    static let tilts: [Double] = [-1.4, 1.15, -0.55, 1.45, -1.05, 0.75]
}

private struct StickyNoteCard: View {
    var note: BrainNote
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var paper: Color { StickyPalette.papers[note.colorIndex % StickyPalette.papers.count] }
    private var tilt: Double { StickyPalette.tilts[note.colorIndex % StickyPalette.tilts.count] }

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(.white.opacity(0.55))
                    .frame(width: 36, height: 8)
                    .frame(maxWidth: .infinity)
                Text(note.text)
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(StickyPalette.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack {
                    Text(note.createdAt, format: .dateTime.hour().minute())
                    Spacer()
                    if note.organizedAt != nil {
                        Image(systemName: "checkmark")
                    }
                }
                .font(.caption2)
                .foregroundStyle(StickyPalette.ink.opacity(0.55))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(paper, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
            .rotationEffect(.degrees(tilt))
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("Note, \(note.text)")
        .accessibilityIdentifier("braindump.note.\(note.text)")
    }
}

private struct BrainNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: BrainNote
    @State private var removed = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Note", text: $note.text, axis: .vertical)
                    .lineLimit(4...10)
                DatePicker("Day", selection: $note.day, displayedComponents: .date)
            }
            .navigationTitle("Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Delete", role: .destructive) {
                        removed = true
                        modelContext.delete(note)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: note.day) {
                let start = Calendar.current.startOfDay(for: note.day)
                if note.day != start { note.day = start }
            }
            .onDisappear {
                guard !removed else { return }
                if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    modelContext.delete(note)
                }
            }
        }
        .tint(AppTheme.accent)
    }
}

private struct OrganizeBraindumpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var account: AccountStore
    @Query private var savedTasks: [StudyTask]

    var request: OrganizeRequest
    var existingTasks: [StudyTask]
    var courses: [StudyCourse]
    var grades: [GradeEntry]
    var busy: [WeekPlanner.BusyInterval]
    var settings: UserSettings?

    @State private var drafts: [TaskDraft] = []
    @State private var plan = PlanReading()
    @State private var usePlan = true
    @State private var usedAI = false
    @State private var loading = true
    @State private var saved = false
    @State private var job: Task<Void, Never>?

    private var readyTasks: [TaskDraft] {
        drafts.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var planFits: Bool {
        guard usePlan, plan.recognized, let settings else { return true }
        let copy = BraindumpOrganizer.copy(of: settings)
        BraindumpOrganizer.apply(plan, to: copy)
        return copy.workdayEndMinutes > copy.workdayStartMinutes
    }

    private var blocks: [WeekPlanner.Block] {
        guard let settings, !loading else { return [] }
        return BraindumpOrganizer.scheduledBlocks(
            existing: existingTasks,
            drafts: readyTasks,
            courses: courses,
            grades: grades,
            busy: busy,
            settings: settings,
            plan: plan,
            applyPlan: usePlan && plan.recognized && planFits
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if saved {
                    savedState
                } else if loading {
                    ProgressView("Reading your notes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    review
                }
            }
            .navigationTitle(saved ? "Saved" : "Organize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "Close" : "Cancel") { dismiss() }
                }
                if !saved && !loading {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saveTitle, action: save)
                            .disabled(!canSave)
                            .accessibilityIdentifier("braindump.save")
                    }
                }
            }
        }
        .tint(AppTheme.accent)
        .onAppear(perform: startReading)
        .onDisappear { job?.cancel() }
    }

    private var saveTitle: String {
        if !readyTasks.isEmpty && usePlan && plan.recognized { return "Use this plan" }
        if !readyTasks.isEmpty { return "Add tasks" }
        return "Use these rules"
    }

    private var canSave: Bool {
        if !readyTasks.isEmpty { return true }
        return usePlan && plan.recognized && planFits && settings != nil
    }

    private var savedState: some View {
        ContentUnavailableView {
            Label("Added to your plan", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.accent)
        } description: {
            Text("Today and Calendar will fit study blocks around classes, work, and sleep. Nothing was added to your calendar.")
        } actions: {
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("braindump.saved")
    }

    private var sourceLabel: String {
        guard usedAI else { return "Prepared from the words in your notes" }
        return account.canUseCloudAI && account.lastNotice == nil ? "Read by Claude · check it before saving" : "Prepared with Apple Intelligence"
    }

    private var review: some View {
        Form {
            Section {
                Label(sourceLabel, systemImage: usedAI ? "sparkles" : "note.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let notice = account.lastNotice {
                    Label(notice.message, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if request.rereading {
                    Text("These notes were already organized. Saving again can add the same tasks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(request.notes) { note in
                    Text(note.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(request.day, format: .dateTime.weekday(.wide).month().day())
            }

            if drafts.isEmpty {
                Section {
                    Text("No assignments in these notes.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach($drafts) { $draft in
                    Section {
                        TextField("Title", text: $draft.title)
                            .accessibilityIdentifier("braindump.task.title")
                        if !courses.filter({ !$0.isArchived }).isEmpty {
                            Picker("Course", selection: $draft.courseID) {
                                Text("None").tag(UUID?.none)
                                ForEach(courses.filter { !$0.isArchived }) { course in
                                    Text(course.pickerLabel).tag(UUID?.some(course.id))
                                }
                            }
                        }
                        Toggle("Due date", isOn: Binding(
                            get: { draft.dueDate != nil },
                            set: { draft.dueDate = $0 ? (draft.dueDate ?? Self.defaultDue) : nil }
                        ))
                        if draft.dueDate != nil {
                            DatePicker("Due", selection: Binding(
                                get: { draft.dueDate ?? Self.defaultDue },
                                set: { draft.dueDate = $0 }
                            ))
                        }
                    }
                }
                .onDelete { drafts.remove(atOffsets: $0) }
            }

            if plan.recognized {
                Section {
                    Toggle("Use these rules", isOn: $usePlan)
                        .accessibilityIdentifier("braindump.plan")
                    ForEach(BraindumpOrganizer.describedChanges(plan), id: \.self) { line in
                        Text(line)
                    }
                    if !planFits {
                        Text("Those hours would end the day before it starts. The tasks can still be added.")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("How the day should work")
                }
            }

            if plan.recognized == false && drafts.isEmpty {
                Section {
                    Text("Nothing here looks like school work or a rule for your day. Add a quiz, an essay, or when you want to study.")
                        .foregroundStyle(.secondary)
                }
            }

            if !blocks.isEmpty {
                Section {
                    ForEach(blocks.prefix(6)) { block in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.title).font(.body.weight(.medium))
                            Text("\(block.start, format: .dateTime.weekday(.abbreviated).hour().minute()) – \(block.end, format: .dateTime.hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("braindump.block.\(block.title)")
                    }
                } header: {
                    Text("Suggested study")
                } footer: {
                    Text("Placed in open time around your calendar, working hours, and sleep. These stay in StudyPlanner until you add them to Calendar yourself. Nothing is saved until you confirm.")
                }
            } else if !readyTasks.isEmpty {
                Section {
                    Text("No open block fits these tasks inside your hours.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func startReading() {
        guard loading, job == nil else { return }
        let text = request.notes
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let courseList = courses
        job = Task {
            let reading = await AskAIService.readBraindump(text, courses: courseList, account: account)
            guard !Task.isCancelled else { return }
            drafts = reading.tasks
            plan = reading.plan
            usePlan = reading.plan.recognized
            usedAI = reading.usedAI
            loading = false
        }
    }

    private func save() {
        guard canSave else { return }
        var inserted: [StudyTask] = []
        for draft in readyTasks {
            let course = courses.first { $0.id == draft.courseID }
            let task = StudyTask(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                dueDate: draft.dueDate,
                courseName: course?.name,
                estimatedMinutes: draft.estimatedMinutes,
                courseID: course?.id
            )
            modelContext.insert(task)
            inserted.append(task)
        }
        let wantsReminders = usePlan && plan.remindersEnabled == true && planFits
        if usePlan && plan.recognized && planFits, let settings {
            BraindumpOrganizer.apply(plan, to: settings)
            if settings.planNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.planNote = BraindumpOrganizer.describedChanges(plan).joined(separator: ". ")
            }
        }
        let now = Date.now
        for note in request.notes where note.organizedAt == nil {
            note.organizedAt = now
        }
        let settings = self.settings
        let known = savedTasks.map(\.persistentModelID)
        let snapshot = savedTasks + inserted.filter { !known.contains($0.persistentModelID) }
        Task {
            if wantsReminders, let settings {
                settings.remindersEnabled = await notifications.requestPermission()
            }
            if let settings {
                notifications.sync(tasks: snapshot, settings: settings)
            }
        }
        saved = true
    }

    private static var defaultDue: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now.addingTimeInterval(86_400)
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow) ?? tomorrow
    }
}
