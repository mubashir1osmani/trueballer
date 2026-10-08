import SwiftUI
import SwiftData
import EventKit

struct TodayView: View {
    var openFocus: (StudyTask) -> Void
    @EnvironmentObject private var calendarService: CalendarService
    @EnvironmentObject private var notifications: NotificationService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyTask.dueDate) private var tasks: [StudyTask]
    @Query private var allSettings: [UserSettings]
    @Query private var calendarRules: [CalendarRule]
    @Query private var titleRules: [TitleRule]
    @Query private var courses: [StudyCourse]
    @Query private var grades: [GradeEntry]
    @State private var reviewingCourse: StudyCourse?
    @State private var showingQuickAdd = false
    @State private var reschedulingTask: StudyTask?
    @State private var showingPlan = false

    private var settings: UserSettings? { allSettings.first }

    private var allEvents: [EKEvent] {
        _ = calendarService.storeVersion
        let selectedIDs = settings?.selectedCalendarIDs.map(Set.init)
        return calendarService.upcomingEvents(selectedIDs: selectedIDs)
    }

    private var ranked: [StudyTask] { Planner.rankedTasks(tasks, courses: courses, grades: grades) }
    private var atRisk: [StudyCourse] {
        courses.filter { !$0.isArchived && AcademicProgress.summary(course: $0, grades: grades).belowTarget }
            .sorted { AcademicProgress.summary(course: $0, grades: grades).gap > AcademicProgress.summary(course: $1, grades: grades).gap }
    }
    private var nextUp: [StudyTask] { Array(ranked.prefix(3)) }
    private var later: [StudyTask] { Array(ranked.dropFirst(3)) }
    private var snoozed: [StudyTask] {
        tasks.filter { !$0.isCompleted && Planner.isSnoozed($0, now: .now) }
    }

    private var daySummary: Planner.DaySummary? {
        guard let settings else { return nil }
        return Planner.daySummary(events: allEvents, settings: settings)
    }

    private var studyBlocks: [WeekPlanner.Block] {
        guard let settings else { return [] }
        return WeekPlanner.suggest(
            tasks: tasks,
            courses: courses,
            grades: grades,
            busy: allEvents.map { WeekPlanner.BusyInterval(start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay) },
            settings: settings
        )
    }

    private var suggestions: [EKEvent] {
        let ignoredCalendars = Set(calendarRules.filter { $0.tag == .ignore }.map(\.calendarID))
        return DeadlineDetector.suggestions(
            events: allEvents.filter { !ignoredCalendars.contains($0.calendar.calendarIdentifier) },
            existingTasks: tasks,
            dismissedEventIDs: settings?.dismissedSuggestionIDs ?? []
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if ranked.isEmpty && suggestions.isEmpty && snoozed.isEmpty && atRisk.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Today")
            .toolbar {
                SettingsToolbarButton()
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingQuickAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add task")
                }
            }
            .sheet(isPresented: $showingQuickAdd) { QuickAddView() }
            .sheet(isPresented: $showingPlan) {
                if let settings { PlanMyWayView(settings: settings) }
            }
            .sheet(item: $reschedulingTask) { task in
                RescheduleSheet(task: task)
            }
            .sheet(item: $reviewingCourse) { course in
                NavigationStack {
                    CourseDetailView(course: course)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { reviewingCourse = nil } } }
                }
            }
            .onChange(of: tasks.map(\.isCompleted)) { syncNotifications() }
            .onChange(of: tasks.count) { syncNotifications() }
            .task { syncNotifications() }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let settings {
                    PlanCard(settings: settings) { showingPlan = true }
                }
                ContentUnavailableView {
                    Label("All clear", systemImage: "sun.max")
                } description: {
                    Text("No tasks yet. Add one the moment it's assigned.")
                } actions: {
                    Button("Add Task") { showingQuickAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private var content: some View {
        List {
            TodayOverview(taskCount: ranked.count, freeMinutes: daySummary?.freeMinutes)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            if let settings {
                PlanCard(settings: settings) { showingPlan = true }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if !nextUp.isEmpty {
                Section {
                    ForEach(nextUp) { task in
                        TaskRow(task: task, emphasized: true, priorityNote: priorityNote(task), openFocus: { openFocus(task) })
                            .taskSwipeActions(task, reschedule: { reschedulingTask = $0 })
                    }
                } header: {
                    Text("Next up")
                } footer: {
                    if let summary = daySummary {
                        FreeTimeLabel(summary: summary)
                    }
                }
            }

            if !studyBlocks.isEmpty {
                Section {
                    ForEach(studyBlocks.prefix(3)) { block in
                        StudyBlockRow(block: block, identifierPrefix: "today.study") {
                            if let task = tasks.first(where: { $0.persistentModelID == block.taskID && !$0.isCompleted }) {
                                openFocus(task)
                            }
                        }
                    }
                } header: {
                    Text("Suggested study")
                } footer: {
                    Text("Placed in open time around your calendar, working hours, and sleep. These are not added to your calendar.")
                }
            }

            if !atRisk.isEmpty {
                Section {
                    ForEach(atRisk.prefix(3)) { course in
                        Button { reviewingCourse = course } label: {
                            CourseProgressRow(course: course, summary: AcademicProgress.summary(course: course, grades: grades))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.course.\(course.name)")
                    }
                } header: { Text("Worth some study time") }
                footer: { Text("These courses are below your target. Their tasks get a priority boost within the same deadline window.") }
            }

            if let summary = daySummary, !summary.lockedEvents.isEmpty {
                Section("Today's schedule") {
                    ForEach(summary.lockedEvents, id: \.eventIdentifier) { event in
                        LockedEventRow(event: event)
                    }
                }
            }

            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions, id: \.eventIdentifier) { event in
                        SuggestionRow(
                            event: event,
                            accept: { acceptSuggestion(event) },
                            dismissSuggestion: { dismissSuggestion(event) }
                        )
                    }
                } header: {
                    Text("From your calendar")
                } footer: {
                    Text("These look like deadlines. Add the real ones.")
                }
            }

            if !later.isEmpty {
                Section("Later") {
                    ForEach(later) { task in
                        TaskRow(task: task, emphasized: false, openFocus: { openFocus(task) })
                            .taskSwipeActions(task, reschedule: { reschedulingTask = $0 })
                    }
                }
            }

            if !snoozed.isEmpty {
                Section("Snoozed") {
                    ForEach(snoozed) { task in
                        TaskRow(task: task, emphasized: false, openFocus: { openFocus(task) })
                            .taskSwipeActions(task, reschedule: { reschedulingTask = $0 })
                    }
                }
            }
        }
        .animation(.default, value: tasks.map(\.isCompleted))

    }

    private func acceptSuggestion(_ event: EKEvent) {
        let groups = Classifier.groups(events: allEvents, calendarRules: calendarRules, titleRules: titleRules)
        let candidates = groups.filter {
            $0.calendarID == event.calendar.calendarIdentifier && $0.tag == .course
                && !DeadlineDetector.isDeadlineTitle($0.displayTitle)
        }
        let course = candidates.count == 1 ? candidates.first : nil
        modelContext.insert(StudyTask(
            title: event.title,
            dueDate: event.startDate,
            courseName: course?.displayTitle,
            sourceEventID: event.eventIdentifier,
            courseID: course.flatMap { group in courses.first { $0.sourceGroupID == group.id }?.id }
        ))
        syncNotifications()
    }

    private func priorityNote(_ task: StudyTask) -> String? {
        guard let course = CourseCatalog.course(for: task, in: courses), !course.isArchived,
              AcademicProgress.summary(course: course, grades: grades).belowTarget else { return nil }
        return "Below \(GradeNumber.text(course.targetPercentage))% target"
    }

    private func dismissSuggestion(_ event: EKEvent) {
        guard let settings, let id = event.eventIdentifier else { return }
        settings.dismissedSuggestionIDs = (settings.dismissedSuggestionIDs ?? []) + [id]
    }

    private func syncNotifications() {
        guard let settings else { return }
        notifications.sync(tasks: tasks, settings: settings)
    }
}

