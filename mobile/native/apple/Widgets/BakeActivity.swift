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
  var body: some Widget { BakeActivityWidget(); KitchenHomeWidget() }
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


struct KitchenEntry: TimelineEntry {
  let date: Date
  let title: String
  let action: String
  let dueAt: Date?
  let generatedAt: Date?
  let bakeId: String?
}
struct KitchenProvider: TimelineProvider {
  func placeholder(in context: Context) -> KitchenEntry {
    KitchenEntry(date: Date(), title: "Crispy Crust", action: "Open a bake on your phone", dueAt: nil, generatedAt: nil, bakeId: nil)
  }
  func getSnapshot(in context: Context, completion: @escaping (KitchenEntry) -> Void) { completion(read()) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<KitchenEntry>) -> Void) {
    completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(15 * 60))))
  }
  private func read() -> KitchenEntry {
    guard let raw = UserDefaults(suiteName: "group.app.crispycrust.shared")?.string(forKey: "snapshot"),
      let data = raw.data(using: .utf8), let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      value["schemaVersion"] as? Int == 1 else {
      return KitchenEntry(date: Date(), title: "Crispy Crust", action: "Open a bake on your phone", dueAt: nil, generatedAt: nil, bakeId: nil)
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return KitchenEntry(date: Date(), title: value["title"] as? String ?? "Bake",
      action: value["action"] as? String ?? "Open phone", dueAt: formatter.date(from: value["dueAt"] as? String ?? ""),
      generatedAt: formatter.date(from: value["generatedAt"] as? String ?? ""), bakeId: value["bakeId"] as? String)
  }
}
struct KitchenHomeWidget: Widget {
  let kind = "CrispyKitchen"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: KitchenProvider()) { entry in
      VStack(alignment: .leading, spacing: 6) {
        Text(entry.title).font(.headline)
        Text(entry.action)
        if let date = entry.dueAt { Text(date, style: .timer).monospacedDigit() }
        if let generated = entry.generatedAt, Date().timeIntervalSince(generated) > 900 {
          Text("Status may be stale. Open phone.").font(.caption)
        }
      }.padding().widgetURL(URL(string: "app.crispycrust://bakes/\(entry.bakeId ?? "")"))
    }.configurationDisplayName("Your next baking action")
      .description("A named next action; check the app for current dough observations.")
      .supportedFamilies([.systemSmall, .systemMedium])
  }
}
