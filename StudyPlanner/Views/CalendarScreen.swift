import SwiftUI
import SwiftData
import EventKit

struct CalendarView: View {
    var openFocus: (StudyTask) -> Void
    @EnvironmentObject private var calendarService: CalendarService
    @Query private var allSettings: [UserSettings]
    @State private var showingPicker = false

    private var settings: UserSettings? { allSettings.first }

    var body: some View {
        NavigationStack {
            Group {
                switch calendarService.authorizationStatus {
                case .notDetermined:
                    ConnectCalendarsView()
                case .fullAccess:
                    MonthSchedule(openFocus: openFocus, showingPicker: $showingPicker)
                default:
                    MonthSchedule(openFocus: openFocus, showingPicker: $showingPicker, accessDenied: true)
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                if calendarService.authorizationStatus == .fullAccess {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingPicker = true } label: { Image(systemName: "checklist") }
                            .accessibilityLabel("Choose calendars")
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                if let settings { CalendarPickerView(settings: settings) }
            }
        }
    }
}

/// Pre-permission explainer — shown before the system prompt so the user
/// understands why access is being requested.
private struct ConnectCalendarsView: View {
    @EnvironmentObject private var calendarService: CalendarService

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Connect your calendars")
                .font(.title2.bold())
            Text("See classes, shifts, and deadlines from the calendars already on your phone. Study suggestions then fit into the open time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Connect Calendars") {
                Task { await calendarService.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("If your school account isn't on this phone yet, add it in Settings → Apps → Calendar → Accounts first.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}

private struct MonthSchedule: View {
    var openFocus: (StudyTask) -> Void
    @Binding var showingPicker: Bool
    var accessDenied = false

    @EnvironmentObject private var calendarService: CalendarService
    @Query private var tasks: [StudyTask]
    @Query private var courses: [StudyCourse]
    @Query private var grades: [GradeEntry]
    @Query private var allSettings: [UserSettings]
    @State private var visibleMonth = MonthGrid.startOfMonth(for: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private var gridDays: [Date] { MonthGrid.days(in: visibleMonth) }

    private var events: [EKEvent] {
        _ = calendarService.storeVersion
        guard let first = gridDays.first, let last = gridDays.last else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let horizon = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        let start = min(first, today)
        let end = max(calendar.date(byAdding: .day, value: 1, to: last) ?? last, horizon)
        return calendarService.events(from: start, to: end, selectedIDs: allSettings.first?.selectedCalendarIDs.map(Set.init))
    }

    private var blocks: [WeekPlanner.Block] {
        guard let settings = allSettings.first else { return [] }
        return WeekPlanner.suggest(
            tasks: tasks,
            courses: courses,
            grades: grades,
            busy: events.map { WeekPlanner.BusyInterval(start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay) },
            settings: settings
        )
    }

    private var entriesByDay: [Date: [PlanEntry]] {
        let calendar = Calendar.current
        var grouped: [Date: [PlanEntry]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.startDate)
            grouped[day, default: []].append(PlanEntry(
                id: event.eventIdentifier ?? "\(event.startDate.timeIntervalSinceReferenceDate)-\(event.title ?? "")",
                start: event.startDate,
                event: event,
                block: nil
            ))
        }
        for block in blocks {
            let day = calendar.startOfDay(for: block.start)
            grouped[day, default: []].append(PlanEntry(id: block.id, start: block.start, event: nil, block: block))
        }
        for day in grouped.keys {
            grouped[day]?.sort { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.event != nil && rhs.event == nil
            }
        }
        return grouped
    }

    private var selectedEntries: [PlanEntry] {
        entriesByDay[Calendar.current.startOfDay(for: selectedDay)] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                monthHeader
                weekdayHeader
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(gridDays, id: \.self) { day in
                        dayCell(day)
                    }
                }
                if accessDenied {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Calendar access is off, so this grid only shows study blocks from your tasks, working hours, and sleep target.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Open Settings", action: openSettings)
                    }
                } else if !blocks.isEmpty {
                    Text(planLine)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(selectedDay, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.headline)
                    if selectedEntries.isEmpty {
                        Text("Nothing on this day.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(selectedEntries) { entry in
                            if let event = entry.event {
                                EventRow(event: event)
                                    .padding(12)
                                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
                            } else if let block = entry.block {
                                StudyBlockRow(block: block, identifierPrefix: "calendar.study") {
                                    if let task = tasks.first(where: { $0.persistentModelID == block.taskID && !$0.isCompleted }) {
                                        openFocus(task)
                                    }
                                }
                                .padding(12)
                                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")
            .accessibilityIdentifier("calendar.month.previous")
            Spacer()
            Text(visibleMonth, format: .dateTime.month(.wide).year())
                .font(.title3.bold())
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next month")
            .accessibilityIdentifier("calendar.month.next")
        }
    }

    private var weekdayHeader: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let ordered = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
        return HStack(spacing: 6) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let inMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let entries = entriesByDay[calendar.startOfDay(for: day)] ?? []
        let hasStudy = entries.contains { $0.block != nil }
        return Button {
            selectedDay = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 4) {
                Text(day, format: .dateTime.day())
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (inMonth ? Color.primary : Color.secondary))
                Circle()
                    .fill(entries.isEmpty ? Color.clear : (hasStudy ? (isSelected ? Color.white : AppTheme.accent) : Color.secondary))
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).fill(AppTheme.accent)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 12).stroke(AppTheme.accent, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityIdentifier("calendar.day.\(Self.dayStamp.string(from: day))")
    }

    private func shiftMonth(by value: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        visibleMonth = MonthGrid.startOfMonth(for: next, calendar: calendar)
        if !calendar.isDate(selectedDay, equalTo: visibleMonth, toGranularity: .month) {
            selectedDay = visibleMonth
        }
    }

    private var planLine: String {
        if let settings = allSettings.first, !settings.planNote.isEmpty {
            return "Study blocks follow your plan: \(PlanStyle.summary(of: settings)). They stay in StudyPlanner until you add them to Calendar yourself."
        }
        return "Study blocks sit in open time around classes, work, and sleep. They stay in StudyPlanner until you add them to Calendar yourself."
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
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

private enum MonthGrid {
    static func startOfMonth(for date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? date
    }

    /// Every cell in the month grid, including the leading and trailing days from neighboring months.
    static func days(in month: Date, calendar: Calendar = .current) -> [Date] {
        let start = startOfMonth(for: month, calendar: calendar)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: start) else { return [] }
        let count = Int((Double(leading + range.count) / 7).rounded(.up)) * 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }
}

private struct PlanEntry: Identifiable {
    var id: String
    var start: Date
    var event: EKEvent?
    var block: WeekPlanner.Block?
}

struct StudyBlockRow: View {
    var block: WeekPlanner.Block
    var identifierPrefix: String
    var focus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(AppTheme.accent)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested study").font(.caption).foregroundStyle(AppTheme.accent)
                Text(block.title).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let course = block.courseName {
                        Text(course)
                    }
                    Text("\(block.start, format: .dateTime.hour().minute()) – \(block.end, format: .dateTime.hour().minute())")
                }
                .font(.caption).foregroundStyle(.secondary)
                if block.protectsGPA {
                    Text("Below your target").font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Button(action: focus) {
                Image(systemName: "timer")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .accessibilityLabel("Start the suggested block for \(block.title)")
        }
        .accessibilityIdentifier("\(identifierPrefix).\(block.title)")
        .padding(.vertical, 2)
    }
}

private struct EventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body)
                Text(event.calendar.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if event.isAllDay {
                Text("All day").font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(event.startDate, format: .dateTime.hour().minute()).font(.subheadline)
                    Text(event.endDate, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
