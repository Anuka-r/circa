import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'circa_colors.dart';
import 'circa_metrics.dart';
import 'circa_typography.dart';

export 'circa_colors.dart';
export 'circa_metrics.dart';
export 'circa_typography.dart';

/// Assembles the Material [ThemeData] from Circa's tokens.
///
/// Material 3 is on, but its colour roles are driven from our own palette
/// rather than a seed — a generated scheme cannot hit the contrast ratios we
/// commit to, and the sky gradient needs exact hues.
abstract final class CircaTheme {
  const CircaTheme._();

  static ThemeData dark({bool reducedMotion = false}) =>
      _build(CircaColors.dark, reducedMotion: reducedMotion);

  static ThemeData light({bool reducedMotion = false}) =>
      _build(CircaColors.light, reducedMotion: reducedMotion);

  static ThemeData _build(CircaColors c, {required bool reducedMotion}) {
    final type = CircaTypography.base;
    final isDark = c.isDark;

    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.solar,
      onPrimary: c.onSolar,
      primaryContainer: isDark
          ? c.solar.withValues(alpha: 0.16)
          : c.solar.withValues(alpha: 0.14),
      onPrimaryContainer: c.solarInk,
      secondary: c.twilight,
      onSecondary: isDark ? c.bgVoid : Colors.white,
      secondaryContainer: c.twilight.withValues(alpha: 0.16),
      onSecondaryContainer: c.twilight,
      tertiary: c.aurora,
      onTertiary: isDark ? c.bgVoid : Colors.white,
      tertiaryContainer: c.aurora.withValues(alpha: 0.16),
      onTertiaryContainer: c.aurora,
      error: c.danger,
      onError: isDark ? c.bgVoid : Colors.white,
      errorContainer: c.danger.withValues(alpha: 0.16),
      onErrorContainer: c.danger,
      surface: c.bgBase,
      onSurface: c.textPrimary,
      surfaceContainerLowest: c.bgVoid,
      surfaceContainerLow: c.bgBase,
      surfaceContainer: c.surface1,
      surfaceContainerHigh: c.surface2,
      surfaceContainerHighest: c.surface3,
      onSurfaceVariant: c.textSecondary,
      outline: c.borderStrong,
      outlineVariant: c.borderSubtle,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.bgBase,
      inversePrimary: c.solarDim,
      shadow: Colors.black,
      scrim: c.bgVoid,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bgBase,
      canvasColor: c.bgBase,
      splashFactory: InkSparkle.splashFactory,
      textTheme: type.toTextTheme(c.textPrimary, c.textSecondary),
      // Family only — `wght` cannot be expressed at ThemeData level, and Space
      // Grotesk's default instance is 300. Anything that inherits this without
      // going through [textTheme] renders light. Every style in
      // CircaTypography sets `wght` itself, so this is a backstop for stray
      // framework text, not the path real UI text takes.
      fontFamily: 'SpaceGrotesk',

      extensions: <ThemeExtension<dynamic>>[
        c,
        type,
        const CircaSpace(),
        const CircaRadii(),
        const CircaElevation(),
        CircaMotion(reduced: reducedMotion),
      ],

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: type.titleM.copyWith(color: c.textPrimary),
        iconTheme: IconThemeData(color: c.textPrimary, size: 24),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              ),
      ),

      iconTheme: IconThemeData(color: c.textSecondary, size: 24),

      dividerTheme: DividerThemeData(
        color: c.borderSubtle,
        thickness: 1,
        space: 1,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface2,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface2,
        modalBarrierColor: c.bgVoid.withValues(alpha: 0.55),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        showDragHandle: true,
        dragHandleColor: c.textTertiary,
        dragHandleSize: const Size(36, 4),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: type.titleM.copyWith(color: c.textPrimary),
        contentTextStyle: type.bodyM.copyWith(color: c.textSecondary),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surface3,
        contentTextStyle: type.bodyM.copyWith(color: c.textPrimary),
        actionTextColor: c.solarInk,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(16),
        elevation: 8,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.solar, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.danger, width: 2),
        ),
        labelStyle: type.bodyM.copyWith(color: c.textTertiary),
        floatingLabelStyle: type.bodyS.copyWith(color: c.solarInk),
        hintStyle: type.bodyM.copyWith(color: c.textTertiary),
        // Reserved slot so focusing a field never shifts the layout.
        helperStyle: type.bodyS.copyWith(color: c.textTertiary),
        errorStyle: type.bodyS.copyWith(color: c.danger),
        helperMaxLines: 2,
        errorMaxLines: 2,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: c.solar,
        inactiveTrackColor: c.surface3,
        thumbColor: c.solar,
        overlayColor: c.solar.withValues(alpha: 0.12),
        trackHeight: 4,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onSolar : c.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.solar : c.surface3,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.solar,
        linearTrackColor: c.surface3,
        circularTrackColor: c.surface3,
        linearMinHeight: 4,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface1,
        indicatorColor: c.solar.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? type.caption.copyWith(color: c.textPrimary)
              : type.caption.copyWith(color: c.textTertiary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? c.solar : c.textTertiary,
          ),
        ),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// `context.circa.color.solar` — the only sanctioned way to reach a token.
extension CircaThemeContext on BuildContext {
  CircaTokens get circa => CircaTokens(Theme.of(this));

  /// Shorthand used constantly in layout code.
  bool get isCompact => MediaQuery.sizeOf(this).width < 600;
  bool get isExpanded => MediaQuery.sizeOf(this).width >= 840;
}

/// Bundles every extension so call sites read as one namespace.
class CircaTokens {
  CircaTokens(this._theme);
  final ThemeData _theme;

  CircaColors get color => _theme.extension<CircaColors>()!;
  CircaTypography get type => _theme.extension<CircaTypography>()!;
  CircaSpace get space => _theme.extension<CircaSpace>()!;
  CircaRadii get radius => _theme.extension<CircaRadii>()!;
  CircaElevation get elevation => _theme.extension<CircaElevation>()!;
  CircaMotion get motion => _theme.extension<CircaMotion>()!;
}
