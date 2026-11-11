import ActivityKit
import WidgetKit
import SwiftUI

struct BakeActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var action: String
    var dueAt: Date
    var generatedAt: Date
    var revision: Int
  }
  let bakeId: String
  let title: String
}

@main struct CrispyWidgetBundle: WidgetBundle {
  var body: some Widget { BakeActivityWidget() }
}
struct BakeActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BakeActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 6) {
        Text(context.attributes.title).font(.headline)
        Text(context.state.action)
        Text(context.state.dueAt, style: .timer).monospacedDigit()
        Text("Check the dough. Timing is a guide.").font(.caption)
      }.padding().widgetURL(URL(string: "app.crispycrust://bakes/\(context.attributes.bakeId)"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { Text(context.attributes.title) }
        DynamicIslandExpandedRegion(.bottom) { Text(context.state.action) }
        DynamicIslandExpandedRegion(.trailing) { Text(context.state.dueAt, style: .timer).monospacedDigit() }
      } compactLeading: { Text("Bake") }
        compactTrailing: { Text(context.state.dueAt, style: .timer).monospacedDigit() }
        minimal: { Image(systemName: "timer") }
    }
  }
}
