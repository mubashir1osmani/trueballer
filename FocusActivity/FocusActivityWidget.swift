import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FocusActivityBundle: WidgetBundle {
    var body: some Widget { FocusActivityWidget() }
}

struct FocusActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: context.state.phase == .paused ? "pause.circle.fill" : "timer")
                    .font(.title).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.phase == .paused ? "Focus paused" : "StudyPlanner · Focus")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(context.attributes.taskTitle).font(.headline).lineLimit(2)
                    if let course = context.attributes.courseName {
                        Text(course).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text("\(context.attributes.estimatedMinutes) min estimated total")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ActivityClock(state: context.state)
                    .font(.title2.weight(.medium)).frame(maxWidth: 110)
            }
            .padding()
            .activityBackgroundTint(Color(.secondarySystemBackground))
            .activitySystemActionForegroundColor(.teal)
            .widgetURL(URL(string: "studyplanner://focus"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.phase == .paused ? "Paused" : "Focus", systemImage: "timer")
                        .foregroundStyle(.teal)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityClock(state: context.state)
                        .font(.title2).frame(maxWidth: 130)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.taskTitle).font(.headline).lineLimit(2)
                        Text("Tap to return to your session")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .paused ? "pause.fill" : "timer")
                    .foregroundStyle(.teal)
            } compactTrailing: {
                ActivityClock(state: context.state).frame(width: 62)
            } minimal: {
                Image(systemName: context.state.phase == .paused ? "pause.fill" : "timer")
                    .foregroundStyle(.teal)
            }
            .widgetURL(URL(string: "studyplanner://focus"))
            .keylineTint(.teal)
        }
    }
}

private struct ActivityClock: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.phase == .running, let start = state.timerStart {
                Text(start, style: .timer)
            } else {
                Text(FocusTimeFormat.clock(state.elapsedSeconds))
            }
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
    }
}
