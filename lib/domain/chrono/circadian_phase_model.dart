import '../value_objects/chronotype.dart';
import 'chronotype_estimator.dart';

/// The two anchors everything downstream depends on.
class PhaseEstimate {
  const PhaseEstimate({
    required this.dlmoLocalHour,
    required this.cbtMinLocalHour,
    required this.confidence,
    required this.chronotype,
    required this.msfScMinutes,
    required this.disagreementHours,
  });

  /// Dim-light melatonin onset, as a local hour-of-day (0..24). The start of
  /// the biological night.
  final double dlmoLocalHour;

  /// Core body temperature minimum, as a local hour-of-day (0..24). The pivot
  /// of the light phase-response curve.
  final double cbtMinLocalHour;

  final PhaseConfidence confidence;
  final Chronotype chronotype;
  final double msfScMinutes;

  /// How far apart the two independent CBTmin estimators were, in hours.
  /// Large disagreement downgrades confidence rather than being hidden.
  final double disagreementHours;

  /// Suggested bedtime — roughly two hours after melatonin onset.
  double get idealBedLocalHour =>
      CircadianPhaseModel.wrapHour(dlmoLocalHour + 2.0);

  /// Suggested wake — roughly two hours after the temperature minimum.
  double get idealWakeLocalHour =>
      CircadianPhaseModel.wrapHour(cbtMinLocalHour + 2.0);
}

/// Estimates circadian phase from sleep behaviour.
///
/// Two independent estimators are computed and cross-checked. When they
/// disagree by more than an hour we take the data-weighted mean and *lower the
/// stated confidence* — the alternative, silently picking one, produces a
/// number that looks authoritative and isn't.
abstract final class CircadianPhaseModel {
  const CircadianPhaseModel._();

  /// Melatonin onset precedes habitual sleep onset by about two hours.
  static const double dlmoBeforeSleepOnsetHours = 2.0;

  /// The temperature minimum trails melatonin onset by about seven hours.
  static const double cbtMinAfterDlmoHours = 7.0;

  /// The temperature minimum sits just after mid-sleep.
  static const double cbtMinAfterMidSleepHours = 0.5;

  /// Disagreement beyond this many hours downgrades confidence.
  static const double disagreementToleranceHours = 1.0;

  static PhaseEstimate estimate({
    required ChronotypeEstimate chronotype,
    required HabitualSchedule schedule,
  }) {
    // Estimator A: from mid-sleep on free days.
    final msfScHour = wrapHour(chronotype.msfScMinutes / 60.0);
    final cbtFromMidSleep = wrapHour(msfScHour + cbtMinAfterMidSleepHours);

    // Estimator B: from habitual sleep onset, via melatonin onset.
    final sleepOnsetHour = wrapHour(schedule.freeBedMinutes / 60.0);
    final dlmoHour = wrapHour(sleepOnsetHour - dlmoBeforeSleepOnsetHours);
    final cbtFromDlmo = wrapHour(dlmoHour + cbtMinAfterDlmoHours);

    final disagreement = _circularDistanceHours(cbtFromMidSleep, cbtFromDlmo);

    // Circular mean of the two estimates, so 23:30 and 00:30 average to
    // midnight rather than to noon.
    final cbtMin = _circularMean(cbtFromMidSleep, cbtFromDlmo);

    var confidence = chronotype.confidence;
    if (disagreement > disagreementToleranceHours) {
      confidence = _downgrade(confidence);
    }

    return PhaseEstimate(
      dlmoLocalHour: dlmoHour,
      cbtMinLocalHour: cbtMin,
      confidence: confidence,
      chronotype: chronotype.chronotype,
      msfScMinutes: chronotype.msfScMinutes,
      disagreementHours: disagreement,
    );
  }

  /// Applies an accumulated phase shift, respecting the daily physiological
  /// ceiling that the caller has already enforced.
  static PhaseEstimate shifted(PhaseEstimate from, double shiftHours) =>
      PhaseEstimate(
        // A positive shift advances, i.e. moves the clock earlier.
        dlmoLocalHour: wrapHour(from.dlmoLocalHour - shiftHours),
        cbtMinLocalHour: wrapHour(from.cbtMinLocalHour - shiftHours),
        confidence: from.confidence,
        chronotype: from.chronotype,
        msfScMinutes: from.msfScMinutes - shiftHours * 60.0,
        disagreementHours: from.disagreementHours,
      );

  static PhaseConfidence _downgrade(PhaseConfidence c) => switch (c) {
        PhaseConfidence.high => PhaseConfidence.medium,
        PhaseConfidence.medium => PhaseConfidence.low,
        PhaseConfidence.low => PhaseConfidence.estimated,
        PhaseConfidence.estimated => PhaseConfidence.estimated,
      };

  /// Normalises an hour into [0, 24).
  static double wrapHour(double hour) {
    var h = hour % 24.0;
    if (h < 0) h += 24.0;
    return h;
  }

  /// Shortest distance between two hours-of-day, in hours (0..12).
  static double _circularDistanceHours(double a, double b) {
    final raw = (a - b).abs() % 24.0;
    return raw > 12 ? 24 - raw : raw;
  }

  /// Mean of two hours-of-day taken the short way round the clock.
  static double _circularMean(double a, double b) {
    var diff = b - a;
    while (diff > 12) {
      diff -= 24;
    }
    while (diff < -12) {
      diff += 24;
    }
    return wrapHour(a + diff / 2);
  }
}
