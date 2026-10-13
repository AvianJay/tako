import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TakoRemoteActivity: Widget {
  private let openURL = URL(string: "tako://remote")!
  private let stopURL = URL(string: "tako://remote/stop")!
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RemoteActivityAttributes.self) { context in
      HStack(spacing: 14) {
        Image(systemName: "hand.tap.fill").font(.title2).foregroundStyle(.green)
        VStack(alignment: .leading, spacing: 4) {
          Text("Tako").font(.headline)
          Text(context.state.message).font(.subheadline)
          Text("\(context.state.actions) actions").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if context.state.running {
          Link(destination: stopURL) { Label("Stop", systemImage: "stop.circle.fill") }
        }
      }
      .padding()
      .activityBackgroundTint(Color(.systemBackground))
      .widgetURL(openURL)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label("Tako", systemImage: "hand.tap.fill").foregroundStyle(.green)
        }
        DynamicIslandExpandedRegion(.trailing) {
          if context.state.running { Link("Stop", destination: stopURL) }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 4) {
            Text(context.state.message).font(.subheadline)
            HStack {
              Text("\(context.state.actions) actions").font(.caption)
              Spacer()
              Text(context.attributes.startedAt, style: .timer).font(.caption.monospacedDigit())
            }
          }
        }
      } compactLeading: {
        Image(systemName: context.state.running ? "hand.tap.fill" : "pause.fill").foregroundStyle(.green)
      } compactTrailing: {
        Text("\(context.state.actions)").font(.caption.monospacedDigit())
      } minimal: {
        Image(systemName: "hand.tap.fill").foregroundStyle(.green)
      }
      .widgetURL(openURL)
      .keylineTint(.green)
    }
  }
}
