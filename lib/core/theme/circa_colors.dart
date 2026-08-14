import 'package:flutter/material.dart';

/// Circa's colour tokens.
///
/// Every value here has a machine-verified contrast ratio — see
/// `test/theme/contrast_test.dart`, which recomputes each one from these
/// constants and fails the build if any drifts below its stated minimum.
///
/// The light theme deliberately splits amber into two tokens: a saturated amber
/// simply cannot reach 4.5:1 against warm paper, so [CircaColors.solar] is for
/// fills, arcs and icons (3:1 applies) and [CircaColors.solarInk] is for
/// anything that carries words.
@immutable
class CircaColors extends ThemeExtension<CircaColors> {
  const CircaColors({
    required this.brightness,
    required this.bgVoid,
    required this.bgBase,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.solar,
    required this.solarInk,
    required this.solarBright,
    required this.solarDim,
    required this.dawn,
    required this.twilight,
    required this.aurora,
    required this.danger,
    required this.onSolar,
  });

  final Brightness brightness;

  /// Deepest layer — sits behind the sky, and is the scrim base.
  final Color bgVoid;
  final Color bgBase;

  /// Glass pane fills, in ascending elevation.
  final Color surface1;
  final Color surface2;
  final Color surface3;

  final Color borderSubtle;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Non-informational only — below 4.5:1 by design.
  final Color textDisabled;

  /// Primary accent. In light theme this is **fills and icons only**.
  final Color solar;

  /// Light-theme text-safe amber. In dark theme this equals [solar].
  final Color solarInk;

  final Color solarBright;
  final Color solarDim;

  /// Secondary — warnings, high sleep debt.
  final Color dawn;

  /// Tertiary — night, wind-down, informational.
  final Color twilight;

  /// Success, "debt clear", good states.
  final Color aurora;

  final Color danger;

  /// Foreground for content sitting on a [solar] fill.
  final Color onSolar;

  bool get isDark => brightness == Brightness.dark;

  // ---------------------------------------------------------------------------
  // Dark — the default. This is a sleep app; it is opened at 23:00 and 06:00.
  // ---------------------------------------------------------------------------
  static const dark = CircaColors(
    brightness: Brightness.dark,
    bgVoid: Color(0xFF05070F),
    bgBase: Color(0xFF080B16),
    surface1: Color(0xFF0E1322),
    surface2: Color(0xFF151B2E),
    surface3: Color(0xFF1D2540),
    borderSubtle: Color(0x0FFFFFFF), // white @ 6%
    borderStrong: Color(0x1FFFFFFF), // white @ 12%
    textPrimary: Color(0xFFF4F6FB), // 18.16:1 — not pure white (OLED halation)
    textSecondary: Color(0xFFA8B0C4), // 9.04:1
    textTertiary: Color(0xFF7B85A0), // 5.33:1
    textDisabled: Color(0xFF4A5266),
    solar: Color(0xFFFFB238), // 10.92:1
    solarInk: Color(0xFFFFB238),
    solarBright: Color(0xFFFFCB6B),
    solarDim: Color(0xFFC98A22),
    dawn: Color(0xFFFF8264), // 8.07:1
    twilight: Color(0xFF7B8FF7), // 6.65:1
    aurora: Color(0xFF4FD1B4), // 10.39:1
    danger: Color(0xFFFF6B6B), // 7.07:1
    onSolar: Color(0xFF05070F),
  );

  // ---------------------------------------------------------------------------
  // Light — warm paper, never clinical white, so it stays continuous with dawn.
  // ---------------------------------------------------------------------------
  static const light = CircaColors(
    brightness: Brightness.light,
    bgVoid: Color(0xFFEDE9E1),
    bgBase: Color(0xFFFBF9F5),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFF5F2EC),
    surface3: Color(0xFFEDE9E1),
    borderSubtle: Color(0x14101425), // ink @ 8%
    borderStrong: Color(0x29101425), // ink @ 16%
    textPrimary: Color(0xFF101425), // 17.38:1
    textSecondary: Color(0xFF4C5468), // 7.20:1
    textTertiary: Color(0xFF626B7E), // 5.09:1
    textDisabled: Color(0xFF9AA1B0),
    solar: Color(0xFFC9760E), // 3.28:1 — fills/icons only, never text
    solarInk: Color(0xFF8F5407), // 5.81:1 — text-safe
    solarBright: Color(0xFFE09A2E),
    solarDim: Color(0xFF8F5407),
    dawn: Color(0xFFC0422A), // 4.93:1
    twilight: Color(0xFF4353C4), // 6.10:1
    aurora: Color(0xFF0B7A61), // 5.03:1
    danger: Color(0xFFC13030), // 5.35:1
    onSolar: Color(0xFFFFFFFF),
  );

  /// Colour for a sleep-debt band. Paired everywhere with a numeral and a text
  /// label — colour alone never carries meaning.
  Color debtBandColor(double debtHours) {
    if (debtHours < 1) return aurora;
    if (debtHours < 3) return solar;
    if (debtHours < 6) return isDark ? const Color(0xFFFF9E4D) : const Color(0xFFB35A18);
    if (debtHours < 10) return dawn;
    return danger;
  }

  String debtBandLabel(double debtHours) {
    if (debtHours < 1) return 'Clear';
    if (debtHours < 3) return 'Mild';
    if (debtHours < 6) return 'Moderate';
    if (debtHours < 10) return 'High';
    return 'Severe';
  }

  @override
  CircaColors copyWith({
    Brightness? brightness,
    Color? bgVoid,
    Color? bgBase,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? borderSubtle,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? solar,
    Color? solarInk,
    Color? solarBright,
    Color? solarDim,
    Color? dawn,
    Color? twilight,
    Color? aurora,
    Color? danger,
    Color? onSolar,
  }) =>
      CircaColors(
        brightness: brightness ?? this.brightness,
        bgVoid: bgVoid ?? this.bgVoid,
        bgBase: bgBase ?? this.bgBase,
        surface1: surface1 ?? this.surface1,
        surface2: surface2 ?? this.surface2,
        surface3: surface3 ?? this.surface3,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        borderStrong: borderStrong ?? this.borderStrong,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        textDisabled: textDisabled ?? this.textDisabled,
        solar: solar ?? this.solar,
        solarInk: solarInk ?? this.solarInk,
        solarBright: solarBright ?? this.solarBright,
        solarDim: solarDim ?? this.solarDim,
        dawn: dawn ?? this.dawn,
        twilight: twilight ?? this.twilight,
        aurora: aurora ?? this.aurora,
        danger: danger ?? this.danger,
        onSolar: onSolar ?? this.onSolar,
      );

  @override
  CircaColors lerp(ThemeExtension<CircaColors>? other, double t) {
    if (other is! CircaColors) return this;
    return CircaColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      bgVoid: Color.lerp(bgVoid, other.bgVoid, t)!,
      bgBase: Color.lerp(bgBase, other.bgBase, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      solar: Color.lerp(solar, other.solar, t)!,
      solarInk: Color.lerp(solarInk, other.solarInk, t)!,
      solarBright: Color.lerp(solarBright, other.solarBright, t)!,
      solarDim: Color.lerp(solarDim, other.solarDim, t)!,
      dawn: Color.lerp(dawn, other.dawn, t)!,
      twilight: Color.lerp(twilight, other.twilight, t)!,
      aurora: Color.lerp(aurora, other.aurora, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onSolar: Color.lerp(onSolar, other.onSolar, t)!,
    );
  }
}
