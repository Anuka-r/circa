import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:uuid/uuid.dart';

import '../../domain/chrono/caffeine_model.dart';
import '../../domain/chrono/chronotype_estimator.dart';
import '../../domain/chrono/light_prc.dart';
import '../../domain/chrono/protocol_engine.dart';
import '../../domain/chrono/sleep_debt_ledger.dart';
import '../../domain/entities/sleep_session.dart';
import '../../domain/value_objects/chronotype.dart';
import '../../domain/value_objects/geo_location.dart';
import '../local/database.dart';

/// The user's settings and derived state, as the app sees it.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.schedule,
    required this.chronotype,
    required this.msfScMinutes,
    required this.nightsLogged,
    required this.sleepNeedMinutes,
    required this.sleepNeedIsPersonalised,
    required this.caffeineHalfLifeMinutes,
    required this.caffeineThresholdMg,
    required this.typicalCaffeineMg,
    required this.activeProtocol,
    required this.isPro,
    required this.onboarded,
    required this.disclaimerAcknowledged,
    this.location,
    this.goal,
    this.wakeDifficulty = 2,
    this.displayName,
  });

  final String id;
  final HabitualSchedule schedule;
  final Chronotype chronotype;
  final double msfScMinutes;
  final int nightsLogged;
  final double sleepNeedMinutes;
  final bool sleepNeedIsPersonalised;
  final double caffeineHalfLifeMinutes;
  final double caffeineThresholdMg;
  final double typicalCaffeineMg;
  final ProtocolKind activeProtocol;
  final bool isPro;
  final bool onboarded;
  final bool disclaimerAcknowledged;
  final GeoLocation? location;
  final String? goal;
  final int wakeDifficulty;
  final String? displayName;

  /// Where we compute the sun. Falls back to a real place rather than leaving
  /// the app blank when location has been declined.
  GeoLocation get effectiveLocation =>
      location ??
      const GeoLocation(
        latitude: 51.5074,
        longitude: -0.1278,
        tzId: 'Europe/London',
        label: 'London, United Kingdom',
      );

  PhaseConfidence get confidence =>
      PhaseConfidence.fromNights(nightsLogged);

  UserProfile copyWith({
    HabitualSchedule? schedule,
    Chronotype? chronotype,
    double? msfScMinutes,
    int? nightsLogged,
    double? sleepNeedMinutes,
    bool? sleepNeedIsPersonalised,
    double? caffeineHalfLifeMinutes,
    double? caffeineThresholdMg,
    double? typicalCaffeineMg,
    ProtocolKind? activeProtocol,
    bool? isPro,
    bool? onboarded,
    bool? disclaimerAcknowledged,
    GeoLocation? location,
    String? goal,
    int? wakeDifficulty,
    String? displayName,
  }) =>
      UserProfile(
        id: id,
        schedule: schedule ?? this.schedule,
        chronotype: chronotype ?? this.chronotype,
        msfScMinutes: msfScMinutes ?? this.msfScMinutes,
        nightsLogged: nightsLogged ?? this.nightsLogged,
        sleepNeedMinutes: sleepNeedMinutes ?? this.sleepNeedMinutes,
        sleepNeedIsPersonalised:
            sleepNeedIsPersonalised ?? this.sleepNeedIsPersonalised,
        caffeineHalfLifeMinutes:
            caffeineHalfLifeMinutes ?? this.caffeineHalfLifeMinutes,
        caffeineThresholdMg: caffeineThresholdMg ?? this.caffeineThresholdMg,
        typicalCaffeineMg: typicalCaffeineMg ?? this.typicalCaffeineMg,
        activeProtocol: activeProtocol ?? this.activeProtocol,
        isPro: isPro ?? this.isPro,
        onboarded: onboarded ?? this.onboarded,
        disclaimerAcknowledged:
            disclaimerAcknowledged ?? this.disclaimerAcknowledged,
        location: location ?? this.location,
        goal: goal ?? this.goal,
        wakeDifficulty: wakeDifficulty ?? this.wakeDifficulty,
        displayName: displayName ?? this.displayName,
      );

  static UserProfile defaults() => const UserProfile(
        id: 'me',
        schedule: HabitualSchedule(
          workBedMinutes: 23 * 60,
          workWakeMinutes: 7 * 60,
          freeBedMinutes: 24 * 60 + 30,
          freeWakeMinutes: 9 * 60,
        ),
        chronotype: Chronotype.intermediate,
        msfScMinutes: 270,
        nightsLogged: 0,
        sleepNeedMinutes: 480,
        sleepNeedIsPersonalised: false,
        caffeineHalfLifeMinutes: CaffeineModel.defaultHalfLifeMinutes,
        caffeineThresholdMg: 30,
        typicalCaffeineMg: 95,
        activeProtocol: ProtocolKind.reset,
        isPro: false,
        onboarded: false,
        disclaimerAcknowledged: false,
      );
}

