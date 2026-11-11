import 'dart:convert';

/// A projection of persisted reminder intent. It is not the durable source of truth.
class ReminderIntent {
  const ReminderIntent({required this.id, required this.aggregateId,
    required this.revision, required this.title, required this.action,
    required this.dueAt, this.isCheck = false});
  final String id;
  final String aggregateId;
  final int revision;
  final String title;
  final String action;
  final DateTime dueAt;
  final bool isCheck;
  String get payload => jsonEncode({'source': 'crispy-crust', 'id': id,
    'aggregateId': aggregateId, 'revision': revision,
    'dueAt': dueAt.toUtc().toIso8601String(), 'title': title, 'action': action, 'isCheck': isCheck});
  int get notificationId => stableNotificationId(id);
}

/// Deterministic FNV-1a, limited to a positive signed native notification id.
int stableNotificationId(String id) {
  var value = 0x811c9dc5;
  for (final byte in utf8.encode('crispy-crust:$id')) {
    value = ((value ^ byte) * 0x01000193) & 0xffffffff;
  }
  return value & 0x7fffffff;
}

class PendingReminder {
  const PendingReminder(this.id, this.payload);
  final int id;
  final String? payload;
  bool get belongsToApp {
    try { return (jsonDecode(payload ?? '') as Map)['source'] == 'crispy-crust'; }
    on FormatException { return false; }
    on TypeError { return false; }
  }
}

abstract interface class ReminderGateway {
  Future<List<PendingReminder>> pending();
  Future<void> schedule(ReminderIntent reminder);
  Future<void> cancel(int id);
}

class ReminderReconciliation {
  const ReminderReconciliation({required this.scheduled, required this.canceled,
    required this.overdue, required this.deferred});
  final int scheduled;
  final int canceled;
  final List<ReminderIntent> overdue;
  final List<ReminderIntent> deferred;
}

/// Reconcile on app start/resume and after every accepted plan change.
/// A bounded horizon reserves room for other OS surfaces; it is NOT a promise
/// of delivery or a claim that every platform has the same queue limit.
class ReminderCoordinator {
  ReminderCoordinator(this.gateway, {this.maximumPending = 48});
  final ReminderGateway gateway;
  final int maximumPending;

  Future<ReminderReconciliation> reconcile(List<ReminderIntent> intents,
      {required DateTime now}) async {
    if (maximumPending < 1) throw ArgumentError.value(maximumPending);
    final byId = <String, ReminderIntent>{};
    for (final intent in intents) {
      final previous = byId[intent.id];
      if (previous == null || previous.revision < intent.revision) {
        byId[intent.id] = intent;
      } else if (previous.revision == intent.revision && previous.payload != intent.payload) {
        throw StateError('Conflicting reminder intent ${intent.id}');
      }
    }
    final future = byId.values.where((r) => r.dueAt.isAfter(now)).toList()
      ..sort((a, b) { final c = a.dueAt.compareTo(b.dueAt); return c == 0 ? a.id.compareTo(b.id) : c; });
    final selected = future.take(maximumPending).toList();
    final nativeIds = <int, String>{};
    for (final item in selected) {
      if (nativeIds.containsKey(item.notificationId)) {
        throw StateError('Native reminder id collision; do not silently overwrite');
      }
      nativeIds[item.notificationId] = item.id;
    }
    final desired = {for (final item in selected) item.notificationId: item};
    final pending = await gateway.pending();
    var canceled = 0;
    var scheduled = 0;
    final same = <int>{};
    for (final item in pending.where((p) => p.belongsToApp)) {
      final target = desired[item.id];
      if (target == null || target.payload != item.payload) {
        await gateway.cancel(item.id); canceled++;
      } else { same.add(item.id); }
    }
    for (final item in selected.where((r) => !same.contains(r.notificationId))) {
      await gateway.schedule(item); scheduled++;
    }
    return ReminderReconciliation(scheduled: scheduled, canceled: canceled,
      overdue: byId.values.where((r) => !r.dueAt.isAfter(now)).toList(),
      deferred: future.skip(maximumPending).toList());
  }
}

class DurableTimer {
  const DurableTimer({required this.id, required this.startedAt,
    required this.duration, required this.aggregateId});
  final String id;
  final String aggregateId;
  final DateTime startedAt;
  final Duration duration;
  DateTime get dueAt => startedAt.add(duration);
  Duration remainingAt(DateTime now) => dueAt.difference(now);
  Map<String, Object> toJson() => {'id': id, 'aggregateId': aggregateId,
    'startedAt': startedAt.toUtc().toIso8601String(), 'durationSeconds': duration.inSeconds};
  factory DurableTimer.fromJson(Map<String, dynamic> json) => DurableTimer(
    id: json['id'] as String, aggregateId: json['aggregateId'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    duration: Duration(seconds: json['durationSeconds'] as int));
}
