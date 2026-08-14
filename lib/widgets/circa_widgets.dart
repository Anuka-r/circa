import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/circa_theme.dart';

// -----------------------------------------------------------------------------
// Glass surface
// -----------------------------------------------------------------------------

/// The base surface of the whole app.
///
/// A translucent pane with a 1px light-catching top hairline, so the sky reads
/// *through* the UI rather than the UI sitting on top of it as a stack of
/// rectangles.
///
/// Backdrop blur is expensive, so this widget centralises the decision to use
/// it: high-contrast mode and low-end devices fall back to a solid fill and no
/// call site has to remember.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.level = 1,
    this.borderRadius,
    this.accentColor,
    this.blurEnabled = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final int level;
  final BorderRadius? borderRadius;

  /// Draws a 4dp accent bar down the leading edge.
  final Color? accentColor;

  final bool blurEnabled;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final radius = borderRadius ?? t.radius.cardRadius;

    final elevation = switch (level) {
      2 => t.elevation.e2,
      3 => t.elevation.e3,
      4 => t.elevation.e4,
      _ => t.elevation.e1,
    };

    final highContrast = MediaQuery.highContrastOf(context);
    final useBlur = blurEnabled && !highContrast;

    final surface = switch (level) {
      2 => colors.surface2,
      3 => colors.surface2,
      4 => colors.surface3,
      _ => colors.surface1,
    };

    Widget content = Container(
      padding: padding ?? EdgeInsets.all(t.space.base),
      decoration: BoxDecoration(
        color: surface.withValues(
          alpha: highContrast ? 1.0 : elevation.fillOpacity,
        ),
        borderRadius: radius,
        border: Border.all(
          color: highContrast ? colors.borderStrong : colors.borderSubtle,
        ),
      ),
      child: child,
    );

    // The top hairline: a gradient border on the top edge only, fading out by
    // 40% down the pane. This is what reads as light caught on a glass edge.
    content = Stack(
      children: [
        content,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 1,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(
                      alpha: colors.isDark ? elevation.hairlineOpacity : 0.0,
                    ),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (accentColor != null)
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadiusDirectional.only(
                    topStart: radius.topLeft,
                    bottomStart: radius.bottomLeft,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    Widget card = ClipRRect(
      borderRadius: radius,
      child: useBlur
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: elevation.blurSigma,
                sigmaY: elevation.blurSigma,
              ),
              child: content,
            )
          : content,
    );

    card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: highContrast ? null : elevation.shadows,
      ),
      child: card,
    );

    if (onTap != null) {
      card = _PressableScale(onTap: onTap!, borderRadius: radius, child: card);
    }

    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