/// A logged light exposure.
class LoggedLight {
  const LoggedLight({
    required this.id,
    required this.atUtc,
    required this.durationMinutes,
    required this.kind,
    required this.lux,
  });

  final String id;
  final DateTime atUtc;
  final int durationMinutes;
  final LightKind kind;
  final int lux;

  LightExposure toExposure() => LightExposure(
        atUtc: atUtc,
        durationMinutes: durationMinutes,
        lux: lux,
      );
}

/// A logged caffeine intake.
class LoggedCaffeine {
  const LoggedCaffeine({
    required this.id,
    required this.atUtc,
    required this.mg,
    required this.drinkKey,
  });

  final String id;
  final DateTime atUtc;
  final int mg;
  final String drinkKey;

  CaffeineDose toDose() => CaffeineDose(atUtc: atUtc, mg: mg.toDouble());
}

/// Local-first data access.
///
/// Reads always come from SQLite and writes are optimistic: the row lands
/// locally immediately and an outbox entry records the intent for whenever a
/// connection exists. That is why every screen behaves identically online and
/// offline — the network is an optimisation, never a dependency.
class CircaRepository {
  CircaRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const profileId = 'me';

  int get _now => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Re-runs [read] whenever one of [tables] changes. This is the reactive
  /// layer sqflite doesn't provide.
  Stream<T> _watch<T>(Set<String> tables, Future<T> Function() read) async* {
    yield await read();
    await for (final changed in _db.changes) {
      if (changed.intersection(tables).isEmpty) continue;
      yield await read();
    }
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  Stream<UserProfile> watchProfile() =>
      _watch({Tables.profile}, getProfile);

  Future<UserProfile> getProfile() async {
    final rows = await _db.raw.query(Tables.profile, limit: 1);
    if (rows.isEmpty) {
      final defaults = UserProfile.defaults();
      await _insertProfile(defaults);
      return defaults;
    }
    return _mapProfile(rows.first);
  }

  Future<void> _insertProfile(UserProfile p) async {
    await _db.raw.insert(Tables.profile, {
      'id': profileId,
      ..._profileValues(p),
      'updated_at': _now,
    });
  }

  Map<String, Object?> _profileValues(UserProfile p) => {
        'display_name': p.displayName,
        'latitude': p.location?.latitude,
        'longitude': p.location?.longitude,
        'city_label': p.location?.label,
        'tz_id': p.location?.tzId ?? 'UTC',
        'work_bed_minutes': p.schedule.workBedMinutes,
        'work_wake_minutes': p.schedule.workWakeMinutes,
        'free_bed_minutes': p.schedule.freeBedMinutes,
        'free_wake_minutes': p.schedule.freeWakeMinutes,
        'chronotype': p.chronotype.name,
        'msf_sc_minutes': p.msfScMinutes,
        'nights_logged': p.nightsLogged,
        'sleep_need_min': p.sleepNeedMinutes.round(),
        'sleep_need_source': p.sleepNeedIsPersonalised ? 'personalised' : 'default',
        'caffeine_half_life_min': p.caffeineHalfLifeMinutes.round(),
        'caffeine_threshold_mg': p.caffeineThresholdMg.round(),
        'typical_caffeine_mg': p.typicalCaffeineMg.round(),
        'active_protocol': p.activeProtocol.name,
        'goal': p.goal,
        'wake_difficulty': p.wakeDifficulty,
        'entitlement': p.isPro ? 'pro' : 'free',
        'onboarded_at': p.onboarded ? _now : null,
        'disclaimer_ack_at': p.disclaimerAcknowledged ? _now : null,
        'sync_state': SyncStates.pending,
      };

  Future<void> saveProfile(UserProfile profile) async {
    final existing = await _db.raw.query(Tables.profile, limit: 1);
    if (existing.isEmpty) {
      await _insertProfile(profile);
    } else {
      await _db.raw.update(
        Tables.profile,
        {..._profileValues(profile), 'updated_at': _now},
        where: 'id = ?',
        whereArgs: [profileId],
      );
    }
    await _enqueue('users', profileId, 'upsert', {'updatedAt': _now});
    _db.notify({Tables.profile});
  }

  UserProfile _mapProfile(Map<String, Object?> r) {
    final lat = r['latitude'] as double?;
    final lon = r['longitude'] as double?;
    return UserProfile(
      id: r['id'] as String,
      displayName: r['display_name'] as String?,
      schedule: HabitualSchedule(
        workBedMinutes: (r['work_bed_minutes'] as num).toDouble(),
        workWakeMinutes: (r['work_wake_minutes'] as num).toDouble(),
        freeBedMinutes: (r['free_bed_minutes'] as num).toDouble(),
        freeWakeMinutes: (r['free_wake_minutes'] as num).toDouble(),
      ),
      chronotype: Chronotype.values.firstWhere(
        (c) => c.name == r['chronotype'],
        orElse: () => Chronotype.intermediate,
      ),
      msfScMinutes: (r['msf_sc_minutes'] as num).toDouble(),
      nightsLogged: (r['nights_logged'] as num?)?.toInt() ?? 0,
      sleepNeedMinutes: (r['sleep_need_min'] as num).toDouble(),
      sleepNeedIsPersonalised: r['sleep_need_source'] == 'personalised',
      caffeineHalfLifeMinutes: (r['caffeine_half_life_min'] as num).toDouble(),
      caffeineThresholdMg: (r['caffeine_threshold_mg'] as num).toDouble(),
      typicalCaffeineMg: (r['typical_caffeine_mg'] as num).toDouble(),
      activeProtocol: ProtocolKind.values.firstWhere(
        (p) => p.name == r['active_protocol'],
        orElse: () => ProtocolKind.reset,
      ),
      isPro: r['entitlement'] == 'pro',
      onboarded: r['onboarded_at'] != null,
      disclaimerAcknowledged: r['disclaimer_ack_at'] != null,
      goal: r['goal'] as String?,
      wakeDifficulty: (r['wake_difficulty'] as num?)?.toInt() ?? 2,
      location: lat != null && lon != null
          ? GeoLocation(
              latitude: lat,
              longitude: lon,
              tzId: r['tz_id'] as String? ?? 'UTC',
              label: r['city_label'] as String?,
            )
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Sleep
  // ---------------------------------------------------------------------------

  Stream<List<SleepSession>> watchSleepSessions({int limitDays = 60}) =>
      _watch({Tables.sleep}, () => getSleepSessions(limitDays: limitDays));

  Future<List<SleepSession>> getSleepSessions({int limitDays = 60}) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: limitDays))
        .millisecondsSinceEpoch;
    final rows = await _db.raw.query(
      Tables.sleep,
      where: 'deleted_at IS NULL AND start_utc > ?',
      whereArgs: [cutoff],
      orderBy: 'start_utc DESC',
    );
    return rows.map(_mapSleep).toList();
  }

