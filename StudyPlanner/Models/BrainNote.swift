import Foundation
import SwiftData

/// One morning sticky. `day` is the start of the calendar day it belongs to.
/// `organizedAt` marks notes already turned into a confirmed plan, so a second
/// pass does not add the same tasks unless the student asks to read them again.
@Model
final class BrainNote {
    var text: String = ""
    var day: Date = Date.now
    var createdAt: Date = Date.now
    var colorIndex: Int = 0
    var organizedAt: Date?

    init(text: String, day: Date, colorIndex: Int = 0) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.day = Calendar.current.startOfDay(for: day)
        self.createdAt = .now
        self.colorIndex = colorIndex
    }
}
