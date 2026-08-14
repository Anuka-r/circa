import 'package:circa/data/local/database.dart';
import 'package:circa/data/repositories/circa_repository.dart';
import 'package:circa/domain/chrono/light_prc.dart';
import 'package:circa/domain/chrono/protocol_engine.dart';
import 'package:circa/domain/chrono/sleep_debt_ledger.dart';
import 'package:circa/domain/entities/sleep_session.dart';
import 'package:circa/domain/value_objects/geo_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;
  late CircaRepository repo;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    repo = CircaRepository(db);
  });

  tearDown(() async => db.close());

  group('Profile', () {
    test('creates sane defaults on first read', () async {
      final profile = await repo.getProfile();
      expect(profile.id, CircaRepository.profileId);
      expect(profile.onboarded, isFalse);
      expect(profile.isPro, isFalse);
      expect(profile.sleepNeedMinutes, 480);
      expect(profile.activeProtocol, ProtocolKind.reset);
    });

    test('round-trips every field it persists', () async {
      final original = await repo.getProfile();
      final updated = original.copyWith(
        onboarded: true,
        disclaimerAcknowledged: true,
        goal: 'More energy',
        wakeDifficulty: 3,
        typicalCaffeineMg: 190,
        activeProtocol: ProtocolKind.earlyRiser,
        location: const GeoLocation(
          latitude: 38.7223,
          longitude: -9.1393,
          tzId: 'Europe/Lisbon',
          label: 'Lisbon, Portugal',
        ),
      );

      await repo.saveProfile(updated);
      final reloaded = await repo.getProfile();

      expect(reloaded.onboarded, isTrue);
      expect(reloaded.disclaimerAcknowledged, isTrue);
      expect(reloaded.goal, 'More energy');
      expect(reloaded.wakeDifficulty, 3);
      expect(reloaded.typicalCaffeineMg, 190);
      expect(reloaded.activeProtocol, ProtocolKind.earlyRiser);
      expect(reloaded.location?.tzId, 'Europe/Lisbon');
      expect(reloaded.location?.label, 'Lisbon, Portugal');
      expect(reloaded.location?.latitude, closeTo(38.7223, 1e-6));
    });

    test('falls back to a real location rather than blanking the app',
        () async {
      final profile = await repo.getProfile();
      expect(profile.location, isNull);
      expect(profile.effectiveLocation.tzId, isNotEmpty);
      expect(profile.effectiveLocation.label, isNotNull);
    });
  });

  group('Sleep', () {
    Future<SleepSession> logNight({
      required int daysAgo,
      int hours = 8,
      String? id,
    }) {
      final wake = DateTime.utc(2026, 7, 22, 7)
          .subtract(Duration(days: daysAgo));
      final bed = wake.subtract(Duration(hours: hours));
      return repo.logSleep(
        startUtc: bed,
        endUtc: wake,
        tzId: 'UTC',
        nightOf: SleepDebtLedger.nightOfLocal(bed),
        quality: 4,
        replaceId: id,
      );
    }

    test('write is visible immediately — reads never wait on a network',
        () async {
      await logNight(daysAgo: 0);
      final sessions = await repo.getSleepSessions();
      expect(sessions, hasLength(1));
      expect(sessions.first.duration.inHours, 8);
      expect(sessions.first.quality, 4);
      expect(sessions.first.source, SleepSource.manual);
    });

    test('queues every write in the outbox for later replay', () async {
      expect(await repo.pendingSyncCount(), 0);
      await logNight(daysAgo: 0);
      await logNight(daysAgo: 1);
      expect(await repo.pendingSyncCount(), 2);
    });

    test('re-logging the same night replaces rather than duplicates',
        () async {
      final first = await logNight(daysAgo: 0, hours: 6);
      final existing = await repo.sessionForNight(first.nightOf);
      expect(existing, isNotNull);

      await logNight(daysAgo: 0, hours: 9, id: existing!.id);

      final sessions = await repo.getSleepSessions();
      expect(sessions, hasLength(1));
      expect(sessions.first.duration.inHours, 9);
    });

    test('delete is soft, and undo restores the row intact', () async {
      final session = await logNight(daysAgo: 0);
      await repo.deleteSleep(session.id);
      expect(await repo.getSleepSessions(), isEmpty);

      await repo.undoDeleteSleep(session.id);
      final restored = await repo.getSleepSessions();
      expect(restored, hasLength(1));
      expect(restored.first.id, session.id);
      expect(restored.first.duration.inHours, 8);
    });

    test('night count tracks distinct nights, not rows', () async {
      await logNight(daysAgo: 0);
      await logNight(daysAgo: 1);
      await logNight(daysAgo: 2);
      expect((await repo.getProfile()).nightsLogged, 3);

      // Overwriting one night must not inflate the count.
      final existing = await repo.sessionForNight(
        (await repo.getSleepSessions()).first.nightOf,
      );
      await logNight(daysAgo: 0, hours: 7, id: existing!.id);
      expect((await repo.getProfile()).nightsLogged, 3);
    });

    test('deleting a night decrements the count', () async {
      final a = await logNight(daysAgo: 0);
      await logNight(daysAgo: 1);
      expect((await repo.getProfile()).nightsLogged, 2);
      await repo.deleteSleep(a.id);
      expect((await repo.getProfile()).nightsLogged, 1);
    });

    test('watchers re-emit when a night is written', () async {
      // take(2) auto-cancels once both events have arrived, so this can never
      // hang on a stream that stays open by design.
      final collected = repo.watchSleepSessions().take(2).toList();

      await Future<void>.delayed(const Duration(milliseconds: 30));
      await logNight(daysAgo: 0);

      final emissions = await collected.timeout(const Duration(seconds: 5));
      expect(emissions.first, isEmpty, reason: 'first emission is the seed');
      expect(emissions.last, hasLength(1), reason: 'then the new night');
    });

    test('computes debt end-to-end from stored nights', () async {
      // Five consecutive 6-hour nights against an 8-hour need.
      for (var i = 0; i < 5; i++) {
        await logNight(daysAgo: i, hours: 6);
      }
      final debt = await repo.computeDebt(
        needMinutes: 480,
        utcOffsetFor: (_) => Duration.zero,
        asOfLocalDate: DateTime(2026, 7, 22),
      );
      expect(debt.hours, greaterThan(3));
      expect(debt.nightsLogged, 5);
    });
  });

  group('Light and caffeine', () {
    test('light exposures round-trip with their kind and lux', () async {
      await repo.logLight(
        atUtc: DateTime.utc(2026, 7, 22, 8),
        tzId: 'UTC',
        durationMinutes: 15,
        kind: LightKind.directSun,
        lux: 55000,
      );
      final logged = await repo.getLight();
      expect(logged, hasLength(1));
      expect(logged.first.kind, LightKind.directSun);
      expect(logged.first.lux, 55000);
      expect(logged.first.durationMinutes, 15);
    });

    test('caffeine intakes round-trip and convert to doses', () async {
      await repo.logCaffeine(
        atUtc: DateTime.utc(2026, 7, 22, 9),
        tzId: 'UTC',
        mg: 95,
        drinkKey: 'drip',
      );
      final logged = await repo.getCaffeine();
      expect(logged, hasLength(1));
      expect(logged.first.mg, 95);
      expect(logged.first.toDose().mg, 95);
    });

    test('deleted entries disappear from reads', () async {
      await repo.logCaffeine(
        atUtc: DateTime.utc(2026, 7, 22, 9),
        tzId: 'UTC',
        mg: 95,
        drinkKey: 'drip',
      );
      final logged = await repo.getCaffeine();
      await repo.deleteCaffeine(logged.first.id);
      expect(await repo.getCaffeine(), isEmpty);
    });
  });

  group('Protocol completions', () {
    test('completing twice is idempotent', () async {
      await repo.completeEvent('2026-07-22:seekLight');
      await repo.completeEvent('2026-07-22:seekLight');
      expect(await repo.getCompletions(), {'2026-07-22:seekLight'});
    });

    test('uncompleting removes it', () async {
      await repo.completeEvent('2026-07-22:seekLight');
      await repo.uncompleteEvent('2026-07-22:seekLight');
      expect(await repo.getCompletions(), isEmpty);
    });
  });

  group('Outbox', () {
    test('draining clears only the acknowledged rows', () async {
      await repo.logCaffeine(
        atUtc: DateTime.utc(2026, 7, 22, 9),
        tzId: 'UTC',
        mg: 95,
        drinkKey: 'drip',
      );
      await repo.logCaffeine(
        atUtc: DateTime.utc(2026, 7, 22, 11),
        tzId: 'UTC',
        mg: 63,
        drinkKey: 'espresso',
      );
      expect(await repo.pendingSyncCount(), 2);

      final rows = await db.raw.query(Tables.outbox, orderBy: 'seq');
      await repo.clearOutbox([rows.first['seq']! as int]);
      expect(await repo.pendingSyncCount(), 1);
    });
  });

  group('Wipe', () {
    test('removes everything, as account deletion requires', () async {
      await repo.logSleep(
        startUtc: DateTime.utc(2026, 7, 21, 23),
        endUtc: DateTime.utc(2026, 7, 22, 7),
        tzId: 'UTC',
        nightOf: '2026-07-21',
      );
      await repo.logCaffeine(
        atUtc: DateTime.utc(2026, 7, 22, 9),
        tzId: 'UTC',
        mg: 95,
        drinkKey: 'drip',
      );
      await repo.completeEvent('2026-07-22:seekLight');

      await repo.wipe();

      expect(await repo.getSleepSessions(), isEmpty);
      expect(await repo.getCaffeine(), isEmpty);
      expect(await repo.getCompletions(), isEmpty);
      expect(await repo.pendingSyncCount(), 0);
    });
  });
}
