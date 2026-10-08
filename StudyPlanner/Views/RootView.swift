import SwiftUI
import SwiftData
import EventKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var focus: FocusManager
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var calendars: CalendarService
    @Query private var tasks: [StudyTask]
    @Query private var settings: [UserSettings]
    @Query private var courses: [StudyCourse]
    @Query private var sessions: [FocusSession]
    @Query private var calendarRules: [CalendarRule]
    @Query private var titleRules: [TitleRule]
    @State private var catalogError: String?
    @State private var selectedTab: Tab = RootView.initialTab
    @State private var selectedFocusTask: StudyTask?

    enum Tab: String, CaseIterable, Identifiable {
        case today, braindump, courses, calendar, focus
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: "Today"
            case .braindump: "Braindump"
            case .courses: "Courses"
            case .calendar: "Calendar"
            case .focus: "Focus"
            }
        }
        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .braindump: "note.text"
            case .courses: "books.vertical"
            case .calendar: "calendar"
            case .focus: "timer"
            }
        }
    }

    /// DEBUG: launch env INITIAL_TAB=calendar (etc.) opens that tab, so
    /// simulator automation can reach any screen without tapping.
    private static var initialTab: Tab {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["INITIAL_TAB"],
           let tab = Tab(rawValue: raw) {
            return tab
        }
        #endif
        return .today
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView { task in
                selectedFocusTask = task
                selectedTab = .focus
            }
            .appTab(.today)
            BraindumpView()
                .appTab(.braindump)
            CoursesView()
                .appTab(.courses)
            CalendarView { task in
                selectedFocusTask = task
                selectedTab = .focus
            }
            .appTab(.calendar)
            FocusView(selectedTask: $selectedFocusTask, showToday: { selectedTab = .today })
                .appTab(.focus)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(selection: $selectedTab)
        }
        .tint(AppTheme.accent)
        .onAppear(perform: ensureSettingsExist)
        .onChange(of: catalogSignature, initial: true) { syncCourses() }
        .task { await focus.restore(context: modelContext) }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                calendars.reloadCalendars()
                Task { await focus.restore(context: modelContext) }
            }
        }
        .onChange(of: tasks.map(\.isCompleted)) {
            if let settings = settings.first { notifications.sync(tasks: tasks, settings: settings) }
            finishCompletedSessionIfNeeded()
        }
        .onChange(of: focus.isBusy) {
            // Also reconcile if Today changed while an ActivityKit update was
            // in flight, or the app relaunched after that task was completed.
            finishCompletedSessionIfNeeded()
        }
        .onOpenURL { url in
            if url.scheme == "studyplanner", url.host == "focus" { selectedTab = .focus }
        }
        .alert("Focus couldn't save", isPresented: Binding(
            get: { focus.errorMessage != nil },
            set: { if !$0 { focus.errorMessage = nil } }
        )) {
            Button("OK") { focus.errorMessage = nil }
        } message: {
            Text(focus.errorMessage ?? "Please try again.")
        }
        .alert("Courses couldn't save", isPresented: Binding(
            get: { catalogError != nil }, set: { if !$0 { catalogError = nil } }
        )) {
            Button("Retry") { syncCourses() }
            Button("OK", role: .cancel) { }
        } message: { Text(catalogError ?? "Please try again.") }
    }

    private var discoveredGroups: [EventGroup] {
        _ = calendars.storeVersion
        let events = calendars.upcomingEvents(selectedIDs: settings.first?.selectedCalendarIDs.map(Set.init))
        return Classifier.groups(events: events, calendarRules: calendarRules, titleRules: titleRules)
    }

    private var catalogSignature: [String] {
        discoveredGroups.map { "\($0.id):\($0.tag?.rawValue ?? "")" }.sorted()
        + tasks.map { "\($0.courseName ?? ""):\($0.courseID?.uuidString ?? "")" }.sorted()
        + courses.map { $0.id.uuidString }.sorted()
        + sessions.map { $0.id.uuidString }.sorted()
    }

    private func syncCourses() {
        do {
            try CourseCatalog.synchronize(groups: discoveredGroups, tasks: tasks, sessions: sessions, context: modelContext)
        } catch { catalogError = "Your saved data is still here. Course discovery couldn't finish; please try again." }
    }

    private func ensureSettingsExist() {
        let descriptor = FetchDescriptor<UserSettings>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        if count == 0 {
            modelContext.insert(UserSettings())
        }
        seedSampleRulesIfRequested()
    }

    private func finishCompletedSessionIfNeeded() {
        guard !focus.isBusy, focus.errorMessage == nil,
              focus.activeSession?.task?.isCompleted == true else { return }
        Task { await focus.finish(completeTask: true) }
    }

    /// DEBUG: SEED_SAMPLE_RULES=1 tags the sample calendars (School→course,
    /// Work→work) so classification can be exercised without tapping.
    private func seedSampleRulesIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["SEED_SAMPLE_RULES"] == "1" else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<CalendarRule>())) ?? []
        guard existing.isEmpty else { return }
        let store = EKEventStore()
        for calendar in store.calendars(for: .event) {
            switch calendar.title {
            case "School (Sample)":
                modelContext.insert(CalendarRule(calendarID: calendar.calendarIdentifier, tag: .course))
            case "Work (Sample)":
                modelContext.insert(CalendarRule(calendarID: calendar.calendarIdentifier, tag: .work))
            default:
                break
            }
        }
        if ProcessInfo.processInfo.environment["SEED_SAMPLE_TASKS"] == "1" {
            let due = Calendar.current.date(byAdding: .day, value: 2, to: .now)
            modelContext.insert(StudyTask(title: "Problem set 4", dueDate: due, courseName: "MATH 210"))
            modelContext.insert(StudyTask(title: "Read chapter 7", dueDate: nil, courseName: "CS 301 Lecture"))
        }
        #endif
    }
}

private extension View {
    func appTab(_ tab: RootView.Tab) -> some View {
        self
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label(tab.title, systemImage: tab.symbol) }
            .tag(tab)
    }
}

private struct AppTabBar: View {
    @Binding var selection: RootView.Tab

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                ForEach(RootView.Tab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 18, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                        .foregroundStyle(selection == tab ? AppTheme.accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityIdentifier("tab.\(tab.rawValue)")
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .accessibilityRemoveTraits(selection == tab ? [] : .isSelected)
                }
            }
        }
        .background(Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom))
    }
}

#Preview {
    RootView()
        .environmentObject(CalendarService())
        .environmentObject(NotificationService())
        .environmentObject(FocusManager(activities: FocusLiveActivityService()))
        .modelContainer(for: [UserSettings.self, CalendarRule.self, TitleRule.self, StudyTask.self, FocusSession.self, StudyCourse.self, GradeEntry.self, BrainNote.self], inMemory: true)
}
