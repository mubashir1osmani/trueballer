import ActivityKit
import Foundation

struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case running, paused, finished }
        var phase: Phase
        /// Effective start includes previously accumulated time. The system
        /// renders the clock without a background process or per-second updates.
        var timerStart: Date?
        var elapsedSeconds: Double
    }

    var sessionID: UUID
    var taskTitle: String
    var courseName: String?
    var estimatedMinutes: Int
}

enum FocusTimeFormat {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m" }
        return "\(total / 3600)h \(total / 60 % 60)m"
    }
}
