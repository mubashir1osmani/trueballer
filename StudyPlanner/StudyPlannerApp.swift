import SwiftUI
import SwiftData

@main
struct StudyPlannerApp: App {
    @StateObject private var calendarService = CalendarService()
    @StateObject private var notificationService = NotificationService()
    @StateObject private var focusManager = FocusManager(activities: FocusLiveActivityService())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(calendarService)
                .environmentObject(notificationService)
                .environmentObject(focusManager)
                #if DEBUG
                .task {
                    calendarService.clearSampleDataIfRequested()
                    await calendarService.seedSampleDataIfRequested()
                }
                #endif
        }
        .modelContainer(for: [UserSettings.self, CalendarRule.self, TitleRule.self, StudyTask.self, FocusSession.self, StudyCourse.self, GradeEntry.self, BrainNote.self])
    }
}
