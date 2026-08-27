import 'dart:math' as math;

import '../value_objects/geo_location.dart';
import '../value_objects/solar_day.dart';
import 'circadian_phase_model.dart';
import 'light_prc.dart';
import 'protocol_engine.dart';

/// Which way the body clock has to move to match the destination.
enum ShiftDirection {
  /// Eastward. The clock must move *earlier* — the weaker lobe of the curve,
  /// and the reason east is worse than west.
  advance,

  /// Westward. The clock must move *later*. Easier, and faster per day.
  delay,

  /// Same effective offset. A long flight north or south needs no shift.
  none;

  bool get isAdvance => this == ShiftDirection.advance;
}

/// The five facts a plan is built from.
class Trip {
  const Trip({
    required this.origin,
    required this.destination,
    required this.departureUtc,
    required this.arrivalUtc,
  });

  final GeoLocation origin;
  final GeoLocation destination;

  /// Wheels up and wheels down, both as absolute instants.
  ///
  /// UTC precisely because the two ends of a flight are quoted in different
  /// local times, and "which timezone did I just type?" is the classic way a
  /// trip planner produces a confidently wrong plan. The UI labels each picker
  /// with its city and offset; by the time a departure reaches here it is an
  /// instant, not a wall clock.
  final DateTime departureUtc;
  final DateTime arrivalUtc;

  Duration get flightDuration => arrivalUtc.difference(departureUtc);

  bool get isValid =>
      arrivalUtc.isAfter(departureUtc) &&
      flightDuration >= const Duration(minutes: 30) &&
      flightDuration <= const Duration(hours: 24);
}

/// One day of the plan.
class JetLagDay {
  const JetLagDay({
    required this.index,
    required this.localDate,
    required this.location,
    required this.utcOffset,
    required this.solarDay,
    required this.isTravelDay,
    required this.isAtDestination,
    required this.targetShiftHours,
    required this.dailyShiftHours,
    required this.cbtMinLocalHour,
    required this.events,
  });

  /// Negative before departure, 0 on the day of the flight, positive after.
  final int index;

  /// The calendar date as it reads on a clock in [location].
  final DateTime localDate;

  /// The city the user is actually in on this day — what makes the light
  /// windows correct in transit rather than correct only at home.
  final GeoLocation location;
  final Duration utcOffset;
  final SolarDay solarDay;

  final bool isTravelDay;
  final bool isAtDestination;

  /// Total shift this day aims to have banked by the time it ends, in hours.
  /// Positive advances (earlier), negative delays.
  final double targetShiftHours;

  /// What this day alone is asked to add. Zero once fully adapted.
  final double dailyShiftHours;

  /// The pivot of the phase-response curve, as an hour-of-day on the clock the
  /// user will actually be reading. Every window below is measured from it.
  final double cbtMinLocalHour;

  final List<ProtocolEvent> events;

  bool get isPreFlight => index < 0;

  /// True once this day asks for no further movement.
  bool get isAdapted => dailyShiftHours.abs() < 1e-9;
}

/// A whole trip's worth of days, plus the honest headline numbers.
class JetLagPlan {
  const JetLagPlan({
    required this.trip,
    required this.deltaHours,
    required this.requiredShiftHours,
    required this.direction,
    required this.requiredDays,
    required this.preFlightDays,
    required this.days,
    required this.adaptedFractionOnArrival,
    required this.truncated,
  });

  final Trip trip;

  /// The raw clock change between the two cities, in hours.
  final double deltaHours;

  /// How far the body clock actually has to move, taken the short way round.
  /// Positive advances (earlier), negative delays (later).
  final double requiredShiftHours;

  final ShiftDirection direction;

  /// Days of shifting at the physiological ceiling — 1.0 h/day advancing,
  /// 1.5 delaying. A floor on how long this takes, not a promise.
  final int requiredDays;

  /// How many of those days happen before the flight.
  final int preFlightDays;

  final List<JetLagDay> days;

  /// How adapted the plan expects you to be when you land, 0..1.
  final double adaptedFractionOnArrival;

  /// True when the plan ran past [JetLagPlanner.maxPlanDays] and was cut. The
  /// UI says so rather than implying the work is over.
  final bool truncated;

  /// The first day spent at the destination, if the plan reaches it.
  JetLagDay? get arrivalDay {
    for (final d in days) {
      if (d.isAtDestination) return d;
    }
    return null;
  }

