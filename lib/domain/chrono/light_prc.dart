import 'dart:math' as math;

/// How the light was received. Determines the effective illuminance when the
/// user hasn't measured it.
enum LightKind {
  directSun('Direct sun', 60000),
  overcast('Outdoors, overcast', 8000),
  window('Through a window', 1200),
  indoor('Indoors', 150),
  lightBox('10,000 lux light box', 10000);

  const LightKind(this.label, this.typicalLux);
  final String label;
  final int typicalLux;

  /// Why "sitting by the window" is not the same as going outside — and the app
  /// says so rather than letting people believe otherwise.
  String get note => switch (this) {
        LightKind.directSun => 'The strongest signal you can give your clock.',
        LightKind.overcast =>
          'Still 20–50× brighter than a lit room. It counts.',
        LightKind.window =>
          'Glass and indoor geometry cost you most of it — about 1,200 lux.',
        LightKind.indoor =>
          'Office lighting is roughly 1/300th of a clear sky. Barely registers.',
        LightKind.lightBox =>
          'Effective when used at the right time, close to your face.',
      };
}

/// A single light exposure.
class LightExposure {
  const LightExposure({
    required this.atUtc,
    required this.durationMinutes,
    required this.lux,
  });

  final DateTime atUtc;
  final int durationMinutes;
  final int lux;
}

/// The result of applying the phase-response curve to a day's light.
class PhaseShift {
  const PhaseShift({
    required this.rawHours,
    required this.cappedHours,
    required this.wasCapped,
  });

  /// What the exposures would produce with no physiological ceiling.
  final double rawHours;

  /// What we actually apply. Positive advances (earlier), negative delays.
  final double cappedHours;

  final bool wasCapped;

  static const zero =
      PhaseShift(rawHours: 0, cappedHours: 0, wasCapped: false);
}

/// The light phase-response curve — the single most important behavioural lever
/// in the product.
///
/// Light **after** your core-temperature minimum advances the clock (pulls you
/// earlier); light **before** it delays the clock (pushes you later). The
/// crossing sits exactly at CBTmin, and there's an effectively dead zone
/// through the middle of the day.
///
/// The curve is deliberately asymmetric — advancing is harder than delaying,
/// which is why flying east is worse than flying west and why the jet-lag
/// planner is honest about taking days rather than one night.
abstract final class LightPrc {
  const LightPrc._();

  static const double _omega = 2 * math.pi / 24.0;

  // Advance lobe (τ > 0): peaks at ≈ +1.0 h around 2.3 h after CBTmin.
  static const double _advanceAmplitude = 2.72;
  static const double _advanceSigma = 3.5;

  // Delay lobe (τ < 0): peaks at ≈ −0.9 h around 3.5 h before CBTmin, and keeps
  // meaningful strength into the evening — 21:00 light really does delay you.
  static const double _delayAmplitude = 1.593;
  static const double _delaySigma = 6.0;

  /// Maximum phase advance achievable in 24 h, in hours.
  static const double maxAdvancePerDay = 1.0;

  /// Maximum phase delay achievable in 24 h, in hours. Delaying is easier.
  static const double maxDelayPerDay = 1.5;

  /// Response magnitude in hours per hour of bright light, as a function of
  /// [hoursFromCbtMin]. Positive = advance, negative = delay.
  static double responseAt(double hoursFromCbtMin) {
    final tau = _wrap(hoursFromCbtMin);
    final sine = math.sin(_omega * tau);

    if (tau >= 0) {
      final gaussian = math.exp(-math.pow(tau / _advanceSigma, 2));
      return _advanceAmplitude * sine * gaussian;
    }
    final gaussian = math.exp(-math.pow(tau / _delaySigma, 2));
    return _delayAmplitude * sine * gaussian;
  }

  /// Saturating intensity response. Doubling lux does **not** double the effect:
  /// 100 lx ≈ 0.29, 1,000 lx ≈ 0.59, 10,000 lx ≈ 0.84, 50,000 lx ≈ 0.93.
  ///
  /// This is why stepping outside on an overcast day is worth far more than the
  /// raw lux ratio against a bright office suggests.
  static double intensityFactor(int lux) {
    if (lux <= 0) return 0;
    final l = math.pow(lux.toDouble(), 0.55).toDouble();
    final half = math.pow(500.0, 0.55).toDouble();
    return l / (l + half);
  }

  /// Saturating duration response — the first ten minutes do most of the work.
  static double durationFactor(int minutes) {
    if (minutes <= 0) return 0;
    return 1 - math.exp(-minutes / 25.0);
  }

  /// Total phase shift produced by a set of exposures.
  ///
  /// [cbtMinUtc] is the core-body-temperature minimum the exposures are
  /// measured against.
  static PhaseShift totalShift({
    required List<LightExposure> exposures,
    required DateTime cbtMinUtc,
  }) {
    if (exposures.isEmpty) return PhaseShift.zero;

    var raw = 0.0;
    for (final e in exposures) {
      // Measure from the midpoint of the exposure, not its start.
      final mid = e.atUtc.add(Duration(minutes: e.durationMinutes ~/ 2));
      final tau = mid.difference(cbtMinUtc).inMinutes / 60.0;

      raw += responseAt(tau) *
          intensityFactor(e.lux) *
          durationFactor(e.durationMinutes);
    }

    final capped = raw.clamp(-maxDelayPerDay, maxAdvancePerDay);
    return PhaseShift(
      rawHours: raw,
      cappedHours: capped,
      wasCapped: (raw - capped).abs() > 1e-9,
    );
  }

  /// The window during which light will *advance* the clock, expressed as hours
  /// from CBTmin. Used to place the morning-light protocol event.
  static (double startTau, double endTau) get advanceWindow => (0.5, 6.0);

  /// The window during which light will *delay* the clock — what to avoid when
  /// trying to get to sleep earlier.
  static (double startTau, double endTau) get delayWindow => (-8.0, -0.5);

  /// True when light at [hoursFromCbtMin] pushes the clock later.
  static bool isDelayZone(double hoursFromCbtMin) =>
      responseAt(hoursFromCbtMin) < -0.05;

  /// True when light at [hoursFromCbtMin] pulls the clock earlier.
  static bool isAdvanceZone(double hoursFromCbtMin) =>
      responseAt(hoursFromCbtMin) > 0.05;

  /// Wraps an arbitrary offset into the (−12, 12] hours the curve is defined on.
  static double _wrap(double hours) {
    var h = hours % 24.0;
    if (h > 12) h -= 24.0;
    if (h <= -12) h += 24.0;
    return h;
  }
}
