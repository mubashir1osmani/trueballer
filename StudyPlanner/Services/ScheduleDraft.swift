import Foundation

enum ScheduleKind: String, CaseIterable, Identifiable {
    case reminder, event
    var id: String { rawValue }
    var label: String { self == .reminder ? "Apple Reminder" : "Calendar Event" }
    var destinationLabel: String { self == .reminder ? "List" : "Calendar" }
}

struct ScheduleDraft: Identifiable {
    var id = UUID()
    var kind: ScheduleKind
    var title: String
    var date: Date?
    var durationMinutes: Int = 60
    var isAllDay = false
    var notes = ""
    var usedAI = false

    var validationError: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a title." }
        if kind == .event && date == nil { return "Choose a date and time for the event." }
        if !(1...1440).contains(durationMinutes) { return "Choose a duration from 1 to 1,440 minutes." }
        return nil
    }
}

enum DraftError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

/// Explicit fallback for devices without Apple Intelligence. It only extracts
/// simple titles/dates; the UI labels this as date matching, never AI output.
enum BasicScheduleParser {
    static func parse(_ prompt: String, now: Date = .now, calendar: Calendar = .current) throws -> ScheduleDraft {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DraftError.message("Describe a reminder or event first.") }
        guard trimmed.count <= 2000 else { throw DraftError.message("Keep your request under 2,000 characters.") }
        guard trimmed.range(of: "\\b(every|daily|weekly|monthly|repeat|recurring)\\b|and (remind|schedule|create)|\\balso\\b", options: [.regularExpression, .caseInsensitive]) == nil else {
            throw DraftError.message("Create one non-repeating reminder or event at a time. You can add repetition in Apple Reminders or Calendar afterward.")
        }
        let explicitlyReminder = trimmed.range(of: "\\b(remind|reminder)\\b", options: [.regularExpression, .caseInsensitive]) != nil
        let kind: ScheduleKind = explicitlyReminder || trimmed.range(of: "\\b(schedule|calendar|event|meeting)\\b", options: [.regularExpression, .caseInsensitive]) == nil ? .reminder : .event
        var title = trimmed
        var date: Date?
        // Relative day + explicit clock is deterministic across locales and DST.
        let lower = trimmed.lowercased()
        let dayOffset = lower.contains("tomorrow") ? 1 : lower.contains("today") ? 0 : nil
        if let dayOffset {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: now)!
            let regex = try NSRegularExpression(pattern: "\\b(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)\\b", options: .caseInsensitive)
            if let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let hourRange = Range(match.range(at: 1), in: trimmed),
               let suffixRange = Range(match.range(at: 3), in: trimmed),
               let hour = Int(trimmed[hourRange]), (1...12).contains(hour) {
                let minute = Range(match.range(at: 2), in: trimmed).flatMap { Int(trimmed[$0]) } ?? 0
                guard minute < 60 else { throw DraftError.message("That time doesn't look valid. Try a time such as 3:30 pm.") }
                let h = hour % 12 + (trimmed[suffixRange].lowercased() == "pm" ? 12 : 0)
                date = calendar.date(bySettingHour: h, minute: minute, second: 0, of: day)
                title = (title as NSString).replacingCharacters(in: match.range, with: "")
            } else {
                date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
            }
            title = title.replacingOccurrences(of: "\\b(today|tomorrow)\\b", with: "", options: [.regularExpression, .caseInsensitive])
        } else {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
            if let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)), let detected = match.date {
                date = detected
                title = (title as NSString).replacingCharacters(in: match.range, with: "")
            }
        }
        var duration = 60
        let durationRegex = try NSRegularExpression(pattern: "\\bfor (\\d+)\\s*(minutes?|mins?|hours?|hrs?)\\b", options: .caseInsensitive)
        if let match = durationRegex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
           let numberRange = Range(match.range(at: 1), in: title), let unitRange = Range(match.range(at: 2), in: title),
           let number = Int(title[numberRange]), number <= 1440 {
            duration = number * (title[unitRange].lowercased().hasPrefix("h") ? 60 : 1)
            title = (title as NSString).replacingCharacters(in: match.range, with: "")
        }
        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: "^(please\\s+)?(remind me( to)?|(?:create|add)(?: a| an)?(?: calendar)? (?:reminder|event)(?: to)?|schedule(?: a| an)?(?: event)?)\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.replacingOccurrences(of: "\\s+(at|on|for)$", with: "", options: [.regularExpression, .caseInsensitive])
        if title.isEmpty { title = trimmed }
        return ScheduleDraft(kind: kind, title: title, date: date, durationMinutes: duration)
    }
}
