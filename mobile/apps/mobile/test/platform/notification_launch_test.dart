import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/platform/local_notifications.dart';

class _LaunchPlugin implements FlutterLocalNotificationsPlugin {
  int initializations = 0;
  int launchReads = 0;
  void Function(NotificationResponse)? onResponse;
  @override
  Future<bool?> initialize({required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse}) async {
    initializations++;
    onResponse = onDidReceiveNotificationResponse;
    return true;
  }
  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async {
    launchReads++;
    return const NotificationAppLaunchDetails(true, notificationResponse: NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: '{"aggregateId":"bake-1"}'));
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('cold launch is retained until router callback exists and delivered once', () async {
    final plugin = _LaunchPlugin();
    final gateway = LocalNotificationGateway(plugin: plugin);
    final opened = <String?>[];
    await gateway.initialize();
    expect(opened, isEmpty);
    await gateway.initialize(onOpen: opened.add);
    await gateway.initialize(onOpen: opened.add);
    expect(opened, ['{"aggregateId":"bake-1"}']);
    expect(plugin.initializations, 1);
    expect(plugin.launchReads, 1);
    plugin.onResponse!(const NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: '{"aggregateId":"bake-2"}'));
    expect(opened, ['{"aggregateId":"bake-1"}', '{"aggregateId":"bake-2"}']);
  });

  test('concurrent startup initialization shares one native operation', () async {
    final plugin = _LaunchPlugin();
    final gateway = LocalNotificationGateway(plugin: plugin);
    final opened = <String?>[];
    await Future.wait([gateway.initialize(onOpen: opened.add), gateway.initialize(onOpen: opened.add)]);
    expect(plugin.initializations, 1);
    expect(plugin.launchReads, 1);
    expect(opened.length, 1);
  });
}
