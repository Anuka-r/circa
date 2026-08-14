import 'dart:math' as math;

import 'package:circa/core/theme/circa_colors.dart';
import 'package:circa/core/theme/sky_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.2 relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('Dark theme contrast', () {
    const c = CircaColors.dark;
    final bg = c.bgBase;

    // Body text must clear 4.5:1.
    const bodyMinimum = 4.5;
    // Graphical objects and large text must clear 3:1.
    const graphicMinimum = 3.0;

    void expectText(String name, Color fg, double claimed) {
      final ratio = contrastRatio(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(bodyMinimum),
        reason: '$name is $ratio:1 against the dark background, '
            'below the 4.5:1 body-text minimum',
      );
      expect(
        ratio,
        closeTo(claimed, 0.1),
        reason: '$name drifted from its documented $claimed:1',
      );
    }

    test('text colours meet 4.5:1 and match the documented values', () {
      expectText('textPrimary', c.textPrimary, 18.16);
      expectText('textSecondary', c.textSecondary, 9.04);
      expectText('textTertiary', c.textTertiary, 5.33);
    });

    test('accent colours meet at least 3:1', () {
      for (final (name, colour) in [
        ('solar', c.solar),
        ('dawn', c.dawn),
        ('twilight', c.twilight),
        ('aurora', c.aurora),
        ('danger', c.danger),
      ]) {
        expect(
          contrastRatio(colour, bg),
          greaterThanOrEqualTo(graphicMinimum),
          reason: '$name fails the 3:1 non-text minimum',
        );
      }
    });

    test('solar is legible as text in dark mode', () {
      expect(contrastRatio(c.solar, bg), greaterThanOrEqualTo(bodyMinimum));
    });

    test('content on a solar fill is legible', () {
      expect(
        contrastRatio(c.onSolar, c.solar),
        greaterThanOrEqualTo(bodyMinimum),
      );
    });

    test('textDisabled is deliberately below the threshold', () {
      // Non-informational only; if this ever passes, someone has started using
      // it for real content.
      expect(contrastRatio(c.textDisabled, bg), lessThan(bodyMinimum));
    });
  });

  group('Light theme contrast', () {
    const c = CircaColors.light;
    final bg = c.bgBase;

    test('text colours meet 4.5:1 and match the documented values', () {
      for (final (name, colour, claimed) in [
        ('textPrimary', c.textPrimary, 17.38),
        ('textSecondary', c.textSecondary, 7.20),
        ('textTertiary', c.textTertiary, 5.09),
        ('solarInk', c.solarInk, 5.81),
        ('dawn', c.dawn, 4.93),
        ('twilight', c.twilight, 6.10),
        ('aurora', c.aurora, 5.03),
        ('danger', c.danger, 5.35),
      ]) {
        final ratio = contrastRatio(colour, bg);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '$name is only $ratio:1 on warm paper');
        expect(ratio, closeTo(claimed, 0.1),
            reason: '$name drifted from its documented $claimed:1');
      }
    });

    test(
        'solar is a fill-only token in light mode — it cannot reach 4.5:1 and '
        'must never be used for text', () {
      final ratio = contrastRatio(c.solar, bg);
      expect(ratio, greaterThanOrEqualTo(3.0),
          reason: 'solar must still clear the 3:1 non-text minimum');
      expect(ratio, lessThan(4.5),
          reason: 'if this ever passes, solarInk may no longer be needed — '
              'but until then, using solar for text is a bug');
      expect(contrastRatio(c.solarInk, bg), greaterThanOrEqualTo(4.5));
    });
  });

  group('Sky gradient', () {
    test('is continuous across every altitude — no band pops', () {
      SkyStops? previous;
      for (var alt = -90.0; alt <= 90.0; alt += 0.5) {
        final stops = SkyPalette.forAltitude(alt);
        if (previous != null) {
          // A half-degree step must never move a channel more than a few
          // points, otherwise the sky visibly jumps between keyframes.
          for (final (a, b) in [
            (previous.top, stops.top),
            (previous.middle, stops.middle),
            (previous.horizon, stops.horizon),
          ]) {
            final delta = ((a.r - b.r).abs() +
                    (a.g - b.g).abs() +
                    (a.b - b.b).abs()) *
                255;
            expect(delta, lessThan(30),
                reason: 'sky jumped at altitude $alt');
          }
        }
        previous = stops;
      }
    });

    test('night is dark and day is bright', () {
      final night = SkyPalette.forAltitude(-40);
      final day = SkyPalette.forAltitude(60);
      expect(_luminance(night.top), lessThan(0.02));
      expect(_luminance(day.top), greaterThan(_luminance(night.top)));
    });

    test('stars fade in below civil twilight and are out in daylight', () {
      expect(SkyPalette.starOpacity(10), 0);
      expect(SkyPalette.starOpacity(-6), 0);
      expect(SkyPalette.starOpacity(-9), closeTo(0.5, 0.01));
      expect(SkyPalette.starOpacity(-12), 1);
      expect(SkyPalette.starOpacity(-40), 1);
    });

    test('light theme renders the sky as a tint, not a photograph', () {
      final darkNight = SkyPalette.forAltitude(-40);
      final lightNight = SkyPalette.forAltitude(-40, lightTheme: true);
      expect(
        _luminance(lightNight.top),
        greaterThan(_luminance(darkNight.top)),
        reason: 'a light-theme night sky must stay readable',
      );
    });
  });
}
