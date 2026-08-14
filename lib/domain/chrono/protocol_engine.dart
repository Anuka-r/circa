import 'dart:math' as math;

import '../value_objects/solar_day.dart';
import 'caffeine_model.dart';
import 'circadian_phase_model.dart';
import 'light_prc.dart';

/// The protocols a user can run. Exactly one is active at a time.
enum ProtocolKind {
  reset(
    'Reset',
    'Lock in the rhythm you already have',
    'Steady your body clock where it is. Morning light, a caffeine cutoff, '
        'and a consistent sleep window.',
    isPro: false,
  ),
  earlyRiser(
    'Early Riser',
    'Shift your clock earlier, safely',
    'Move your body clock earlier by up to an hour a day using precisely '
        'timed light — and strict light avoidance in the evening.',
    isPro: true,
  ),
  shiftWork(
    'Shift Work',
    'For a schedule you do not control',
    'Anchors light to your shift rather than the sun, including the commute '
        'home — the single biggest uncontrolled light exposure of a night '
        'shift.',
    isPro: true,
  ),
  jetLag(
    'Jet Lag',
    'Adapt before you land',
    'A day-by-day plan that starts before you fly, using the light '
        'phase-response curve in the direction you are travelling.',
    isPro: true,
  );

  const ProtocolKind(this.title, this.tagline, this.description,
      {required this.isPro});

  final String title;
  final String tagline;
  final String description;
  final bool isPro;
}

enum EventPriority { critical, recommended, optional }

/// What kind of action an event represents. Drives the icon and accent colour.
enum ProtocolEventKind {
  seekLight('Morning light'),
  avoidLight('Dim the lights'),
  caffeineCutoff('Caffeine cutoff'),
  windDown('Wind-down'),
  sleep('Sleep'),
  wake('Wake');

  const ProtocolEventKind(this.defaultTitle);
  final String defaultTitle;
}

/// One timed instruction.
class ProtocolEvent {
  const ProtocolEvent({
    required this.kind,
    required this.startUtc,
    required this.endUtc,
    required this.priority,
    required this.title,
    required this.detail,
    required this.why,
    this.minLux,
    this.minDurationMinutes,
  });

  final ProtocolEventKind kind;
  final DateTime startUtc;
  final DateTime endUtc;
  final EventPriority priority;

  /// Short label, e.g. "Morning light".
  final String title;

  /// One-line instruction, e.g. "10 minutes outside".
  final String detail;

  /// Plain-English reason. Shown in the action sheet, never jargon.
  final String why;

  final int? minLux;
  final int? minDurationMinutes;

  Duration get duration => endUtc.difference(startUtc);

  /// Stable identity across regenerations of the same day's plan, so
  /// notification scheduling and completion tracking are idempotent.
  String keyFor(String localDate) => '$localDate:${kind.name}';

  bool isActiveAt(DateTime utc) =>
      !utc.isBefore(startUtc) && utc.isBefore(endUtc);

  bool isPastAt(DateTime utc) => utc.isAfter(endUtc);
}

/// Builds a day's worth of timed instructions from the user's circadian phase
/// and the sun above them.
///
/// Everything here is derived — no hard-coded "get up at 7am" advice. Two users
/// in the same city with different chronotypes get genuinely different plans.
abstract final class ProtocolEngine {
  const ProtocolEngine._();

  /// How long after waking the morning light window stays open.
  static const Duration lightWindowLength = Duration(hours: 2);

  /// Target outdoor exposure. Ten minutes of real daylight beats an hour by a
  /// window, which is why the copy insists on outside.
  static const int targetLightMinutes = 10;

  /// Evening light avoidance starts this long before bed.
  static const Duration avoidLightBefore = Duration(hours: 2);

  /// Wind-down length.
  static const Duration windDownLength = Duration(minutes: 45);

