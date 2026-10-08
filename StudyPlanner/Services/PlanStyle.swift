import Foundation

enum StudyTime: String, CaseIterable, Identifiable {
    case any, morning, afternoon, evening
    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: "Whenever there's open time"
        case .morning: "Mornings"
        case .afternoon: "Afternoons"
        case .evening: "Evenings"
        }
    }
}

/// What a planning note changed. Nil fields were not mentioned and stay as they are.
struct PlanReading: Equatable {
    var studyTime: StudyTime?
    var blockMinutes: Int?
    var dailyCapMinutes: Int?
    var remindersEnabled: Bool?
    var reminderLeadMinutes: Int?
    var dayStartMinutes: Int?
    var dayEndMinutes: Int?
    var sleepHours: Double?

    var recognized: Bool {
        studyTime != nil || blockMinutes != nil || dailyCapMinutes != nil || remindersEnabled != nil
            || reminderLeadMinutes != nil || dayStartMinutes != nil || dayEndMinutes != nil || sleepHours != nil
    }

    mutating func fillGaps(from other: PlanReading) {
        if studyTime == nil { studyTime = other.studyTime }
        if blockMinutes == nil { blockMinutes = other.blockMinutes }
        if dailyCapMinutes == nil { dailyCapMinutes = other.dailyCapMinutes }
        if remindersEnabled == nil { remindersEnabled = other.remindersEnabled }
        if reminderLeadMinutes == nil { reminderLeadMinutes = other.reminderLeadMinutes }
        if dayStartMinutes == nil { dayStartMinutes = other.dayStartMinutes }
        if dayEndMinutes == nil { dayEndMinutes = other.dayEndMinutes }
        if sleepHours == nil { sleepHours = other.sleepHours }
    }
}

/// Turns the student's own planning note into concrete rules.
/// Explicit phrases win. Anything unrecognized is left alone so a vague sentence
/// cannot quietly rewrite the day.
enum PlanStyle {
    static func parse(_ note: String) -> PlanReading {
        var reading = PlanReading()
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return reading }

        if text.range(of: #"(?:don'?t|do not|no)\s+(?:send\s+|notify|remind)|(?:don'?t|do not)\s+notify|\bno\s+(?:notifications?|reminders?|nudges?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            reading.remindersEnabled = false
        } else if text.range(of: #"\b(?:remind|notif)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            reading.remindersEnabled = true
            if text.range(of: #"\b(?:night|day)\s+before\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                reading.reminderLeadMinutes = 24 * 60
            } else if text.range(of: #"\b(?:an|one|1)\s+hours?\s+before\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                reading.reminderLeadMinutes = 60
            } else if text.range(of: #"\b(?:two|2)\s+hours?\s+before\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                reading.reminderLeadMinutes = 120
            } else if text.range(of: #"\b(?:30\s+minutes?|half an hour)\s+before\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                reading.reminderLeadMinutes = 30
            }
        }

