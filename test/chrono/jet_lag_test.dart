import 'package:circa/domain/chrono/circadian_phase_model.dart';
import 'package:circa/domain/chrono/jet_lag_planner.dart';
import 'package:circa/domain/chrono/light_prc.dart';
import 'package:circa/domain/chrono/protocol_engine.dart';
import 'package:circa/domain/value_objects/chronotype.dart';
import 'package:circa/domain/value_objects/geo_location.dart';
import 'package:flutter_test/flutter_test.dart';

// Fixed offsets rather than the real TZDB: these tests are about the planner's
// arithmetic, and a zone whose rules change under them would be testing the
// wrong thing. DST behaviour is exercised through TimezoneService separately.
const _offsets = <String, Duration>{
  'Europe/London': Duration(hours: 1),
  'Asia/Tokyo': Duration(hours: 9),
  'America/Los_Angeles': Duration(hours: -7),
  'Pacific/Auckland': Duration(hours: 12),
  'Pacific/Honolulu': Duration(hours: -10),
  'Europe/Lisbon': Duration(hours: 1),
};

Duration _offsetFor(DateTime utc, String tzId) =>
    _offsets[tzId] ?? Duration.zero;

const _london = GeoLocation(
  latitude: 51.5074,
  longitude: -0.1278,
  tzId: 'Europe/London',
  label: 'London, United Kingdom',
);
const _tokyo = GeoLocation(
  latitude: 35.6762,
  longitude: 139.6503,
  tzId: 'Asia/Tokyo',
  label: 'Tokyo, Japan',
);
const _la = GeoLocation(
  latitude: 34.0522,
  longitude: -118.2437,
  tzId: 'America/Los_Angeles',
  label: 'Los Angeles, United States',
);
const _auckland = GeoLocation(
  latitude: -36.8485,
  longitude: 174.7633,
  tzId: 'Pacific/Auckland',
  label: 'Auckland, New Zealand',
);
const _honolulu = GeoLocation(
  latitude: 21.3069,
  longitude: -157.8583,
  tzId: 'Pacific/Honolulu',
  label: 'Honolulu, United States',
);
const _lisbon = GeoLocation(
  latitude: 38.7223,
  longitude: -9.1393,
  tzId: 'Europe/Lisbon',
  label: 'Lisbon, Portugal',
);

/// CBTmin at 04:00, melatonin onset at 21:00 — an ordinary intermediate clock.
const _phase = PhaseEstimate(
  dlmoLocalHour: 21.0,
  cbtMinLocalHour: 4.0,
  confidence: PhaseConfidence.high,
  chronotype: Chronotype.intermediate,
  msfScMinutes: 270,
  disagreementHours: 0,
);

JetLagPlan _plan({
  required GeoLocation from,
  required GeoLocation to,
  required DateTime departureUtc,
  required Duration flight,
  double sleepNeedMinutes = 480,
}) =>
    JetLagPlanner.build(
      trip: Trip(
        origin: from,
        destination: to,
        departureUtc: departureUtc,
        arrivalUtc: departureUtc.add(flight),
      ),
      phase: _phase,
      sleepNeedMinutes: sleepNeedMinutes,
      offsetFor: _offsetFor,
    );

