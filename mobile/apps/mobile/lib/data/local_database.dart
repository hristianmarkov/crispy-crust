import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Small explicit Drift schema: immutable events, materialised local records,
/// preferences and the durable sync outbox share one SQLite transaction.
class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(super.executor);
  factory LocalDatabase.file(File file) => LocalDatabase(NativeDatabase.createInBackground(file));
  factory LocalDatabase.memory() => LocalDatabase(NativeDatabase.memory());
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
    await customStatement('CREATE TABLE records (id TEXT PRIMARY KEY, kind TEXT NOT NULL, fields TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL, deleted_at TEXT)');
    await customStatement('CREATE INDEX records_kind ON records(kind, deleted_at, updated_at)');
    await customStatement('CREATE TABLE events (id TEXT PRIMARY KEY, aggregate_id TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, occurred_at TEXT NOT NULL, recorded_at TEXT NOT NULL, base_revision INTEGER NOT NULL, corrects_id TEXT)');
    await customStatement('CREATE INDEX events_aggregate ON events(aggregate_id, recorded_at)');
    await customStatement('CREATE TABLE outbox (operation_id TEXT PRIMARY KEY REFERENCES events(id), aggregate_id TEXT NOT NULL, state TEXT NOT NULL DEFAULT \'local\', attempts INTEGER NOT NULL DEFAULT 0)');
    await customStatement('CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await customStatement('CREATE TABLE sync_cursors (kitchen_id TEXT PRIMARY KEY, cursor INTEGER NOT NULL)');
  });
}
