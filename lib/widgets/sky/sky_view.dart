import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/circa_theme.dart';
import '../../core/theme/sky_palette.dart';
import '../../domain/value_objects/solar_day.dart';

/// The live sky.
///
/// Not decoration and not an asset: the gradient, the star field and the
/// position of the sun are all driven by the real solar altitude at the user's
/// coordinates at this instant. At 03:00 it is near-black with stars; at 06:50
/// amber bleeds from the horizon; at noon it is a pale high-key blue.
///
/// This is the thing people notice on day one and describe to other people.
class SkyView extends StatelessWidget {
  const SkyView({
    super.key,
    required this.solarDay,
    required this.nowUtc,
    this.showSunArc = true,
    this.child,
  });

  final SolarDay solarDay;
  final DateTime nowUtc;
  final bool showSunArc;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.circa.color;
    final motion = context.circa.motion;
    final altitude = solarDay.altitudeAt(nowUtc);
    final stops = SkyPalette.forAltitude(altitude, lightTheme: !colors.isDark);
    final starOpacity = SkyPalette.starOpacity(altitude);

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The gradient itself. Animated so that crossing a band boundary
          // eases rather than pops — the transition through sunrise takes
          // roughly forty real-world minutes and stays continuous throughout.
          AnimatedContainer(
            duration: motion.skyDrift,
            curve: Curves.linear,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: stops.colors,
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),

          if (starOpacity > 0 && colors.isDark)
            AnimatedOpacity(
              opacity: starOpacity,
              duration: motion.skyDrift,
              child: CustomPaint(
                painter: _StarFieldPainter(
                  seed: solarDay.date.day * 100 + solarDay.date.month,
                  twinkle: !motion.reduced,
                  phase: nowUtc.millisecondsSinceEpoch / 1000.0,
                ),
              ),
            ),

          if (showSunArc)
            CustomPaint(
              painter: _SunArcPainter(
                progress: solarDay.arcProgressAt(nowUtc),
                altitude: altitude,
                isDaylight: solarDay.isDaylight(nowUtc),
                trackColor: colors.textPrimary.withValues(alpha: 0.10),
              ),
            ),

          // Scrim so foreground text stays legible against a bright midday sky.
          IgnorePointer(
            child: AnimatedContainer(
              duration: motion.skyDrift,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.bgVoid.withValues(
                      alpha: SkyPalette.contentScrimOpacity(
                        altitude,
                        isDark: colors.isDark,
                      ),
                    ),
                    colors.bgBase.withValues(alpha: colors.isDark ? 0.75 : 0.55),
                  ],
                  stops: const [0.45, 1.0],
                ),
              ),
            ),
          ),

          ?child,
        ],
      ),
    );
  }
}

/// Deterministic star field.
///
/// Positions are seeded from the date rather than random, so stars do not jump
/// between rebuilds — a moving star field reads as a bug, not as sky.
class _StarFieldPainter extends CustomPainter {
  _StarFieldPainter({
    required this.seed,
    required this.twinkle,
    required this.phase,
  });

  final int seed;
  final bool twinkle;
  final double phase;

  static const _count = 140;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _count; i++) {
      final x = rng.nextDouble() * size.width;
      // Bias upward: stars thin out towards the horizon glow.
      final y = math.pow(rng.nextDouble(), 1.6).toDouble() * size.height * 0.85;
      final radius = 0.4 + rng.nextDouble() * 1.1;
      final baseOpacity = 0.25 + rng.nextDouble() * 0.6;

      var opacity = baseOpacity;
      if (twinkle) {
        // Each star has its own 4–7 s period.
        final period = 4.0 + rng.nextDouble() * 3.0;
        final offset = rng.nextDouble() * period;
        final t = ((phase + offset) % period) / period;
        opacity = baseOpacity * (0.55 + 0.45 * math.sin(t * 2 * math.pi));
      }

      paint.color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_StarFieldPainter old) =>
      old.seed != seed || old.phase != phase || old.twinkle != twinkle;
}

/// The sun (or moon) travelling its true arc across the header.
class _SunArcPainter extends CustomPainter {
  _SunArcPainter({
    required this.progress,
    required this.altitude,
    required this.isDaylight,
    required this.trackColor,
  });

  final double progress;
  final double altitude;
  final bool isDaylight;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * 0.86;
    final peakY = size.height * 0.22;
    final left = size.width * 0.06;
    final right = size.width * 0.94;

    // A parabola from horizon to horizon, peaking at solar noon.
    final path = Path()..moveTo(left, horizonY);
    path.quadraticBezierTo(
      size.width / 2,
      peakY - (horizonY - peakY) * 0.35,
      right,
      horizonY,
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = trackColor,
    );

    // Horizon line.
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(size.width, horizonY),
      Paint()
        ..strokeWidth = 1
        ..color = trackColor,
    );

    // Position along the parabola.
    final t = progress.clamp(0.0, 1.0);
    final x = _quadratic(left, size.width / 2, right, t);
    final y = _quadratic(
      horizonY,
      peakY - (horizonY - peakY) * 0.35,
      horizonY,
      t,
    );

    final bodyColor = SkyPalette.bodyColor(altitude);
    final glowColor = SkyPalette.bodyGlow(altitude);
    final radius = isDaylight ? 11.0 : 9.0;

    // Glow.
    canvas.drawCircle(
      Offset(x, y),
      radius * 3.2,
      Paint()
        ..color = glowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    if (isDaylight) {
      canvas.drawCircle(Offset(x, y), radius, Paint()..color = bodyColor);
      return;
    }

    // Night: carve a crescent so the marker reads as a moon rather than a dim
    // sun. The cut-out needs its own layer — a bare BlendMode.clear would
    // erase everything painted beneath it, not just the disc.
    final bounds = Rect.fromCircle(center: Offset(x, y), radius: radius * 2);
    canvas.saveLayer(bounds, Paint());
    canvas.drawCircle(Offset(x, y), radius, Paint()..color = bodyColor);
    canvas.drawCircle(
      Offset(x + radius * 0.55, y - radius * 0.25),
      radius * 0.92,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  static double _quadratic(double p0, double p1, double p2, double t) {
    final u = 1 - t;
    return u * u * p0 + 2 * u * t * p1 + t * t * p2;
  }

  @override
  bool shouldRepaint(_SunArcPainter old) =>
      old.progress != progress ||
      old.altitude != altitude ||
      old.isDaylight != isDaylight;
}
