import EventKit
import SwiftUI

/// Wraps EKEventStore: permission, calendar listing, and event fetching.
/// This reader never changes events. Explicit Ask AI saves live in
/// PersonalScheduleService; the DEBUG seeder creates simulator samples.
@MainActor
final class CalendarService: ObservableObject {
    private let store = EKEventStore()

    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var calendars: [EKCalendar] = []
    /// Bumped whenever the system reports external calendar changes, so views re-fetch.
    @Published private(set) var storeVersion = 0

    private var changeObserver: NSObjectProtocol?

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadCalendars()
                self?.storeVersion += 1
            }
        }
        reloadCalendars()
    }

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        reloadCalendars()
    }

    func reloadCalendars() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard authorizationStatus == .fullAccess else {
            calendars = []
            return
        }
        calendars = store.calendars(for: .event)
            .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
    }

    /// Calendars grouped by account (EKSource), for the picker UI.
    var calendarsByAccount: [(account: String, calendars: [EKCalendar])] {
        Dictionary(grouping: calendars, by: { $0.source.title })
            .map { (account: $0.key, calendars: $0.value) }
            .sorted { $0.account < $1.account }
    }

    /// Events for the next `days` days. `selectedIDs == nil` means all calendars.
    func upcomingEvents(selectedIDs: Set<String>?, days: Int = 14) -> [EKEvent] {
        let start = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else { return [] }
        return events(from: start, to: end, selectedIDs: selectedIDs)
    }

    /// Events that overlap `[start, end)`. `selectedIDs == nil` means all calendars.
    func events(from start: Date, to end: Date, selectedIDs: Set<String>?) -> [EKEvent] {
        guard authorizationStatus == .fullAccess, end > start else { return [] }
        let included = calendars.filter { selectedIDs?.contains($0.calendarIdentifier) ?? true }
        guard !included.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: included)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    #if DEBUG
    /// Removes calendars created by SEED_SAMPLE_EVENTS. Launch with
    /// CLEAR_SAMPLE_EVENTS=1. Release builds do not include this.
    func clearSampleDataIfRequested() {
        guard ProcessInfo.processInfo.environment["CLEAR_SAMPLE_EVENTS"] == "1",
              authorizationStatus == .fullAccess else { return }
        let seeded = store.calendars(for: .event).filter {
            $0.title == "School (Sample)" || $0.title == "Work (Sample)" || $0.title.hasPrefix("StudyPlanner Calendar Test")
        }
        guard !seeded.isEmpty else { return }
        for calendar in seeded {
            try? store.removeCalendar(calendar, commit: false)
        }
        try? store.commit()
        reloadCalendars()
        storeVersion += 1
    }

    /// Creates sample calendars + events on the simulator's local source so the
    /// flow can be exercised without real accounts. Triggered by launch env
    /// SEED_SAMPLE_EVENTS=1; never runs in release builds.
    func seedSampleDataIfRequested() async {
        guard ProcessInfo.processInfo.environment["SEED_SAMPLE_EVENTS"] == "1",
              authorizationStatus == .fullAccess,
              let source = store.sources.first(where: { $0.sourceType == .local }),
              !calendars.contains(where: { $0.title == "School (Sample)" })
        else { return }

        func makeCalendar(_ title: String, _ color: UIColor) -> EKCalendar {
            let cal = EKCalendar(for: .event, eventStore: store)
            cal.title = title
            cal.cgColor = color.cgColor
            cal.source = source
            try? store.saveCalendar(cal, commit: false)
            return cal
        }

        func addEvent(_ title: String, calendar: EKCalendar, dayOffset: Int, hour: Int, minute: Int = 0, durationMinutes: Int = 60, allDay: Bool = false) {
            let event = EKEvent(eventStore: store)
            event.title = title
            event.calendar = calendar
            let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Calendar.current.startOfDay(for: .now))!
            event.startDate = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            event.endDate = event.startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
            event.isAllDay = allDay
            try? store.save(event, span: .thisEvent, commit: false)
        }

        let school = makeCalendar("School (Sample)", .systemIndigo)
        let work = makeCalendar("Work (Sample)", .systemOrange)

        for offset in 0..<10 {
            let weekday = Calendar.current.component(.weekday, from: Calendar.current.date(byAdding: .day, value: offset, to: .now)!)
            guard (2...6).contains(weekday) else { continue }  // weekdays only
            addEvent("CS 301 Lecture", calendar: school, dayOffset: offset, hour: 10)
            if weekday == 3 || weekday == 5 {
                addEvent("MATH 210", calendar: school, dayOffset: offset, hour: 13, durationMinutes: 90)
            }
            if weekday == 2 || weekday == 4 {
                addEvent("Cafe shift", calendar: work, dayOffset: offset, hour: 17, durationMinutes: 240)
            }
        }
        addEvent("Essay 2 due", calendar: school, dayOffset: 3, hour: 23, minute: 59, durationMinutes: 1)
        addEvent("CS 301 Quiz", calendar: school, dayOffset: 6, hour: 10)

        try? store.commit()
        reloadCalendars()
        storeVersion += 1
    }
    #endif
}
