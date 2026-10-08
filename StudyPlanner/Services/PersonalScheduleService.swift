import EventKit
import Foundation

@MainActor
final class PersonalScheduleService: ObservableObject {
    @Published private(set) var destinations: [EKCalendar] = []
    @Published private(set) var hasAccess = false
    @Published private(set) var accessDenied = false
    private let store = EKEventStore()
    private var savedDrafts = Set<UUID>()

    func refresh(for kind: ScheduleKind) {
        let entity: EKEntityType = kind == .reminder ? .reminder : .event
        let status = EKEventStore.authorizationStatus(for: entity)
        hasAccess = status == .fullAccess
        accessDenied = status == .denied || status == .restricted
        destinations = hasAccess ? store.calendars(for: entity).filter(\.allowsContentModifications)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } : []
    }

    func requestAccess(for kind: ScheduleKind) async throws {
        if kind == .reminder { _ = try await store.requestFullAccessToReminders() }
        else { _ = try await store.requestFullAccessToEvents() }
        refresh(for: kind)
    }

    func defaultDestination(for kind: ScheduleKind) -> String? {
        let defaultID = (kind == .reminder ? store.defaultCalendarForNewReminders() : store.defaultCalendarForNewEvents)?.calendarIdentifier
        return destinations.first { $0.calendarIdentifier == defaultID }?.calendarIdentifier ?? destinations.first?.calendarIdentifier
    }

    func save(_ draft: ScheduleDraft, destinationID: String) throws {
        guard !savedDrafts.contains(draft.id) else { return }
        if let error = draft.validationError { throw DraftError.message(error) }
        refresh(for: draft.kind)
        guard hasAccess, let calendar = destinations.first(where: { $0.calendarIdentifier == destinationID }) else {
            throw DraftError.message("Choose a writable destination. You may need to enable access in Settings.")
        }
        if draft.kind == .reminder {
            let reminder = EKReminder(eventStore: store)
            reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.notes = draft.notes
            reminder.calendar = calendar
            if let date = draft.date {
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                components.calendar = Calendar.current
                components.timeZone = TimeZone.current
                reminder.dueDateComponents = components
                reminder.addAlarm(EKAlarm(absoluteDate: date))
            }
            try store.save(reminder, commit: true)
        } else {
            guard let start = draft.date else { throw DraftError.message("Choose a start date.") }
            let event = EKEvent(eventStore: store)
            event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            event.notes = draft.notes
            event.calendar = calendar
            event.isAllDay = draft.isAllDay
            event.startDate = draft.isAllDay ? Calendar.current.startOfDay(for: start) : start
            event.endDate = draft.isAllDay
                ? Calendar.current.date(byAdding: .day, value: 1, to: event.startDate)!
                : start.addingTimeInterval(Double(draft.durationMinutes) * 60)
            try store.save(event, span: .thisEvent, commit: true)
        }
        savedDrafts.insert(draft.id)
    }
}
