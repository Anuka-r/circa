import 'dart:math' as math;

/// A single caffeine dose.
class CaffeineDose {
  const CaffeineDose({required this.atUtc, required this.mg});
  final DateTime atUtc;
  final double mg;
}

/// A drink preset. Values are typical servings, not marketing claims.
class DrinkPreset {
  const DrinkPreset(this.key, this.label, this.mg, this.servingMl);
  final String key;
  final String label;
  final int mg;
  final int servingMl;

  static const all = <DrinkPreset>[
    DrinkPreset('espresso', 'Espresso', 63, 30),
    DrinkPreset('doubleEspresso', 'Double espresso', 125, 60),
    DrinkPreset('drip', 'Filter coffee', 95, 240),
    DrinkPreset('latte', 'Latte / cappuccino', 77, 350),
    DrinkPreset('instant', 'Instant coffee', 62, 240),
    DrinkPreset('coldBrew', 'Cold brew', 155, 350),
    DrinkPreset('blackTea', 'Black tea', 47, 240),
    DrinkPreset('greenTea', 'Green tea', 28, 240),
    DrinkPreset('matcha', 'Matcha', 70, 240),
    DrinkPreset('energyDrink', 'Energy drink', 80, 250),
    DrinkPreset('cola', 'Cola', 34, 355),
    DrinkPreset('darkChocolate', 'Dark chocolate (50g)', 30, 0),
  ];

  static DrinkPreset? byKey(String key) {
    for (final d in all) {
      if (d.key == key) return d;
    }
    return null;
  }
}

/// How sensitive the user says they are to caffeine. Sets the residual they can
/// tolerate at bedtime.
enum CaffeineSensitivity {
  sensitive('Sensitive', 15),
  typical('Typical', 30),
  tolerant('Tolerant', 50);

  const CaffeineSensitivity(this.label, this.bedtimeThresholdMg);
  final String label;
  final int bedtimeThresholdMg;
}

/// Single-compartment, first-order caffeine pharmacokinetics.
///
/// This is the model behind the number that surprises people most: a 95 mg
/// filter coffee at 13:30 still leaves ~30 mg on board at an 23:00 bedtime.
abstract final class CaffeineModel {
  const CaffeineModel._();

  /// Population default elimination half-life. Adjustable 4.0–9.0 h in settings
  /// because the real spread between individuals is enormous (oral
  /// contraceptives roughly double it; heavy smoking roughly halves it).
  static const double defaultHalfLifeMinutes = 342; // 5.7 h

  /// Absorption is not instantaneous — a coffee 20 minutes ago is not yet fully
  /// on board. Modelled as a linear ramp.
  static const double absorptionMinutes = 45;

  /// Dose giving a half-maximal alertness effect, in mg.
  static const double halfEffectMg = 120;

  /// Milligrams **in plasma** at [atUtc] — absorption ramp included.
  ///
  /// This is the right quantity for the alertness curve: a coffee twenty
  /// minutes ago is not yet doing its full job.
  static double plasmaMg({
    required List<CaffeineDose> doses,
    required DateTime atUtc,
    double halfLifeMinutes = defaultHalfLifeMinutes,
  }) {
    var total = 0.0;
    for (final dose in doses) {
      final elapsed = atUtc.difference(dose.atUtc).inMinutes.toDouble();
      if (elapsed < 0) continue;

      // Linear absorption ramp, then first-order decay from full absorption.
      if (elapsed < absorptionMinutes) {
        total += dose.mg * (elapsed / absorptionMinutes);
        continue;
      }
      final decayFor = elapsed - absorptionMinutes;
      total += dose.mg * math.pow(0.5, decayFor / halfLifeMinutes);
    }
    return total;
  }

  /// Milligrams **still in the body** at [atUtc] — elimination only, measured
  /// from the moment of ingestion.
  ///
  /// This is the right quantity for the bedtime threshold and the cutoff time.
  /// Using the plasma figure there would be actively misleading: an espresso
  /// downed at bedtime has barely reached the bloodstream, so a plasma-based
  /// check would call it harmless when in fact the entire dose is about to
  /// arrive and then sit there for hours.
  static double onBoardMg({
    required List<CaffeineDose> doses,
    required DateTime atUtc,
    double halfLifeMinutes = defaultHalfLifeMinutes,
  }) {
    var total = 0.0;
    for (final dose in doses) {
      final elapsed = atUtc.difference(dose.atUtc).inMinutes.toDouble();
      if (elapsed < 0) continue;
      total += dose.mg * math.pow(0.5, elapsed / halfLifeMinutes);
    }
    return total;
  }

  /// Saturating alertness contribution in 0..1 for a given residual.
  static double alertnessEffect(double residual) =>
      residual <= 0 ? 0.0 : residual / (residual + halfEffectMg);

  /// The latest time you could take [plannedMg] and still have no more than
  /// [thresholdMg] on board by [bedtimeUtc].
  ///
  /// Closed form, so it costs nothing to recompute on every keystroke:
  ///   t = bedtime − halfLife · log₂(planned / threshold)
  static DateTime? cutoffTime({
    required DateTime bedtimeUtc,
    required double plannedMg,
    required double thresholdMg,
    double halfLifeMinutes = defaultHalfLifeMinutes,
  }) {
    if (plannedMg <= 0) return null;
    if (plannedMg <= thresholdMg) return bedtimeUtc;

    final halfLives = math.log(plannedMg / thresholdMg) / math.ln2;
    final minutesBefore = halfLives * halfLifeMinutes;
    return bedtimeUtc.subtract(Duration(minutes: minutesBefore.round()));
  }

  /// How many minutes past the cutoff a dose was taken. Negative means it was
  /// safely before. Used for the `caffeine_logged` analytics dimension.
  static int minutesRelativeToCutoff({
    required DateTime doseAtUtc,
    required DateTime cutoffUtc,
  }) =>
      doseAtUtc.difference(cutoffUtc).inMinutes;

  /// Given existing doses, how much more could be taken now without exceeding
  /// [thresholdMg] at bedtime. Returns 0 when already over budget.
  static double headroomMg({
    required List<CaffeineDose> doses,
    required DateTime nowUtc,
    required DateTime bedtimeUtc,
    required double thresholdMg,
    double halfLifeMinutes = defaultHalfLifeMinutes,
  }) {
    final atBed = onBoardMg(
      doses: doses,
      atUtc: bedtimeUtc,
      halfLifeMinutes: halfLifeMinutes,
    );
    final remaining = thresholdMg - atBed;
    if (remaining <= 0) return 0;

    final minutesToBed = bedtimeUtc.difference(nowUtc).inMinutes.toDouble();
    if (minutesToBed <= 0) return remaining;

    // Invert the decay: how large a dose now decays to `remaining` by bedtime?
    final surviving = math.pow(0.5, minutesToBed / halfLifeMinutes).toDouble();
    if (surviving <= 0) return double.infinity;
    return remaining / surviving;
  }
}