  static List<ProtocolEvent> buildDay({
    required ProtocolKind protocol,
    required PhaseEstimate phase,
    required SolarDay solarDay,
    required double sleepNeedMinutes,
    required double caffeineThresholdMg,
    required double caffeineHalfLifeMinutes,
    required double plannedCaffeineMg,
  }) {
    final offset = solarDay.utcOffset;

    DateTime localHourToUtc(double hour) {
      final normalised = CircadianPhaseModel.wrapHour(hour);
      final h = normalised.floor();
      final m = ((normalised - h) * 60).round();
      return DateTime.utc(
        solarDay.date.year,
        solarDay.date.month,
        solarDay.date.day,
        h,
        m,
      ).subtract(offset);
    }

    final wakeHour = phase.idealWakeLocalHour;
    final bedHour = phase.idealBedLocalHour;

    var wakeUtc = localHourToUtc(wakeHour);
    var bedUtc = localHourToUtc(bedHour);
    // Bedtime belongs to the evening of this date; if the ideal bedtime lands
    // in the small hours it belongs to the *next* calendar day.
    if (bedHour < 12) bedUtc = bedUtc.add(const Duration(days: 1));
    // Likewise a very late wake hour still belongs to this morning.
    if (wakeHour > 18) wakeUtc = wakeUtc.subtract(const Duration(days: 1));

    final events = <ProtocolEvent>[];

    // ---- Morning light -----------------------------------------------------
    // The light must land in the advance lobe of the phase-response curve,
    // which opens shortly after the core-temperature minimum.
    final cbtMinUtc = localHourToUtc(phase.cbtMinLocalHour);
    final prcOpensUtc = cbtMinUtc.add(
      Duration(minutes: (LightPrc.advanceWindow.$1 * 60).round()),
    );

    var lightStart = wakeUtc.isAfter(prcOpensUtc) ? wakeUtc : prcOpensUtc;
    // No point sending someone outside before there is any light to get.
    final sunriseUtc = solarDay.sunriseUtc;
    if (sunriseUtc != null && lightStart.isBefore(sunriseUtc)) {
      lightStart = sunriseUtc;
    }
    final lightEnd = lightStart.add(lightWindowLength);

    final polar = solarDay.isPolarNight;
    events.add(ProtocolEvent(
      kind: ProtocolEventKind.seekLight,
      startUtc: lightStart,
      endUtc: lightEnd,
      priority: EventPriority.critical,
      title: 'Morning light',
      detail: polar
          ? '$targetLightMinutes min with a light box'
          : '$targetLightMinutes min outside',
      why: polar
          ? 'The sun does not rise here today, so a 10,000 lux light box does '
              'the job instead. Light at this hour is what pulls your clock '
              'earlier.'
          : 'Light in the couple of hours after you wake is the strongest '
              'signal you can give your body clock. It sets tonight’s bedtime '
              'and tomorrow’s energy.',
      minLux: polar ? 10000 : 1000,
      minDurationMinutes: targetLightMinutes,
    ));

    // ---- Caffeine cutoff ---------------------------------------------------
    final cutoff = CaffeineModel.cutoffTime(
      bedtimeUtc: bedUtc,
      plannedMg: plannedCaffeineMg,
      thresholdMg: caffeineThresholdMg,
      halfLifeMinutes: caffeineHalfLifeMinutes,
    );
    if (cutoff != null && cutoff.isAfter(wakeUtc)) {
      final localCutoff = cutoff.add(offset);
      events.add(ProtocolEvent(
        kind: ProtocolEventKind.caffeineCutoff,
        startUtc: cutoff,
        endUtc: cutoff,
        priority: EventPriority.recommended,
        title: 'Caffeine cutoff',
        detail: 'Last coffee by '
            '${localCutoff.hour.toString().padLeft(2, '0')}:'
            '${localCutoff.minute.toString().padLeft(2, '0')}',
        why: 'Caffeine has a half-life of about '
            '${(caffeineHalfLifeMinutes / 60).toStringAsFixed(1)} hours. A cup '
            'after this time still leaves enough in your system at bedtime to '
            'cost you deep sleep — even if you fall asleep fine.',
      ));
    }

    // ---- Evening light avoidance ------------------------------------------
    if (protocol != ProtocolKind.shiftWork) {
      final avoidStart = bedUtc.subtract(avoidLightBefore);
      events.add(ProtocolEvent(
        kind: ProtocolEventKind.avoidLight,
        startUtc: avoidStart,
        endUtc: bedUtc,
        priority: protocol == ProtocolKind.earlyRiser
            ? EventPriority.critical
            : EventPriority.optional,
        title: 'Dim the lights',
        detail: 'Lamps low, screens dimmed',
        why: 'Bright light now sits in the delay part of your light response '
            'curve — it pushes your clock later, which makes tomorrow morning '
            'harder.',
        minLux: 0,
      ));
    }

    // ---- Wind-down ---------------------------------------------------------
    final windDownStart = bedUtc.subtract(windDownLength);
    events.add(ProtocolEvent(
      kind: ProtocolEventKind.windDown,
      startUtc: windDownStart,
      endUtc: bedUtc,
      priority: EventPriority.recommended,
      title: 'Wind-down',
      detail: '${windDownLength.inMinutes} min before bed',
      why: 'Your body needs a runway into sleep. A consistent wind-down is the '
          'single habit most associated with falling asleep faster.',
    ));

    // ---- Sleep window ------------------------------------------------------
    final sleepEnd = bedUtc.add(Duration(minutes: sleepNeedMinutes.round()));
    events.add(ProtocolEvent(
      kind: ProtocolEventKind.sleep,
      startUtc: bedUtc,
      endUtc: sleepEnd,
      priority: EventPriority.critical,
      title: 'Sleep',
      detail: _formatDuration(sleepNeedMinutes.round()),
      why: 'Going to bed and getting up at consistent times matters more for '
          'how you feel than the total hours do.',
    ));

    events.sort((a, b) => a.startUtc.compareTo(b.startUtc));
    return events;
  }

