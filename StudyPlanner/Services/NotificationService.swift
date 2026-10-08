import Foundation
import UserNotifications

/// Schedules local reminders for task due dates. Notifications are re-synced
/// (wipe + reschedule) whenever tasks or prefs change — simpler than diffing
/// and cheap at student scale.
@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    init() {
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    /// Returns true if permission is granted (existing or newly).
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        return granted
    }

    /// Reschedules all reminders from current open tasks. Call after any task
    /// or settings change. No-ops (and clears) when reminders are disabled.
    func sync(tasks: [StudyTask], settings: UserSettings) {
        center.removeAllPendingNotificationRequests()
        guard settings.remindersEnabled, authorizationStatus == .authorized else { return }

        let lead = TimeInterval(settings.reminderLeadMinutes * 60)
        for task in tasks where !task.isCompleted {
            guard let due = task.dueDate else { continue }
            let fireDate = due.addingTimeInterval(-lead)
            guard fireDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = task.courseName.map { "\($0) — due \(due.formatted(date: .omitted, time: .shortened))" }
                ?? "Due \(due.formatted(date: .omitted, time: .shortened))"
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(
                identifier: "task-\(task.id.uuidString)",
                content: content,
                trigger: trigger
            ))
        }
    }
}

extension NotificationService {
    /// Lightweight migration can give every pre-existing task the same default
    /// UUID. Reminder IDs must be unique, so reassign any repeats.
    @discardableResult
    static func repairDuplicateIDs(_ tasks: [StudyTask]) -> Bool {
        var seen = Set<UUID>()
        var changed = false
        for task in tasks.sorted(by: { $0.createdAt < $1.createdAt }) {
            if !seen.insert(task.id).inserted {
                task.id = UUID()
                seen.insert(task.id)
                changed = true
            }
        }
        return changed
    }
}
