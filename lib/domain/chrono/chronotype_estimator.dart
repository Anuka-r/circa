import 'dart:math' as math;

import '../entities/sleep_session.dart';
import '../value_objects/chronotype.dart';

/// A habitual schedule as collected during onboarding, in minutes past local
/// midnight. Bedtimes after 18:00 are stored as-is and normalised internally.
class HabitualSchedule {
  const HabitualSchedule({
    required this.workBedMinutes,
    required this.workWakeMinutes,
    required this.freeBedMinutes,
    required this.freeWakeMinutes,
  });

  final double workBedMinutes;
  final double workWakeMinutes;
  final double freeBedMinutes;
  final double freeWakeMinutes;

  /// Sleep duration on workdays, in minutes, handling the midnight wrap.
  double get workDuration => _span(workBedMinutes, workWakeMinutes);

  /// Sleep duration on free days, in minutes.
  double get freeDuration => _span(freeBedMinutes, freeWakeMinutes);

  static double _span(double from, double to) {
    var d = to - from;
    if (d <= 0) d += 1440.0;
    return d;
  }

  HabitualSchedule copyWith({
    double? workBedMinutes,
    double? workWakeMinutes,
    double? freeBedMinutes,
    double? freeWakeMinutes,
  }) =>
      HabitualSchedule(
        workBedMinutes: workBedMinutes ?? this.workBedMinutes,
        workWakeMinutes: workWakeMinutes ?? this.workWakeMinutes,
        freeBedMinutes: freeBedMinutes ?? this.freeBedMinutes,
        freeWakeMinutes: freeWakeMinutes ?? this.freeWakeMinutes,
      );
}

/// The result of a chronotype estimation, carrying its own confidence.
class ChronotypeEstimate {
  const ChronotypeEstimate({
    required this.msfScMinutes,
    required this.chronotype,
    required this.confidence,
    required this.nightsUsed,
    this.midpointSdMinutes,
  });

  /// Mid-sleep on free days, corrected for sleep debt. Minutes past midnight;
  /// may be negative for very early types.
  final double msfScMinutes;

  final Chronotype chronotype;
  final PhaseConfidence confidence;
  final int nightsUsed;

  /// Standard deviation of nightly mid-sleep — our consistency measure.
  final double? midpointSdMinutes;
}

/// Estimates chronotype using the MCTQ construct, seeded from the onboarding
/// questionnaire and refined continuously once real nights exist.
abstract final class ChronotypeEstimator {
  const ChronotypeEstimator._();

  /// Smoothing factor for the running re-estimate. Low enough that the value
  /// drifts rather than jumping after one unusual night.
  static const double emaAlpha = 0.15;

  /// Night 0: everything we know comes from the questionnaire.
  static ChronotypeEstimate fromQuestionnaire(HabitualSchedule s) {
    final msfSc = _msfSc(
      freeOnset: s.freeBedMinutes,
      freeDuration: s.freeDuration,
      workDuration: s.workDuration,
    );
    return ChronotypeEstimate(
      msfScMinutes: msfSc,
      chronotype: Chronotype.fromMsfSc(msfSc),
      confidence: PhaseConfidence.estimated,
      nightsUsed: 0,
    );
  }

