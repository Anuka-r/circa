import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/circa_theme.dart';
import '../../domain/chrono/two_process_model.dart';

/// The alertness forecast.
///
/// Hand-painted rather than delegated to a charting library: the curve is the
/// product's visual identity, it has to morph rather than rebuild when the data
/// changes, and no library gives us the "now" marker, the feature annotations
/// and the asleep shading in one coherent pass.
class EnergyCurve extends StatefulWidget {
  const EnergyCurve({
    super.key,
    required this.points,
    required this.features,
    required this.nowUtc,
    required this.utcOffset,
    this.height = 190,
    this.showAxis = true,
    this.interactive = true,
  });

  final List<EnergyPoint> points;
  final List<EnergyFeature> features;
  final DateTime nowUtc;
  final Duration utcOffset;
  final double height;
  final bool showAxis;
  final bool interactive;

  @override
  State<EnergyCurve> createState() => _EnergyCurveState();
}

class _EnergyCurveState extends State<EnergyCurve>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal;
  double? _scrubX;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    if (widget.points.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Not enough data yet',
            style: t.type.bodyS.copyWith(color: colors.textTertiary),
          ),
        ),
      );
    }

    // Reduced motion: no draw-on animation, just the finished curve.
    if (t.motion.reduced && _reveal.value < 1) _reveal.value = 1;

    final scrubbed = _scrubbedPoint();

    return Semantics(
      label: 'Energy forecast',
      value: _semanticSummary(),
      child: SizedBox(
        height: widget.height,
        child: GestureDetector(
          onHorizontalDragStart: widget.interactive
              ? (d) => setState(() => _scrubX = d.localPosition.dx)
              : null,
          onHorizontalDragUpdate: widget.interactive
              ? (d) => setState(() => _scrubX = d.localPosition.dx)
              : null,
          onHorizontalDragEnd:
              widget.interactive ? (_) => setState(() => _scrubX = null) : null,
          onTapDown: widget.interactive
              ? (d) => setState(() => _scrubX = d.localPosition.dx)
              : null,
          onTapUp:
              widget.interactive ? (_) => setState(() => _scrubX = null) : null,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _reveal,
                  builder: (context, _) => CustomPaint(
                    painter: _EnergyCurvePainter(
                      points: widget.points,
                      features: widget.features,
                      nowUtc: widget.nowUtc,
                      utcOffset: widget.utcOffset,
                      reveal: CircaMotion.emphasized.transform(_reveal.value),
                      lineColor: colors.solar,
                      fillTop: colors.solar.withValues(alpha: 0.28),
                      asleepColor: colors.twilight.withValues(alpha: 0.10),
                      gridColor: colors.textPrimary.withValues(alpha: 0.06),
                      axisTextColor: colors.textTertiary,
                      markerColor: colors.textPrimary,
                      showAxis: widget.showAxis,
                      scrubX: _scrubX,
                      axisStyle: t.type.caption,
                    ),
                  ),
                ),
              ),
              if (scrubbed != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: t.space.sm,
                        vertical: t.space.xs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface3,
                        borderRadius: t.radius.pillRadius,
                        border: Border.all(color: colors.borderSubtle),
                      ),
                      child: Text(
                        '${_hhmm(scrubbed.atUtc.add(widget.utcOffset))}  ·  '
                        '${(scrubbed.alertness * 100).round()}%',
                        style: t.type.caption.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  EnergyPoint? _scrubbedPoint() {
    final x = _scrubX;
    if (x == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    if (width <= 0) return null;
    final index = ((x / width) * (widget.points.length - 1))
        .round()
        .clamp(0, widget.points.length - 1);
    return widget.points[index];
  }

  String _semanticSummary() {
    if (widget.features.isEmpty) return 'No notable peaks or dips.';
    final parts = widget.features.map((f) {
      final local = f.atUtc.add(widget.utcOffset);
      final label = switch (f.kind) {
        EnergyFeatureKind.morningPeak => 'Morning peak',
        EnergyFeatureKind.afternoonDip => 'Afternoon dip',
        EnergyFeatureKind.eveningPeak => 'Evening peak',
        EnergyFeatureKind.nightLow => 'Night low',
      };
      return '$label at ${_hhmm(local)}';
    });
    return '${parts.join('. ')}.';
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class _EnergyCurvePainter extends CustomPainter {
  _EnergyCurvePainter({
    required this.points,
    required this.features,
    required this.nowUtc,
    required this.utcOffset,
    required this.reveal,
    required this.lineColor,
    required this.fillTop,
    required this.asleepColor,
    required this.gridColor,
    required this.axisTextColor,
    required this.markerColor,
    required this.showAxis,
    required this.scrubX,
    required this.axisStyle,
  });

  final List<EnergyPoint> points;
  final List<EnergyFeature> features;
  final DateTime nowUtc;
  final Duration utcOffset;
  final double reveal;
  final Color lineColor;
  final Color fillTop;
  final Color asleepColor;
  final Color gridColor;
  final Color axisTextColor;
  final Color markerColor;
  final bool showAxis;
  final double? scrubX;
  final TextStyle axisStyle;

  static const _axisHeight = 20.0;
  static const _topPadding = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final chartHeight = size.height - (showAxis ? _axisHeight : 0) - _topPadding;
    if (chartHeight <= 0) return;

    final first = points.first.atUtc;
    final last = points.last.atUtc;
    final span = last.difference(first).inSeconds.toDouble();
    if (span <= 0) return;

    double xFor(DateTime t) =>
        (t.difference(first).inSeconds / span) * size.width;
    double yFor(double alertness) =>
        _topPadding + chartHeight * (1 - alertness.clamp(0.0, 1.0));

    // Asleep bands, so the night reads as night rather than as a crash.
    _paintSleepBands(canvas, size, chartHeight, xFor);

    if (showAxis) _paintAxis(canvas, size, chartHeight, xFor);

    // The curve itself, revealed left to right.
    final visibleCount =
        (points.length * reveal).clamp(2, points.length).toInt();
    final visible = points.take(visibleCount).toList();

    final line = Path();
    for (var i = 0; i < visible.length; i++) {
      final p = visible[i];
      final x = xFor(p.atUtc);
      final y = yFor(p.alertness);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        // Smooth with a midpoint quadratic — cheaper than a full spline and
        // visually indistinguishable at this sample density.
        final prev = visible[i - 1];
        final px = xFor(prev.atUtc);
        final py = yFor(prev.alertness);
        line.quadraticBezierTo(px, py, (px + x) / 2, (py + y) / 2);
      }
    }

    final fill = Path.from(line)
      ..lineTo(xFor(visible.last.atUtc), _topPadding + chartHeight)
      ..lineTo(xFor(visible.first.atUtc), _topPadding + chartHeight)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillTop, fillTop.withValues(alpha: 0)],
        ).createShader(
          Rect.fromLTWH(0, _topPadding, size.width, chartHeight),
        ),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor,
    );

    _paintFeatures(canvas, size, xFor, yFor);
    _paintNowMarker(canvas, size, chartHeight, xFor, yFor);

    if (scrubX != null) {
      canvas.drawLine(
        Offset(scrubX!, _topPadding),
        Offset(scrubX!, _topPadding + chartHeight),
        Paint()
          ..strokeWidth = 1
          ..color = markerColor.withValues(alpha: 0.4),
      );
    }
  }

  void _paintSleepBands(
    Canvas canvas,
    Size size,
    double chartHeight,
    double Function(DateTime) xFor,
  ) {
    DateTime? bandStart;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.asleep && bandStart == null) bandStart = p.atUtc;
      final isLast = i == points.length - 1;
      if ((!p.asleep || isLast) && bandStart != null) {
        final end = p.asleep && isLast ? p.atUtc : points[i - 1].atUtc;
        canvas.drawRect(
          Rect.fromLTRB(
            xFor(bandStart),
            _topPadding,
            xFor(end),
            _topPadding + chartHeight,
          ),
          Paint()..color = asleepColor,
        );
        bandStart = null;
      }
    }
  }

  void _paintAxis(
    Canvas canvas,
    Size size,
    double chartHeight,
    double Function(DateTime) xFor,
  ) {
    final first = points.first.atUtc.add(utcOffset);
    final last = points.last.atUtc.add(utcOffset);
    final totalHours = last.difference(first).inHours;
    // Six-hourly ticks on a day view, daily dividers on a multi-day view.
    final stepHours = totalHours > 30 ? 12 : 6;

    var tick = DateTime(first.year, first.month, first.day, first.hour);
    while (tick.hour % stepHours != 0) {
      tick = tick.add(const Duration(hours: 1));
    }

    while (tick.isBefore(last)) {
      final x = xFor(tick.subtract(utcOffset));
      if (x > 2 && x < size.width - 2) {
        canvas.drawLine(
          Offset(x, _topPadding),
          Offset(x, _topPadding + chartHeight),
          Paint()
            ..strokeWidth = 1
            ..color = gridColor,
        );

        final tp = TextPainter(
          text: TextSpan(
            text: tick.hour.toString().padLeft(2, '0'),
            style: axisStyle.copyWith(color: axisTextColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(x - tp.width / 2, _topPadding + chartHeight + 4),
        );
      }
      tick = tick.add(Duration(hours: stepHours));
    }
  }

  void _paintFeatures(
    Canvas canvas,
    Size size,
    double Function(DateTime) xFor,
    double Function(double) yFor,
  ) {
    for (final f in features) {
      final x = xFor(f.atUtc);
      if (x < 0 || x > size.width) continue;
      final y = yFor(f.alertness);

      final isDip = f.kind == EnergyFeatureKind.afternoonDip ||
          f.kind == EnergyFeatureKind.nightLow;

      canvas.drawCircle(
        Offset(x, y),
        3.5,
        Paint()..color = lineColor.withValues(alpha: isDip ? 0.55 : 0.85),
      );
      canvas.drawCircle(
        Offset(x, y),
        3.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = lineColor.withValues(alpha: 0.25),
      );
    }
  }

  void _paintNowMarker(
    Canvas canvas,
    Size size,
    double chartHeight,
    double Function(DateTime) xFor,
    double Function(double) yFor,
  ) {
    if (nowUtc.isBefore(points.first.atUtc) ||
        nowUtc.isAfter(points.last.atUtc)) {
      return;
    }

    // Nearest sample to now.
    var nearest = points.first;
    var bestDelta = double.infinity;
    for (final p in points) {
      final d = (p.atUtc.difference(nowUtc).inSeconds).abs().toDouble();
      if (d < bestDelta) {
        bestDelta = d;
        nearest = p;
      }
    }

    final x = xFor(nearest.atUtc);
    final y = yFor(nearest.alertness);

    canvas.drawLine(
      Offset(x, _topPadding),
      Offset(x, _topPadding + chartHeight),
      Paint()
        ..strokeWidth = 1
        ..color = markerColor.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      Offset(x, y),
      9,
      Paint()
        ..color = lineColor.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(Offset(x, y), 5, Paint()..color = lineColor);
    canvas.drawCircle(
      Offset(x, y),
      2,
      Paint()..color = markerColor,
    );
  }

  @override
  bool shouldRepaint(_EnergyCurvePainter old) =>
      old.reveal != reveal ||
      old.scrubX != scrubX ||
      old.nowUtc != nowUtc ||
      !identical(old.points, points);
}

/// A compact 24-hour band showing the shape of the day: sleep, light windows,
/// caffeine cutoff. This is how a user *sees* their schedule at a glance.
class PhaseTimeline extends StatelessWidget {
  const PhaseTimeline({
    super.key,
    required this.segments,
    required this.nowFraction,
    this.height = 34,
  });

  final List<TimelineSegment> segments;

  /// 0..1 position of "now" through the local day.
  final double nowFraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return Semantics(
      label: 'Today’s rhythm',
      value: segments.map((s) => s.label).join(', '),
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _TimelinePainter(
            segments: segments,
            nowFraction: nowFraction,
            trackColor: t.color.textPrimary.withValues(alpha: 0.07),
            markerColor: t.color.textPrimary,
            radius: height / 2,
          ),
        ),
      ),
    );
  }
}

class TimelineSegment {
  const TimelineSegment({
    required this.start,
    required this.end,
    required this.color,
    required this.label,
  });

  /// 0..1 through the local day.
  final double start;
  final double end;
  final Color color;
  final String label;
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.segments,
    required this.nowFraction,
    required this.trackColor,
    required this.markerColor,
    required this.radius,
  });

  final List<TimelineSegment> segments;
  final double nowFraction;
  final Color trackColor;
  final Color markerColor;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(rrect, Paint()..color = trackColor);

    canvas.save();
    canvas.clipRRect(rrect);
    for (final s in segments) {
      final left = (s.start.clamp(0.0, 1.0)) * size.width;
      final right = (s.end.clamp(0.0, 1.0)) * size.width;
      if (right <= left) continue;
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()..color = s.color,
      );
    }
    canvas.restore();

    // "Now" marker.
    final x = nowFraction.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(x, -2),
      Offset(x, size.height + 2),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = markerColor,
    );
    canvas.drawCircle(
      Offset(x, size.height + 2),
      2.5,
      Paint()..color = markerColor,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.nowFraction != nowFraction || old.segments.length != segments.length;
}

/// Small helper used by the trends screen.
double clamp01(double v) => math.max(0, math.min(1, v));
