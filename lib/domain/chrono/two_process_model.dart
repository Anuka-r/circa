import 'dart:math' as math;

import 'caffeine_model.dart';

/// A sleep or planned-sleep interval, in UTC.
class SleepWindow {
  const SleepWindow({required this.startUtc, required this.endUtc});
  final DateTime startUtc;
  final DateTime endUtc;

  bool contains(DateTime utc) =>
      !utc.isBefore(startUtc) && utc.isBefore(endUtc);

  Duration get duration => endUtc.difference(startUtc);
}

/// One sample of the forecast.
class EnergyPoint {
  const EnergyPoint({
    required this.atUtc,
    required this.alertness,
    required this.processS,
    required this.processC,
    required this.caffeine,
    required this.inertia,
    required this.asleep,
  });

  final DateTime atUtc;

  /// Composite alertness, 0..1.
  final double alertness;

  /// Homeostatic sleep pressure, 0..1. Higher = sleepier.
  final double processS;

  /// Circadian drive, −1..1.
  final double processC;

  /// Caffeine contribution, 0..1.
  final double caffeine;

  /// Sleep-inertia penalty, 0..0.55.
  final double inertia;

  final bool asleep;
}

/// A named feature of the forecast curve, used for the annotations on the chart.
class EnergyFeature {
  const EnergyFeature({
    required this.atUtc,
    required this.alertness,
    required this.kind,
    required this.dominantCause,
  });

  final DateTime atUtc;
  final double alertness;
  final EnergyFeatureKind kind;

  /// Which process contributed most to this feature — this is what lets the app
  /// say "mostly sleep debt" rather than just drawing a dip.
  final EnergyCause dominantCause;
}

enum EnergyFeatureKind { morningPeak, afternoonDip, eveningPeak, nightLow }

enum EnergyCause {
  sleepPressure('sleep debt'),
  circadian('your body clock'),
  caffeine('caffeine'),
  inertia('waking up');

  const EnergyCause(this.plainLabel);
  final String plainLabel;
}

/// Borbély's two-process model of alertness: a homeostatic pressure that builds
/// while awake and dissipates during sleep, riding on a circadian oscillation.
///
/// The harmonic coefficients below were fitted numerically so the composite
/// curve reproduces the three features people actually recognise in their own
/// day — a late-morning peak, a mid-afternoon dip around eight hours after
/// waking, and an evening "wake maintenance" rebound. A pure sinusoid produces
/// none of them.
abstract final class TwoProcessModel {
  const TwoProcessModel._();

  /// Rise time constant of Process S while awake, in hours.
  static const double tauRise = 18.2;

  /// Decay time constant of Process S while asleep, in hours.
  static const double tauDecay = 4.2;

  // Circadian harmonics — see the fitting note above.
  static const double _a2 = 0.45;
  static const double _p2 = 1.83260;
  static const double _a3 = 0.12;
  static const double _p3 = math.pi / 2;

  /// Weight of the circadian drive in the composite.
  static const double kCircadian = 0.42;

  /// Weight of the homeostatic pressure in the composite.
  static const double kHomeostatic = 0.48;

  /// Baseline offset, chosen so a rested person sits around 0.75 at their peak.
  static const double baseline = 0.72;

  /// Peak sleep-inertia penalty immediately on waking.
  static const double inertiaPeak = 0.55;

  /// Inertia decay constant, in hours (≈95% gone after an hour).
  static const double inertiaTau = 0.35;

  /// Burn-in before the requested window so Process S is well-conditioned
  /// rather than seeded from a guess.
  static const Duration burnIn = Duration(days: 3);

  static const double _omega = 2 * math.pi / 24.0;

  /// Circadian drive at a local hour-of-day, given the CBTmin anchor.
  ///
  /// Normalised so the fundamental's minimum sits exactly on CBTmin.
  static double processC({
    required double localHourOfDay,
    required double cbtMinLocalHour,
  }) {
    final theta = _omega * (localHourOfDay - cbtMinLocalHour) - math.pi / 2;
    return math.sin(theta) +
        _a2 * math.sin(2 * theta + _p2) +
        _a3 * math.sin(3 * theta + _p3);
  }

