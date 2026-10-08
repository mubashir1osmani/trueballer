import SwiftUI
import SwiftData

struct FocusView: View {
    @EnvironmentObject private var focus: FocusManager
    @Query private var tasks: [StudyTask]
    @Query private var courses: [StudyCourse]
    @Query private var grades: [GradeEntry]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Binding var selectedTask: StudyTask?
    @State private var estimateMinutes = 25
    let showToday: () -> Void

    private var nextTask: StudyTask? {
        if let selectedTask, !selectedTask.isCompleted { return selectedTask }
        return Planner.rankedTasks(tasks, courses: courses, grades: grades).first
    }

    private var finishedSessions: [FocusSession] { sessions.filter { $0.endedAt != nil } }

    var body: some View {
        NavigationStack {
            List {
                if let session = focus.activeSession {
                    activeTimer(session)
                } else if let task = nextTask {
                    readyTimer(task)
                } else {
                    ContentUnavailableView {
                        Label("Ready when you are", systemImage: "timer")
                    } description: {
                        Text("Add a task on Today, then come here for a little focused time.")
                    } actions: {
                        Button("Go to Today", action: showToday)
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }

                if let notice = focus.activityNotice, focus.activeSession != nil {
                    Section {
                        Label(notice, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !finishedSessions.isEmpty {
                    Section {
                        ForEach(finishedSessions.prefix(20)) { session in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(session.taskTitle).font(.body.weight(.medium))
                                    Spacer()
                                    Text(FocusTimeFormat.duration(session.accumulatedSeconds))
                                        .monospacedDigit()
                                }
                                if let course = session.courseName {
                                    Text(course).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                                if let task = session.task {
                                    effortSummary(task: task, estimate: task.estimatedMinutes ?? session.estimatedMinutes, now: .now)
                                }
                                if session.completedTask {
                                    Label("Task completed", systemImage: "checkmark.circle.fill")
                                        .font(.caption).foregroundStyle(AppTheme.accent)
                                }
                            }
                            .padding(.vertical, 3)
                            .accessibilityIdentifier("focus.history.\(session.id)")
                        }
                    } header: {
                        Text("Recent sessions")
                    } footer: {
                        Text("All focus time is saved on this device, including sessions on completed tasks.")
                    }
                }
            }
            .navigationTitle("Focus")

            .onChange(of: nextTask?.persistentModelID, initial: true) {
                estimateMinutes = nextTask?.estimatedMinutes ?? 25
            }
        }
    }

    private func readyTimer(_ task: StudyTask) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Label("Next task", systemImage: "scope")
                    .font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.accent)
                taskHeading(title: task.title, course: task.courseName)
                Text("One task, at your pace.")
                    .foregroundStyle(.secondary)
                Stepper(value: $estimateMinutes, in: 5...1440, step: 5) {
                    LabeledContent("Estimated total", value: "\(estimateMinutes) min")
                }
                .accessibilityIdentifier("focus.estimate")
                if totalSeconds(for: task, now: .now) > 0 {
                    effortSummary(task: task, estimate: estimateMinutes, now: .now)
                }
                Button {
                    Task { await focus.start(task: task, estimateMinutes: estimateMinutes) }
                } label: {
                    Label("Start Focus", systemImage: "play.fill")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                .disabled(focus.isBusy)
                .accessibilityIdentifier("focus.start")
            }
            .padding(.vertical, 8)
        } footer: {
            Text("The timer counts up. Pause for breaks; finish when you're ready. Choose a different task from Today.")
        }
    }

    private func activeTimer(_ session: FocusSession) -> some View {
        Section {
            VStack(spacing: 20) {
                taskHeading(title: session.taskTitle, course: session.courseName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    VStack(spacing: 8) {
                        Text(FocusTimeFormat.clock(session.elapsed(at: timeline.date)))
                            .font(.system(size: 56, weight: .light, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                            .accessibilityIdentifier("focus.elapsed")
                        Label(session.isPaused ? "Paused" : "Focusing", systemImage: session.isPaused ? "pause.circle" : "circle.dotted")
                            .font(.subheadline).foregroundStyle(AppTheme.accent)
                            .accessibilityIdentifier("focus.status")
                        if let task = session.task {
                            effortSummary(task: task, estimate: session.estimatedMinutes, now: timeline.date)
                        }
                    }
                }
                Button {
                    Task { await focus.togglePause() }
                } label: {
                    Label(session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill")
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(AppTheme.accent)
                .accessibilityIdentifier("focus.pause")
                Button {
                    Task { await focus.finish(completeTask: true) }
                } label: {
                    Label("Complete Task & Log Time", systemImage: "checkmark")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                .accessibilityIdentifier("focus.complete")
                Button("End Session & Log Time") {
                    Task { await focus.finish(completeTask: false) }
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("focus.end")
            }
            .disabled(focus.isBusy)
            .padding(.vertical, 12)
        } footer: {
            Text("Time continues while the app is closed or your phone is locked. Pauses don't count. End a session to keep the task open.")
        }
    }

    private func taskHeading(title: String, course: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold))
            if let course { Text(course).font(.subheadline).foregroundStyle(.secondary) }
        }
    }

    private func totalSeconds(for task: StudyTask, now: Date) -> TimeInterval {
        sessions.filter { $0.task?.persistentModelID == task.persistentModelID }
            .reduce(0) { $0 + $1.elapsed(at: now) }
    }

    private func effortSummary(task: StudyTask, estimate: Int, now: Date) -> some View {
        Text("\(FocusTimeFormat.duration(totalSeconds(for: task, now: now))) focused total · \(estimate) min estimated")
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("focus.effort")
    }
}