  Future<SleepSession?> sessionForNight(String nightOf) async {
    final rows = await _db.raw.query(
      Tables.sleep,
      where: 'deleted_at IS NULL AND night_of = ?',
      whereArgs: [nightOf],
      limit: 1,
    );
    return rows.isEmpty ? null : _mapSleep(rows.first);
  }

  /// Optimistic write: returns after the local insert, outbox carries it later.
  Future<SleepSession> logSleep({
    required DateTime startUtc,
    required DateTime endUtc,
    required String tzId,
    required String nightOf,
    SleepSource source = SleepSource.manual,
    int? quality,
    int? latencyMin,
    int? awakenings,
    String? note,
    String? replaceId,
  }) async {
    final id = replaceId ?? _uuid.v4();
    final now = DateTime.now().toUtc();

    await _db.raw.insert(
      Tables.sleep,
      {
        'id': id,
        'start_utc': startUtc.millisecondsSinceEpoch,
        'end_utc': endUtc.millisecondsSinceEpoch,
        'tz_id': tzId,
        'night_of': nightOf,
        'quality': quality,
        'source': source.name,
        'latency_min': latencyMin,
        'awakenings': awakenings,
        'note': note,
        'deleted_at': null,
        'updated_at': now.millisecondsSinceEpoch,
        'sync_state': SyncStates.pending,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _enqueue('sleepSessions', id, 'upsert', {
      'startUtc': startUtc.millisecondsSinceEpoch,
      'endUtc': endUtc.millisecondsSinceEpoch,
      'nightOf': nightOf,
      'source': source.name,
    });
    await _refreshNightsLogged();
    _db.notify({Tables.sleep, Tables.profile});

    return SleepSession(
      id: id,
      startUtc: startUtc,
      endUtc: endUtc,
      tzId: tzId,
      nightOf: nightOf,
      source: source,
      quality: quality,
      latencyMin: latencyMin,
      awakenings: awakenings,
      note: note,
      updatedAt: now,
    );
  }

  /// Soft delete, so the removal syncs to a device that was offline.
  Future<void> deleteSleep(String id) async {
    await _db.raw.update(
      Tables.sleep,
      {
        'deleted_at': _now,
        'updated_at': _now,
        'sync_state': SyncStates.pending,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueue('sleepSessions', id, 'delete', const {});
    await _refreshNightsLogged();
    _db.notify({Tables.sleep, Tables.profile});
  }

  Future<void> undoDeleteSleep(String id) async {
    await _db.raw.update(
      Tables.sleep,
      {
        'deleted_at': null,
        'updated_at': _now,
        'sync_state': SyncStates.pending,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueue('sleepSessions', id, 'upsert', const {});
    await _refreshNightsLogged();
    _db.notify({Tables.sleep, Tables.profile});
  }

  /// Keeps the cached night count (which drives confidence) in step.
  ///
  /// Ensures the profile row exists first: a user can log a night before
  /// anything has read the profile, and an UPDATE against a missing row fails
  /// silently — leaving the count stuck at zero and the confidence badge
  /// permanently reading "Estimated".
  Future<void> _refreshNightsLogged() async {
    final result = await _db.raw.rawQuery(
      'SELECT COUNT(DISTINCT night_of) AS c FROM ${Tables.sleep} '
      "WHERE deleted_at IS NULL AND source != 'estimated'",
    );
    final count = (result.first['c'] as num?)?.toInt() ?? 0;

    final existing = await _db.raw.query(Tables.profile, limit: 1);
    if (existing.isEmpty) {
      await _insertProfile(UserProfile.defaults());
    }

    await _db.raw.update(
      Tables.profile,
      {'nights_logged': count, 'updated_at': _now},
      where: 'id = ?',
      whereArgs: [profileId],
    );
  }

  SleepSession _mapSleep(Map<String, Object?> r) => SleepSession(
        id: r['id'] as String,
        startUtc: DateTime.fromMillisecondsSinceEpoch(
          (r['start_utc'] as num).toInt(),
          isUtc: true,
        ),
        endUtc: DateTime.fromMillisecondsSinceEpoch(
          (r['end_utc'] as num).toInt(),
          isUtc: true,
        ),
        tzId: r['tz_id'] as String,
        nightOf: r['night_of'] as String,
        source: SleepSource.values.firstWhere(
          (s) => s.name == r['source'],
          orElse: () => SleepSource.manual,
        ),
        quality: (r['quality'] as num?)?.toInt(),
        latencyMin: (r['latency_min'] as num?)?.toInt(),
        awakenings: (r['awakenings'] as num?)?.toInt(),
        note: r['note'] as String?,
        parentId: r['parent_id'] as String?,
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (r['deleted_at'] as num).toInt(),
                isUtc: true,
              ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (r['updated_at'] as num).toInt(),
          isUtc: true,
        ),
      );

  // ---------------------------------------------------------------------------
  // Light
  // ---------------------------------------------------------------------------

  Stream<List<LoggedLight>> watchLight({int limitDays = 14}) =>
      _watch({Tables.light}, () => getLight(limitDays: limitDays));

  Future<List<LoggedLight>> getLight({int limitDays = 14}) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: limitDays))
        .millisecondsSinceEpoch;
    final rows = await _db.raw.query(
      Tables.light,
      where: 'deleted_at IS NULL AND at_utc > ?',
      whereArgs: [cutoff],
      orderBy: 'at_utc DESC',
    );
    return rows
        .map((r) => LoggedLight(
              id: r['id'] as String,
              atUtc: DateTime.fromMillisecondsSinceEpoch(
                (r['at_utc'] as num).toInt(),
                isUtc: true,
              ),
              durationMinutes: (r['duration_min'] as num).toInt(),
              kind: LightKind.values.firstWhere(
                (k) => k.name == r['kind'],
                orElse: () => LightKind.overcast,
              ),
              lux: (r['estimated_lux'] as num).toInt(),
            ))
        .toList();
  }

  Future<void> logLight({
    required DateTime atUtc,
    required String tzId,
    required int durationMinutes,
    required LightKind kind,
    required int lux,
  }) async {
    final id = _uuid.v4();
    await _db.raw.insert(Tables.light, {
      'id': id,
      'at_utc': atUtc.millisecondsSinceEpoch,
      'tz_id': tzId,
      'duration_min': durationMinutes,
      'kind': kind.name,
      'estimated_lux': lux,
      'auto_logged': 0,
      'updated_at': _now,
      'sync_state': SyncStates.pending,
    });
    await _enqueue('lightExposures', id, 'upsert', {
      'atUtc': atUtc.millisecondsSinceEpoch,
      'durationMin': durationMinutes,
      'kind': kind.name,
      'lux': lux,
    });
    _db.notify({Tables.light});
  }

  Future<void> deleteLight(String id) async {
    await _db.raw.update(
      Tables.light,
      {'deleted_at': _now, 'updated_at': _now, 'sync_state': SyncStates.pending},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueue('lightExposures', id, 'delete', const {});
    _db.notify({Tables.light});
  }

  // ---------------------------------------------------------------------------
  // Caffeine
  // ---------------------------------------------------------------------------

  Stream<List<LoggedCaffeine>> watchCaffeine({int limitDays = 7}) =>
      _watch({Tables.caffeine}, () => getCaffeine(limitDays: limitDays));

  Future<List<LoggedCaffeine>> getCaffeine({int limitDays = 7}) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: limitDays))
        .millisecondsSinceEpoch;
    final rows = await _db.raw.query(
      Tables.caffeine,
      where: 'deleted_at IS NULL AND at_utc > ?',
      whereArgs: [cutoff],
      orderBy: 'at_utc DESC',
    );
    return rows
        .map((r) => LoggedCaffeine(
              id: r['id'] as String,
              atUtc: DateTime.fromMillisecondsSinceEpoch(
                (r['at_utc'] as num).toInt(),
                isUtc: true,
              ),
              mg: (r['mg'] as num).toInt(),
              drinkKey: r['drink_key'] as String,
            ))
        .toList();
  }

