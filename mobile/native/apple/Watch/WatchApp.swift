import SwiftUI
import WatchConnectivity
import CrispyCompanionCore

final class KitchenConnection: NSObject, ObservableObject, WCSessionDelegate {
  @Published var task: TaskSnapshot?
  @Published var message = "Open a bake on your phone."
  override init() {
    super.init()
    if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
  }
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    if let json = session.receivedApplicationContext["snapshot"] as? String { receive(json) }
  }
  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    if applicationContext["clear"] as? Bool == true {
      DispatchQueue.main.async { self.task = nil; self.message = "Open a bake on your phone." }; return
    }
    if let json = applicationContext["snapshot"] as? String { receive(json) }
  }
  private func receive(_ json: String) {
    guard let snapshot = try? TaskSnapshot.decode(Data(json.utf8)) else { return }
    DispatchQueue.main.async { self.task = snapshot; self.message = "" }
  }
  func acknowledge(_ task: TaskSnapshot) {
    guard WCSession.default.isReachable else { message = "Phone unavailable. Open the phone to confirm."; return }
    guard let data = try? JSONEncoder().encode(CompanionAction(task: task)),
      let json = String(data: data, encoding: .utf8) else { return }
    message = "Waiting for phone acknowledgement…"
    WCSession.default.sendMessage(["action": json], replyHandler: { reply in
      DispatchQueue.main.async { self.message = reply["accepted"] as? Bool == true ? "Acknowledged on phone" : "Open phone to review" }
    }, errorHandler: { _ in DispatchQueue.main.async { self.message = "Not synced. Open the phone." } })
  }
}

@main struct CrispyWatchApp: App {
  @StateObject private var connection = KitchenConnection()
  var body: some Scene {
    WindowGroup {
      ScrollView {
        if let task = connection.task {
          VStack(alignment: .leading, spacing: 8) {
            Text(task.title).font(.headline)
            Text(task.action)
            Text(task.dueAt, style: .timer).monospacedDigit()
            if task.isStale(at: Date()) { Text("Status may be stale. Open phone.").foregroundStyle(.orange) }
            Button("Acknowledge") { connection.acknowledge(task) }
            Text("Acknowledging does not complete this step.").font(.caption)
          }
        }
        Text(connection.message).font(.caption)
      }.padding()
    }
  }
}
