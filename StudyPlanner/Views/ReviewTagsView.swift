import SwiftUI
import SwiftData
import EventKit

/// Tag review: one row per recurring event group. Picking a tag saves a
/// TitleRule (2 taps to fix a mis-tag: open menu, pick tag). Calendar-level
/// defaults live in the per-calendar section at the bottom.
struct ReviewTagsView: View {
    @EnvironmentObject private var calendarService: CalendarService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [UserSettings]
    @Query private var calendarRules: [CalendarRule]
    @Query private var titleRules: [TitleRule]

    private var groups: [EventGroup] {
        _ = calendarService.storeVersion
        let selectedIDs = allSettings.first?.selectedCalendarIDs.map(Set.init)
        let events = calendarService.upcomingEvents(selectedIDs: selectedIDs)
        return Classifier.groups(events: events, calendarRules: calendarRules, titleRules: titleRules)
    }

    var body: some View {
        NavigationStack {
            List {
                let needsReview = groups.filter { $0.source == .none }
                let reviewed = groups.filter { $0.source != .none }

                if !needsReview.isEmpty {
                    Section("Needs review") {
                        ForEach(needsReview) { group in
                            GroupTagRow(group: group, setTag: { setTitleRule(group, $0) })
                        }
                    }
                }

                if !reviewed.isEmpty {
                    Section("Tagged") {
                        ForEach(reviewed) { group in
                            GroupTagRow(group: group, setTag: { setTitleRule(group, $0) })
                        }
                    }
                }

                Section {
                    ForEach(calendarService.calendars, id: \.calendarIdentifier) { calendar in
                        CalendarDefaultRow(
                            calendar: calendar,
                            currentTag: calendarRules.first { $0.calendarID == calendar.calendarIdentifier }?.tag,
                            setTag: { setCalendarRule(calendar, $0) }
                        )
                    }
                } header: {
                    Text("Calendar defaults")
                } footer: {
                    Text("Events inherit their calendar's default unless tagged individually.")
                }
            }
            .navigationTitle("Review Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func setTitleRule(_ group: EventGroup, _ tag: ClassificationTag) {
        if let existing = titleRules.first(where: {
            $0.calendarID == group.calendarID && $0.normalizedTitle == group.normalizedTitle
        }) {
            existing.tag = tag
        } else {
            modelContext.insert(TitleRule(
                calendarID: group.calendarID,
                normalizedTitle: group.normalizedTitle,
                tag: tag
            ))
        }
    }

    private func setCalendarRule(_ calendar: EKCalendar, _ tag: ClassificationTag) {
        if let existing = calendarRules.first(where: { $0.calendarID == calendar.calendarIdentifier }) {
            existing.tag = tag
        } else {
            modelContext.insert(CalendarRule(calendarID: calendar.calendarIdentifier, tag: tag))
        }
    }
}

private struct GroupTagRow: View {
    let group: EventGroup
    let setTag: (ClassificationTag) -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: group.calendarColor))
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayTitle)
                Text("\(group.eventCount) upcoming · \(group.calendarTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TagMenu(current: group.tag, inherited: group.source == .calendarRule, setTag: setTag)
        }
    }
}

private struct CalendarDefaultRow: View {
    let calendar: EKCalendar
    let currentTag: ClassificationTag?
    let setTag: (ClassificationTag) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 12, height: 12)
            Text(calendar.title)
            Spacer()
            TagMenu(current: currentTag, inherited: false, setTag: setTag)
        }
    }
}

private struct TagMenu: View {
    let current: ClassificationTag?
    let inherited: Bool
    let setTag: (ClassificationTag) -> Void

    var body: some View {
        Menu {
            ForEach(ClassificationTag.allCases) { tag in
                Button {
                    setTag(tag)
                } label: {
                    Label(tag.label, systemImage: tag.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let current {
                    Image(systemName: current.icon)
                    Text(current.label)
                    if inherited {
                        Text("(default)")
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Tag…")
                        .fontWeight(.medium)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline)
            .foregroundStyle(current == nil ? Color.accentColor : Color.secondary)
        }
    }
}
