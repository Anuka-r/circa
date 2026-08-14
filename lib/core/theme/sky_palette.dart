import 'dart:ui' show Color, lerpDouble;

import 'package:flutter/material.dart' show Colors, HSLColor;

/// The sky is not a static asset — it is a function of solar altitude.
///
/// This is the thing users notice on day one and describe to other people: at
/// 03:00 the home screen is near-black with stars, at 06:50 it bleeds amber
/// from the horizon, at noon it is a pale high-key blue. It moves because the
/// real sun moves.
///
/// Bands are interpolated continuously, so the transition across sunrise takes
/// about forty real-world minutes and never pops between keyframes.
class SkyStops {
  const SkyStops(this.top, this.middle, this.horizon, this.name);

  /// Zenith colour — top of the gradient.
  final Color top;

  /// Mid-sky.
  final Color middle;

  /// At the horizon line, where the sun actually is.
  final Color horizon;

  /// Human-readable band name, used in semantics and debug overlays.
  final String name;

  static SkyStops lerp(SkyStops a, SkyStops b, double t) => SkyStops(
        Color.lerp(a.top, b.top, t)!,
        Color.lerp(a.middle, b.middle, t)!,
        Color.lerp(a.horizon, b.horizon, t)!,
        t < 0.5 ? a.name : b.name,
      );

  List<Color> get colors => [top, middle, horizon];
}

abstract final class SkyPalette {
  const SkyPalette._();

  /// Band boundaries in degrees of solar altitude, paired with their stops.
  /// Ordered from deepest night to full day.
  static const List<(double altitude, SkyStops stops)> _bands = [
    (
      -90,
      SkyStops(
        Color(0xFF05070F),
        Color(0xFF080B16),
        Color(0xFF0B1024),
        'Astronomical night',
      )
    ),
    (
      -18,
      SkyStops(
        Color(0xFF070A16),
        Color(0xFF0E1430),
        Color(0xFF141B47),
        'Astronomical twilight',
      )
    ),
    (
      -12,
      SkyStops(
        Color(0xFF0A1030),
        Color(0xFF1A2158),
        Color(0xFF33306E),
        'Nautical twilight',
      )
    ),
    (
      -6,
      SkyStops(
        Color(0xFF141A45),
        Color(0xFF4A3A76),
        Color(0xFFB2607A),
        'Civil twilight',
      )
    ),
    (
      0,
      SkyStops(
        Color(0xFF233B7A),
        Color(0xFF8B5A8C),
        Color(0xFFFF9E5E),
        'Sunrise',
      )
    ),
    (
      6,
      SkyStops(
        Color(0xFF2E5FA8),
        Color(0xFF5E8FC4),
        Color(0xFFFFC98A),
        'Golden',
      )
    ),
    (
      25,
      SkyStops(
        Color(0xFF3B7BC4),
        Color(0xFF7FB2DC),
        Color(0xFFC9E3F2),
        'Day',
      )
    ),
  ];

  /// Interpolated sky for a given solar altitude in degrees.
  ///
  /// [lightTheme] renders the same function at reduced saturation and raised
  /// lightness, so the sky reads as a tint rather than a photograph — otherwise
  /// light mode would be unreadable at 3am.
  static SkyStops forAltitude(double altitudeDeg, {bool lightTheme = false}) {
    final stops = _interpolate(altitudeDeg);
    if (!lightTheme) return stops;
    return SkyStops(
      _toTint(stops.top),
      _toTint(stops.middle),
      _toTint(stops.horizon),
      stops.name,
    );
  }

  static SkyStops _interpolate(double altitudeDeg) {
    final alt = altitudeDeg.clamp(-90.0, 90.0);

    if (alt <= _bands.first.$1) return _bands.first.$2;
    if (alt >= _bands.last.$1) return _bands.last.$2;

    for (var i = 0; i < _bands.length - 1; i++) {
      final (lowAlt, lowStops) = _bands[i];
      final (highAlt, highStops) = _bands[i + 1];
      if (alt >= lowAlt && alt <= highAlt) {
        final t = ((alt - lowAlt) / (highAlt - lowAlt)).clamp(0.0, 1.0);
        return SkyStops.lerp(lowStops, highStops, t);
      }
    }
    return _bands.last.$2;
  }

  /// 45% saturation, 130% lightness — the light-theme treatment.
  static Color _toTint(Color source) {
    final hsl = HSLColor.fromColor(source);
    return hsl
        .withSaturation((hsl.saturation * 0.45).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 1.3 + 0.42).clamp(0.0, 1.0))
        .toColor();
  }

  /// How visible the star field should be, 0..1. Stars fade in below civil
  /// twilight and are fully out by −12°.
  static double starOpacity(double altitudeDeg) {
    if (altitudeDeg >= -6) return 0;
    if (altitudeDeg <= -12) return 1;
    return ((-6 - altitudeDeg) / 6).clamp(0.0, 1.0);
  }

  /// Opacity of the scrim laid over the sky so foreground text stays legible
  /// at every hour. Day skies are bright and need more; night skies need none.
  static double contentScrimOpacity(double altitudeDeg, {required bool isDark}) {
    if (!isDark) return 0.0;
    final t = ((altitudeDeg + 6) / 31).clamp(0.0, 1.0);
    return lerpDouble(0.0, 0.42, t)!;
  }

  /// Colour of the sun/moon marker travelling the arc.
  static Color bodyColor(double altitudeDeg) {
    if (altitudeDeg > 6) return const Color(0xFFFFF3D6);
    if (altitudeDeg > 0) return const Color(0xFFFFD08A);
    if (altitudeDeg > -6) return const Color(0xFFFFA06B);
    return const Color(0xFFD9E2F5); // moon
  }

  /// Glow colour around the marker.
  static Color bodyGlow(double altitudeDeg) =>
      bodyColor(altitudeDeg).withValues(alpha: altitudeDeg > -6 ? 0.45 : 0.22);

  /// Convenience for a debug/fallback flat colour.
  static Color get fallback => Colors.black;
}
