import SwiftUI
import EventKit

/// Choose which device calendars count. Selection is stored in UserSettings;
/// nil means "all calendars" (the default after granting access).
struct CalendarPickerView: View {
    @EnvironmentObject private var calendarService: CalendarService
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: UserSettings

    var body: some View {
        NavigationStack {
            List {
                ForEach(calendarService.calendarsByAccount, id: \.account) { group in
                    Section(group.account) {
                        ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                            CalendarToggleRow(
                                calendar: calendar,
                                isOn: isSelected(calendar),
                                toggle: { toggle(calendar) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isSelected(_ calendar: EKCalendar) -> Bool {
        settings.selectedCalendarIDs?.contains(calendar.calendarIdentifier) ?? true
    }

    private func toggle(_ calendar: EKCalendar) {
        let allIDs = calendarService.calendars.map(\.calendarIdentifier)
        var selected = Set(settings.selectedCalendarIDs ?? allIDs)
        if selected.contains(calendar.calendarIdentifier) {
            selected.remove(calendar.calendarIdentifier)
        } else {
            selected.insert(calendar.calendarIdentifier)
        }
        // Back to "all selected"? Store nil so newly added calendars are included automatically.
        settings.selectedCalendarIDs = selected == Set(allIDs) ? nil : Array(selected)
    }
}

private struct CalendarToggleRow: View {
    let calendar: EKCalendar
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 12, height: 12)
                Text(calendar.title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
        }
    }
}