  /// Simulates alertness across [fromUtc]..[toUtc] at [step] resolution.
  ///
  /// [sleepWindows] should contain both real past sleep and the planned future
  /// sleep window, so the forecast reflects the night the user intends to have.
  static List<EnergyPoint> simulate({
    required DateTime fromUtc,
    required DateTime toUtc,
    required List<SleepWindow> sleepWindows,
    required double cbtMinLocalHour,
    required Duration utcOffset,
    List<CaffeineDose> caffeine = const [],
    double caffeineHalfLifeMinutes = CaffeineModel.defaultHalfLifeMinutes,
    Duration step = const Duration(minutes: 10),
  }) {
    final windows = [...sleepWindows]
      ..sort((a, b) => a.startUtc.compareTo(b.startUtc));

    final simStart = fromUtc.subtract(burnIn);
    final stepHours = step.inMilliseconds / 3600000.0;

    // Seed at a plausible mid-range pressure; three days of burn-in washes out
    // any error in this choice.
    var s = 0.55;
    DateTime? lastWakeUtc;

    final out = <EnergyPoint>[];

    for (var t = simStart;
        !t.isAfter(toUtc);
        t = t.add(step)) {
      final asleep = windows.any((w) => w.contains(t));

      if (asleep) {
        s = s * math.exp(-stepHours / tauDecay);
      } else {
        s = 1 - (1 - s) * math.exp(-stepHours / tauRise);
      }

      // Track the most recent wake transition for sleep inertia.
      final prev = t.subtract(step);
      final wasAsleep = windows.any((w) => w.contains(prev));
      if (wasAsleep && !asleep) lastWakeUtc = t;

      if (t.isBefore(fromUtc)) continue;

      final local = t.add(utcOffset);
      final hourOfDay =
          local.hour + local.minute / 60.0 + local.second / 3600.0;

      final c = processC(
        localHourOfDay: hourOfDay,
        cbtMinLocalHour: cbtMinLocalHour,
      );

      final hoursSinceWake = lastWakeUtc == null
          ? 99.0
          : t.difference(lastWakeUtc).inMinutes / 60.0;
      final inertia = asleep
          ? 0.0
          : inertiaPeak * math.exp(-hoursSinceWake / inertiaTau);

      // Plasma, not total on board: the alertness effect follows what has
      // actually been absorbed.
      final residual = CaffeineModel.plasmaMg(
        doses: caffeine,
        atUtc: t,
        halfLifeMinutes: caffeineHalfLifeMinutes,
      );
      final caffeineEffect = CaffeineModel.alertnessEffect(residual) * 0.25;

      final alertness = (baseline +
              kCircadian * c -
              kHomeostatic * s -
              inertia +
              caffeineEffect)
          .clamp(0.0, 1.0);

      out.add(EnergyPoint(
        atUtc: t,
        alertness: alertness,
        processS: s,
        processC: c,
        caffeine: caffeineEffect,
        inertia: inertia,
        asleep: asleep,
      ));
    }

    return out;
  }

  /// Minimum prominence, as a fraction of the day's alertness range, for an
  /// extremum to be worth annotating. Below this it's a ripple, not a feature.
  static const double _minProminenceFraction = 0.08;

