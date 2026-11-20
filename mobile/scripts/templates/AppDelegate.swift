import Flutter
import UIKit
import EventKit
import UserNotifications
import WatchConnectivity
import ActivityKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, WCSessionDelegate {
  private let eventStore = EKEventStore()
  private var kitchenChannel: FlutterMethodChannel?
  private var pendingWatchSnapshot: String?
  private var pendingWatchClear = false

  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    UNUserNotificationCenter.current().delegate = self
    if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    kitchenChannel = FlutterMethodChannel(name: "app.crispycrust/kitchen", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    kitchenChannel?.setMethodCallHandler { [weak self] call, result in
          guard let self else { return }
          let args = call.arguments as? [String: Any] ?? [:]
          switch call.method {
          case "setKeepAwake":
            UIApplication.shared.isIdleTimerDisabled = args["enabled"] as? Bool ?? false
            result(nil)
          case "clearCompanion":
            UserDefaults(suiteName: "group.app.crispycrust.shared")?.removeObject(forKey: "snapshot")
            WidgetCenter.shared.reloadAllTimelines()
            self.pendingWatchSnapshot = nil
            self.pendingWatchClear = true
            _ = self.sendWatchSnapshot()
            if #available(iOS 16.2, *) {
              Task { for activity in Activity<BakeActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) } }
            }
            result(nil)
          case "publishCompanion":
            guard let snapshot = args["snapshot"] as? [String: Any], snapshot["schemaVersion"] as? Int == 1,
              JSONSerialization.isValidJSONObject(snapshot), let data = try? JSONSerialization.data(withJSONObject: snapshot),
              let json = String(data: data, encoding: .utf8) else {
              result(FlutterError(code: "INVALID_SNAPSHOT", message: "Invalid companion task", details: nil)); return
            }
            UserDefaults(suiteName: "group.app.crispycrust.shared")?.set(json, forKey: "snapshot")
            WidgetCenter.shared.reloadAllTimelines()
            self.pendingWatchSnapshot = json
            self.pendingWatchClear = false
            let watchTransport = self.sendWatchSnapshot()
            if args["enableLiveActivity"] as? Bool == true, #available(iOS 16.2, *) {
              self.updateActivity(snapshot)
            }
            result(["widget": true, "watchTransport": watchTransport, "watchReceiptConfirmed": false])
          case "readBusy":
            guard let start = args["start"] as? NSNumber, let end = args["end"] as? NSNumber,
              end.doubleValue > start.doubleValue, end.doubleValue - start.doubleValue <= 31 * 86400000 else {
              result(FlutterError(code: "INVALID_RANGE", message: "Select a range of up to 31 days", details: nil)); return
            }
            self.requestCalendar(start: start.doubleValue / 1000, end: end.doubleValue / 1000, result: result)
          default: result(FlutterMethodNotImplemented)
          }
        }
  }
  private func sendWatchSnapshot() -> Bool {
    guard WCSession.isSupported(), WCSession.default.activationState == .activated,
      WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return false }
    let context: [String: Any]
    if pendingWatchClear { context = ["clear": true] }
    else if let snapshot = pendingWatchSnapshot { context = ["snapshot": snapshot] }
    else { return false }
    do { try WCSession.default.updateApplicationContext(context); return true }
    catch { return false }
  }
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { _ = self.sendWatchSnapshot() }
  }
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    guard let raw = message["action"] as? String, let data = raw.data(using: .utf8),
      let action = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { replyHandler(["accepted": false]); return }
    DispatchQueue.main.async {
      guard let channel = self.kitchenChannel else { replyHandler(["accepted": false]); return }
      channel.invokeMethod("companionAction", arguments: action) { value in
        replyHandler(["accepted": (value as? [String: Any])?["accepted"] as? Bool ?? false])
      }
    }
  }
  @available(iOS 16.2, *)
  private func updateActivity(_ snapshot: [String: Any]) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled,
      let bakeId = snapshot["bakeId"] as? String, let title = snapshot["title"] as? String,
      let action = snapshot["action"] as? String, let due = snapshot["dueAt"] as? String,
      let generated = snapshot["generatedAt"] as? String, let revision = snapshot["revision"] as? Int else { return }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let dueAt = formatter.date(from: due), let generatedAt = formatter.date(from: generated) else { return }
    let state = BakeActivityAttributes.ContentState(action: action, dueAt: dueAt, generatedAt: generatedAt, revision: revision)
    let content = ActivityContent(state: state, staleDate: generatedAt.addingTimeInterval(900))
    if let existing = Activity<BakeActivityAttributes>.activities.first(where: { $0.attributes.bakeId == bakeId }) {
      Task { await existing.update(content) }
    } else {
      _ = try? Activity.request(attributes: BakeActivityAttributes(bakeId: bakeId, title: title), content: content, pushType: nil)
    }
  }
  private func requestCalendar(start: Double, end: Double, result: @escaping FlutterResult) {
    let completion: (Bool, Error?) -> Void = { [weak self] allowed, _ in
      DispatchQueue.main.async {
        guard allowed, let self else { result(["status": "denied"]); return }
        let predicate = self.eventStore.predicateForEvents(withStart: Date(timeIntervalSince1970: start),
          end: Date(timeIntervalSince1970: end), calendars: nil)
        let blocks = self.eventStore.events(matching: predicate).filter { $0.availability != .free }
          .map { ["start": Int64($0.startDate.timeIntervalSince1970 * 1000), "end": Int64($0.endDate.timeIntervalSince1970 * 1000)] }
        result(["status": "available", "blocks": blocks])
      }
    }
    if #available(iOS 17.0, *) { eventStore.requestFullAccessToEvents(completion: completion) }
    else { eventStore.requestAccess(to: .event, completion: completion) }
  }
}

@available(iOS 16.2, *)
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
