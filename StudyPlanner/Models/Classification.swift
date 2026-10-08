import Foundation
import SwiftData

enum ClassificationTag: String, Codable, CaseIterable, Identifiable {
    case course, work, internship, project, personal, ignore

    var id: String { rawValue }

    var label: String {
        switch self {
        case .course: "Course"
        case .work: "Work"
        case .internship: "Internship"
        case .project: "Project"
        case .personal: "Personal"
        case .ignore: "Ignore"
        }
    }

    var icon: String {
        switch self {
        case .course: "graduationcap"
        case .work: "briefcase"
        case .internship: "building.2"
        case .project: "hammer"
        case .personal: "person"
        case .ignore: "eye.slash"
        }
    }
}

/// Default tag for everything on one calendar ("this whole calendar is school").
@Model
final class CalendarRule {
    @Attribute(.unique) var calendarID: String
    var tagRaw: String

    init(calendarID: String, tag: ClassificationTag) {
        self.calendarID = calendarID
        self.tagRaw = tag.rawValue
    }

    var tag: ClassificationTag {
        get { ClassificationTag(rawValue: tagRaw) ?? .personal }
        set { tagRaw = newValue.rawValue }
    }
}

/// Override for one recurring title within a calendar ("'Gym' on the school
/// calendar is Personal"). Wins over the calendar default.
@Model
final class TitleRule {
    var calendarID: String
    var normalizedTitle: String
    var tagRaw: String

    init(calendarID: String, normalizedTitle: String, tag: ClassificationTag) {
        self.calendarID = calendarID
        self.normalizedTitle = normalizedTitle
        self.tagRaw = tag.rawValue
    }

    var tag: ClassificationTag {
        get { ClassificationTag(rawValue: tagRaw) ?? .personal }
        set { tagRaw = newValue.rawValue }
    }
}

/// Shared normalization so "CS 301  Lecture" and "cs 301 lecture" key the same.
func normalizeEventTitle(_ title: String) -> String {
    title.lowercased()
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}
