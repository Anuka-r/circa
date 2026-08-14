import 'dart:math' as math;

import 'package:circa/domain/chrono/caffeine_model.dart';
import 'package:circa/domain/chrono/chronotype_estimator.dart';
import 'package:circa/domain/chrono/circadian_phase_model.dart';
import 'package:circa/domain/chrono/light_prc.dart';
import 'package:circa/domain/chrono/sleep_debt_ledger.dart';
import 'package:circa/domain/chrono/two_process_model.dart';
import 'package:circa/domain/entities/sleep_session.dart';
import 'package:circa/domain/value_objects/chronotype.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  group('LightPrc', () {
    test('crosses zero exactly at CBTmin', () {
      expect(LightPrc.responseAt(0), closeTo(0, 1e-9));
    });

    test('light after CBTmin advances, light before it delays', () {
      expect(LightPrc.responseAt(2), greaterThan(0), reason: 'morning advances');
      expect(LightPrc.responseAt(-3), lessThan(0), reason: 'evening delays');
    });

    test('peak advance is ~+1.0 h and lands ~2-3 h after CBTmin', () {
      var bestTau = 0.0;
      var best = -99.0;
      for (var t = 0.0; t <= 12; t += 0.05) {
        final v = LightPrc.responseAt(t);
        if (v > best) {
          best = v;
          bestTau = t;
        }
      }
      expect(best, closeTo(1.0, 0.05));
      expect(bestTau, inInclusiveRange(1.8, 3.0));
    });

    test('peak delay is ~-0.9 h and lands ~3-4 h before CBTmin', () {
      var bestTau = 0.0;
      var best = 99.0;
      for (var t = -12.0; t < 0; t += 0.05) {
        final v = LightPrc.responseAt(t);
        if (v < best) {
          best = v;
          bestTau = t;
        }
      }
      expect(best, closeTo(-0.9, 0.05));
      expect(bestTau, inInclusiveRange(-4.2, -3.0));
    });

    test('advancing is harder than delaying — the asymmetry is real', () {
      expect(LightPrc.maxAdvancePerDay, lessThan(LightPrc.maxDelayPerDay));
    });

    test('mid-afternoon is a dead zone', () {
      // ~8-10 h after CBTmin, i.e. early afternoon for a 05:00 CBTmin.
      for (final tau in [8.0, 9.0, 10.0]) {
        expect(LightPrc.responseAt(tau).abs(), lessThan(0.06),
            reason: 'tau=$tau should be inert');
      }
    });

    test('evening light retains a meaningful delaying effect', () {
      // 21:00 for a 05:00 CBTmin is tau = -8.
      expect(LightPrc.responseAt(-8), lessThan(-0.15));
    });

    test('is monotonic within the advance lobe up to its peak', () {
      var previous = LightPrc.responseAt(0);
      for (var t = 0.05; t <= 2.0; t += 0.05) {
        final v = LightPrc.responseAt(t);
        expect(v, greaterThanOrEqualTo(previous - 1e-9));
        previous = v;
      }
    });

    test('intensity response saturates', () {
      expect(LightPrc.intensityFactor(0), 0);
      expect(LightPrc.intensityFactor(100), closeTo(0.29, 0.03));
      expect(LightPrc.intensityFactor(1000), closeTo(0.59, 0.03));
      expect(LightPrc.intensityFactor(10000), closeTo(0.84, 0.03));
      expect(LightPrc.intensityFactor(50000), closeTo(0.93, 0.03));

      // Doubling lux must never double the effect.
      final a = LightPrc.intensityFactor(1000);
      final b = LightPrc.intensityFactor(2000);
      expect(b, lessThan(a * 2));
    });

    test('duration response saturates — the first ten minutes matter most', () {
      expect(LightPrc.durationFactor(0), 0);
      final ten = LightPrc.durationFactor(10);
      final twenty = LightPrc.durationFactor(20);
      final sixty = LightPrc.durationFactor(60);
      expect(twenty, lessThan(ten * 2));
      expect(sixty, greaterThan(0.9));
    });

    test('daily shift is clamped to the physiological ceiling', () {
      final cbt = DateTime.utc(2026, 7, 22, 5);
      // An absurd amount of perfectly-timed light.
      final exposures = List.generate(
        20,
        (i) => LightExposure(
          atUtc: cbt.add(const Duration(hours: 2)),
          durationMinutes: 120,
          lux: 100000,
        ),
      );
      final shift = LightPrc.totalShift(exposures: exposures, cbtMinUtc: cbt);
      expect(shift.rawHours, greaterThan(LightPrc.maxAdvancePerDay));
      expect(shift.cappedHours, LightPrc.maxAdvancePerDay);
      expect(shift.wasCapped, isTrue);
    });

    test('no exposures means no shift', () {
      final shift = LightPrc.totalShift(
        exposures: const [],
        cbtMinUtc: DateTime.utc(2026, 7, 22, 5),
      );
      expect(shift.cappedHours, 0);
    });
  });

  // ---------------------------------------------------------------------------
  group('CaffeineModel', () {
    final noon = DateTime.utc(2026, 7, 22, 12);

    test('on-board amount decays by half every half-life', () {
      final doses = [CaffeineDose(atUtc: noon, mg: 100)];
      const halfLife = 300.0; // 5 h, for clean arithmetic

      double at(double minutes) => CaffeineModel.onBoardMg(
            doses: doses,
            atUtc: noon.add(Duration(minutes: minutes.round())),
            halfLifeMinutes: halfLife,
          );

      expect(at(0), closeTo(100, 0.5));
      expect(at(halfLife), closeTo(50, 0.5));
      expect(at(halfLife * 2), closeTo(25, 0.5));
      expect(at(halfLife * 3), closeTo(12.5, 0.5));
    });

    test('plasma level ramps up rather than jumping', () {
      final doses = [CaffeineDose(atUtc: noon, mg: 100)];
      final immediately = CaffeineModel.plasmaMg(doses: doses, atUtc: noon);
      final halfway = CaffeineModel.plasmaMg(
        doses: doses,
        atUtc: noon.add(const Duration(minutes: 22)),
      );
      expect(immediately, closeTo(0, 0.01));
      expect(halfway, closeTo(49, 3));
    });

    test(
        'a dose taken at bedtime is fully on board even though plasma is still '
        'near zero', () {
      // The bug this guards against: using plasma for the bedtime check would
      // score an espresso at bedtime as harmless.
      final doses = [CaffeineDose(atUtc: noon, mg: 95)];
      expect(CaffeineModel.plasmaMg(doses: doses, atUtc: noon), closeTo(0, 0.01));
      expect(CaffeineModel.onBoardMg(doses: doses, atUtc: noon), closeTo(95, 0.01));
    });

    test('ignores doses in the future', () {
      final doses = [
        CaffeineDose(atUtc: noon.add(const Duration(hours: 3)), mg: 200),
      ];
      expect(CaffeineModel.plasmaMg(doses: doses, atUtc: noon), 0);
      expect(CaffeineModel.onBoardMg(doses: doses, atUtc: noon), 0);
    });

    test('doses accumulate', () {
      final doses = [
        CaffeineDose(atUtc: noon, mg: 100),
        CaffeineDose(atUtc: noon, mg: 100),
      ];
      final single = CaffeineModel.plasmaMg(
        doses: [doses.first],
        atUtc: noon.add(const Duration(hours: 3)),
      );
      final both = CaffeineModel.plasmaMg(
        doses: doses,
        atUtc: noon.add(const Duration(hours: 3)),
      );
      expect(both, closeTo(single * 2, 0.01));
    });

    test('closed-form cutoff matches a numerical solve to within a minute', () {
      final bedtime = DateTime.utc(2026, 7, 22, 23);
      const planned = 95.0;
      const threshold = 30.0;

      final closedForm = CaffeineModel.cutoffTime(
        bedtimeUtc: bedtime,
        plannedMg: planned,
        thresholdMg: threshold,
      )!;

      // Numerical: walk back from bedtime until a dose taken then would still
      // leave more than the threshold on board at bedtime.
      DateTime? numerical;
      for (var m = 0; m < 24 * 60; m++) {
        final candidate = bedtime.subtract(Duration(minutes: m));
        final onBoard = CaffeineModel.onBoardMg(
          doses: [CaffeineDose(atUtc: candidate, mg: planned)],
          atUtc: bedtime,
        );
        if (onBoard <= threshold) {
          numerical = candidate;
          break;
        }
      }

      expect(numerical, isNotNull);
      expect(
        closedForm.difference(numerical!).inMinutes.abs(),
        lessThanOrEqualTo(1),
      );
    });

    test('a 95 mg coffee against a 23:00 bedtime cuts off in the afternoon', () {
      final bedtime = DateTime.utc(2026, 7, 22, 23);
      final cutoff = CaffeineModel.cutoffTime(
        bedtimeUtc: bedtime,
        plannedMg: 95,
        thresholdMg: 30,
      )!;
      // This is the number that surprises people. Keep it honest.
      expect(cutoff.hour, inInclusiveRange(12, 15));
    });

    test('a dose already under threshold needs no cutoff', () {
      final bedtime = DateTime.utc(2026, 7, 22, 23);
      final cutoff = CaffeineModel.cutoffTime(
        bedtimeUtc: bedtime,
        plannedMg: 10,
        thresholdMg: 30,
      );
      expect(cutoff, bedtime);
    });

    test('more sensitive means an earlier cutoff', () {
      final bedtime = DateTime.utc(2026, 7, 22, 23);
      DateTime cutoffFor(CaffeineSensitivity s) => CaffeineModel.cutoffTime(
            bedtimeUtc: bedtime,
            plannedMg: 95,
            thresholdMg: s.bedtimeThresholdMg.toDouble(),
          )!;
      expect(
        cutoffFor(CaffeineSensitivity.sensitive)
            .isBefore(cutoffFor(CaffeineSensitivity.typical)),
        isTrue,
      );
      expect(
        cutoffFor(CaffeineSensitivity.typical)
            .isBefore(cutoffFor(CaffeineSensitivity.tolerant)),
        isTrue,
      );
    });

    test('alertness effect saturates', () {
      expect(CaffeineModel.alertnessEffect(0), 0);
      expect(CaffeineModel.alertnessEffect(120), closeTo(0.5, 0.001));
      expect(CaffeineModel.alertnessEffect(1000), lessThan(1.0));
      expect(
        CaffeineModel.alertnessEffect(400),
        lessThan(CaffeineModel.alertnessEffect(200) * 2),
      );
    });

    test('headroom is zero once already over budget at bedtime', () {
      final bedtime = DateTime.utc(2026, 7, 22, 23);
      final headroom = CaffeineModel.headroomMg(
        doses: [CaffeineDose(atUtc: DateTime.utc(2026, 7, 22, 21), mg: 200)],
        nowUtc: DateTime.utc(2026, 7, 22, 22),
        bedtimeUtc: bedtime,
        thresholdMg: 30,
      );
      expect(headroom, 0);
    });

    test('every drink preset is well-formed and uniquely keyed', () {
      final keys = DrinkPreset.all.map((d) => d.key).toSet();
      expect(keys.length, DrinkPreset.all.length);
      for (final d in DrinkPreset.all) {
        expect(d.mg, greaterThan(0));
        expect(d.label, isNotEmpty);
        expect(DrinkPreset.byKey(d.key), same(d));
      }
      expect(DrinkPreset.byKey('not-a-drink'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('SleepDebtLedger', () {
    final today = DateTime(2026, 7, 22);
    const need = 480.0; // 8 h

    Map<String, double> nightsOf(List<double> minutesNewestFirst) {
      final map = <String, double>{};
      for (var i = 0; i < minutesNewestFirst.length; i++) {
        final date = today.subtract(Duration(days: i));
        map[SleepDebtLedger.formatNight(date)] = minutesNewestFirst[i];
      }
      return map;
    }

    test('a perfectly slept fortnight has zero debt', () {
      final debt = SleepDebtLedger.compute(
        sleepByNight: nightsOf(List.filled(14, need)),
        needMinutes: need,
        asOfDateLocal: today,
      );
      expect(debt.minutes, closeTo(0, 0.001));
      expect(debt.isClear, isTrue);
      expect(debt.nightsLogged, 14);
    });

    test('accumulates debt from short nights', () {
      final debt = SleepDebtLedger.compute(
        sleepByNight: nightsOf(List.filled(7, 360)), // 6 h each
        needMinutes: need,
        asOfDateLocal: today,
      );
      expect(debt.hours, greaterThan(4));
      expect(debt.hours, lessThan(14));
    });

    test('is always within [0, 20 h]', () {
      final huge = SleepDebtLedger.compute(
        sleepByNight: nightsOf(List.filled(14, 0)),
        needMinutes: need,
        asOfDateLocal: today,
      );
      expect(huge.minutes, inInclusiveRange(0, SleepDebtLedger.maxDebtMinutes));

      final oversleep = SleepDebtLedger.compute(
        sleepByNight: nightsOf(List.filled(14, 720)), // 12 h each
        needMinutes: need,
        asOfDateLocal: today,
      );
      expect(oversleep.minutes, 0, reason: 'debt can never go negative');
    });

    test('adding sleep never increases debt', () {
      final rng = math.Random(20260722);
      for (var trial = 0; trial < 60; trial++) {
        final base =
            List.generate(14, (_) => 240.0 + rng.nextInt(360).toDouble());
        final improved = base.map((m) => m + 30).toList();

        final a = SleepDebtLedger.compute(
          sleepByNight: nightsOf(base),
          needMinutes: need,
          asOfDateLocal: today,
        );
        final b = SleepDebtLedger.compute(
          sleepByNight: nightsOf(improved),
          needMinutes: need,
          asOfDateLocal: today,
        );
        expect(b.minutes, lessThanOrEqualTo(a.minutes + 1e-9),
            reason: 'more sleep must not mean more debt');
      }
    });

    test('older deficits weigh less than recent ones', () {
      // One 4-hour deficit, last night vs 13 nights ago.
      final recent = SleepDebtLedger.compute(
        sleepByNight: {SleepDebtLedger.formatNight(today): 240.0},
        needMinutes: need,
        asOfDateLocal: today,
      );
      final old = SleepDebtLedger.compute(
        sleepByNight: {
          SleepDebtLedger.formatNight(
            today.subtract(const Duration(days: 13)),
          ): 240.0,
        },
        needMinutes: need,
        asOfDateLocal: today,
      );
      expect(old.minutes, lessThan(recent.minutes * 0.25));
    });

    test('decay half-life is about 4.85 days', () {
      final decayAt5 = math.exp(-5 / SleepDebtLedger.decayTauDays);
      expect(decayAt5, closeTo(0.49, 0.02));
    });

    test('nights outside the 14-day window are ignored', () {
      final debt = SleepDebtLedger.compute(
        sleepByNight: {
          SleepDebtLedger.formatNight(
            today.subtract(const Duration(days: 20)),
          ): 0.0,
        },
        needMinutes: need,
        asOfDateLocal: today,
      );
      expect(debt.minutes, 0);
      expect(debt.nightsLogged, 0);
    });

    test('an unlogged night contributes nothing rather than a fake deficit', () {
      final debt = SleepDebtLedger.compute(
        sleepByNight: const {},
        needMinutes: need,
        asOfDateLocal: today,
      );
      expect(debt.minutes, 0);
      expect(debt.nights.every((n) => !n.wasLogged), isTrue);
      expect(debt.nights.length, SleepDebtLedger.windowDays);
    });

    test('surplus repays at half rate', () {
      // 2 h deficit last night, then a 2 h surplus tonight should leave debt.
      final debt = SleepDebtLedger.compute(
        sleepByNight: nightsOf([need + 120, need - 120]),
        needMinutes: need,
        asOfDateLocal: today,
      );
      expect(debt.minutes, greaterThan(0),
          reason: 'one big lie-in does not undo a short night');
    });

    test('recovery projection is honest about how many nights it takes', () {
      const debt = SleepDebt(minutes: 300, nights: [], nightsLogged: 14);
      // 60 min surplus repays 30 min/night → 10 nights.
      expect(debt.nightsToClear(surplusMinutesPerNight: 60), 10);
      expect(debt.nightsToClear(surplusMinutesPerNight: 0), 0);
    });

    test('nightOf anchors noon-to-noon so a night is never split', () {
      // 23:40 on the 5th and 00:20 on the 6th are the same night.
      expect(
        SleepDebtLedger.nightOfLocal(DateTime(2026, 7, 5, 23, 40)),
        '2026-07-05',
      );
      expect(
        SleepDebtLedger.nightOfLocal(DateTime(2026, 7, 6, 0, 20)),
        '2026-07-05',
      );
      // Midday belongs to the night that starts that evening.
      expect(
        SleepDebtLedger.nightOfLocal(DateTime(2026, 7, 6, 13)),
        '2026-07-06',
      );
    });

    test('Health data outranks a manual entry for the same night', () {
      final start = DateTime.utc(2026, 7, 21, 22);
      SleepSession make(SleepSource source, int hours) => SleepSession(
            id: '$source',
            startUtc: start,
            endUtc: start.add(Duration(hours: hours)),
            tzId: 'UTC',
            nightOf: '2026-07-21',
            source: source,
            updatedAt: DateTime.utc(2026, 7, 22),
          );

      final totals = SleepDebtLedger.aggregate(
        [make(SleepSource.manual, 8), make(SleepSource.health, 6)],
        utcOffsetFor: (_) => Duration.zero,
      );
      expect(totals['2026-07-21'], 360, reason: 'Health (6 h) should win');
    });

    test('biphasic segments from the same source add together', () {
      final start = DateTime.utc(2026, 7, 21, 22);
      final totals = SleepDebtLedger.aggregate(
        [
          SleepSession(
            id: 'a',
            startUtc: start,
            endUtc: start.add(const Duration(hours: 4)),
            tzId: 'UTC',
            nightOf: '2026-07-21',
            source: SleepSource.manual,
            updatedAt: start,
          ),
          SleepSession(
            id: 'b',
            startUtc: start.add(const Duration(hours: 5)),
            endUtc: start.add(const Duration(hours: 8)),
            tzId: 'UTC',
            nightOf: '2026-07-21',
            source: SleepSource.manual,
            updatedAt: start,
          ),
        ],
        utcOffsetFor: (_) => Duration.zero,
      );
      expect(totals['2026-07-21'], 420); // 4 h + 3 h
    });

    test('deleted and estimated sessions are excluded', () {
      final start = DateTime.utc(2026, 7, 21, 22);
      final totals = SleepDebtLedger.aggregate(
        [
          SleepSession(
            id: 'deleted',
            startUtc: start,
            endUtc: start.add(const Duration(hours: 8)),
            tzId: 'UTC',
            nightOf: '2026-07-21',
            source: SleepSource.manual,
            deletedAt: start,
            updatedAt: start,
          ),
          SleepSession(
            id: 'estimated',
            startUtc: start,
            endUtc: start.add(const Duration(hours: 8)),
            tzId: 'UTC',
            nightOf: '2026-07-20',
            source: SleepSource.estimated,
            updatedAt: start,
          ),
        ],
        utcOffsetFor: (_) => Duration.zero,
      );
      expect(totals, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('TwoProcessModel', () {
    // A conventional schedule: asleep 23:00–07:00, CBTmin at 05:00.
    List<SleepWindow> nightlySleep(int days) => List.generate(
          days + 2,
          (i) => SleepWindow(
            startUtc: DateTime.utc(2026, 7, 18).add(Duration(days: i, hours: 23)),
            endUtc: DateTime.utc(2026, 7, 19).add(Duration(days: i, hours: 7)),
          ),
        );

    List<EnergyPoint> dayCurve() => TwoProcessModel.simulate(
          fromUtc: DateTime.utc(2026, 7, 22, 7),
          toUtc: DateTime.utc(2026, 7, 22, 23),
          sleepWindows: nightlySleep(8),
          cbtMinLocalHour: 5.0,
          utcOffset: Duration.zero,
        );

    test('produces a continuous curve within [0,1]', () {
      final points = dayCurve();
      expect(points, isNotEmpty);
      for (final p in points) {
        expect(p.alertness, inInclusiveRange(0.0, 1.0));
        expect(p.processS, inInclusiveRange(0.0, 1.0));
        expect(p.processC, inInclusiveRange(-2.0, 2.0));
      }
    });

    test('sleep pressure falls during sleep and rises while awake', () {
      final overnight = TwoProcessModel.simulate(
        fromUtc: DateTime.utc(2026, 7, 21, 22),
        toUtc: DateTime.utc(2026, 7, 22, 12),
        sleepWindows: nightlySleep(8),
        cbtMinLocalHour: 5.0,
        utcOffset: Duration.zero,
      );
      final atBed = overnight.firstWhere((p) => p.atUtc.hour == 23).processS;
      final atWake = overnight.firstWhere(
        (p) => p.atUtc.day == 22 && p.atUtc.hour == 7,
      ).processS;
      final atNoon = overnight.firstWhere(
        (p) => p.atUtc.day == 22 && p.atUtc.hour == 12,
      ).processS;

      expect(atWake, lessThan(atBed), reason: 'sleep should dissipate pressure');
      expect(atNoon, greaterThan(atWake), reason: 'waking rebuilds pressure');
    });

    test('sleep inertia decays within about an hour of waking', () {
      final points = TwoProcessModel.simulate(
        fromUtc: DateTime.utc(2026, 7, 22, 7),
        toUtc: DateTime.utc(2026, 7, 22, 9),
        sleepWindows: nightlySleep(8),
        cbtMinLocalHour: 5.0,
        utcOffset: Duration.zero,
      );
      final justAwake = points.first;
      final anHourLater =
          points.firstWhere((p) => p.atUtc.hour == 8 && p.atUtc.minute == 10);
      expect(justAwake.inertia, greaterThan(0.3));
      expect(anHourLater.inertia, lessThan(0.05));
    });

    test('reproduces the three features people recognise in their own day', () {
      final points = dayCurve();
      final features = TwoProcessModel.findFeatures(points);

      final morning = features
          .where((f) => f.kind == EnergyFeatureKind.morningPeak)
          .toList();
      final dip = features
          .where((f) => f.kind == EnergyFeatureKind.afternoonDip)
          .toList();
      final evening = features
          .where((f) => f.kind == EnergyFeatureKind.eveningPeak)
          .toList();

      expect(morning, isNotEmpty, reason: 'expected a late-morning peak');
      expect(dip, isNotEmpty, reason: 'expected an afternoon dip');
      expect(evening, isNotEmpty, reason: 'expected an evening rebound');

      // Wake is 07:00, so the dip should land mid-afternoon.
      final dipHour = dip.first.atUtc.hour;
      expect(dipHour, inInclusiveRange(13, 17),
          reason: 'afternoon dip landed at $dipHour:00');

      // And it must be visible on a chart, not a rounding artefact.
      final depth = morning.first.alertness - dip.first.alertness;
      expect(depth, greaterThan(0.05),
          reason: 'dip depth of $depth would be invisible');
    });

    test('a short night lowers the whole day versus a full night', () {
      List<EnergyPoint> withSleepHours(int hours) => TwoProcessModel.simulate(
            fromUtc: DateTime.utc(2026, 7, 22, 8),
            toUtc: DateTime.utc(2026, 7, 22, 20),
            sleepWindows: List.generate(
              10,
              (i) => SleepWindow(
                startUtc: DateTime.utc(2026, 7, 14)
                    .add(Duration(days: i, hours: 23)),
                endUtc: DateTime.utc(2026, 7, 14)
                    .add(Duration(days: i, hours: 23 + hours)),
              ),
            ),
            cbtMinLocalHour: 5.0,
            utcOffset: Duration.zero,
          );

      double mean(List<EnergyPoint> ps) =>
          ps.map((p) => p.alertness).reduce((a, b) => a + b) / ps.length;

      expect(mean(withSleepHours(5)), lessThan(mean(withSleepHours(8))));
    });

    test('caffeine raises alertness', () {
      final base = TwoProcessModel.simulate(
        fromUtc: DateTime.utc(2026, 7, 22, 14),
        toUtc: DateTime.utc(2026, 7, 22, 18),
        sleepWindows: nightlySleep(8),
        cbtMinLocalHour: 5.0,
        utcOffset: Duration.zero,
      );
      final caffeinated = TwoProcessModel.simulate(
        fromUtc: DateTime.utc(2026, 7, 22, 14),
        toUtc: DateTime.utc(2026, 7, 22, 18),
        sleepWindows: nightlySleep(8),
        cbtMinLocalHour: 5.0,
        utcOffset: Duration.zero,
        caffeine: [
          CaffeineDose(atUtc: DateTime.utc(2026, 7, 22, 14), mg: 150),
        ],
      );
      for (var i = 0; i < base.length; i++) {
        expect(caffeinated[i].alertness,
            greaterThanOrEqualTo(base[i].alertness - 1e-9));
      }
      expect(caffeinated.last.alertness, greaterThan(base.last.alertness));
    });

    test('circadian drive bottoms out at CBTmin', () {
      var worstHour = 0.0;
      var worst = 99.0;
      for (var h = 0.0; h < 24; h += 0.1) {
        final c =
            TwoProcessModel.processC(localHourOfDay: h, cbtMinLocalHour: 5.0);
        if (c < worst) {
          worst = c;
          worstHour = h;
        }
      }
      expect(worstHour, closeTo(5.0, 1.25));
    });

    test('features are not reported for a curve that is entirely asleep', () {
      final points = TwoProcessModel.simulate(
        fromUtc: DateTime.utc(2026, 7, 22, 0),
        toUtc: DateTime.utc(2026, 7, 22, 6),
        sleepWindows: nightlySleep(8),
        cbtMinLocalHour: 5.0,
        utcOffset: Duration.zero,
      );
      expect(TwoProcessModel.findFeatures(points), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('ChronotypeEstimator', () {
    const typical = HabitualSchedule(
      workBedMinutes: 23 * 60,
      workWakeMinutes: 7 * 60,
      freeBedMinutes: 24 * 60 + 30, // 00:30
      freeWakeMinutes: 9 * 60,
    );

    test('computes sleep durations across the midnight wrap', () {
      expect(typical.workDuration, 480); // 23:00 → 07:00
      expect(typical.freeDuration, 510); // 00:30 → 09:00
    });

    test('seeds a plausible chronotype from the questionnaire alone', () {
      final estimate = ChronotypeEstimator.fromQuestionnaire(typical);
      expect(estimate.confidence, PhaseConfidence.estimated);
      expect(estimate.nightsUsed, 0);
      // Mid-sleep on free days ≈ 04:45, minus a small debt correction.
      expect(estimate.msfScMinutes, inInclusiveRange(250, 290));
      expect(estimate.chronotype, Chronotype.intermediate);
    });

    test('the MCTQ debt correction only applies when catching up on free days',
        () {
      // Free-day sleep equal to workday sleep → no correction.
      const noCatchUp = HabitualSchedule(
        workBedMinutes: 23 * 60,
        workWakeMinutes: 7 * 60,
        freeBedMinutes: 23 * 60,
        freeWakeMinutes: 7 * 60,
      );
      final a = ChronotypeEstimator.fromQuestionnaire(noCatchUp);
      expect(a.msfScMinutes, closeTo(3 * 60, 1)); // mid-sleep 03:00

      // Sleeping much longer on free days pulls MSFsc earlier.
      const catchUp = HabitualSchedule(
        workBedMinutes: 23 * 60,
        workWakeMinutes: 6 * 60, // only 7 h on workdays
        freeBedMinutes: 23 * 60,
        freeWakeMinutes: 10 * 60, // 11 h on free days
      );
      final b = ChronotypeEstimator.fromQuestionnaire(catchUp);
      final uncorrectedMidSleep = 23 * 60 + (11 * 60) / 2 - 1440; // 04:30
      expect(b.msfScMinutes, lessThan(uncorrectedMidSleep));
    });

    test('classifies larks and owls at the MCTQ boundaries', () {
      expect(Chronotype.fromMsfSc(120), Chronotype.extremeEarly); // 02:00
      expect(Chronotype.fromMsfSc(170), Chronotype.moderateEarly); // 02:50
      expect(Chronotype.fromMsfSc(230), Chronotype.slightEarly); // 03:50
      expect(Chronotype.fromMsfSc(290), Chronotype.intermediate); // 04:50
      expect(Chronotype.fromMsfSc(350), Chronotype.slightLate); // 05:50
      expect(Chronotype.fromMsfSc(410), Chronotype.moderateLate); // 06:50
      expect(Chronotype.fromMsfSc(470), Chronotype.extremeLate); // 07:50
    });

    test('a pre-midnight mid-sleep classifies as extremely early, not late', () {
      // 23:00 mid-sleep is a very early type, not an extreme owl.
      expect(Chronotype.fromMsfSc(23 * 60), Chronotype.extremeEarly);
    });

    test('falls back to the questionnaire when there is no usable data', () {
      final estimate = ChronotypeEstimator.fromSessions(
        sessions: const [],
        fallback: typical,
        utcOffsetFor: (_) => Duration.zero,
      );
      expect(estimate.confidence, PhaseConfidence.estimated);
      expect(estimate.nightsUsed, 0);
    });

    test('confidence climbs with logged nights', () {
      expect(PhaseConfidence.fromNights(0), PhaseConfidence.estimated);
      expect(PhaseConfidence.fromNights(3), PhaseConfidence.low);
      expect(PhaseConfidence.fromNights(9), PhaseConfidence.medium);
      expect(PhaseConfidence.fromNights(20, midpointSdMinutes: 20),
          PhaseConfidence.high);
      // An erratic schedule keeps confidence down no matter how many nights.
      expect(PhaseConfidence.fromNights(40, midpointSdMinutes: 95),
          PhaseConfidence.medium);
    });

    test('smoothing prevents one odd night from moving the estimate far', () {
      final smoothed = ChronotypeEstimator.smooth(240, 480);
      expect(smoothed - 240, closeTo(240 * ChronotypeEstimator.emaAlpha, 0.001));
      expect(smoothed, lessThan(300));
    });

    test('estimates from real sessions and reports the nights used', () {
      // Fourteen consistent nights, 23:00–07:00 UTC.
      final sessions = List.generate(14, (i) {
        final start = DateTime.utc(2026, 7, 1).add(Duration(days: i, hours: 23));
        return SleepSession(
          id: 'n$i',
          startUtc: start,
          endUtc: start.add(const Duration(hours: 8)),
          tzId: 'UTC',
          nightOf: SleepDebtLedger.formatNight(
            DateTime(2026, 7, 1).add(Duration(days: i)),
          ),
          source: SleepSource.manual,
          updatedAt: start,
        );
      });

      final estimate = ChronotypeEstimator.fromSessions(
        sessions: sessions,
        fallback: typical,
        utcOffsetFor: (_) => Duration.zero,
      );
      expect(estimate.nightsUsed, 14);
      expect(estimate.midpointSdMinutes, closeTo(0, 1),
          reason: 'a perfectly regular schedule has zero midpoint variance');
    });

    test('naps are excluded from chronotype maths', () {
      final nap = SleepSession(
        id: 'nap',
        startUtc: DateTime.utc(2026, 7, 22, 14),
        endUtc: DateTime.utc(2026, 7, 22, 15),
        tzId: 'UTC',
        nightOf: '2026-07-22',
        source: SleepSource.manual,
        updatedAt: DateTime.utc(2026, 7, 22),
      );
      expect(nap.isNap(Duration.zero), isTrue);

      final estimate = ChronotypeEstimator.fromSessions(
        sessions: [nap],
        fallback: typical,
        utcOffsetFor: (_) => Duration.zero,
      );
      expect(estimate.nightsUsed, 0, reason: 'a nap is not a night');
    });
  });

  // ---------------------------------------------------------------------------
  group('CircadianPhaseModel', () {
    const schedule = HabitualSchedule(
      workBedMinutes: 23 * 60,
      workWakeMinutes: 7 * 60,
      freeBedMinutes: 23 * 60,
      freeWakeMinutes: 7 * 60,
    );

    test('places DLMO before bedtime and CBTmin in the small hours', () {
      final chrono = ChronotypeEstimator.fromQuestionnaire(schedule);
      final phase = CircadianPhaseModel.estimate(
        chronotype: chrono,
        schedule: schedule,
      );

      // Bed at 23:00 → melatonin onset ≈ 21:00.
      expect(phase.dlmoLocalHour, closeTo(21, 0.25));
      // CBTmin should land somewhere in the small hours.
      expect(phase.cbtMinLocalHour, inInclusiveRange(2.0, 5.5));
    });

    test('the two independent estimators broadly agree for a normal schedule',
        () {
      final chrono = ChronotypeEstimator.fromQuestionnaire(schedule);
      final phase = CircadianPhaseModel.estimate(
        chronotype: chrono,
        schedule: schedule,
      );
      expect(phase.disagreementHours, lessThan(1.5));
    });

    test('disagreement downgrades confidence instead of hiding it', () {
      // A schedule where mid-sleep and sleep onset imply very different phases.
      const contradictory = HabitualSchedule(
        workBedMinutes: 22 * 60,
        workWakeMinutes: 6 * 60,
        freeBedMinutes: 22 * 60,
        freeWakeMinutes: 14 * 60, // a 16-hour free-day sleep
      );
      final chrono = ChronotypeEstimator.fromQuestionnaire(contradictory);
      final phase = CircadianPhaseModel.estimate(
        chronotype: chrono,
        schedule: contradictory,
      );
      if (phase.disagreementHours >
          CircadianPhaseModel.disagreementToleranceHours) {
        expect(phase.confidence, PhaseConfidence.estimated);
      }
    });

    test('an owl has a later phase than a lark', () {
      const lark = HabitualSchedule(
        workBedMinutes: 21 * 60,
        workWakeMinutes: 5 * 60,
        freeBedMinutes: 21 * 60,
        freeWakeMinutes: 5 * 60,
      );
      const owl = HabitualSchedule(
        workBedMinutes: 2 * 60,
        workWakeMinutes: 10 * 60,
        freeBedMinutes: 2 * 60,
        freeWakeMinutes: 10 * 60,
      );

      final larkPhase = CircadianPhaseModel.estimate(
        chronotype: ChronotypeEstimator.fromQuestionnaire(lark),
        schedule: lark,
      );
      final owlPhase = CircadianPhaseModel.estimate(
        chronotype: ChronotypeEstimator.fromQuestionnaire(owl),
        schedule: owl,
      );

      expect(larkPhase.cbtMinLocalHour, lessThan(owlPhase.cbtMinLocalHour));
    });

    test('shifting advances both anchors together', () {
      final chrono = ChronotypeEstimator.fromQuestionnaire(schedule);
      final phase = CircadianPhaseModel.estimate(
        chronotype: chrono,
        schedule: schedule,
      );
      final shifted = CircadianPhaseModel.shifted(phase, 1.0);

      expect(
        shifted.cbtMinLocalHour,
        closeTo(CircadianPhaseModel.wrapHour(phase.cbtMinLocalHour - 1), 1e-9),
      );
      expect(
        shifted.dlmoLocalHour,
        closeTo(CircadianPhaseModel.wrapHour(phase.dlmoLocalHour - 1), 1e-9),
      );
    });

    test('hour wrapping is stable across midnight', () {
      expect(CircadianPhaseModel.wrapHour(25), 1);
      expect(CircadianPhaseModel.wrapHour(-1), 23);
      expect(CircadianPhaseModel.wrapHour(0), 0);
      expect(CircadianPhaseModel.wrapHour(23.5), 23.5);
    });
  });
}
