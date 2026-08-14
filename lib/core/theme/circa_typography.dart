import 'package:flutter/material.dart';

/// Circa's type scale.
///
/// Two bundled variable fonts:
/// * **Fraunces** — display and hero numerals. The `opsz` axis is genuinely
///   driven, so a 72pt numeral gets wide, warm apertures and a 34pt one doesn't.
/// * **Space Grotesk** — all UI text. Squared terminals and narrowed apertures
///   give a data-dense app some identity, where the neutral grotesque it
///   replaced read as the platform default. Retains a true tabular figure set.
///
/// Every clock time, duration and metric uses tabular figures so digits don't
/// jitter while a value animates.
///
/// **Weights are spread deliberately wide.** The scale previously spanned only
/// 400–600, which on a phone is close enough that headings and body read as one
/// flat wall of text — the hierarchy existed in the token names and nowhere on
/// screen. Titles now sit at 650–700 against 400 body, which is the contrast
/// doing the work rather than size alone. Space Grotesk's axis tops out at 700,
/// so that is the ceiling here, not a preference.
@immutable
class CircaTypography extends ThemeExtension<CircaTypography> {
  const CircaTypography({
    required this.heroNumeral,
    required this.displayL,
    required this.displayM,
    required this.titleL,
    required this.titleM,
    required this.titleS,
    required this.bodyL,
    required this.bodyM,
    required this.bodyS,
    required this.label,
    required this.caption,
  });

  final TextStyle heroNumeral;
  final TextStyle displayL;
  final TextStyle displayM;
  final TextStyle titleL;
  final TextStyle titleM;
  final TextStyle titleS;
  final TextStyle bodyL;
  final TextStyle bodyM;
  final TextStyle bodyS;
  final TextStyle label;
  final TextStyle caption;

  static const _sans = 'SpaceGrotesk';
  static const _serif = 'Fraunces';

  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  static const base = CircaTypography(
    heroNumeral: TextStyle(
      fontFamily: _serif,
      fontSize: 72,
      height: 1.0,
      letterSpacing: -2.16, // -3%
      fontVariations: [
        FontVariation('opsz', 72),
        FontVariation('wght', 500),
        FontVariation('SOFT', 20),
        FontVariation('WONK', 0),
      ],
      fontFeatures: _tabular,
    ),
    displayL: TextStyle(
      fontFamily: _serif,
      fontSize: 44,
      height: 48 / 44,
      letterSpacing: -1.1,
      fontVariations: [
        FontVariation('opsz', 44),
        FontVariation('wght', 500),
        FontVariation('SOFT', 10),
        FontVariation('WONK', 0),
      ],
      fontFeatures: _tabular,
    ),
    displayM: TextStyle(
      fontFamily: _serif,
      fontSize: 34,
      height: 40 / 34,
      letterSpacing: -0.68,
      fontVariations: [
        FontVariation('opsz', 34),
        FontVariation('wght', 500),
        FontVariation('SOFT', 0),
        FontVariation('WONK', 0),
      ],
      fontFeatures: _tabular,
    ),
    titleL: TextStyle(
      fontFamily: _sans,
      fontSize: 26,
      height: 32 / 26,
      letterSpacing: -0.39,
      fontVariations: [FontVariation('wght', 700)],
    ),
    titleM: TextStyle(
      fontFamily: _sans,
      fontSize: 20,
      height: 26 / 20,
      letterSpacing: -0.2,
      fontVariations: [FontVariation('wght', 700)],
    ),
    titleS: TextStyle(
      fontFamily: _sans,
      fontSize: 17,
      height: 22 / 17,
      letterSpacing: -0.085,
      fontVariations: [FontVariation('wght', 650)],
    ),
    bodyL: TextStyle(
      fontFamily: _sans,
      fontSize: 16,
      height: 24 / 16,
      fontVariations: [FontVariation('wght', 400)],
    ),
    bodyM: TextStyle(
      fontFamily: _sans,
      fontSize: 15,
      height: 22 / 15,
      fontVariations: [FontVariation('wght', 400)],
    ),
    bodyS: TextStyle(
      fontFamily: _sans,
      fontSize: 13,
      height: 18 / 13,
      letterSpacing: 0.065,
      fontVariations: [FontVariation('wght', 400)],
    ),
    label: TextStyle(
      fontFamily: _sans,
      fontSize: 13,
      height: 16 / 13,
      letterSpacing: 0.26,
      fontVariations: [FontVariation('wght', 650)],
    ),
    caption: TextStyle(
      fontFamily: _sans,
      fontSize: 11,
      height: 14 / 11,
      letterSpacing: 0.44,
      fontVariations: [FontVariation('wght', 500)],
    ),
  );

