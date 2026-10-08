import Foundation
import SwiftData

@Model
final class GradeEntry {
    var id: UUID = UUID()
    var courseID: UUID
    var title: String
    var percentage: Double
    /// Percentage of the entire course grade, not of work entered so far.
    var weight: Double
    var receivedAt: Date
    var createdAt: Date = Date.now

    init(courseID: UUID, title: String, percentage: Double, weight: Double, receivedAt: Date = .now) {
        self.courseID = courseID
        self.title = title
        self.percentage = percentage
        self.weight = weight
        self.receivedAt = receivedAt
    }
}
