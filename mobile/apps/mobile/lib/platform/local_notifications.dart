import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'platform_result.dart';
import 'reminders.dart';

class LocalNotificationGateway implements ReminderGateway {
  LocalNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
      : plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin plugin;
  bool _initialized = false;
  bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS);

  Future<CapabilityResult<bool>> initialize({void Function(String?)? onOpen}) async {
    if (!supported) { return const CapabilityResult(CapabilityStatus.unsupported,
      'Native reminders are available on iOS and Android. In-app deadlines remain visible.'); }
    tz_data.initializeTimeZones();
    await plugin.initialize(settings: const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(requestAlertPermission: false,
        requestBadgePermission: false, requestSoundPermission: false)),
      onDidReceiveNotificationResponse: (response) => onOpen?.call(response.payload));
    _initialized = true;
    return const CapabilityResult.available(true);
  }

  /// Request only after the user opts into a useful reminder.
  Future<CapabilityResult<bool>> requestPermission() async {
    if (!_initialized) { await initialize(); }
    if (!supported) { return const CapabilityResult(CapabilityStatus.unsupported, 'Native reminders unavailable.'); }
    final bool? allowed;
    if (defaultTargetPlatform == TargetPlatform.android) {
      allowed = await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    } else {
      allowed = await plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    return allowed == true ? const CapabilityResult.available(true) :
      const CapabilityResult(CapabilityStatus.denied,
        'Reminders are off. Deadlines remain in the app; enable alerts in device settings.', false);
  }

  Future<CapabilityResult<bool>> requestExactScheduling() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
      return const CapabilityResult(CapabilityStatus.unsupported,
        'Exact-alarm permission is an Android capability. Other platforms use their native reminder scheduling.');
    }
    if (!_initialized) { await initialize(); }
    final allowed = await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestExactAlarmsPermission();
    return allowed == true ? const CapabilityResult.available(true) :
      const CapabilityResult(CapabilityStatus.denied,
        'Precise scheduling is unavailable. Alerts may be delayed; in-app deadlines remain accurate.', false);
  }

  @override
  Future<List<PendingReminder>> pending() async {
    if (!supported) { return []; }
    if (!_initialized) { await initialize(); }
    return (await plugin.pendingNotificationRequests())
      .map((p) => PendingReminder(p.id, p.payload)).toList();
  }

  @override
  Future<void> cancel(int id) async {
    if (supported) { await plugin.cancel(id: id); }
  }

  @override
  Future<void> schedule(ReminderIntent reminder) async {
    if (!supported) { throw UnsupportedError('Native reminders require iOS or Android'); }
    if (!_initialized) { await initialize(); }
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final exactAllowed = await android?.canScheduleExactNotifications() ?? false;
    await plugin.zonedSchedule(id: reminder.notificationId, title: reminder.title,
      body: reminder.isCheck ? '${reminder.action} · check the dough; timing is an estimate' : reminder.action,
      scheduledDate: tz.TZDateTime.from(reminder.dueAt.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('baking_reminders', 'Baking reminders',
          channelDescription: 'Named starter and bake actions you choose to be reminded about',
          importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails()),
      androidScheduleMode: exactAllowed ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.payload);
  }
}
