import Foundation
import SwiftData

@Model
final class StudyCourse {
    var id: UUID = UUID()
    var name: String
    /// Calendar + normalized title, retained even when events leave the window.
    var sourceGroupID: String?
    var calendarName: String?
    var credits: Double = 3
    var targetPercentage: Double = 70
    var isArchived: Bool = false
    /// Explicitly supplied using the school's conversion; never inferred from %.
    var gpaPoints: Double?
    var gpaScale: Double = 4

    init(name: String, sourceGroupID: String? = nil, calendarName: String? = nil) {
        self.name = name
        self.sourceGroupID = sourceGroupID
        self.calendarName = calendarName
    }

    var pickerLabel: String {
        calendarName.map { "\(name) · \($0)" } ?? name
    }
}