  int get adaptedPercentOnArrival => (adaptedFractionOnArrival * 100).round();
}

/// Builds a day-by-day jet-lag plan from the light phase-response curve.
///
/// The whole feature rests on one asymmetry: light *after* your temperature
/// minimum pulls the clock earlier, light *before* it pushes the clock later,
/// and earlier is the weaker direction. That is why flying east is worse than
/// flying west, why an honest plan takes days rather than a night, and why the
/// advice it gives on arrival is frequently the opposite of "get some morning
/// sun".
///
/// **On [requiredDays].** It divides the shift by the *ceiling* in
/// [LightPrc.maxAdvancePerDay]/[LightPrc.maxDelayPerDay], per
/// docs/02-circadian-engine.md §10.4. A single light block scored through
/// [LightPrc.totalShift] delivers less than that ceiling, so the day count is a
/// best case. It is presented as "at least", never as a guarantee.
abstract final class JetLagPlanner {
  const JetLagPlanner._();

  /// Shifting starts at most this many days before the flight. Past three days
  /// of pre-shifting, adherence collapses and the plan becomes fiction.
  static const int maxPreFlightDays = 3;

  /// Ceiling on plan length, so a 12-hour eastward haul renders as a readable
  /// list rather than a month of near-identical cards.
  static const int maxPlanDays = 14;

  /// How long each light block runs.
  static const Duration lightBlockLength = Duration(hours: 3);

  /// Wake sits about this long after the temperature minimum — the same
  /// relation [PhaseEstimate.idealWakeLocalHour] uses.
  static const double wakeAfterCbtMinHours = 2.0;

  static JetLagPlan build({
    required Trip trip,
    required PhaseEstimate phase,
    required double sleepNeedMinutes,
    required Duration Function(DateTime utc, String tzId) offsetFor,
  }) {
    final originOffset = offsetFor(trip.departureUtc, trip.origin.tzId);
    final destinationOffset = offsetFor(trip.arrivalUtc, trip.destination.tzId);

    final deltaHours = (destinationOffset - originOffset).inMinutes / 60.0;
    final requiredShift = shortWayHours(deltaHours);
    final direction = requiredShift.abs() < 0.25
        ? ShiftDirection.none
        : (requiredShift > 0 ? ShiftDirection.advance : ShiftDirection.delay);

    final perDay = direction.isAdvance
        ? LightPrc.maxAdvancePerDay
        : LightPrc.maxDelayPerDay;
    final requiredDays = ProtocolEngine.daysToShift(requiredShift);
    final preFlight = math.min(maxPreFlightDays, requiredDays);

    final departureLocal = trip.departureUtc.add(originOffset);
    final departureDate = DateTime(
      departureLocal.year,
      departureLocal.month,
      departureLocal.day,
    );

    final arrivalLocal = trip.arrivalUtc.add(destinationOffset);
    final arrivalDate = DateTime(
      arrivalLocal.year,
      arrivalLocal.month,
      arrivalLocal.day,
    );

    final firstIndex = -preFlight;
    // The last day with shifting left to do. Day 0 — the flight itself —
    // counts as one of them.
    final lastShiftIndex = firstIndex + math.max(requiredDays - 1, 0);
    // How many calendar days the flight itself crosses: 0 landing the same
    // day, 1 landing tomorrow, -1 for the westward flights that land before
    // they left.
    final arrivalIndex = arrivalDate.difference(departureDate).inDays;
    var lastIndex = math.max(lastShiftIndex, math.max(arrivalIndex, 0));

    final truncated = lastIndex - firstIndex + 1 > maxPlanDays;
    if (truncated) lastIndex = firstIndex + maxPlanDays - 1;

    final days = <JetLagDay>[];
    for (var i = firstIndex; i <= lastIndex; i++) {
      // The whole day is planned against where it is trying to get to, so the
      // sleep window and the light windows can never disagree about which
      // phase they are anchored on.
      final target = _clampToward((i - firstIndex + 1) * perDay, requiredShift);
      final previous = _clampToward((i - firstIndex) * perDay, requiredShift);

      // The flight day is planned at the origin — that is where you wake and
      // where the day's light is available — and everything from the day you
      // land onward is planned at the destination. Clamping to 1 covers the
      // westward flights that touch down on the same local date they left, or
      // an earlier one: the travel day still belongs to the origin.
      final atDestination = i >= math.max(arrivalIndex, 1);
      final location = atDestination ? trip.destination : trip.origin;

      // Dates stay consecutive across the switch. The local calendar really
      // does repeat or skip a day over the date line, but a plan that prints
      // the same date on two cards reads as a bug, so the day *after* landing
      // is always the day after the arrival date.
      final date = atDestination
          ? arrivalDate.add(Duration(days: i - arrivalIndex))
          : departureDate.add(Duration(days: i));

      // Resolved on the day itself, so a plan straddling a DST change stays
      // correct rather than inheriting the offset in force at booking.
      final offset = offsetFor(
        DateTime.utc(date.year, date.month, date.day, 12),
        location.tzId,
      );

      final solarDay = SolarDay.compute(
        date: date,
        location: location,
        utcOffset: offset,
      );

      // Biological phase on the clock the user is reading. Subtracting the
      // banked shift moves it earlier; adding the required shift at the
      // destination re-expresses the same biological instant on the new clock.
      // Fully adapted the two cancel and CBTmin lands back at its home hour —
      // which is precisely what "adapted" means.
      final cbtMin = CircadianPhaseModel.wrapHour(
        phase.cbtMinLocalHour - target + (atDestination ? requiredShift : 0.0),
      );

      days.add(JetLagDay(
        index: i,
        localDate: date,
        location: location,
        utcOffset: offset,
        solarDay: solarDay,
        isTravelDay: i == 0,
        isAtDestination: atDestination,
        targetShiftHours: target,
        dailyShiftHours: target - previous,
        cbtMinLocalHour: cbtMin,
        events: _eventsFor(
          date: date,
          offset: offset,
          solarDay: solarDay,
          cbtMinLocalHour: cbtMin,
          direction: direction,
          isTravelDay: i == 0,
          sleepNeedMinutes: sleepNeedMinutes,
        ),
      ));
    }

    // Measured at the moment the wheels touch down — the shift banked by the
    // *start* of the arrival day — not by the end of it. Counting the arrival
    // day's own light would overstate how adapted someone is when they walk
    // off the aircraft, which is the one number a traveller plans around.
    final onArrival = _clampToward(
      (math.max(arrivalIndex, 1) - firstIndex) * perDay,
      requiredShift,
    );
    final fraction = requiredShift.abs() < 1e-9
        ? 1.0
        : (onArrival / requiredShift).clamp(0.0, 1.0);

    return JetLagPlan(
      trip: trip,
      deltaHours: deltaHours,
      requiredShiftHours: requiredShift,
      direction: direction,
      requiredDays: requiredDays,
      preFlightDays: preFlight,
      days: days,
      adaptedFractionOnArrival: fraction,
      truncated: truncated,
    );
  }

