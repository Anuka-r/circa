import 'dart:math' as math;

import '../entities/sleep_session.dart';

/// One night's contribution to the ledger.
class DebtNight {
  const DebtNight({
    required this.nightOf,
    required this.actualMinutes,
    required this.needMinutes,
    required this.ageInDays,
    required this.weight,
    required this.contributionMinutes,
    required this.wasLogged,
  });

  final String nightOf;
  final double actualMinutes;
  final double needMinutes;
  final int ageInDays;

  /// Exponential decay weight applied to this night.
  final double weight;

  /// Weighted signed contribution: positive adds debt, negative repays it.
  final double contributionMinutes;

  final bool wasLogged;
}

/// The running sleep-debt total.
class SleepDebt {
  const SleepDebt({
    required this.minutes,
    required this.nights,
    required this.nightsLogged,
  });

  /// Total debt in minutes, clamped to [0, 1200] (20 hours).
  final double minutes;

  final List<DebtNight> nights;
  final int nightsLogged;

  double get hours => minutes / 60.0;

  bool get isClear => hours < 1.0;

  /// Nights at a given nightly surplus needed to clear the debt.
  ///
  /// Surplus repays at half rate, which is why "one big lie-in" doesn't fix a
  /// week of short nights — and the app says so instead of implying otherwise.
  int nightsToClear({required double surplusMinutesPerNight}) {
    if (minutes <= 0 || surplusMinutesPerNight <= 0) return 0;
    return (minutes / (SleepDebtLedger.surplusRepayRate * surplusMinutesPerNight))
        .ceil();
  }

  static const empty = SleepDebt(minutes: 0, nights: [], nightsLogged: 0);
}

/// A 14-day rolling, decay-weighted sleep-debt ledger.
///
/// Two deliberate choices:
/// * **Surplus repays at half rate.** Sleeping an extra hour does not undo an
///   hour of deficit; recovery is real but asymmetric.
/// * **Old debt decays.** A deficit from 13 days ago contributes about 15% of
///   its face value. Without this, debt only ever climbs and the number stops
///   meaning anything.
abstract final class SleepDebtLedger {
  const SleepDebtLedger._();

  /// Rolling window.
  static const int windowDays = 14;

  /// Decay time constant in days; gives a half-life of ~4.85 days.
  static const double decayTauDays = 7.0;

  /// Fraction of a surplus that counts towards repayment.
  static const double surplusRepayRate = 0.5;

  /// Naps repay at half the rate of night sleep.
  static const double napRepayRate = 0.5;

  /// Hard ceiling so a pathological history can't produce an absurd number.
  static const double maxDebtMinutes = 1200; // 20 hours

  /// Computes debt as of [asOfNightOf] (a `yyyy-MM-dd` string).
  ///
  /// [sleepByNight] maps `nightOf` to total slept minutes for that night
  /// (already merged across biphasic segments and nap-adjusted by the caller).
  static SleepDebt compute({
    required Map<String, double> sleepByNight,
    required double needMinutes,
    required DateTime asOfDateLocal,
  }) {
    final nights = <DebtNight>[];
    var total = 0.0;
    var logged = 0;

    for (var age = 0; age < windowDays; age++) {
      final date = DateTime(
        asOfDateLocal.year,
        asOfDateLocal.month,
        asOfDateLocal.day,
      ).subtract(Duration(days: age));
      final key = formatNight(date);

      final actual = sleepByNight[key];
      final weight = math.exp(-age / decayTauDays);

      if (actual == null) {
        // An unlogged night is not a zero-sleep night. Contributing nothing is
        // the only honest option — inventing a deficit would punish people for
        // forgetting to log.
        nights.add(DebtNight(
          nightOf: key,
          actualMinutes: 0,
          needMinutes: needMinutes,
          ageInDays: age,
          weight: weight,
          contributionMinutes: 0,
          wasLogged: false,
        ));
        continue;
      }

      logged++;
      final deficit = math.max(0.0, needMinutes - actual);
      final surplus = math.max(0.0, actual - needMinutes) * surplusRepayRate;
      final contribution = weight * (deficit - surplus);
      total += contribution;

      nights.add(DebtNight(
        nightOf: key,
        actualMinutes: actual,
        needMinutes: needMinutes,
        ageInDays: age,
        weight: weight,
        contributionMinutes: contribution,
        wasLogged: true,
      ));
    }

    return SleepDebt(
      minutes: total.clamp(0.0, maxDebtMinutes),
      nights: nights,
      nightsLogged: logged,
    );
  }

  /// Collapses sessions into total slept minutes per night, applying the nap
  /// discount and letting the higher-precedence source win a same-night clash.
  static Map<String, double> aggregate(
    List<SleepSession> sessions, {
    required Duration Function(DateTime utc) utcOffsetFor,
  }) {
    final bySourcePrecedence = <String, int>{};
    final totals = <String, double>{};

    for (final s in sessions) {
      if (s.isDeleted) continue;
      if (s.source == SleepSource.estimated) continue;

      final minutes = s.duration.inMinutes.toDouble() *
          (s.isNap(utcOffsetFor(s.startUtc)) ? napRepayRate : 1.0);

      final existing = bySourcePrecedence[s.nightOf];
      if (existing == null) {
        bySourcePrecedence[s.nightOf] = s.source.precedence;
        totals[s.nightOf] = minutes;
      } else if (s.source.precedence > existing) {
        // A higher-precedence source replaces what's there.
        bySourcePrecedence[s.nightOf] = s.source.precedence;
        totals[s.nightOf] = minutes;
      } else if (s.source.precedence == existing) {
        // Same source: these are segments of one biphasic night, so they add.
        totals[s.nightOf] = (totals[s.nightOf] ?? 0) + minutes;
      }
    }
    return totals;
  }

  /// `yyyy-MM-dd` for a local date.
  static String formatNight(DateTime localDate) {
    final y = localDate.year.toString().padLeft(4, '0');
    final m = localDate.month.toString().padLeft(2, '0');
    final d = localDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// The night a local instant belongs to, anchored noon-to-noon.
  ///
  /// Sleep starting at 23:40 on the 5th and sleep starting at 00:20 on the 6th
  /// are the same night — this is what makes that true.
  static String nightOfLocal(DateTime localInstant) {
    final anchor = localInstant.hour < 12
        ? localInstant.subtract(const Duration(days: 1))
        : localInstant;
    return formatNight(DateTime(anchor.year, anchor.month, anchor.day));
  }
}
