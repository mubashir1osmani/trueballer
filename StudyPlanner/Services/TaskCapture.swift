import Foundation

/// A school task the student has not confirmed yet. Nothing is saved until
/// they accept the preview.
struct TaskDraft: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var courseID: UUID?
    var dueDate: Date?
    var estimatedMinutes: Int?
    var usedAI = false
}

/// Fallback for iPhones without Apple Intelligence. One task per line.
/// Understands today, tomorrow, tonight, and weekday names, plus a clock time.
/// The preview is where the student fixes anything this misses.
enum BasicTaskParser {
    static func parse(_ prompt: String, courses: [StudyCourse] = [], now: Date = .now, calendar: Calendar = .current) throws -> [TaskDraft] {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DraftError.message("Describe an assignment first.") }
        guard trimmed.count <= 2_000 else { throw DraftError.message("Keep your note under 2,000 characters.") }
        let lines = trimmed.split(whereSeparator: { $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw DraftError.message("Describe an assignment first.") }
        guard lines.count <= 5 else { throw DraftError.message("Add up to 5 tasks at a time. Put one assignment on each line.") }
        return try lines.map { try parseLine(String($0), courses: courses, now: now, calendar: calendar) }
    }

    private static func parseLine(_ rawLine: String, courses: [StudyCourse], now: Date, calendar: Calendar) throws -> TaskDraft {
        var working = rawLine.replacingOccurrences(of: #"^([-*•]\s+)+"#, with: "", options: .regularExpression)
        var minutes: Int?
        if let duration = matchDuration(in: working) {
            minutes = duration.minutes
            working.removeSubrange(duration.range)
        }

        let clock = try matchClock(in: working)
        var due: Date?
        var removals: [Range<String.Index>] = []
        if let day = matchRelativeDay(in: working, now: now, calendar: calendar) {
            due = apply(clock: clock, to: day.date, calendar: calendar)
            removals.append(day.range)
            if let clock { removals.append(clock.range) }
            if clock == nil {
                working = removing(ranges: removals, from: working)
                working = working.replacingOccurrences(of: #"\s+night\b"#, with: "", options: [.regularExpression, .caseInsensitive])
                removals = []
            }
        } else if let day = matchWeekday(in: working, now: now, calendar: calendar) {
            due = apply(clock: clock, to: day.date, calendar: calendar)
            removals.append(day.range)
            if let clock { removals.append(clock.range) }
        } else if clock == nil {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
            if let found = detector.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)),
               let date = found.date, let range = Range(found.range, in: working) {
                due = date
                removals.append(range)
            }
        }

        working = removing(ranges: removals, from: working)
        if let course = bestCourse(in: rawLine, courses: courses) {
            let pattern = "\\bfor\\s+\(NSRegularExpression.escapedPattern(for: course.name))\\b"
            working = working.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            working = cleanup(working, dateWasFound: due != nil)
            let title = working.isEmpty ? rawLine.trimmingCharacters(in: .whitespacesAndNewlines) : working
            return TaskDraft(title: title, courseID: course.id, dueDate: due, estimatedMinutes: minutes)
        }
        working = cleanup(working, dateWasFound: due != nil)
        let title = working.isEmpty ? rawLine.trimmingCharacters(in: .whitespacesAndNewlines) : working
        return TaskDraft(title: title, dueDate: due, estimatedMinutes: minutes)
    }