  /// The short way round the clock face.
  ///
  /// A 19-hour clock change is a 5-hour delay, not a 19-hour advance. Getting
  /// this wrong does not merely overstate the work — it sends the user the long
  /// way round, which points every light instruction in the plan the wrong
  /// direction.
  static double shortWayHours(double hours) {
    var h = hours % 24.0;
    if (h > 12) h -= 24.0;
    if (h <= -12) h += 24.0;
    return h;
  }

  /// Accumulated shift, never overshooting the target or flipping its sign.
  static double _clampToward(double magnitude, double target) {
    if (target == 0) return 0;
    final capped = math.min(magnitude.abs(), target.abs());
    return target > 0 ? capped : -capped;
  }

  /// One day's instructions.
  ///
  /// The three blocks are placed relative to the sleep window rather than on
  /// the raw lobe peaks: the strongest delay light of all falls in the middle
  /// of the biological night, and a plan that tells someone to go outside while
  /// asleep is not a plan. Seek and avoid therefore sit immediately either side
  /// of sleep — which puts each on the correct lobe, keeps both in waking
  /// hours, and makes overlap structurally impossible.
  static List<ProtocolEvent> _eventsFor({
    required DateTime date,
    required Duration offset,
    required SolarDay solarDay,
    required double cbtMinLocalHour,
    required ShiftDirection direction,
    required bool isTravelDay,
    required double sleepNeedMinutes,
  }) {
    DateTime atLocalHour(double hour) => DateTime.utc(
          date.year,
          date.month,
          date.day,
        ).add(Duration(minutes: (hour * 60).round())).subtract(offset);

    // Wake is the anchor, not bedtime: it is the end of the window an alarm
    // actually controls, and it is what the morning light block keys off.
    final wakeUtc = atLocalHour(cbtMinLocalHour + wakeAfterCbtMinHours);
    final bedUtc = wakeUtc.subtract(
      Duration(minutes: sleepNeedMinutes.round()),
    );

    final events = <ProtocolEvent>[
      ProtocolEvent(
        kind: ProtocolEventKind.sleep,
        startUtc: bedUtc,
        endUtc: wakeUtc,
        priority: EventPriority.critical,
        title: isTravelDay ? 'Sleep — on the plane if you can' : 'Sleep',
        detail: _formatDuration(sleepNeedMinutes.round()),
        why: isTravelDay
            ? 'This is the window your body is ready to sleep in today, '
                'wherever you happen to be. Sleeping across it on the aircraft '
                'is worth more than sleeping when the cabin lights go down.'
            : 'Tonight is one step toward the destination, not a jump to it. '
                'Moving bedtime the whole way at once produces a night awake, '
                'not an adapted clock.',
      ),
    ];

    if (direction == ShiftDirection.none) {
      events.add(ProtocolEvent(
        kind: ProtocolEventKind.seekLight,
        startUtc: wakeUtc,
        endUtc: wakeUtc.add(ProtocolEngine.lightWindowLength),
        priority: EventPriority.recommended,
        title: 'Morning light',
        detail: '${ProtocolEngine.targetLightMinutes} min outside',
        why: 'Your destination keeps effectively the same time as home, so '
            'there is no clock to shift. Ordinary morning light is all this '
            'trip asks for.',
        minLux: 1000,
        minDurationMinutes: ProtocolEngine.targetLightMinutes,
      ));
      events.sort((a, b) => a.startUtc.compareTo(b.startUtc));
      return events;
    }

    final advancing = direction.isAdvance;

    // East: light after waking (advance lobe), dark before bed (delay lobe).
    // West: light before bed, dark after waking. Both blocks land on the
    // biological clock, not the wall clock — which is how the plan comes to
    // tell an eastbound traveller to avoid the local morning sun.
    final (seekStart, avoidStart) = advancing
        ? (wakeUtc, bedUtc.subtract(lightBlockLength))
        : (bedUtc.subtract(lightBlockLength), wakeUtc);

    final seekEnd = seekStart.add(lightBlockLength);

    // Whether daylight is actually available decides between "get outside" and
    // a light box. Telling someone to step outside at 02:00 destination time is
    // how a plan loses its credibility on day one.
    final sunrise = solarDay.sunriseUtc;
    final sunset = solarDay.sunsetUtc;
    final daylight = solarDay.isPolarDay ||
        (sunrise != null &&
            sunset != null &&
            seekEnd.isAfter(sunrise) &&
            seekStart.isBefore(sunset));

    events.add(ProtocolEvent(
      kind: ProtocolEventKind.seekLight,
      startUtc: seekStart,
      endUtc: seekEnd,
      priority: EventPriority.critical,
      title: advancing ? 'Light to pull earlier' : 'Light to push later',
      detail: daylight
          ? 'Outside, ${ProtocolEngine.targetLightMinutes}+ min of it'
          : 'Bright indoor light or a 10,000 lux box',
      why: advancing
          ? 'Light in the hours after your temperature minimum lands on the '
              'advance side of your response curve and pulls your clock '
              'earlier — the direction eastward travel needs. Note the clock '
              'this is set by is yours, not the local one.'
          : 'Light in the hours before your temperature minimum lands on the '
              'delay side of your response curve and pushes your clock later — '
              'the direction westward travel needs. Staying up for it is the '
              'point, not a side effect.',
      minLux: daylight ? 1000 : 10000,
      minDurationMinutes: ProtocolEngine.targetLightMinutes,
    ));

    events.add(ProtocolEvent(
      kind: ProtocolEventKind.avoidLight,
      startUtc: avoidStart,
      endUtc: avoidStart.add(lightBlockLength),
      priority: EventPriority.critical,
      title: 'Avoid light',
      detail: 'Sunglasses outdoors, screens dim',
      why: advancing
          ? 'Light here lands on the delay side of your curve and pushes your '
              'clock the wrong way. In the first days after landing this is '
              'often the local morning sun — the one thing everybody tells you '
              'to go and get.'
          : 'Light here lands on the advance side of your curve and pulls your '
              'clock earlier, undoing the delay you are working for. Keep the '
              'local morning dim.',
      minLux: 0,
    ));

    events.sort((a, b) => a.startUtc.compareTo(b.startUtc));
    return events;
  }

  static String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