  /// Applies a colour to the whole scale in one pass.
  CircaTypography withColor(Color color) => CircaTypography(
        heroNumeral: heroNumeral.copyWith(color: color),
        displayL: displayL.copyWith(color: color),
        displayM: displayM.copyWith(color: color),
        titleL: titleL.copyWith(color: color),
        titleM: titleM.copyWith(color: color),
        titleS: titleS.copyWith(color: color),
        bodyL: bodyL.copyWith(color: color),
        bodyM: bodyM.copyWith(color: color),
        bodyS: bodyS.copyWith(color: color),
        label: label.copyWith(color: color),
        caption: caption.copyWith(color: color),
      );

  /// Builds the Material [TextTheme] so stock widgets inherit our scale too.
  TextTheme toTextTheme(Color primary, Color secondary) => TextTheme(
        displayLarge: displayL.copyWith(color: primary),
        displayMedium: displayM.copyWith(color: primary),
        displaySmall: titleL.copyWith(color: primary),
        headlineLarge: titleL.copyWith(color: primary),
        headlineMedium: titleM.copyWith(color: primary),
        headlineSmall: titleS.copyWith(color: primary),
        titleLarge: titleM.copyWith(color: primary),
        titleMedium: titleS.copyWith(color: primary),
        titleSmall: label.copyWith(color: primary),
        bodyLarge: bodyL.copyWith(color: primary),
        bodyMedium: bodyM.copyWith(color: secondary),
        bodySmall: bodyS.copyWith(color: secondary),
        labelLarge: label.copyWith(color: primary),
        labelMedium: label.copyWith(color: secondary),
        labelSmall: caption.copyWith(color: secondary),
      );

  @override
  CircaTypography copyWith({
    TextStyle? heroNumeral,
    TextStyle? displayL,
    TextStyle? displayM,
    TextStyle? titleL,
    TextStyle? titleM,
    TextStyle? titleS,
    TextStyle? bodyL,
    TextStyle? bodyM,
    TextStyle? bodyS,
    TextStyle? label,
    TextStyle? caption,
  }) =>
      CircaTypography(
        heroNumeral: heroNumeral ?? this.heroNumeral,
        displayL: displayL ?? this.displayL,
        displayM: displayM ?? this.displayM,
        titleL: titleL ?? this.titleL,
        titleM: titleM ?? this.titleM,
        titleS: titleS ?? this.titleS,
        bodyL: bodyL ?? this.bodyL,
        bodyM: bodyM ?? this.bodyM,
        bodyS: bodyS ?? this.bodyS,
        label: label ?? this.label,
        caption: caption ?? this.caption,
      );

  @override
  CircaTypography lerp(ThemeExtension<CircaTypography>? other, double t) {
    if (other is! CircaTypography) return this;
    return CircaTypography(
      heroNumeral: TextStyle.lerp(heroNumeral, other.heroNumeral, t)!,
      displayL: TextStyle.lerp(displayL, other.displayL, t)!,
      displayM: TextStyle.lerp(displayM, other.displayM, t)!,
      titleL: TextStyle.lerp(titleL, other.titleL, t)!,
      titleM: TextStyle.lerp(titleM, other.titleM, t)!,
      titleS: TextStyle.lerp(titleS, other.titleS, t)!,
      bodyL: TextStyle.lerp(bodyL, other.bodyL, t)!,
      bodyM: TextStyle.lerp(bodyM, other.bodyM, t)!,
      bodyS: TextStyle.lerp(bodyS, other.bodyS, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
    );
  }
}
