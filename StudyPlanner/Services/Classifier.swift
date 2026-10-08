import EventKit
import Foundation

/// Where a group's tag came from — drives the "needs review" state.
enum TagSource {
    case titleRule      // user confirmed this exact title
    case calendarRule   // inherited from the calendar's default
    case none           // untagged; needs review
}

/// A cluster of events sharing (calendar, normalized title) — one recurring
/// class, shift, etc. This is the unit users tag in the review UI.
struct EventGroup: Identifiable {
    let calendarID: String
    let calendarTitle: String
    let calendarColor: CGColor
    let normalizedTitle: String
    let displayTitle: String
    let eventCount: Int
    let nextStart: Date
    var tag: ClassificationTag?
    var source: TagSource

    var id: String { "\(calendarID)|\(normalizedTitle)" }
}

enum Classifier {
    /// Groups events by (calendar, normalized title) and resolves each group's
    /// tag: title rule > calendar rule > untagged.
    static func groups(events: [EKEvent],
                       calendarRules: [CalendarRule],
                       titleRules: [TitleRule]) -> [EventGroup] {
        let calendarDefaults = Dictionary(uniqueKeysWithValues: calendarRules.map { ($0.calendarID, $0.tag) })
        var titleOverrides: [String: ClassificationTag] = [:]
        for rule in titleRules {
            titleOverrides["\(rule.calendarID)|\(rule.normalizedTitle)"] = rule.tag
        }

        let grouped = Dictionary(grouping: events.filter { $0.title != nil }) { event in
            "\(event.calendar.calendarIdentifier)|\(normalizeEventTitle(event.title))"
        }

        return grouped.values.compactMap { events -> EventGroup? in
            guard let first = events.min(by: { $0.startDate < $1.startDate }) else { return nil }
            let calendarID = first.calendar.calendarIdentifier
            let key = "\(calendarID)|\(normalizeEventTitle(first.title))"

            let tag: ClassificationTag?
            let source: TagSource
            if let override = titleOverrides[key] {
                (tag, source) = (override, .titleRule)
            } else if let fallback = calendarDefaults[calendarID] {
                (tag, source) = (fallback, .calendarRule)
            } else {
                (tag, source) = (nil, .none)
            }

            return EventGroup(
                calendarID: calendarID,
                calendarTitle: first.calendar.title,
                calendarColor: first.calendar.cgColor,
                normalizedTitle: normalizeEventTitle(first.title),
                displayTitle: first.title,
                eventCount: events.count,
                nextStart: first.startDate,
                tag: tag,
                source: source
            )
        }
        .sorted { $0.nextStart < $1.nextStart }
    }
}