  /// Finds the peaks and dips worth annotating on the chart.
  ///
  /// Only waking points are considered — a trough at 04:00 while asleep is not
  /// something to warn anyone about.
  ///
  /// Features are classified by their **ordinal position within the waking
  /// day**, not by thresholds on the underlying processes. The first peak is
  /// the morning one whatever the circadian drive happens to be; a trough
  /// bracketed by two peaks is the afternoon dip. Threshold-based labelling
  /// gets this wrong precisely when the user's phase is unusual — which is
  /// exactly who this app is for.
  static List<EnergyFeature> findFeatures(List<EnergyPoint> points) {
    final features = <EnergyFeature>[];

    for (final run in _awakeRuns(points)) {
      if (run.length < 5) continue;

      final values = run.map((p) => p.alertness).toList();
      final range = values.reduce(math.max) - values.reduce(math.min);
      if (range < 0.02) continue;
      final minProminence = range * _minProminenceFraction;

      // Collect interior extrema in chronological order.
      final extrema = <({int index, bool isMax})>[];
      for (var i = 1; i < run.length - 1; i++) {
        final prev = values[i - 1];
        final cur = values[i];
        final next = values[i + 1];
        final isMax = cur > prev && cur >= next;
        final isMin = cur < prev && cur <= next;
        if (!isMax && !isMin) continue;

        // Collapse plateaus: keep only the first sample of a flat run.
        if (extrema.isNotEmpty &&
            extrema.last.isMax == isMax &&
            i - extrema.last.index < 6) {
          continue;
        }
        extrema.add((index: i, isMax: isMax));
      }

      // Drop extrema that aren't prominent enough against their neighbours.
      final prominent = <({int index, bool isMax})>[];
      for (var k = 0; k < extrema.length; k++) {
        final e = extrema[k];
        final left = k == 0 ? values.first : values[extrema[k - 1].index];
        final right =
            k == extrema.length - 1 ? values.last : values[extrema[k + 1].index];
        final v = values[e.index];
        final prominence =
            e.isMax ? v - math.max(left, right) : math.min(left, right) - v;
        if (prominence >= minProminence) prominent.add(e);
      }

      // Classify by order: first max = morning, later maxima = evening, a
      // trough between two maxima = the afternoon dip.
      var maximaSeen = 0;
      for (var k = 0; k < prominent.length; k++) {
        final e = prominent[k];
        final point = run[e.index];

        final EnergyFeatureKind kind;
        if (e.isMax) {
          kind = maximaSeen == 0
              ? EnergyFeatureKind.morningPeak
              : EnergyFeatureKind.eveningPeak;
          maximaSeen++;
        } else {
          final bracketed = k > 0 &&
              k < prominent.length - 1 &&
              prominent[k - 1].isMax &&
              prominent[k + 1].isMax;
          kind = bracketed
              ? EnergyFeatureKind.afternoonDip
              : EnergyFeatureKind.nightLow;
        }

        features.add(EnergyFeature(
          atUtc: point.atUtc,
          alertness: point.alertness,
          kind: kind,
          dominantCause: _dominantCause(point),
        ));
      }
    }

    return features;
  }

  /// Splits the samples into contiguous runs of wakefulness, so a peak on
  /// Monday and a peak on Tuesday are never treated as one feature.
  static List<List<EnergyPoint>> _awakeRuns(List<EnergyPoint> points) {
    final runs = <List<EnergyPoint>>[];
    var current = <EnergyPoint>[];
    for (final p in points) {
      if (p.asleep) {
        if (current.isNotEmpty) {
          runs.add(current);
          current = <EnergyPoint>[];
        }
        continue;
      }
      current.add(p);
    }
    if (current.isNotEmpty) runs.add(current);
    return runs;
  }

  /// Attributes a feature to whichever term moved the composite furthest from
  /// its baseline at that instant.
  static EnergyCause _dominantCause(EnergyPoint p) {
    final contributions = <EnergyCause, double>{
      EnergyCause.sleepPressure: (kHomeostatic * p.processS).abs(),
      EnergyCause.circadian: (kCircadian * p.processC).abs(),
      EnergyCause.caffeine: p.caffeine.abs(),
      EnergyCause.inertia: p.inertia.abs(),
    };
    var best = EnergyCause.circadian;
    var bestValue = -1.0;
    contributions.forEach((cause, value) {
      if (value > bestValue) {
        bestValue = value;
        best = cause;
      }
    });
    return best;
  }
}