    private static func apply(clock: ClockMatch?, to day: Date, calendar: Calendar) -> Date? {
        if let clock {
            return calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day)
        }
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day)
    }

    private static func cleanup(_ text: String, dateWasFound: Bool) -> String {
        var title = text
        if dateWasFound {
            title = title.replacingOccurrences(of: #"\b(due|by)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        }
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(
            of: #"^(please\s+)?(remind me to|add(?: a)? task(?: to)?|i (?:have|need)(?: to)?)\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        title = title.replacingOccurrences(of: #"\s+\b(at|on)\b\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: ".,-–—:;"))
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removing(ranges: [Range<String.Index>], from text: String) -> String {
        var copy = text
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            guard range.lowerBound >= copy.startIndex, range.upperBound <= copy.endIndex else { continue }
            copy.removeSubrange(range)
        }
        return copy
    }

    private static func bestCourse(in text: String, courses: [StudyCourse]) -> StudyCourse? {
        let haystack = text.lowercased()
        let matches = courses.filter { course in
            let name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !course.isArchived && name.count >= 2 && haystack.contains(name.lowercased())
        }
        guard let longest = matches.map(\.name.count).max() else { return nil }
        let top = matches.filter { $0.name.count == longest }
        return top.count == 1 ? top[0] : nil
    }

    private struct DurationMatch {
        var minutes: Int
        var range: Range<String.Index>
    }

    private static func matchDuration(in text: String) -> DurationMatch? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:for|about)\s+(\d+)\s*(minutes?|mins?|hours?|hrs?)\b"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let full = Range(match.range, in: text),
              let number = Int(text[numberRange]), number > 0
        else { return nil }
        let minutes = number * (text[unitRange].lowercased().hasPrefix("h") ? 60 : 1)
        guard (1...1_440).contains(minutes) else { return nil }
        return DurationMatch(minutes: minutes, range: full)
    }

    private struct ClockMatch {
        var hour: Int
        var minute: Int
        var range: Range<String.Index>
    }

    private static func matchClock(in text: String) throws -> ClockMatch? {
        let regex = try NSRegularExpression(pattern: #"(?:\bat\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#, options: .caseInsensitive)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              let suffixRange = Range(match.range(at: 3), in: text),
              let full = Range(match.range, in: text),
              let hour = Int(text[hourRange])
        else { return nil }
        let minute = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
        guard (1...12).contains(hour), (0..<60).contains(minute) else {
            throw DraftError.message("That time doesn't look valid. Try a time such as 3:30 pm.")
        }
        let normalized = hour % 12 + (text[suffixRange].lowercased() == "pm" ? 12 : 0)
        return ClockMatch(hour: normalized, minute: minute, range: full)
    }

    private struct DayMatch {
        var date: Date
        var range: Range<String.Index>
    }

    private static func matchRelativeDay(in text: String, now: Date, calendar: Calendar) -> DayMatch? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:(?:due|by|on)\s+)?(today|tomorrow|tonight)\b"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let wordRange = Range(match.range(at: 1), in: text),
              let full = Range(match.range, in: text)
        else { return nil }
        let word = text[wordRange].lowercased()
        let offset = word == "tomorrow" ? 1 : 0
        let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: now) ?? now)
        return DayMatch(date: day, range: full)
    }

    private static func matchWeekday(in text: String, now: Date, calendar: Calendar) -> DayMatch? {
        var aliases: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7),
            ("tues", 3), ("thur", 5), ("thurs", 5)
        ]
        for (index, symbol) in calendar.weekdaySymbols.enumerated() {
            aliases.append((symbol.lowercased(), index + 1))
        }
        for (index, symbol) in calendar.shortWeekdaySymbols.enumerated() {
            let name = symbol.lowercased().replacingOccurrences(of: ".", with: "")
            if name.count >= 3 { aliases.append((name, index + 1)) }
        }
        var lookup: [String: Int] = [:]
        var banned = Set<String>()
        for (name, weekday) in aliases where name.count >= 3 && !banned.contains(name) {
            if let existing = lookup[name], existing != weekday {
                lookup.removeValue(forKey: name)
                banned.insert(name)
            } else if lookup[name] == nil {
                lookup[name] = weekday
            }
        }
        let names = lookup.sorted { $0.key.count > $1.key.count }
        guard !names.isEmpty else { return nil }
        let pattern = "(?:(?:due|by|on)\\s+)?(next\\s+)?(" + names.map { NSRegularExpression.escapedPattern(for: $0.key) }.joined(separator: "|") + ")\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(match.range(at: 2), in: text),
              let full = Range(match.range, in: text),
              let weekday = lookup[text[nameRange].lowercased()]
        else { return nil }
        let today = calendar.component(.weekday, from: now)
        var delta = weekday - today
        if delta < 0 { delta += 7 }
        let saidNext = Range(match.range(at: 1), in: text).map { !text[$0].isEmpty } ?? false
        if delta == 0 && saidNext { delta = 7 }
        let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: delta, to: now) ?? now)
        return DayMatch(date: day, range: full)
    }
}
