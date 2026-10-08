import SwiftUI
import SwiftData

/// The student writes how they want their time to work, checks the rules, then saves them.
struct PlanMyWayView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var notifications: NotificationService
    @Query private var tasks: [StudyTask]
    @Bindable var settings: UserSettings

    @State private var note: String
    @State private var studyTime: StudyTime
    @State private var blockMinutes: Int
    @State private var blockCustom: Bool
    @State private var dailyCap: Int
    @State private var remindersOn: Bool
    @State private var lead: Int
    @State private var dayStart: Date
    @State private var dayEnd: Date
    @State private var sleep: Double
    @State private var message: String?
    @State private var reading = false
    @FocusState private var noteFocused: Bool

    init(settings: UserSettings) {
        self.settings = settings
        _note = State(initialValue: settings.planNote)
        _studyTime = State(initialValue: StudyTime(rawValue: settings.studyTime) ?? .any)
        _blockMinutes = State(initialValue: settings.blockMinutes)
        _blockCustom = State(initialValue: settings.usesCustomBlockLength)
        _dailyCap = State(initialValue: settings.dailyCapMinutes)
        _remindersOn = State(initialValue: settings.remindersEnabled)
        _lead = State(initialValue: settings.reminderLeadMinutes)
        _dayStart = State(initialValue: settings.workdayStart)
        _dayEnd = State(initialValue: settings.workdayEnd)
        _sleep = State(initialValue: settings.sleepTargetHours)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("You decide how this day works. Say when you study, how long a block should be, and whether a reminder helps.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    TextField("Study in the morning, 25 minutes at a time. Remind me the night before.", text: $note, axis: .vertical)
                        .lineLimit(4...8)
                        .focused($noteFocused)
                        .accessibilityIdentifier("plan.note")
                    Button(action: readNote) {
                        HStack {
                            if reading { ProgressView() }
                            Text(reading ? "Reading…" : "Read this")
                        }
                    }
                    .disabled(reading || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("plan.read")
                    example("Mornings only, 25-minute blocks. Remind me the night before.")
                    example("Evenings, no more than 2 hours. Don't send notifications.")
                    example("Done by 9 pm. Remind me an hour before.")
                } header: {
                    Text("In your words")
                } footer: {
                    Text(AskAIService.isAvailable
                         ? "Apple Intelligence reads this on your iPhone, then you confirm. Nothing changes until you save."
                         : "The app reads times and reminders it recognizes. You confirm every change. On-device AI needs iOS 26 with Apple Intelligence.")
                }

                Section {
                    Picker("Study when", selection: $studyTime) {
                        ForEach(StudyTime.allCases) { time in
                            Text(time.label).tag(time)
                        }
                    }
                    Stepper(value: $blockMinutes, in: 25...90, step: 5) {
                        Text("\(blockMinutes)-minute blocks")
                    }
                    Stepper(value: $dailyCap, in: 0...360, step: 30) {
                        Text(dailyCap == 0 ? "No daily limit" : "Up to \(PlanStyle.span(dailyCap)) a day")
                    }
                    Toggle("Due-date reminders", isOn: $remindersOn)
                    if remindersOn {
                        Picker("Remind me", selection: $lead) {
                            Text("30 minutes before").tag(30)
                            Text("1 hour before").tag(60)
                            Text("2 hours before").tag(120)
                            Text("The night before").tag(24 * 60)
                        }
                    }
                    DatePicker("Day starts", selection: $dayStart, displayedComponents: .hourAndMinute)
                    DatePicker("Day ends", selection: $dayEnd, displayedComponents: .hourAndMinute)
                    Stepper(value: $sleep, in: 5...12, step: 0.5) {
                        Text("Sleep \(sleep, specifier: "%.1f") h")
                    }
                } header: {
                    Text("What I'll follow")
                } footer: {
                    Text("Deadlines and courses under your target still come first, inside the hours you chose. Suggestions stay on this phone.")
                }

                if let message {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
                if dayEndMinutes <= dayStartMinutes {
                    Section {
                        Text("Your day has to end after it starts.").foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Plan my way")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use this plan", action: save)
                        .disabled(dayEndMinutes <= dayStartMinutes)
                        .accessibilityIdentifier("plan.save")
                }
            }
        }
        .tint(AppTheme.accent)
    }

    private var dayStartMinutes: Int { UserSettings.minutes(from: dayStart) }
    private var dayEndMinutes: Int { UserSettings.minutes(from: dayEnd) }

    private func example(_ text: String) -> some View {
        Button(text) {
            note = text
            readNote()
        }
        .font(.subheadline)
        .disabled(reading)
    }

    private func readNote() {
        guard !reading else { return }
        noteFocused = false
        reading = true
        message = nil
        let written = note
        Task {
            let result = await AskAIService.interpretPlan(written)
            if let time = result.studyTime { studyTime = time }
            if let minutes = result.blockMinutes {
                blockMinutes = minutes
                blockCustom = true
            }
            if let cap = result.dailyCapMinutes { dailyCap = cap }
            if let enabled = result.remindersEnabled { remindersOn = enabled }
            if let reminderLead = result.reminderLeadMinutes { lead = nearestLead(reminderLead) }
            if let start = result.dayStartMinutes { dayStart = date(fromMinutes: start) }
            if let end = result.dayEndMinutes { dayEnd = date(fromMinutes: end) }
            if let hours = result.sleepHours { sleep = hours }
            message = result.recognized
                ? "Here's what I understood. Change anything, then save."
                : "I kept your words. Set a time of day, a block length, or a reminder below if you want the schedule to change."
            reading = false
        }
    }

    private func save() {
        settings.planNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.studyTime = studyTime.rawValue
        let changedLength = blockMinutes != settings.blockMinutes
        settings.usesCustomBlockLength = blockCustom || changedLength || settings.usesCustomBlockLength
        settings.blockMinutes = blockMinutes
        settings.dailyCapMinutes = dailyCap
        settings.workdayStartMinutes = dayStartMinutes
        settings.workdayEndMinutes = dayEndMinutes
        settings.sleepTargetHours = sleep
        settings.reminderLeadMinutes = lead
        let wantsReminders = remindersOn
        Task {
            if wantsReminders {
                settings.remindersEnabled = await notifications.requestPermission()
            } else {
                settings.remindersEnabled = false
            }
            notifications.sync(tasks: tasks, settings: settings)
            dismiss()
        }
    }

    private func nearestLead(_ minutes: Int) -> Int {
        [30, 60, 120, 24 * 60].min { abs($0 - minutes) < abs($1 - minutes) } ?? 120
    }

    private func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }
}

struct PlanCard: View {
    var settings: UserSettings
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                Label(settings.planNote.isEmpty ? "You set the rules" : "Your plan", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                Text(settings.planNote.isEmpty
                     ? "Say when you study, how long a block should be, and when a reminder helps. The day follows that, and you can change it anytime."
                     : settings.planNote)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if !settings.planNote.isEmpty {
                    Text(PlanStyle.summary(of: settings))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("plan.summary")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.open")
    }
}
