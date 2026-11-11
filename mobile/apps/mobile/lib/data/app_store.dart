import 'package:flutter/foundation.dart';

dynamic freezeJson(dynamic value) {
  if (value is Map) return Map<String,dynamic>.unmodifiable(value.map((k,v)=>MapEntry(k.toString(),freezeJson(v))));
  if (value is List) return List<dynamic>.unmodifiable(value.map(freezeJson));
  return value;
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
  Future<AppRecord> createBake(Map<String, dynamic> recipe, {double scale = 1, DateTime? serveAt});
  Future<void> completeStep(String bakeId, {DateTime? occurredAt, int? expectedIndex});
  Future<void> logFeed(String starterId, {required double seed, required double flour, required double water, DateTime? occurredAt});
  Future<String> exportArchive();
  Future<void> importArchive(String source);
  Future<void> resetLocalData();
}
