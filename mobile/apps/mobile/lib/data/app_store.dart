import 'package:flutter/foundation.dart';

const analyticsConsentKey = 'posthogAnalyticsOptIn';

dynamic freezeJson(dynamic value) {
  if (value is Map) return Map<String,dynamic>.unmodifiable(value.map((k,v)=>MapEntry(k.toString(),freezeJson(v))));
  if (value is List) return List<dynamic>.unmodifiable(value.map(freezeJson));
  return value;
}


class BakeSetup {
  const BakeSetup({this.starterId, this.addToShopping = true, this.timeAway = const []});
  final String? starterId;
  final bool addToShopping;
  final List<(DateTime, DateTime)> timeAway;

  List<AppRecord> get awayRecords => [
    for (final (index, window) in timeAway.indexed)
      AppRecord(id: 'bake-away-$index', kind: 'availability', updatedAt: window.$1, fields: {
        'startAt': window.$1.toUtc().toIso8601String(),
        'endAt': window.$2.toUtc().toIso8601String(),
      }),
  ];
}

class AppRecord {
  AppRecord({required this.id, required this.kind, required Map<String,dynamic> fields, required this.updatedAt, this.revision=1}):fields=freezeJson(fields) as Map<String,dynamic>;
  final String id;
  final String kind;
  final Map<String, dynamic> fields;
  final DateTime updatedAt;
  final int revision;
  String text(String key, [String fallback = '']) => fields[key]?.toString() ?? fallback;
  num number(String key, [num fallback = 0]) => fields[key] is num ? fields[key] as num : num.tryParse(text(key)) ?? fallback;
  bool flag(String key) => fields[key] == true;
  DateTime? date(String key) => DateTime.tryParse(text(key));
}

abstract class AppStore extends ChangeNotifier {
  List<AppRecord> records(String kind);
  AppRecord? find(String id);
  List<Map<String, dynamic>> get recipes;
  List<Map<String, dynamic>> get lessons;
  List<Map<String, dynamic>> get guidance;
  bool get darkMode;
  bool get beginnerMode;
  String get storageDescription;
  Future<AppRecord> save(String kind, Map<String, dynamic> fields, {String? id});
  Future<void> remove(String id);
  Future<void> setPreference(String key, dynamic value);
  dynamic preference(String key, [dynamic fallback]);
  Future<AppRecord> createBake(Map<String, dynamic> recipe, {double scale = 1, DateTime? serveAt, DateTime? startAt, Map<String,dynamic>? expectedSchedule, bool beginImmediately = false, BakeSetup setup = const BakeSetup()});
  Future<void> completeStep(String bakeId, {DateTime? occurredAt, int? expectedIndex});
  Future<void> saveBakeSchedule(AppRecord bake, Map<String, dynamic> fields) async {
    if (find(bake.id)?.revision != bake.revision) throw BakeScheduleChanged();
    await save('bake', fields, id: bake.id);
  }
  Future<void> logFeed(String starterId, {required double seed, required double flour, required double water, DateTime? occurredAt});
  Future<void> reconcileStock(String id, {
    required int expectedRevision, required double grams, required String reason,
    bool withdrawal = false, String? bakeId,
  }) => throw UnsupportedError('This store does not support stock reconciliation.');
  Future<String> exportArchive();
  Future<void> importArchive(String source);
  Future<void> resetLocalData();
}
class BakeScheduleChanged extends StateError {
  BakeScheduleChanged() : super('The schedule changed after review. Review the updated times before creating the bake.');
}