  /// Re-estimate from logged sleep, falling back to the questionnaire when
  /// there isn't enough data yet.
  ///
  /// [utcOffsetFor] resolves the local UTC offset for a given instant, so a
  /// history spanning a DST change or a flight still lands on the right
  /// wall-clock midpoints.
  static ChronotypeEstimate fromSessions({
    required List<SleepSession> sessions,
    required HabitualSchedule fallback,
    required Duration Function(DateTime utc) utcOffsetFor,
    Set<int> freeDayWeekdays = const {DateTime.saturday, DateTime.sunday},
  }) {
    final usable = sessions
        .where((s) => !s.isDeleted)
        .where((s) => s.source != SleepSource.estimated)
        .where((s) => !s.isNap(utcOffsetFor(s.startUtc)))
        .toList();

    if (usable.isEmpty) return fromQuestionnaire(fallback);

    final midpoints = <double>[];
    final freeMidpoints = <double>[];
    final freeDurations = <double>[];
    final workDurations = <double>[];

    for (final s in usable) {
      final offset = utcOffsetFor(s.midpointUtc);
      final localMid = s.midpointUtc.add(offset);
      final minutes = localMid.hour * 60.0 + localMid.minute + localMid.second / 60.0;
      // Express small-hours midpoints as a continuous scale around midnight so
      // 23:40 and 00:20 average to midnight rather than to noon.
      final centred = minutes >= 720 ? minutes - 1440.0 : minutes;
      midpoints.add(centred);

      final localStart = s.startUtc.add(offset);
      // The "free day" is the day you wake up on.
      final wakeWeekday = s.endUtc.add(offset).weekday;
      final isFree = freeDayWeekdays.contains(wakeWeekday);

      if (isFree) {
        freeMidpoints.add(centred);
        freeDurations.add(s.duration.inMinutes.toDouble());
      } else {
        workDurations.add(s.duration.inMinutes.toDouble());
      }
      // localStart is intentionally unused beyond validation of the offset.
      assert(localStart.isBefore(localMid) || localStart == localMid);
    }

    final nights = usable.length;
    final sd = _standardDeviation(midpoints);

    // Not enough free days to compute a true MSF — blend the questionnaire with
    // the observed overall midpoint instead of inventing precision.
    if (freeMidpoints.isEmpty || freeDurations.isEmpty) {
      final observed = _mean(midpoints);
      final seeded = fromQuestionnaire(fallback).msfScMinutes;
      final blended = seeded + (observed - seeded) * math.min(1.0, nights / 14.0);
      return ChronotypeEstimate(
        msfScMinutes: blended,
        chronotype: Chronotype.fromMsfSc(blended),
        confidence: PhaseConfidence.fromNights(nights, midpointSdMinutes: sd),
        nightsUsed: nights,
        midpointSdMinutes: sd,
      );
    }

    final msf = _mean(freeMidpoints);
    final sdFree = _mean(freeDurations);
    final sdWork = workDurations.isEmpty ? sdFree : _mean(workDurations);
    final nFree = freeDurations.length;
    final nWork = workDurations.length;
    final sdWeek = (nFree + nWork) == 0
        ? sdFree
        : (sdWork * nWork + sdFree * nFree) / (nWork + nFree);

    // The MCTQ sleep-debt correction only applies when free-day sleep exceeds
    // the weekly average — i.e. when you're catching up.
    final msfSc = sdFree <= sdWeek ? msf : msf - (sdFree - sdWeek) / 2.0;

    return ChronotypeEstimate(
      msfScMinutes: msfSc,
      chronotype: Chronotype.fromMsfSc(msfSc),
      confidence: PhaseConfidence.fromNights(nights, midpointSdMinutes: sd),
      nightsUsed: nights,
      midpointSdMinutes: sd,
    );
  }

  /// Exponentially smooths a new estimate against the stored one so the value
  /// never jumps more than a few minutes from a single night.
  static double smooth(double previousMsfSc, double newMsfSc) =>
      previousMsfSc + emaAlpha * (newMsfSc - previousMsfSc);

  static double _msfSc({
    required double freeOnset,
    required double freeDuration,
    required double workDuration,
  }) {
    // Mid-sleep on free days, expressed around midnight.
    var msf = freeOnset + freeDuration / 2.0;
    msf %= 1440.0;
    if (msf >= 720) msf -= 1440.0;

    final sdWeek = (5 * workDuration + 2 * freeDuration) / 7.0;
    if (freeDuration <= sdWeek) return msf;
    return msf - (freeDuration - sdWeek) / 2.0;
  }

  static double _mean(List<double> xs) =>
      xs.reduce((a, b) => a + b) / xs.length;

  static double _standardDeviation(List<double> xs) {
    if (xs.length < 2) return 0;
    final m = _mean(xs);
    final variance =
        xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (xs.length - 1);
    return math.sqrt(variance);
  }
}