/// Scales slightly on press with a light haptic — used by every tappable card.
class _PressableScale extends StatefulWidget {
  const _PressableScale({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: t.motion.quick,
        curve: CircaMotion.standard,
        child: widget.child,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Buttons
// -----------------------------------------------------------------------------

enum CircaButtonVariant { primary, secondary, tertiary, destructive }

enum CircaButtonSize { sm, md, lg }

class CircaButton extends StatefulWidget {
  const CircaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = CircaButtonVariant.primary,
    this.size = CircaButtonSize.md,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final CircaButtonVariant variant;
  final CircaButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  State<CircaButton> createState() => _CircaButtonState();
}

class _CircaButtonState extends State<CircaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final enabled = widget.onPressed != null && !widget.loading;

    final height = switch (widget.size) {
      CircaButtonSize.sm => 40.0,
      CircaButtonSize.md => 48.0,
      CircaButtonSize.lg => 56.0,
    };
    final hPad = switch (widget.size) {
      CircaButtonSize.sm => t.space.base,
      CircaButtonSize.md => t.space.lg,
      CircaButtonSize.lg => t.space.xl,
    };

    final (bg, fg, border) = switch (widget.variant) {
      CircaButtonVariant.primary => (colors.solar, colors.onSolar, null),
      CircaButtonVariant.secondary => (
          colors.surface2.withValues(alpha: 0.85),
          colors.textPrimary,
          colors.borderStrong,
        ),
      CircaButtonVariant.tertiary => (
          Colors.transparent,
          colors.solarInk,
          null,
        ),
      CircaButtonVariant.destructive => (
          Colors.transparent,
          colors.danger,
          colors.danger.withValues(alpha: 0.4),
        ),
    };

    final child = widget.loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(fg),
            ),
          )
        : Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: fg),
                SizedBox(width: t.space.sm),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  style: t.type.titleS.copyWith(color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.4,
          duration: t.motion.quick,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1.0,
            duration: t.motion.quick,
            curve: CircaMotion.standard,
            child: Container(
              height: height,
              width: widget.expand ? double.infinity : null,
              padding: EdgeInsets.symmetric(horizontal: hPad),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: t.radius.pillRadius,
                border: border != null ? Border.all(color: border) : null,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Chips & badges
// -----------------------------------------------------------------------------

class CircaChip extends StatelessWidget {
  const CircaChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final fg = selected ? colors.solarInk : colors.textSecondary;

    return Semantics(
      selected: selected,
      button: onTap != null,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: t.radius.pillRadius,
        child: AnimatedContainer(
          duration: t.motion.quick,
          constraints: const BoxConstraints(minHeight: 36),
          padding: EdgeInsets.symmetric(
            horizontal: t.space.md + 2,
            vertical: t.space.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.solar.withValues(alpha: 0.16)
                : colors.surface2.withValues(alpha: 0.7),
            borderRadius: t.radius.pillRadius,
            border: Border.all(
              color: selected ? colors.solar : colors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                SizedBox(width: t.space.xs + 2),
              ],
              Text(label, style: t.type.label.copyWith(color: fg)),
              if (trailing != null) ...[
                SizedBox(width: t.space.xs + 2),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The "PRO" lock marker. Always paired with visible value, never a bare lock.
class LockChip extends StatelessWidget {
  const LockChip({super.key, this.label = 'PRO'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: 3),
      decoration: BoxDecoration(
        color: t.color.solar.withValues(alpha: 0.16),
        borderRadius: t.radius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 11, color: t.color.solarInk),
          const SizedBox(width: 4),
          Text(label, style: t.type.caption.copyWith(color: t.color.solarInk)),
        ],
      ),
    );
  }
}

/// Section heading used throughout.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md, left: t.space.xs),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text.toUpperCase(),
                style: t.type.caption.copyWith(color: t.color.textTertiary),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// States
// -----------------------------------------------------------------------------

/// Every empty state has an action. Copy is specific, never "Nothing here yet".
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional "3 of 5 nights logged" progress.
  final ({int current, int target})? progress;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    // Scrollable and centred: an empty state is often handed straight to a
    // Scaffold body, where a bare Column overflows on a short screen or at a
    // large text scale.
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: t.space.xl,
        vertical: t.space.xxl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: colors.surface2.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Icon(icon, size: 34, color: colors.textTertiary),
          ),
          SizedBox(height: t.space.lg),
          Text(
            title,
            style: t.type.titleS.copyWith(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: t.space.sm),
          Text(
            body,
            style: t.type.bodyM.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (progress != null) ...[
            SizedBox(height: t.space.base),
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress!.current / progress!.target,
                  minHeight: 6,
                  backgroundColor: colors.surface3,
                  valueColor: AlwaysStoppedAnimation(colors.solar),
                ),
              ),
            ),
            SizedBox(height: t.space.sm),
            Text(
              '${progress!.current} of ${progress!.target}',
              style: t.type.caption.copyWith(color: colors.textTertiary),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: t.space.lg),
            CircaButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

/// Inline error. Never blanks the screen — siblings keep rendering.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.title,
    required this.body,
    this.onRetry,
    this.details,
  });

  final String title;
  final String body;
  final VoidCallback? onRetry;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 20, color: colors.dawn),
              SizedBox(width: t.space.sm),
              Expanded(
                child: Text(
                  title,
                  style: t.type.titleS.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.sm),
          Text(
            body,
            style: t.type.bodyM.copyWith(color: colors.textSecondary),
          ),
          if (details != null) ...[
            SizedBox(height: t.space.sm),
            // Codes live behind a disclosure, never in the title.
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                'Details',
                style: t.type.bodyS.copyWith(color: colors.textTertiary),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    details!,
                    style: t.type.bodyS.copyWith(color: colors.textTertiary),
                  ),
                ),
              ],
            ),
          ],
          if (onRetry != null) ...[
            SizedBox(height: t.space.base),
            CircaButton(
              label: 'Try again',
              size: CircaButtonSize.sm,
              variant: CircaButtonVariant.secondary,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// Shape-accurate skeleton. Matches the real content's box so there is zero
/// layout shift when data resolves.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only run the shimmer when it will actually be drawn. Repeating the
    // controller under reduced motion would burn a frame's work every frame
    // for an animation nobody sees — and would hang any test that waits for
    // the tree to settle.
    final reduced = context.circa.motion.reduced;
    if (reduced && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduced && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    // Reduced motion: a static fill, not a sweep.
    if (t.motion.reduced) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1 + _controller.value * 2, -0.3),
            end: Alignment(1 + _controller.value * 2, 0.3),
            colors: [colors.surface2, colors.surface3, colors.surface2],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Pro gate
// -----------------------------------------------------------------------------

/// Renders the *real* feature behind a blur, never a locked door with no
/// window. The user always sees the shape of what they're missing.
class ProGate extends StatelessWidget {
  const ProGate({
    super.key,
    required this.isPro,
    required this.child,
    required this.headline,
    required this.onUnlock,
    this.blurSigma = 12,
  });

  final bool isPro;
  final Widget child;
  final String headline;
  final VoidCallback onUnlock;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    if (isPro) return child;

    final t = context.circa;
    final colors = t.color;

    return Stack(
      children: [
        // The real widget, so the shape and scale are honest.
        ExcludeSemantics(
          child: IgnorePointer(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
                tileMode: TileMode.decal,
              ),
              child: child,
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.bgBase.withValues(alpha: 0.45),
              borderRadius: t.radius.cardRadius,
            ),
          ),
        ),
        Positioned.fill(
          child: Semantics(
            button: true,
            label: '$headline. Available with Circa Pro.',
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LockChip(),
                  SizedBox(height: t.space.md),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: t.space.lg),
                    child: Text(
                      headline,
                      textAlign: TextAlign.center,
                      style: t.type.titleS.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  SizedBox(height: t.space.base),
                  CircaButton(
                    label: 'Unlock with Pro',
                    size: CircaButtonSize.sm,
                    onPressed: onUnlock,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Feedback
// -----------------------------------------------------------------------------

/// Presents a Circa sheet.
///
/// Imperative rather than a GoRouter `Page`: `ModalBottomSheetRoute` is a
/// `PopupRoute` and does not reliably materialise from a declarative page
/// stack — the route silently produces nothing. Sheets are transient UI, not
/// navigation destinations, so this is also the more honest model.
Future<T?> showCircaSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => child,
  );
}

enum SnackKind { neutral, success, warning, error }

void showCircaSnack(
  BuildContext context,
  String message, {
  SnackKind kind = SnackKind.neutral,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final t = context.circa;
  final colors = t.color;

  final accent = switch (kind) {
    SnackKind.success => colors.aurora,
    SnackKind.warning => colors.solar,
    SnackKind.error => colors.danger,
    SnackKind.neutral => colors.twilight,
  };

  final messenger = ScaffoldMessenger.of(context);
  // Queue depth of one: a new message replaces the old rather than stacking.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Container(width: 3, height: 26, color: accent),
          SizedBox(width: t.space.md),
          Expanded(
            child: Text(
              message,
              style: t.type.bodyM.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
      duration: Duration(seconds: onAction != null ? 6 : 4),
      action: actionLabel != null && onAction != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: colors.solarInk,
              onPressed: onAction,
            )
          : null,
    ),
  );
}
