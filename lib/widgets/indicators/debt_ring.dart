import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/circa_theme.dart';
import '../../domain/value_objects/chronotype.dart';

/// The hero indicator: a 270° arc showing accumulated sleep debt.
///
/// Colour never carries the meaning alone — the arc is always paired with the
/// numeral and a band label, so it reads correctly for colour-blind users and
/// for anyone using a screen reader.
class DebtRing extends StatelessWidget {
  const DebtRing({
    super.key,
    required this.debtHours,
    required this.confidence,
    this.size = 220,
    this.maxHours = 12,
    this.caption = 'sleep debt',
    this.onTap,
  });

  final double debtHours;
  final PhaseConfidence confidence;
  final double size;
  final double maxHours;
  final String caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final bandColor = colors.debtBandColor(debtHours);
    final bandLabel = colors.debtBandLabel(debtHours);

    final hours = debtHours.floor();
    final minutes = ((debtHours - hours) * 60).round();

    return Semantics(
      label: 'Sleep debt',
      value: '${_spoken(hours, minutes)}, $bandLabel. '
          'Confidence: ${confidence.label}.',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: debtHours.clamp(0, maxHours)),
            duration: t.motion.deliberate,
            curve: CircaMotion.emphasized,
            builder: (context, animatedHours, _) {
              return CustomPaint(
                painter: _DebtRingPainter(
                  value: animatedHours / maxHours,
                  color: bandColor,
                  trackColor: colors.textPrimary.withValues(alpha: 0.08),
                  glow: !t.motion.reduced,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tabular figures so digits don't jitter while animating.
                      _RollingDuration(
                        hours: animatedHours.floor(),
                        minutes:
                            ((animatedHours - animatedHours.floor()) * 60)
                                .round(),
                        style: t.type.heroNumeral.copyWith(
                          color: colors.textPrimary,
                          fontSize: size * 0.26,
                        ),
                      ),
                      SizedBox(height: t.space.xs),
                      Text(
                        caption,
                        style: t.type.bodyS.copyWith(color: colors.textSecondary),
                      ),
                      SizedBox(height: t.space.sm),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: bandColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: t.space.xs + 2),
                          Text(
                            bandLabel,
                            style: t.type.label.copyWith(color: bandColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _spoken(int h, int m) {
    if (h == 0 && m == 0) return 'none';
    final parts = <String>[];
    if (h > 0) parts.add('$h ${h == 1 ? 'hour' : 'hours'}');
    if (m > 0) parts.add('$m ${m == 1 ? 'minute' : 'minutes'}');
    return parts.join(' ');
  }
}

/// Duration rendered with tabular figures so the layout is rock-steady while
/// the value animates.
class _RollingDuration extends StatelessWidget {
  const _RollingDuration({
    required this.hours,
    required this.minutes,
    required this.style,
  });

  final int hours;
  final int minutes;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final unitStyle = style.copyWith(
      fontSize: (style.fontSize ?? 48) * 0.42,
      color: style.color?.withValues(alpha: 0.7),
    );
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        children: [
          TextSpan(text: '$hours', style: style),
          TextSpan(text: 'h ', style: unitStyle),
          TextSpan(text: minutes.toString().padLeft(2, '0'), style: style),
          TextSpan(text: 'm', style: unitStyle),
        ],
      ),
    );
  }
}

class _DebtRingPainter extends CustomPainter {
  _DebtRingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.glow,
  });

  /// 0..1 of the ring's full sweep.
  final double value;
  final Color color;
  final Color trackColor;
  final bool glow;

  /// 270° sweep with the gap at the bottom.
  static const _startAngle = math.pi * 0.75;
  static const _sweepAngle = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.055;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.width - stroke) / 2,
    );

    canvas.drawArc(
      rect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = trackColor,
    );

    final swept = _sweepAngle * value.clamp(0.0, 1.0);
    if (swept <= 0) return;

    if (glow) {
      canvas.drawArc(
        rect,
        _startAngle,
        swept,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }

    canvas.drawArc(
      rect,
      _startAngle,
      swept,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepAngle,
          colors: [color.withValues(alpha: 0.55), color],
          transform: GradientRotation(_startAngle),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_DebtRingPainter old) =>
      old.value != value || old.color != color || old.glow != glow;
}

/// The 4-segment trust meter shown beside every modelled number.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({super.key, required this.confidence, this.onTap});

  final PhaseConfidence confidence;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final isEstimate = confidence == PhaseConfidence.estimated;
    final tint = isEstimate ? colors.textTertiary : colors.aurora;

    return Semantics(
      label: 'Confidence: ${confidence.label}. ${confidence.explanation}',
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: t.radius.pillRadius,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: t.space.sm,
            vertical: t.space.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 4; i++) ...[
                Container(
                  width: 5,
                  height: 5 + i * 2.5,
                  decoration: BoxDecoration(
                    color: i < confidence.filledSegments
                        ? tint
                        : tint.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                if (i < 3) const SizedBox(width: 2),
              ],
              SizedBox(width: t.space.sm - 2),
              Text(
                confidence.label,
                style: t.type.caption.copyWith(color: tint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
