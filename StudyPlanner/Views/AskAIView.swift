import SwiftUI
import SwiftData
import EventKit

private enum AskMode: String, CaseIterable, Identifiable {
    case tasks, schedule
    var id: String { rawValue }
    var label: String { self == .tasks ? "School tasks" : "Reminder or event" }
    var placeholder: String {
        self == .tasks ? "History essay due Friday" : "Remind me to submit my essay tomorrow at 5 pm"
    }
}

private enum AskPreview: Identifiable {
    case schedule(ScheduleDraft)
    case tasks([TaskDraft])
    var id: String {
        switch self {
        case .schedule(let draft): return draft.id.uuidString
        case .tasks(let drafts): return drafts.map(\.id.uuidString).joined(separator: "-")
        }
    }
}

struct AskAIView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StudyCourse.name) private var courses: [StudyCourse]
    @State private var mode: AskMode = .tasks
    @State private var prompt = ""
    @State private var preview: AskPreview?
    @State private var generating = false
    @State private var error: String?
    @State private var offerSimple = false
    @State private var generation: Task<Void, Never>?
    @FocusState private var promptFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles").font(.title2)
                            .foregroundStyle(AppTheme.accent).padding(16).background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode == .tasks ? "Add what you were just assigned." : "Say it. Make time for it.")
                                .font(.title2.bold())
                            Text(mode == .tasks
                                 ? "One assignment per line. You’ll review it before it’s saved."
                                 : "Reminders and calendar events, in your words.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(AskMode.allCases) { item in
                            Button { mode = item; error = nil; offerSimple = false } label: {
                                Text(item.label)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(mode == item ? AppTheme.accent : Color.clear, in: Capsule())
                                    .foregroundStyle(mode == item ? Color.white : .primary)
                                    .overlay(Capsule().stroke(AppTheme.accent.opacity(0.35)))
                            }
                            .accessibilityIdentifier(item == .tasks ? "askAI.mode.tasks" : "askAI.mode.schedule")
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(mode == .tasks ? "What was assigned?" : "What would you like to plan?").font(.headline)
                        TextField(mode.placeholder, text: $prompt, axis: .vertical)
                            .lineLimit(4...7).focused($promptFocused)
                            .padding(16).background(AppTheme.background, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("askAI.prompt")
                        Button(action: prepareDraft) {
                            HStack {
                                if generating { ProgressView().tint(.white) }
                                else { Image(systemName: "sparkles") }
                                Text(generating ? "Preparing your draft…" : "Preview Draft")
                            }
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                        .disabled(generating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("askAI.preview")
                    }
                    .padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24))
                    if let error {
                        Label(error, systemImage: "info.circle").font(.footnote).foregroundStyle(.orange)
                        if offerSimple {
                            Button("Use Simple Date Matching", action: useSimpleMatching)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TRY ASKING").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                        ForEach(examples, id: \.text) { example in
                            exampleButton(example.text, icon: example.icon)
                        }
                    }
                    Label(AskAIService.availabilityMessage, systemImage: AskAIService.isAvailable ? "iphone" : "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(mode == .tasks
                         ? "Tasks stay on this phone. The week plan then fits them around classes, work, and sleep. Nothing is saved until you confirm."
                         : "One item at a time. Nothing is saved until you confirm the preview. Your prompts stay on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("Ask AI").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("askAI.close") } }
            .sheet(item: $preview) { item in
                switch item {
                case .schedule(let draft):
                    SchedulePreviewView(initialDraft: draft)
                case .tasks(let drafts):
                    TaskPreviewView(initialDrafts: drafts, onFinished: { dismiss() })
                }
            }
            .onDisappear { generation?.cancel() }
        }
        .tint(AppTheme.accent)
    }

    private var examples: [(text: String, icon: String)] {
        switch mode {
        case .tasks:
            return [
                ("History essay due Friday", "doc.text"),
                ("Chem quiz Thursday at 10 am", "checkmark.circle")
            ]
        case .schedule:
            return [
                ("Remind me to submit my essay tomorrow at 5 pm", "checklist"),
                ("Schedule a study session tomorrow at 3 pm for 45 minutes", "calendar")
            ]
        }
    }

    private func exampleButton(_ text: String, icon: String) -> some View {
        Button { prompt = text; promptFocused = true } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(AppTheme.accent)
                Text(text).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(generating)
    }

    private func prepareDraft() {
        guard !generating else { return }
        promptFocused = false
        generating = true
        error = nil
        offerSimple = false
        let requested = mode
        generation = Task {
            defer { generating = false }
            do {
                switch requested {
                case .tasks:
                    let drafts = try await AskAIService.captureTasks(from: prompt, courses: courses)
                    try Task.checkCancellation()
                    preview = .tasks(drafts)
                case .schedule:
                    let draft = try await AskAIService.draft(from: prompt)
                    try Task.checkCancellation()
                    preview = .schedule(draft)
                }
            } catch is CancellationError { }
            catch let failure as DraftError { error = failure.localizedDescription }
            catch { self.error = "The on-device model couldn't prepare this request. Try a shorter note, or use simple date matching below."; offerSimple = true }
        }
    }

    private func useSimpleMatching() {
        do {
            switch mode {
            case .tasks:
                preview = .tasks(try BasicTaskParser.parse(prompt, courses: courses))
            case .schedule:
                preview = .schedule(try BasicScheduleParser.parse(prompt))
            }
            error = nil
            offerSimple = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct TaskPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyCourse.name) private var courses: [StudyCourse]
    @State private var drafts: [TaskDraft]
    @State private var saved = false
    var onFinished: () -> Void

    init(initialDrafts: [TaskDraft], onFinished: @escaping () -> Void) {
        _drafts = State(initialValue: initialDrafts)
        self.onFinished = onFinished
    }

    private var activeCourses: [StudyCourse] { courses.filter { !$0.isArchived } }
    private var canSave: Bool { drafts.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    var body: some View {
        NavigationStack {
            Group {
                if saved {
                    ContentUnavailableView {
                        Label("Added to Today", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    } description: {
                        Text("Your week plan will fit \(drafts.count == 1 ? "it" : "them") into open time around classes, work, and sleep.")
                    } actions: {
                        Button("Done", action: onFinished).buttonStyle(.borderedProminent)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("askAI.task.saved")
                } else {
                    Form {
                        Section {
                            Label(drafts.contains(where: \.usedAI) ? "Prepared with Apple Intelligence" : "Prepared from the dates in your note", systemImage: drafts.contains(where: \.usedAI) ? "sparkles" : "calendar.badge.clock")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach($drafts) { $draft in
                            Section {
                                TextField("Title", text: $draft.title).accessibilityIdentifier("askAI.task.title")
                                if !activeCourses.isEmpty {
                                    Picker("Course", selection: $draft.courseID) {
                                        Text("None").tag(UUID?.none)
                                        ForEach(activeCourses) { course in
                                            Text(course.pickerLabel).tag(UUID?.some(course.id))
                                        }
                                    }
                                }
                                Toggle("Due date", isOn: Binding(
                                    get: { draft.dueDate != nil },
                                    set: { draft.dueDate = $0 ? (draft.dueDate ?? Self.defaultDue) : nil }
                                ))
                                if draft.dueDate != nil {
                                    DatePicker("Due", selection: Binding(get: { draft.dueDate ?? Self.defaultDue }, set: { draft.dueDate = $0 }))
                                }
                                Toggle("Estimate", isOn: Binding(
                                    get: { draft.estimatedMinutes != nil },
                                    set: { draft.estimatedMinutes = $0 ? (draft.estimatedMinutes ?? 45) : nil }
                                ))
                                if let minutes = draft.estimatedMinutes {
                                    Stepper("\(minutes) minutes", value: Binding(
                                        get: { draft.estimatedMinutes ?? 45 },
                                        set: { draft.estimatedMinutes = $0 }
                                    ), in: 15...240, step: 15)
                                }
                            }
                        }
                        .onDelete { drafts.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle(saved ? "Saved" : "Preview").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "Close" : "Cancel") { dismiss() }
                }
                if !saved {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add", action: save)
                            .disabled(!canSave)
                            .accessibilityIdentifier("askAI.task.save")
                    }
                }
            }
        }
        .tint(AppTheme.accent)
    }

    private func save() {
        let ready = drafts.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !ready.isEmpty else { return }
        for draft in ready {
            let course = courses.first { $0.id == draft.courseID }
            modelContext.insert(StudyTask(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                dueDate: draft.dueDate,
                courseName: course?.name,
                estimatedMinutes: draft.estimatedMinutes,
                courseID: course?.id
            ))
        }
        saved = true
    }

    private static var defaultDue: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now.addingTimeInterval(86_400)
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow) ?? tomorrow
    }
}

struct SchedulePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var calendars: CalendarService
    @StateObject private var service = PersonalScheduleService()
    @State private var draft: ScheduleDraft
    @State private var destinationID = ""
    @State private var busy = false
    @State private var saved = false
    @State private var savedDestination = ""
    @State private var error: String?

    init(initialDraft: ScheduleDraft) { _draft = State(initialValue: initialDraft) }

    var body: some View {
        NavigationStack {
            Group {
                if saved {
                    ContentUnavailableView {
                        Label("You're all set", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    } description: {
                        Text("\(draft.title) was saved to \(draft.kind == .reminder ? "Apple Reminders" : "Calendar") in \(savedDestination).")
                    } actions: {
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                    .accessibilityIdentifier("askAI.saved")
                } else {
                    Form {
                        Section {
                            Label(draft.usedAI ? "Prepared with Apple Intelligence" : "Prepared with simple date matching", systemImage: draft.usedAI ? "sparkles" : "calendar.badge.clock")
                                .font(.footnote).foregroundStyle(.secondary)
                            Picker("Create", selection: $draft.kind) {
                                ForEach(ScheduleKind.allCases) { Text($0.label).tag($0) }
                            }
                            TextField("Title", text: $draft.title).accessibilityIdentifier("askAI.title")
                            Toggle(draft.kind == .reminder ? "Remind me at a time" : "Set a date", isOn: Binding(
                                get: { draft.date != nil },
                                set: { draft.date = $0 ? Date.now.addingTimeInterval(3600) : nil }
                            ))
                            if draft.date != nil {
                                DatePicker(draft.kind == .reminder ? "Due" : "Starts", selection: Binding(
                                    get: { draft.date ?? .now }, set: { draft.date = $0 }
                                ), displayedComponents: draft.kind == .event && draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                                if draft.kind == .event {
                                    Toggle("All day", isOn: $draft.isAllDay)
                                    if !draft.isAllDay {
                                        Stepper("\(draft.durationMinutes) minutes", value: $draft.durationMinutes, in: 1...1440, step: 5)
                                    }
                                }
                            }
                            TextField("Notes (optional)", text: $draft.notes, axis: .vertical).lineLimit(2...4)
                        } header: { Text("Review your draft") }
                        footer: {
                            Text("Check the title, date, and destination. A date without a time may use 9 AM. Times use \(TimeZone.current.identifier).")
                        }
                        Section {
                            if service.hasAccess {
                                if service.destinations.isEmpty {
                                    Text("No writable \(draft.kind == .reminder ? "reminder lists" : "calendars") found. Create one in \(draft.kind == .reminder ? "Apple Reminders" : "Calendar"), then return here.")
                                } else {
                                    Picker(draft.kind.destinationLabel, selection: $destinationID) {
                                        ForEach(service.destinations, id: \.calendarIdentifier) { calendar in
                                            Text("\(calendar.title) · \(calendar.source.title)").tag(calendar.calendarIdentifier)
                                        }
                                    }
                                }
                            } else if service.accessDenied {
                                Text("Access is off. Enable \(draft.kind == .reminder ? "Reminders" : "Calendar") for StudyPlanner in Settings.")
                                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                            } else {
                                Text("Connect \(draft.kind == .reminder ? "Apple Reminders" : "Calendar") to choose where to save this item.")
                                Button("Connect \(draft.kind == .reminder ? "Apple Reminders" : "Calendar")") {
                                    Task {
                                        busy = true
                                        defer { busy = false }
                                        do { try await service.requestAccess(for: draft.kind); refreshDestinations() }
                                        catch { self.error = "Access couldn't be requested. Please try again." }
                                    }
                                }
                                .accessibilityIdentifier("askAI.connect")
                            }
                        } header: { Text("Save to") }
                        footer: { Text("Saved items follow your existing account sync settings in Apple Reminders and Calendar.") }
                        if let validation = draft.validationError { Text(validation).foregroundStyle(.orange) }
                        if let date = draft.date, date < .now { Text("This date is in the past. Review it before saving.").foregroundStyle(.orange) }
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                    .disabled(busy)
                }
            }
            .navigationTitle(saved ? "Saved" : "Preview").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(saved ? "Close" : "Cancel") { dismiss() }.disabled(busy) }
                if !saved {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(busy || !service.hasAccess || destinationID.isEmpty || draft.validationError != nil)
                            .accessibilityIdentifier("askAI.save")
                    }
                }
            }
            .onChange(of: draft.kind, initial: true) { refreshDestinations() }
            .onChange(of: scenePhase) { if scenePhase == .active { refreshDestinations() } }
            .interactiveDismissDisabled(busy)
        }
        .tint(AppTheme.accent)
    }

    private func refreshDestinations() {
        service.refresh(for: draft.kind)
        if !service.destinations.contains(where: { $0.calendarIdentifier == destinationID }) {
            destinationID = service.defaultDestination(for: draft.kind) ?? ""
        }
    }

    private func save() {
        guard !busy, !saved else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            savedDestination = service.destinations.first { $0.calendarIdentifier == destinationID }?.title ?? "your account"
            try service.save(draft, destinationID: destinationID)
            saved = true
            calendars.reloadCalendars()
        } catch { self.error = error.localizedDescription }
    }
}