// MARK: - Rows

private struct TaskRow: View {
    let task: StudyTask
    let emphasized: Bool
    var priorityNote: String? = nil
    let openFocus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                task.isCompleted.toggle()
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(emphasized ? .body.weight(.medium) : .body)
                if let course = task.courseName {
                    Text(course)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let priorityNote {
                    Text(priorityNote).font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            if let due = task.dueDate {
                DueLabel(date: due)
            }
            Button(action: openFocus) {
                Image(systemName: "timer")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .accessibilityLabel("Focus on \(task.title)")
        }
    }
}

private extension View {
    /// Swipe right → Done; swipe left → Snooze (to tomorrow morning) and Reschedule.
    func taskSwipeActions(_ task: StudyTask, reschedule: @escaping (StudyTask) -> Void) -> some View {
        self
            .swipeActions(edge: .leading) {
                Button {
                    task.isCompleted = true
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button {
                    reschedule(task)
                } label: {
                    Label("Reschedule", systemImage: "calendar")
                }
                .tint(.orange)
                Button {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
                    task.snoozedUntil = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
                } label: {
                    Label("Snooze", systemImage: "moon.zzz")
                }
                .tint(.indigo)
            }
    }
}

private struct DueLabel: View {
    let date: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(date, format: .dateTime.weekday().month().day())
                .font(.subheadline)
            Text(date, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(date < .now ? .red : .primary)
    }
}

private struct LockedEventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 4, height: 32)
            Text(event.title)
                .font(.subheadline)
            Spacer()
            Text("\(event.startDate, format: .dateTime.hour().minute()) – \(event.endDate, format: .dateTime.hour().minute())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FreeTimeLabel: View {
    let summary: Planner.DaySummary

    var body: some View {
        let hours = summary.freeMinutes / 60
        let minutes = summary.freeMinutes % 60
        Text(summary.freeMinutes == 0
             ? "No free time left in your day."
             : "About \(hours > 0 ? "\(hours)h " : "")\(minutes)m free until day's end.")
    }
}

private struct SuggestionRow: View {
    let event: EKEvent
    let accept: () -> Void
    let dismissSuggestion: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Text(event.startDate, format: .dateTime.weekday().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add", action: accept)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button {
                dismissSuggestion()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Reschedule

private struct RescheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: StudyTask
    @State private var newDate: Date

    init(task: StudyTask) {
        self.task = task
        _newDate = State(initialValue: task.dueDate ?? .now.addingTimeInterval(86_400))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("New due date", selection: $newDate)
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        task.dueDate = newDate
                        task.snoozedUntil = nil
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