  /// The next event due after [nowUtc], or null when the day is done.
  static ProtocolEvent? nextUp(
    List<ProtocolEvent> events,
    DateTime nowUtc, {
    Set<String> completedKeys = const {},
    required String localDate,
  }) {
    for (final e in events) {
      if (completedKeys.contains(e.keyFor(localDate))) continue;
      if (e.endUtc.isAfter(nowUtc)) return e;
    }
    return null;
  }

  /// Hours the clock would move if the user follows this plan exactly.
  /// Positive advances (earlier). Capped at the physiological ceiling.
  static double projectedShiftHours({
    required List<ProtocolEvent> events,
    required PhaseEstimate phase,
    required SolarDay solarDay,
  }) {
    final exposures = <LightExposure>[];
    for (final e in events) {
      if (e.kind != ProtocolEventKind.seekLight) continue;
      exposures.add(LightExposure(
        atUtc: e.startUtc,
        durationMinutes: e.minDurationMinutes ?? targetLightMinutes,
        lux: e.minLux ?? 1000,
      ));
    }
    if (exposures.isEmpty) return 0;

    final offset = solarDay.utcOffset;
    final cbtHour = phase.cbtMinLocalHour;
    final cbtUtc = DateTime.utc(
      solarDay.date.year,
      solarDay.date.month,
      solarDay.date.day,
      cbtHour.floor(),
      ((cbtHour - cbtHour.floor()) * 60).round(),
    ).subtract(offset);

    return LightPrc.totalShift(exposures: exposures, cbtMinUtc: cbtUtc)
        .cappedHours;
  }

  /// How many days a phase shift of [hours] honestly takes.
  ///
  /// Advancing is capped lower than delaying, which is why eastward travel is
  /// worse — and why we say so rather than promising an overnight fix.
  static int daysToShift(double hours) {
    if (hours == 0) return 0;
    final perDay = hours > 0
        ? LightPrc.maxAdvancePerDay
        : LightPrc.maxDelayPerDay;
    return (hours.abs() / perDay).ceil();
  }

  static String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// Clamp helper shared with the jet-lag planner.
  static double clampDailyShift(double hours) => hours > 0
      ? math.min(hours, LightPrc.maxAdvancePerDay)
      : math.max(hours, -LightPrc.maxDelayPerDay);
}