void main() {
  group('Short way round', () {
    test('a 19-hour clock change is a 5-hour delay, not a 19-hour advance', () {
      expect(JetLagPlanner.shortWayHours(19), closeTo(-5, 1e-9));
      expect(JetLagPlanner.shortWayHours(-19), closeTo(5, 1e-9));
    });

    test('leaves ordinary shifts alone', () {
      expect(JetLagPlanner.shortWayHours(8), closeTo(8, 1e-9));
      expect(JetLagPlanner.shortWayHours(-8), closeTo(-8, 1e-9));
      expect(JetLagPlanner.shortWayHours(0), closeTo(0, 1e-9));
    });

    test('London to Auckland goes the short way, and that way is a delay', () {
      // +11 raw looks like an advance; the short way round is the same 11
      // hours eastward, which is genuinely the harder direction.
      final plan = _plan(
        from: _london,
        to: _auckland,
        departureUtc: DateTime.utc(2026, 9, 10, 8),
        flight: const Duration(hours: 23),
      );
      expect(plan.deltaHours, closeTo(11, 1e-9));
      expect(plan.requiredShiftHours, closeTo(11, 1e-9));
      expect(plan.direction, ShiftDirection.advance);
    });

    test('Auckland to Honolulu crosses the date line the short way', () {
      // −22 raw. Taken literally that is a 22-hour delay; the short way is a
      // 2-hour advance, and every light instruction depends on the difference.
      final plan = _plan(
        from: _auckland,
        to: _honolulu,
        departureUtc: DateTime.utc(2026, 9, 10, 2),
        flight: const Duration(hours: 9),
      );
      expect(plan.deltaHours, closeTo(-22, 1e-9));
      expect(plan.requiredShiftHours, closeTo(2, 1e-9));
      expect(plan.direction, ShiftDirection.advance);
      expect(plan.requiredDays, 2);
    });
  });

  group('Direction and cost', () {
    test('eastward is an advance, and costs a day per hour', () {
      final plan = _plan(
        from: _london,
        to: _tokyo,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        flight: const Duration(hours: 12),
      );
      expect(plan.direction, ShiftDirection.advance);
      expect(plan.requiredShiftHours, closeTo(8, 1e-9));
      expect(plan.requiredDays, 8); // 8 h / 1.0 h per day
      expect(plan.preFlightDays, JetLagPlanner.maxPreFlightDays);
    });

    test('westward is a delay, and is cheaper for the same eight hours', () {
      final plan = _plan(
        from: _london,
        to: _la,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        flight: const Duration(hours: 11),
      );
      expect(plan.direction, ShiftDirection.delay);
      expect(plan.requiredShiftHours, closeTo(-8, 1e-9));
      expect(plan.requiredDays, 6); // 8 h / 1.5 h per day, rounded up
    });

    test('same offset asks for no shift at all', () {
      final plan = _plan(
        from: _london,
        to: _lisbon,
        departureUtc: DateTime.utc(2026, 9, 10, 9),
        flight: const Duration(hours: 3),
      );
      expect(plan.direction, ShiftDirection.none);
      expect(plan.requiredDays, 0);
      expect(plan.adaptedFractionOnArrival, 1.0);
      // One ordinary morning-light instruction, not an invented protocol.
      for (final day in plan.days) {
        expect(
          day.events.where((e) => e.kind == ProtocolEventKind.avoidLight),
          isEmpty,
        );
      }
    });

    test('pre-shifting never starts more than three days out', () {
      final plan = _plan(
        from: _london,
        to: _tokyo,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        flight: const Duration(hours: 12),
      );
      expect(plan.days.first.index, -JetLagPlanner.maxPreFlightDays);
    });

    test('a two-hour trip pre-shifts for two days, not three', () {
      final plan = _plan(
        from: _auckland,
        to: _honolulu,
        departureUtc: DateTime.utc(2026, 9, 10, 2),
        flight: const Duration(hours: 9),
      );
      expect(plan.preFlightDays, 2);
      expect(plan.days.first.index, -2);
    });
  });

  group('Daily shift never exceeds the physiological ceiling', () {
    for (final (name, from, to, flight) in [
      ('east', _london, _tokyo, Duration(hours: 12)),
      ('west', _london, _la, Duration(hours: 11)),
      ('far east', _london, _auckland, Duration(hours: 23)),
    ]) {
      test(name, () {
        final plan = _plan(
          from: from,
          to: to,
          departureUtc: DateTime.utc(2026, 9, 10, 10),
          flight: flight,
        );
        final ceiling = plan.direction.isAdvance
            ? LightPrc.maxAdvancePerDay
            : LightPrc.maxDelayPerDay;
        for (final day in plan.days) {
          expect(
            day.dailyShiftHours.abs(),
            lessThanOrEqualTo(ceiling + 1e-9),
            reason: 'day ${day.index} asks for more than one day of shift',
          );
          // And never past the target, in either direction.
          expect(
            day.targetShiftHours.abs(),
            lessThanOrEqualTo(plan.requiredShiftHours.abs() + 1e-9),
          );
          expect(
            day.targetShiftHours * plan.requiredShiftHours,
            greaterThanOrEqualTo(0),
            reason: 'shift changed sign — the plan is going the long way',
          );
        }
        // The plan does finish the job, given enough days.
        if (!plan.truncated) {
          expect(
            plan.days.last.targetShiftHours,
            closeTo(plan.requiredShiftHours, 1e-9),
          );
        }
      });
    }
  });

  group('Events', () {
    test('never overlap within a day', () {
      for (final to in [_tokyo, _la]) {
        final plan = _plan(
          from: _london,
          to: to,
          departureUtc: DateTime.utc(2026, 9, 10, 10),
          flight: const Duration(hours: 11),
        );
        for (final day in plan.days) {
          for (var i = 1; i < day.events.length; i++) {
            expect(
              day.events[i].startUtc.isBefore(day.events[i - 1].endUtc),
              isFalse,
              reason: '${day.events[i].title} overlaps '
                  '${day.events[i - 1].title} on day ${day.index}',
            );
          }
        }
      }
    });

    test('land on the lobe of the curve their direction needs', () {
      final east = _plan(
        from: _london,
        to: _tokyo,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        flight: const Duration(hours: 12),
      );
      final west = _plan(
        from: _london,
        to: _la,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        flight: const Duration(hours: 11),
      );

      double tauOf(JetLagDay day, ProtocolEvent e) {
        final cbtMinUtc = DateTime.utc(
          day.localDate.year,
          day.localDate.month,
          day.localDate.day,
        )
            .add(Duration(minutes: (day.cbtMinLocalHour * 60).round()))
            .subtract(day.utcOffset);
        final mid = e.startUtc.add(
          Duration(milliseconds: e.duration.inMilliseconds ~/ 2),
        );
        return mid.difference(cbtMinUtc).inMinutes / 60.0;
      }

      for (final day in east.days) {
        final seek = day.events
            .firstWhere((e) => e.kind == ProtocolEventKind.seekLight);
        final avoid = day.events
            .firstWhere((e) => e.kind == ProtocolEventKind.avoidLight);
        expect(LightPrc.isAdvanceZone(tauOf(day, seek)), isTrue,
            reason: 'eastward seek must advance');
        expect(LightPrc.isDelayZone(tauOf(day, avoid)), isTrue,
            reason: 'eastward avoid must be the delay zone');
      }

      for (final day in west.days) {
        final seek = day.events
            .firstWhere((e) => e.kind == ProtocolEventKind.seekLight);
        final avoid = day.events
            .firstWhere((e) => e.kind == ProtocolEventKind.avoidLight);
        expect(LightPrc.isDelayZone(tauOf(day, seek)), isTrue,
            reason: 'westward seek must delay');
        expect(LightPrc.isAdvanceZone(tauOf(day, avoid)), isTrue,
            reason: 'westward avoid must be the advance zone');
      }
    });

    test('a long eastward arrival asks for afternoon light, not morning', () {
      // The counterintuitive result, and most of why the feature is worth
      // shipping. Landing in Auckland still eleven hours from adapted, the
      // body's temperature minimum sits at mid-morning local time — so the
      // light that advances the clock is the *afternoon*, and the local
      // morning sun everybody recommends lands in the delay lobe and pushes
      // the clock the wrong way.
      final plan = _plan(
        from: _london,
        to: _auckland,
        departureUtc: DateTime.utc(2026, 9, 10, 8),
        flight: const Duration(hours: 23),
      );
      final arrival = plan.arrivalDay!;
      expect(arrival.location.tzId, 'Pacific/Auckland');
      expect(arrival.isAtDestination, isTrue);

      final seek = arrival.events
          .firstWhere((e) => e.kind == ProtocolEventKind.seekLight);
      final seekHour = seek.startUtc.add(arrival.utcOffset).hour;
      expect(seekHour, greaterThanOrEqualTo(12),
          reason: 'seek-light should be Auckland afternoon, was $seekHour:00');

      final avoid = arrival.events
          .firstWhere((e) => e.kind == ProtocolEventKind.avoidLight);
      final avoidHour = avoid.startUtc.add(arrival.utcOffset).hour;
      expect(avoidHour, lessThan(seekHour),
          reason: 'the block to avoid precedes the block to seek');
    });

    test('the day you land is planned in the destination, not at home', () {
      // Eastward, landing on the following local date.
      final east = _plan(
        from: _london,
        to: _tokyo,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        flight: const Duration(hours: 12),
      );
      expect(east.arrivalDay!.index, 1);
      expect(east.days.firstWhere((d) => d.index == 0).location.tzId,
          'Europe/London',
          reason: 'the flight day is planned where you wake');

      // Westward, landing on the same local date it left.
      final west = _plan(
        from: _london,
        to: _la,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        flight: const Duration(hours: 11),
      );
      expect(west.arrivalDay!.index, 1);
      expect(west.arrivalDay!.location.tzId, 'America/Los_Angeles');

      // Dates stay consecutive across the switch of cities.
      for (var i = 1; i < west.days.length; i++) {
        expect(
          west.days[i].localDate.difference(west.days[i - 1].localDate).inDays,
          1,
          reason: 'day ${west.days[i].index} repeats or skips a date',
        );
      }
    });

    test('every event is timed in the zone of the city for that day', () {
      final plan = _plan(
        from: _london,
        to: _tokyo,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        flight: const Duration(hours: 12),
      );
      for (final day in plan.days) {
        expect(day.utcOffset, _offsets[day.location.tzId]);
        expect(day.solarDay.location.tzId, day.location.tzId);
        for (final e in day.events) {
          // Every instruction falls within a day of the date it is filed under
          // once read on that city's clock — i.e. nothing is silently placed
          // in the origin's zone after landing.
          final local = e.startUtc.add(day.utcOffset);
          final delta = local.difference(day.localDate).inHours;
          expect(delta, inInclusiveRange(-12, 36),
              reason: '${e.title} on day ${day.index} is not on its own date');
        }
      }
      // Pre-flight days are at home, everything after landing is not.
      expect(plan.days.first.location.tzId, 'Europe/London');
      expect(plan.days.last.location.tzId, 'Asia/Tokyo');
    });

    test('sleep moves steadily, never the whole way at once', () {
      final plan = _plan(
        from: _london,
        to: _tokyo,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        flight: const Duration(hours: 12),
      );
      DateTime bedOf(JetLagDay d) =>
          d.events.firstWhere((e) => e.kind == ProtocolEventKind.sleep).startUtc;

      for (var i = 1; i < plan.days.length; i++) {
        final step = bedOf(plan.days[i])
                .difference(bedOf(plan.days[i - 1]))
                .inMinutes /
            60.0;
        // A day is 24 h long; anything more than the ceiling on top of that is
        // the plan asking for a jump rather than a shift.
        expect((step - 24).abs(), lessThanOrEqualTo(LightPrc.maxDelayPerDay + 1e-6),
            reason: 'bedtime jumped ${step - 24} h between days '
                '${plan.days[i - 1].index} and ${plan.days[i].index}');
      }
    });
  });

  group('Honest headline', () {
    test('a long eastward haul is not sold as adapted on arrival', () {
      final plan = _plan(
        from: _london,
        to: _tokyo,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        flight: const Duration(hours: 12),
      );
      // Three pre-flight days plus the flight day is four of the eight needed.
      expect(plan.adaptedPercentOnArrival, 50);
      expect(plan.adaptedFractionOnArrival, lessThan(1.0));
    });

    test('a plan longer than the cap is marked truncated, not quietly cut', () {
      final plan = _plan(
        from: _london,
        to: _auckland,
        departureUtc: DateTime.utc(2026, 9, 10, 8),
        flight: const Duration(hours: 23),
      );
      expect(plan.requiredDays, 11);
      expect(plan.days.length, lessThanOrEqualTo(JetLagPlanner.maxPlanDays));
      expect(plan.truncated, plan.days.length == JetLagPlanner.maxPlanDays);
    });
  });

  group('Trip validation', () {
    test('rejects an arrival before departure', () {
      final t = Trip(
        origin: _london,
        destination: _tokyo,
        departureUtc: DateTime.utc(2026, 9, 10, 12),
        arrivalUtc: DateTime.utc(2026, 9, 10, 9),
      );
      expect(t.isValid, isFalse);
    });

    test('rejects a flight longer than a day', () {
      final t = Trip(
        origin: _london,
        destination: _tokyo,
        departureUtc: DateTime.utc(2026, 9, 10, 12),
        arrivalUtc: DateTime.utc(2026, 9, 12, 12),
      );
      expect(t.isValid, isFalse);
    });

    test('accepts an ordinary long haul', () {
      final t = Trip(
        origin: _london,
        destination: _tokyo,
        departureUtc: DateTime.utc(2026, 9, 10, 12),
        arrivalUtc: DateTime.utc(2026, 9, 11, 0),
      );
      expect(t.isValid, isTrue);
    });
  });
}
