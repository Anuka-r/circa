import 'package:flutter/material.dart';

/// Spacing, radius, elevation and motion tokens.
///
/// Feature code never writes a raw number — `context.circa.space.lg`, not `20`.
@immutable
class CircaSpace extends ThemeExtension<CircaSpace> {
  const CircaSpace();

  double get xxs => 2;
  double get xs => 4;
  double get sm => 8;
  double get md => 12;
  double get base => 16;
  double get lg => 20;
  double get xl => 24;
  double get xxl => 32;
  double get x3 => 40;
  double get x4 => 56;
  double get x5 => 72;

  /// Horizontal screen gutter for the given width.
  double gutter(double width) {
    if (width >= 840) return 48;
    if (width >= 600) return 32;
    return 20;
  }

  /// Vertical rhythm between major sections.
  double get section => 32;

  /// Maximum readable content width on large screens.
  double get maxContentWidth => 720;

  @override
  CircaSpace copyWith() => const CircaSpace();

  @override
  CircaSpace lerp(ThemeExtension<CircaSpace>? other, double t) => this;
}

@immutable
class CircaRadii extends ThemeExtension<CircaRadii> {
  const CircaRadii();

  double get xs => 6;
  double get sm => 10;
  double get md => 14;
  double get lg => 20;
  double get xl => 28;
  double get xxl => 36;
  double get pill => 999;

  BorderRadius get cardRadius => BorderRadius.circular(20);
  BorderRadius get sheetRadius =>
      const BorderRadius.vertical(top: Radius.circular(36));
  BorderRadius get inputRadius => BorderRadius.circular(14);
  BorderRadius get pillRadius => BorderRadius.circular(999);

  @override
  CircaRadii copyWith() => const CircaRadii();

  @override
  CircaRadii lerp(ThemeExtension<CircaRadii>? other, double t) => this;
}

/// One rung of the glass elevation ladder.
///
/// Each level is a fill opacity, a backdrop blur sigma, a top hairline opacity
/// and a shadow stack. The top hairline is the whole trick — a 1px gradient on
/// the top edge only, fading out by 40% down the pane, reading as light caught
/// on a glass edge.
@immutable
class CircaElevationLevel {
  const CircaElevationLevel({
    required this.fillOpacity,
    required this.blurSigma,
    required this.hairlineOpacity,
    required this.shadows,
  });

  final double fillOpacity;
  final double blurSigma;
  final double hairlineOpacity;
  final List<BoxShadow> shadows;
}

@immutable
class CircaElevation extends ThemeExtension<CircaElevation> {
  const CircaElevation();

  static const _shadowColor = Color(0xFF000000);

  CircaElevationLevel get e1 => CircaElevationLevel(
        fillOpacity: 0.72,
        blurSigma: 18,
        hairlineOpacity: 0.08,
        shadows: [
          BoxShadow(
            color: _shadowColor.withValues(alpha: 0.20),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: _shadowColor.withValues(alpha: 0.14),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      );

  CircaElevationLevel get e2 => CircaElevationLevel(
        fillOpacity: 0.80,
        blurSigma: 24,
        hairlineOpacity: 0.10,
        shadows: [
          BoxShadow(
            color: _shadowColor.withValues(alpha: 0.24),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: _shadowColor.withValues(alpha: 0.18),
            offset: const Offset(0, 10),
            blurRadius: 28,
          ),
        ],
      );

  CircaElevationLevel get e3 => CircaElevationLevel(
        fillOpacity: 0.88,
        blurSigma: 32,
        hairlineOpacity: 0.12,
        shadows: [
          BoxShadow(
            color: _shadowColor.withValues(alpha: 0.28),
            offset: const Offset(0, -2),
            blurRadius: 6,
          ),
          BoxShadow(
            color: _shadowColor.withValues(alpha: 0.24),
            offset: const Offset(0, -16),
            blurRadius: 48,
          ),
        ],
      );

  CircaElevationLevel get e4 => CircaElevationLevel(
        fillOpacity: 0.94,
        blurSigma: 40,
        hairlineOpacity: 0.14,
        shadows: [
          BoxShadow(
            color: _shadowColor.withValues(alpha: 0.30),
            offset: const Offset(0, 8),
            blurRadius: 16,
          ),
          BoxShadow(
            color: _shadowColor.withValues(alpha: 0.28),
            offset: const Offset(0, 24),
            blurRadius: 64,
          ),
        ],
      );

  @override
  CircaElevation copyWith() => const CircaElevation();

  @override
  CircaElevation lerp(ThemeExtension<CircaElevation>? other, double t) => this;
}

/// Motion tokens. Durations collapse under reduced-motion — see
/// `CircaMotion.scaled`.
@immutable
class CircaMotion extends ThemeExtension<CircaMotion> {
  const CircaMotion({this.reduced = false});

  /// True when the platform asks for reduced motion. Every duration getter
  /// respects it, so no call site has to remember.
  final bool reduced;

  Duration get instant => _d(80);
  Duration get quick => _d(140);
  Duration get base => _d(220);
  Duration get slow => _d(340);
  Duration get deliberate => _d(520);
  Duration get ambient => _d(900);

  /// Sky cross-fade when the solar altitude band changes.
  Duration get skyDrift => reduced ? Duration.zero : const Duration(seconds: 2);

  Duration _d(int ms) => Duration(
        milliseconds: reduced ? (ms > 120 ? 120 : ms) : ms,
      );

  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve decelerate = Cubic(0, 0, 0, 1);
  static const Curve accelerate = Cubic(0.3, 0, 1, 1);
  static const Curve overshoot = Cubic(0.34, 1.56, 0.64, 1);

  /// Used for sheets and drag hand-off.
  static const SpringDescription spring =
      SpringDescription(mass: 1, stiffness: 400, damping: 30);

  @override
  CircaMotion copyWith({bool? reduced}) =>
      CircaMotion(reduced: reduced ?? this.reduced);

  @override
  CircaMotion lerp(ThemeExtension<CircaMotion>? other, double t) => this;
}