  Future<void> logCaffeine({
    required DateTime atUtc,
    required String tzId,
    required int mg,
    required String drinkKey,
  }) async {
    final id = _uuid.v4();
    await _db.raw.insert(Tables.caffeine, {
      'id': id,
      'at_utc': atUtc.millisecondsSinceEpoch,
      'tz_id': tzId,
      'mg': mg,
      'drink_key': drinkKey,
      'updated_at': _now,
      'sync_state': SyncStates.pending,
    });
    await _enqueue('caffeineIntakes', id, 'upsert', {
      'atUtc': atUtc.millisecondsSinceEpoch,
      'mg': mg,
      'drinkKey': drinkKey,
    });
    _db.notify({Tables.caffeine});
  }

  Future<void> deleteCaffeine(String id) async {
    await _db.raw.update(
      Tables.caffeine,
      {'deleted_at': _now, 'updated_at': _now, 'sync_state': SyncStates.pending},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueue('caffeineIntakes', id, 'delete', const {});
    _db.notify({Tables.caffeine});
  }

  // ---------------------------------------------------------------------------
  // Energy check-ins
  // ---------------------------------------------------------------------------

  Future<void> logCheckin({
    required DateTime atUtc,
    required String tzId,
    required int rating,
  }) async {
    final id = _uuid.v4();
    await _db.raw.insert(Tables.checkins, {
      'id': id,
      'at_utc': atUtc.millisecondsSinceEpoch,
      'tz_id': tzId,
      'rating': rating,
      'updated_at': _now,
      'sync_state': SyncStates.pending,
    });
    await _enqueue('energyCheckins', id, 'upsert', {'rating': rating});
    _db.notify({Tables.checkins});
  }

  Future<int?> latestCheckinRating() async {
    final rows = await _db.raw.query(
      Tables.checkins,
      where: 'deleted_at IS NULL',
      orderBy: 'at_utc DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['rating'] as num).toInt();
  }

  // ---------------------------------------------------------------------------
  // Protocol completions
  // ---------------------------------------------------------------------------

  Stream<Set<String>> watchCompletions() =>
      _watch({Tables.completions}, getCompletions);

  Future<Set<String>> getCompletions() async {
    final rows = await _db.raw.query(
      Tables.completions,
      where: 'deleted_at IS NULL',
    );
    return rows.map((r) => r['event_key'] as String).toSet();
  }

  Future<void> completeEvent(String eventKey) async {
    await _db.raw.insert(
      Tables.completions,
      {
        'id': _uuid.v4(),
        'event_key': eventKey,
        'completed_at': _now,
        'deleted_at': null,
        'updated_at': _now,
        'sync_state': SyncStates.pending,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _enqueue('protocolCompletions', eventKey, 'upsert', {
      'eventKey': eventKey,
      'completedAt': _now,
    });
    _db.notify({Tables.completions});
  }

  Future<void> uncompleteEvent(String eventKey) async {
    await _db.raw.delete(
      Tables.completions,
      where: 'event_key = ?',
      whereArgs: [eventKey],
    );
    await _enqueue('protocolCompletions', eventKey, 'delete', const {});
    _db.notify({Tables.completions});
  }

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  Future<SleepDebt> computeDebt({
    required double needMinutes,
    required Duration Function(DateTime) utcOffsetFor,
    required DateTime asOfLocalDate,
  }) async {
    final sessions = await getSleepSessions();
    final byNight =
        SleepDebtLedger.aggregate(sessions, utcOffsetFor: utcOffsetFor);
    return SleepDebtLedger.compute(
      sleepByNight: byNight,
      needMinutes: needMinutes,
      asOfDateLocal: asOfLocalDate,
    );
  }

  // ---------------------------------------------------------------------------
  // Outbox
  // ---------------------------------------------------------------------------

  Future<void> _enqueue(
    String collection,
    String docId,
    String op,
    Map<String, Object?> payload,
  ) async {
    await _db.raw.insert(Tables.outbox, {
      'collection': collection,
      'doc_id': docId,
      'op': op,
      'payload': jsonEncode(payload),
      'attempt': 0,
      'next_try_at': 0,
    });
  }

  /// How many local writes are waiting for a connection. Surfaced in
  /// Settings → Sync, never as a blocking banner.
  Stream<int> watchPendingSyncCount() =>
      _watch({Tables.outbox, Tables.sleep, Tables.light, Tables.caffeine},
          pendingSyncCount);

  Future<int> pendingSyncCount() async {
    final rows =
        await _db.raw.rawQuery('SELECT COUNT(*) AS c FROM ${Tables.outbox}');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> clearOutbox(List<int> seqs) async {
    if (seqs.isEmpty) return;
    final placeholders = List.filled(seqs.length, '?').join(',');
    await _db.raw.delete(
      Tables.outbox,
      where: 'seq IN ($placeholders)',
      whereArgs: seqs,
    );
    _db.notify({Tables.outbox});
  }

  /// Wipes all local data — used by sign-out and account deletion.
  Future<void> wipe() async {
    await _db.raw.transaction((txn) async {
      for (final table in [
        Tables.sleep,
        Tables.light,
        Tables.caffeine,
        Tables.checkins,
        Tables.completions,
        Tables.outbox,
        Tables.profile,
      ]) {
        await txn.delete(table);
      }
    });
    _db.notify({
      Tables.sleep,
      Tables.light,
      Tables.caffeine,
      Tables.checkins,
      Tables.completions,
      Tables.outbox,
      Tables.profile,
    });
  }
}