        if let cap = firstNumber(in: text, pattern: #"(?:no more than|at most|up to|only)\s+(\d+)\s*(hours?|hrs?|minutes?|mins?)\b(?!\s+before)"#)
            ?? firstNumber(in: text, pattern: #"(\d+)\s*(hours?|hrs?|minutes?|mins?)\s+a\s+day\b"#) {
            reading.dailyCapMinutes = cap
        } else if text.range(of: #"\b(?:don'?t fill|do not fill|light day|leave room)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            reading.dailyCapMinutes = 90
        }

        let eveningsFree = text.range(of: #"\bevenings?\s+free\b|\bleave\s+(?:my\s+)?evenings?\s+free\b|\bkeep\s+evenings?\s+free\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let morningsFree = text.range(of: #"\bmornings?\s+free\b|\bleave\s+(?:my\s+)?mornings?\s+free\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        if eveningsFree {
            reading.dayEndMinutes = 17 * 60
        } else if let minutes = clock(in: text, pattern: #"(?:done by|free after|never after|not after|stop at|finished by)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#, endOfDay: true) {
            reading.dayEndMinutes = minutes
        }
        if morningsFree {
            reading.dayStartMinutes = 12 * 60
        } else if let minutes = clock(in: text, pattern: #"(?:start at|starts at|not before|day starts at)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#, endOfDay: false) {
            reading.dayStartMinutes = minutes
        }

        if let length = blockLength(in: text) {
            reading.blockMinutes = min(90, max(25, length))
        }
        if let sleep = sleepHours(in: text) {
            reading.sleepHours = min(12, max(5, sleep))
        }

        let withoutReminders = text.replacingOccurrences(of: #"remind me[^.!\n]*"#, with: "", options: [.regularExpression, .caseInsensitive])
        if !eveningsFree, withoutReminders.range(of: #"\b(?:evenings?|after dinner)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            reading.studyTime = .evening
        } else if !morningsFree, withoutReminders.range(of: #"\b(?:mornings?|before lunch|before noon)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            reading.studyTime = .morning
        } else if withoutReminders.range(of: #"\bafternoons?\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            reading.studyTime = .afternoon
        }
        return reading
    }

    static func summary(of settings: UserSettings) -> String {
        var parts: [String] = []
        if let time = StudyTime(rawValue: settings.studyTime), time != .any {
            parts.append(time.label)
        }
        if settings.usesCustomBlockLength {
            parts.append("\(settings.blockMinutes)-minute blocks")
        }
        if settings.dailyCapMinutes > 0 {
            parts.append("up to \(span(settings.dailyCapMinutes)) a day")
        }
        parts.append(reminderPhrase(enabled: settings.remindersEnabled, lead: settings.reminderLeadMinutes))
        let start = clockLabel(settings.workdayStartMinutes)
        let end = clockLabel(settings.workdayEndMinutes)
        parts.append("\(start)–\(end)")
        return parts.joined(separator: " · ")
    }

    static func reminderPhrase(enabled: Bool, lead: Int) -> String {
        guard enabled else { return "No reminders" }
        switch lead {
        case 30: return "A reminder 30 minutes before"
        case 60: return "A reminder an hour before"
        case 120: return "A reminder 2 hours before"
        case 24 * 60: return "A reminder the night before"
        default: return "A reminder \(lead) minutes before"
        }
    }

    static func span(_ minutes: Int) -> String {
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        if minutes > 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    static func clockLabel(_ minutes: Int) -> String {
        let hour24 = min(23, max(0, minutes / 60))
        let minute = min(59, max(0, minutes % 60))
        let suffix = hour24 >= 12 ? "pm" : "am"
        let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
        if minute == 0 { return "\(hour) \(suffix)" }
        return String(format: "%d:%02d %@", hour, minute, suffix)
    }

    private static func blockLength(in text: String) -> Int? {
        if text.range(of: #"\bpomodoro"#, options: [.regularExpression, .caseInsensitive]) != nil { return 25 }
        let patterns = [
            #"(\d+)\s*-?\s*(?:minute|min)s?\s+(?:blocks?|sessions?|chunks?)"#,
            #"(?:blocks?|sessions?)\s+of\s+(\d+)\s*(hours?|hrs?|minutes?|mins?)"#,
            #"(\d+)\s*-?\s*(?:minute|min)s?\b(?!\s+before)"#
        ]
        for pattern in patterns {
            if let value = firstNumber(in: text, pattern: pattern) { return value }
        }
        return nil
    }

    private static func sleepHours(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s+hours?\s+of\s+sleep"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]) else { return nil }
        return value
    }

    /// Returns minutes. Hour-unit matches are converted. A trailing "before" is rejected by the pattern.
    private static func firstNumber(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let number = Int(text[numberRange]), number > 0 else { return nil }
        let unit: String
        if match.numberOfRanges > 2, let unitRange = Range(match.range(at: 2), in: text) {
            unit = text[unitRange].lowercased()
        } else {
            unit = "minute"
        }
        let minutes = unit.hasPrefix("h") ? number * 60 : number
        guard (1...12 * 60).contains(minutes) else { return nil }
        return minutes
    }

    private static func clock(in text: String, pattern: String, endOfDay: Bool) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              let hour = Int(text[hourRange]) else { return nil }
        let minute = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
        guard (0..<60).contains(minute) else { return nil }
        if (13...23).contains(hour) { return hour * 60 + minute }
        guard (1...12).contains(hour) else { return nil }
        let suffix = Range(match.range(at: 3), in: text).map { text[$0].lowercased() }
        let isPM: Bool
        if suffix == "pm" { isPM = true }
        else if suffix == "am" { isPM = false }
        else if endOfDay { isPM = hour != 12 }
        else { isPM = (1...4).contains(hour) }
        let normalized = hour % 12 + (isPM ? 12 : 0)
        return normalized * 60 + minute
    }
}
