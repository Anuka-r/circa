import 'dart:async';

import 'package:sqflite/sqflite.dart';

/// Circa's local store.
///
/// Hand-written SQL rather than a generated ORM: `drift_dev` at the only
/// version compatible with the analyzer `flutter_test` pins silently drops
/// every `IntegerColumn` from its output (verified with a minimal probe table),
/// and almost every column here is an integer timestamp. Explicit SQL costs a
/// little boilerplate and removes an entire class of toolchain risk.
///
/// Conventions, enforced by review:
/// * every timestamp is **UTC epoch milliseconds**;
/// * every row records the **IANA zone** in effect at that instant, so a
///   session logged in Lisbon still renders correctly when reviewed in Tokyo;
/// * deletes are **soft** (`deleted_at`), so a removal propagates to a device
///   that was offline when it happened;
/// * every write is mirrored into `outbox` for later replay.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  Database get raw => _db;

  /// Emits after every mutation so query streams can re-read. sqflite has no
  /// reactive queries, so this is the change feed the repository builds on.
  final _changes = StreamController<Set<String>>.broadcast();

  Stream<Set<String>> get changes => _changes.stream;

  void notify(Set<String> tables) {
    if (!_changes.isClosed) _changes.add(tables);
  }

  static const _schemaVersion = 1;

  static Future<AppDatabase> open({String fileName = 'circa.db'}) async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      '$dir/$fileName',
      version: _schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async => _createSchema(db),
    );
    return AppDatabase._(db);
  }

  /// In-memory instance for tests — no files, no platform paths.
  static Future<AppDatabase> openInMemory() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: _schemaVersion,
      onCreate: (db, version) async => _createSchema(db),
    );
    return AppDatabase._(db);
  }

  Future<void> close() async {
    await _changes.close();
    await _db.close();
  }

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE user_profile (
        id                     TEXT PRIMARY KEY,
        display_name           TEXT,
        email                  TEXT,
        latitude               REAL,
        longitude              REAL,
        city_label             TEXT,
        tz_id                  TEXT NOT NULL DEFAULT 'UTC',
        work_bed_minutes       REAL NOT NULL DEFAULT 1380,
        work_wake_minutes      REAL NOT NULL DEFAULT 420,
        free_bed_minutes       REAL NOT NULL DEFAULT 1470,
        free_wake_minutes      REAL NOT NULL DEFAULT 540,
        chronotype             TEXT NOT NULL DEFAULT 'intermediate',
        msf_sc_minutes         REAL NOT NULL DEFAULT 270,
        nights_logged          INTEGER NOT NULL DEFAULT 0,
        sleep_need_min         INTEGER NOT NULL DEFAULT 480,
        sleep_need_source      TEXT NOT NULL DEFAULT 'default',
        caffeine_half_life_min INTEGER NOT NULL DEFAULT 342,
        caffeine_threshold_mg  INTEGER NOT NULL DEFAULT 30,
        typical_caffeine_mg    INTEGER NOT NULL DEFAULT 95,
        active_protocol        TEXT NOT NULL DEFAULT 'reset',
        goal                   TEXT,
        wake_difficulty        INTEGER NOT NULL DEFAULT 2,
        entitlement            TEXT NOT NULL DEFAULT 'free',
        entitlement_expires_at INTEGER,
        onboarded_at           INTEGER,
        disclaimer_ack_at      INTEGER,
        updated_at             INTEGER NOT NULL,
        sync_state             TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    batch.execute('''
      CREATE TABLE sleep_sessions (
        id          TEXT PRIMARY KEY,
        start_utc   INTEGER NOT NULL,
        end_utc     INTEGER NOT NULL,
        tz_id       TEXT NOT NULL,
        night_of    TEXT NOT NULL,
        quality     INTEGER,
        source      TEXT NOT NULL,
        latency_min INTEGER,
        awakenings  INTEGER,
        note        TEXT,
        parent_id   TEXT,
        deleted_at  INTEGER,
        updated_at  INTEGER NOT NULL,
        sync_state  TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_sleep_night ON sleep_sessions (night_of)',
    );
    batch.execute(
      'CREATE INDEX idx_sleep_start ON sleep_sessions (start_utc)',
    );

    batch.execute('''
      CREATE TABLE light_exposures (
        id            TEXT PRIMARY KEY,
        at_utc        INTEGER NOT NULL,
        tz_id         TEXT NOT NULL,
        duration_min  INTEGER NOT NULL,
        kind          TEXT NOT NULL,
        estimated_lux INTEGER NOT NULL,
        auto_logged   INTEGER NOT NULL DEFAULT 0,
        deleted_at    INTEGER,
        updated_at    INTEGER NOT NULL,
        sync_state    TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    batch.execute('CREATE INDEX idx_light_at ON light_exposures (at_utc)');

    batch.execute('''
      CREATE TABLE caffeine_intakes (
        id         TEXT PRIMARY KEY,
        at_utc     INTEGER NOT NULL,
        tz_id      TEXT NOT NULL,
        mg         INTEGER NOT NULL,
        drink_key  TEXT NOT NULL,
        deleted_at INTEGER,
        updated_at INTEGER NOT NULL,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    batch.execute('CREATE INDEX idx_caffeine_at ON caffeine_intakes (at_utc)');

    batch.execute('''
      CREATE TABLE energy_checkins (
        id         TEXT PRIMARY KEY,
        at_utc     INTEGER NOT NULL,
        tz_id      TEXT NOT NULL,
        rating     INTEGER NOT NULL,
        deleted_at INTEGER,
        updated_at INTEGER NOT NULL,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    batch.execute('''
      CREATE TABLE protocol_completions (
        id           TEXT PRIMARY KEY,
        event_key    TEXT NOT NULL UNIQUE,
        completed_at INTEGER NOT NULL,
        deleted_at   INTEGER,
        updated_at   INTEGER NOT NULL,
        sync_state   TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    batch.execute('''
      CREATE TABLE outbox (
        seq         INTEGER PRIMARY KEY AUTOINCREMENT,
        collection  TEXT NOT NULL,
        doc_id      TEXT NOT NULL,
        op          TEXT NOT NULL,
        payload     TEXT NOT NULL,
        attempt     INTEGER NOT NULL DEFAULT 0,
        next_try_at INTEGER NOT NULL DEFAULT 0,
        last_error  TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_outbox_ready ON outbox (next_try_at)');

    await batch.commit(noResult: true);
  }
}

/// Table names, so a typo is a compile error rather than a silent empty result.
abstract final class Tables {
  static const profile = 'user_profile';
  static const sleep = 'sleep_sessions';
  static const light = 'light_exposures';
  static const caffeine = 'caffeine_intakes';
  static const checkins = 'energy_checkins';
  static const completions = 'protocol_completions';
  static const outbox = 'outbox';
}

abstract final class SyncStates {
  static const pending = 'pending';
  static const synced = 'synced';
  static const failed = 'failed';
}
