import SwiftUI

enum AppTheme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.86, blue: 0.76, alpha: 1)
            : UIColor(red: 0.02, green: 0.40, blue: 0.36, alpha: 1)
    })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct TodayOverview: View {
    var taskCount: Int
    var freeMinutes: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.caption.weight(.semibold)).textCase(.uppercase).tracking(1)
                Spacer()
                Image(systemName: "sun.max.fill")
            }
            .foregroundStyle(.white.opacity(0.8))
            Text(taskCount == 0 ? "Room for a fresh start." : "A little focus goes a long way.")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 24) {
                metric("\(taskCount)", label: taskCount == 1 ? "task ready" : "tasks ready")
                if let freeMinutes {
                    Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 35)
                    metric(FocusTimeFormat.duration(Double(freeMinutes * 60)), label: "free today")
                }
            }
        }
        .padding(22)
        .background(LinearGradient(colors: [Color(red: 0.02, green: 0.36, blue: 0.33), Color(red: 0.07, green: 0.48, blue: 0.44)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
    }
}
