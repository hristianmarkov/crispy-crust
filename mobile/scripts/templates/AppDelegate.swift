import Flutter
import UIKit
import EventKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let eventStore = EKEventStore()

  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    UNUserNotificationCenter.current().delegate = self
    FlutterMethodChannel(name: "app.crispycrust/kitchen", binaryMessenger: engineBridge.applicationRegistrar.messenger())
        .setMethodCallHandler { [weak self] call, result in
          guard let self else { return }
          let args = call.arguments as? [String: Any] ?? [:]
          switch call.method {
          case "setKeepAwake":
            UIApplication.shared.isIdleTimerDisabled = args["enabled"] as? Bool ?? false
            result(nil)
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
