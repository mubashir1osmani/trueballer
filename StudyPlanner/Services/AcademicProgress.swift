import Foundation

enum AcademicProgress {
    struct TrendPoint: Identifiable {
        var id: UUID
        var date: Date
        var average: Double
    }

    struct Summary {
        var average: Double?
        var gradedWeight: Double
        var target: Double
        var trend: [TrendPoint]

        var belowTarget: Bool { average.map { $0 + 0.000_001 < target } ?? false }
        var gap: Double { average.map { max(0, target - $0) } ?? 0 }
        var trendChange: Double? {
            guard trend.count >= 2 else { return nil }
            return trend[trend.count - 1].average - trend[trend.count - 2].average
        }
        var requiredOnRemaining: Double? {
            guard let average, gradedWeight > 0, gradedWeight < 100 - 0.000_001 else { return nil }
            return max(0, (target * 100 - average * gradedWeight) / (100 - gradedWeight))
        }
    }

    static func summary(course: StudyCourse, grades: [GradeEntry]) -> Summary {
        let entries = grades.filter {
            $0.courseID == course.id && $0.percentage.isFinite && (0...100).contains($0.percentage)
                && $0.weight.isFinite && $0.weight > 0 && $0.weight <= 100
        }.sorted {
            if $0.receivedAt != $1.receivedAt { return $0.receivedAt < $1.receivedAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        var weight = 0.0
        var weighted = 0.0
        var trend: [TrendPoint] = []
        for entry in entries {
            weight += entry.weight
            weighted += entry.percentage * entry.weight
            trend.append(TrendPoint(id: entry.id, date: entry.receivedAt, average: weighted / weight))
        }
        return Summary(average: weight > 0 ? weighted / weight : nil, gradedWeight: weight,
                       target: course.targetPercentage, trend: trend)
    }

    static func gradeError(title: String, percentage: Double?, weight: Double?, otherWeight: Double) -> String? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Add an assessment name." }
        guard let percentage, percentage.isFinite, (0...100).contains(percentage) else { return "Enter a grade from 0 to 100%." }
        guard let weight, weight.isFinite, weight > 0, weight <= 100 else { return "Enter a weight greater than 0 and up to 100%." }
        guard otherWeight + weight <= 100.000_001 else { return "Assessment weights cannot add up to more than 100%." }
        return nil
    }

    static func priorityBoost(course: StudyCourse, grades: [GradeEntry]) -> Double {
        guard !course.isArchived else { return 1 }
        let gap = summary(course: course, grades: grades).gap
        let creditFactor = min(2, max(0.5, course.credits / 3))
        return min(2, 1 + gap / 50 * creditFactor)
    }

    struct GPA: Identifiable {
        var scale: Double
        var value: Double
        var courseCount: Int
        var credits: Double
        var id: Double { scale }
    }

    static func gpa(courses: [StudyCourse]) -> [GPA] {
        let entered = courses.filter {
            !$0.isArchived && $0.credits.isFinite && $0.credits > 0 && $0.gpaScale > 0 &&
                $0.gpaPoints.map { $0.isFinite && $0 >= 0 } == true
        }.filter { ($0.gpaPoints ?? 0) <= $0.gpaScale }
        return Dictionary(grouping: entered, by: \.gpaScale).map { scale, courses in
            let credits = courses.reduce(0) { $0 + $1.credits }
            let points = courses.reduce(0) { $0 + ($1.gpaPoints ?? 0) * $1.credits }
            return GPA(scale: scale, value: points / credits, courseCount: courses.count, credits: credits)
        }.sorted { $0.scale < $1.scale }
    }

    /// Only finished sessions are counted, by completion date. No extrapolation
    /// for unlogged study time or unfinished sessions.
    static func focusSeconds(course: StudyCourse, courses: [StudyCourse], sessions: [FocusSession], since: Date? = nil, through: Date = .now) -> Double {
        sessions.filter { session in
            guard let ended = session.endedAt, ended <= through,
                  since.map({ ended >= $0 }) ?? true else { return false }
            return CourseCatalog.course(for: session, in: courses)?.id == course.id
        }.reduce(0) { $0 + max(0, $1.accumulatedSeconds) }
    }

    struct EffortWeek: Identifiable {
        var start: Date
        var seconds: Double
        var id: Date { start }
    }

    static func effortWeeks(course: StudyCourse, courses: [StudyCourse], sessions: [FocusSession], now: Date = .now, calendar: Calendar = .current) -> [EffortWeek] {
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        return (-3...0).map { offset in
            let start = calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeek)!
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            let seconds = focusSeconds(course: course, courses: courses, sessions: sessions,
                                       since: start, through: min(now, end.addingTimeInterval(-0.001)))
            return EffortWeek(start: start, seconds: seconds)
        }
    }
}

enum GradeNumber {
    static func parse(_ text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strict parsing prevents accepting an accidental trailing character.
        let separator = formatter.decimalSeparator ?? "."
        let normalized = trimmed.replacingOccurrences(of: separator, with: ".")
        guard normalized.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        return Double(normalized)
    }

    static func text(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}
