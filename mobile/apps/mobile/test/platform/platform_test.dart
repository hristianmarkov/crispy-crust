import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/platform/calendar_export.dart';
import 'package:crispy_crust/platform/companion_snapshot.dart';
import 'package:crispy_crust/platform/reminders.dart';
import 'package:crispy_crust/platform/sensor_reading.dart';
import 'package:crispy_crust/platform/cloud_session.dart';

class FakeGateway implements ReminderGateway {
  final values = <int, PendingReminder>{};
  final scheduled = <ReminderIntent>[];
  final canceled = <int>[];
  @override Future<List<PendingReminder>> pending() async => values.values.toList();
  @override Future<void> cancel(int id) async { canceled.add(id); values.remove(id); }
  @override Future<void> schedule(ReminderIntent r) async {
    scheduled.add(r); values[r.notificationId] = PendingReminder(r.notificationId, r.payload);
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 11, 10);
  ReminderIntent reminder(String id, int revision, int minutes) => ReminderIntent(
    id: id, aggregateId: 'bake-a', revision: revision, title: 'Country loaf',
    action: 'Check the rise', dueAt: now.add(Duration(minutes: minutes)), isCheck: true);
  test('reconciliation is idempotent and does not cancel unrelated notifications', () async {
    final gateway = FakeGateway();
    gateway.values[123] = const PendingReminder(123, '{"source":"other"}');
    final coordinator = ReminderCoordinator(gateway);
    final r = reminder('a', 1, 5);
    expect((await coordinator.reconcile([r], now: now)).scheduled, 1);
    expect((await coordinator.reconcile([r], now: now)).scheduled, 0);
    await coordinator.reconcile([], now: now);
    expect(gateway.canceled, [r.notificationId]);
    expect(gateway.values.containsKey(123), isTrue);
  });
  test('revision replaces only superseded reminder and retains durable overdue tasks', () async {
    final gateway = FakeGateway();
    final coordinator = ReminderCoordinator(gateway, maximumPending: 1);
    await coordinator.reconcile([reminder('a', 1, 5)], now: now);
    final result = await coordinator.reconcile([
      reminder('a', 2, 10), reminder('b', 1, 30), reminder('overdue', 1, -3),
    ], now: now);
    expect(result.scheduled, 1); expect(result.canceled, 1);
    expect(result.overdue.single.id, 'overdue'); expect(result.deferred.single.id, 'b');
    expect(jsonDecode(gateway.values.values.single.payload!)['revision'], 2);
  });
  test('same-revision conflicting instructions are rejected instead of silently lost', () async {
    expect(() => ReminderCoordinator(FakeGateway()).reconcile([
      reminder('a', 1, 2), reminder('a', 1, 3)], now: now), throwsStateError);
  });
  test('timer survives serialization, restart and zone changes as an absolute deadline', () {
    final timer = DurableTimer(id: 'oven', startedAt: now,
      duration: const Duration(minutes: 45), aggregateId: 'dough');
    final restored = DurableTimer.fromJson(jsonDecode(jsonEncode(timer.toJson())));
    expect(restored.remainingAt(now.add(const Duration(minutes: 46))), const Duration(minutes: -1));
    expect(restored.dueAt, DateTime.utc(2026, 11, 11, 10, 45));
  });
  test('calendar export escapes injection and keeps UTC sequence identity', () {
    final result = exportCalendar([CalendarTask(id: 'dough-fold-1', title: 'Fold, rye; batch\nEND:VEVENT',
      start: now, end: now.add(const Duration(minutes: 2)), revision: 3)], generatedAt: now);
    expect(result, contains('DTSTART:20261111T100000Z\r\n'));
    expect(result, contains('SUMMARY:Fold\\, rye\\; batch\\nEND:VEVENT'));
    expect(result, contains('SEQUENCE:3')); expect(result.split('BEGIN:VEVENT').length, 2);
  });
  test('SIG temperature decodes signed readings and rejects malformed values', () {
    final reading = decodeEnvironmentalTemperature([0x70, 0xFE], deviceId: 'probe',
      role: SensorRole.fridge, receivedAt: now);
    expect(reading.celsius, -4);
    expect(reading.isStaleAt(now.add(const Duration(minutes: 6))), isTrue);
    expect(() => decodeEnvironmentalTemperature([1], deviceId: 'p', role: SensorRole.dough,
      receivedAt: now), throwsFormatException);
  });
  test('companion replay/stale revisions cannot apply physical actions', () {
    final task = CompanionTaskSnapshot(bakeId: 'b', stepId: 'fold-2', title: 'Country loaf',
      action: 'Check the rise', revision: 3, dueAt: now, generatedAt: now);
    final action = CompanionAction.fromJson({'operationId': 'op1', 'bakeId': 'b',
      'stepId': 'fold-2', 'expectedRevision': 3, 'type': 'acknowledge'});
    expect(companionActionCanApply(action, task, {}), isTrue);
    expect(companionActionCanApply(action, task, {'op1'}), isFalse);
    expect(() => CompanionAction.fromJson({'type': 'complete'}), throwsFormatException);
  });
  test('auth only accepts the exact app callback and HTTPS configuration', () {
    expect(CloudSessionService.isAllowedAuthRedirect(Uri.parse('app.crispycrust://auth/callback?code=x')), isTrue);
    expect(CloudSessionService.isAllowedAuthRedirect(Uri.parse('evil://auth/callback?code=x')), isFalse);
    expect(CloudSessionService.isAllowedAuthRedirect(Uri.parse('app.crispycrust://auth/callback/else')), isFalse);
    expect(const CloudConfiguration(url: 'https://app.supabase.co', publishableKey: 'public').isConfigured, isTrue);
    expect(const CloudConfiguration(url: 'http://app.supabase.co', publishableKey: 'public').isConfigured, isFalse);
    expect(const CloudConfiguration(url: '', publishableKey: '').isConfigured, isFalse);
  });
}
