import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/circa_theme.dart';
import '../../domain/chrono/protocol_engine.dart';
import '../../domain/chrono/two_process_model.dart';
import '../../widgets/charts/energy_curve.dart';
import '../../widgets/circa_widgets.dart';
import '../../widgets/indicators/debt_ring.dart';
import '../../widgets/sky/sky_view.dart';
import '../logging/log_sheets.dart';
import '../sleep/sleep_screen.dart';

/// Today — the screen the app is judged on.
///
/// One question, answered in under three seconds: what should I do next, and
/// when? Everything else on the screen supports that answer.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.circa;
    final state = ref.watch(todayProvider);

    return Scaffold(
      backgroundColor: t.color.bgBase,
      body: state.when(
        loading: () => const _TodaySkeleton(),
        error: (e, st) => SafeArea(
          child: Padding(
            padding: EdgeInsets.all(t.space.lg),
            child: ErrorStateView(
              title: 'We couldn’t build today’s plan',
              body: 'Your data is safe on this device. Try again?',
              details: e.toString(),
              onRetry: () => ref.invalidate(todayProvider),
            ),
          ),
        ),
        data: (data) => _TodayContent(data: data),
      ),
    );
  }
}

class _TodayContent extends ConsumerWidget {
  const _TodayContent({required this.data});

  final TodayState data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.circa;
    final colors = t.color;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = t.space.gutter(width);
    final isPro = ref.watch(isProProvider);

    final next = data.nextUp;
    final remaining = data.events
        .where((e) => e != next && !data.isCompleted(e))
        .toList();
    final done = data.events.where(data.isCompleted).toList();

    return RefreshIndicator(
      color: colors.solar,
      backgroundColor: colors.surface2,
      onRefresh: () => ref.read(todayProvider.notifier).refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: colors.bgBase,
            flexibleSpace: FlexibleSpaceBar(
              background: SkyView(
                solarDay: data.solarDay,
                nowUtc: data.nowUtc,
              ),
              titlePadding: EdgeInsetsDirectional.only(
                start: gutter,
                bottom: t.space.md,
              ),
              title: _CollapsedTitle(data: data),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                t.space.xl,
                gutter,
                t.space.x4,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: t.space.maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Greeting(data: data),
                      SizedBox(height: t.space.lg),

                      Center(
                        child: DebtRing(
                          debtHours: data.debt.hours,
                          confidence: data.profile.confidence,
                          onTap: () => _showHowCalculated(context, data),
                        ),
                      ),
                      SizedBox(height: t.space.sm),
                      Center(
                        child: ConfidenceBadge(
                          confidence: data.profile.confidence,
                          onTap: () => _showHowCalculated(context, data),
                        ),
                      ),

                      SizedBox(height: t.space.section),

                      if (next != null) ...[
                        const SectionLabel('Next up'),
                        _PrimaryActionCard(
                          event: next,
                          data: data,
                          onComplete: () => ref
                              .read(todayProvider.notifier)
                              .completeEvent(next),
                        ),
                        SizedBox(height: t.space.lg),
                      ],

                      if (data.lastNight == null) ...[
                        _LogSleepPrompt(
                          onTap: () => showCircaSheet(context, const LogSleepSheet()),
                        ),
                        SizedBox(height: t.space.lg),
                      ],

                      SectionLabel(
                        'Energy forecast',
                        trailing: TextButton(
                          onPressed: () => context.push('/today/forecast'),
                          child: Text(
                            isPro ? '3 days' : 'Details',
                            style: t.type.label
                                .copyWith(color: colors.solarInk),
                          ),
                        ),
                      ),
                      GlassCard(
                        padding: EdgeInsets.fromLTRB(
                          t.space.sm,
                          t.space.base,
                          t.space.sm,
                          t.space.sm,
                        ),
                        child: Column(
                          children: [
                            EnergyCurve(
                              points: data.forecast,
                              features: data.features,
                              nowUtc: data.nowUtc,
                              utcOffset: data.utcOffset,
                            ),
                            if (_dipSentence(data) != null)
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  t.space.sm,
                                  t.space.md,
                                  t.space.sm,
                                  t.space.xs,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.trending_down_rounded,
                                      size: 16,
                                      color: colors.textTertiary,
                                    ),
                                    SizedBox(width: t.space.sm),
                                    Expanded(
                                      child: Text(
                                        _dipSentence(data)!,
                                        style: t.type.bodyS.copyWith(
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),

                      SizedBox(height: t.space.section),

                      const SectionLabel('Today’s rhythm'),
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PhaseTimeline(
                              segments: _timelineSegments(context, data),
                              nowFraction: _nowFraction(data),
                            ),
                            SizedBox(height: t.space.md),
                            Wrap(
                              spacing: t.space.md,
                              runSpacing: t.space.sm,
                              children: [
                                _LegendDot(
                                  color: colors.twilight
                                      .withValues(alpha: 0.55),
                                  label: 'Sleep',
                                ),
                                _LegendDot(
                                  color:
                                      colors.solar.withValues(alpha: 0.65),
                                  label: 'Light window',
                                ),
                                _LegendDot(
                                  color: colors.dawn.withValues(alpha: 0.5),
                                  label: 'Dim the lights',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (remaining.isNotEmpty) ...[
                        SizedBox(height: t.space.section),
                        const SectionLabel('Later today'),
                        for (final e in remaining)
                          Padding(
                            padding: EdgeInsets.only(bottom: t.space.sm),
                            child: _CompactActionRow(
                              event: e,
                              data: data,
                              onComplete: () => ref
                                  .read(todayProvider.notifier)
                                  .completeEvent(e),
                            ),
                          ),
                      ],

                      if (done.isNotEmpty) ...[
                        SizedBox(height: t.space.lg),
                        for (final e in done)
                          Padding(
                            padding: EdgeInsets.only(bottom: t.space.sm),
                            child: _CompactActionRow(
                              event: e,
                              data: data,
                              completed: true,
                              onComplete: () => ref
                                  .read(todayProvider.notifier)
                                  .uncompleteEvent(e),
                            ),
                          ),
                      ],

                      SizedBox(height: t.space.section),
                      _InsightCard(data: data),

                      SizedBox(height: t.space.section),
                      _QuickLogRow(data: data),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String? _dipSentence(TodayState data) {
    final dip = data.features
        .where((f) => f.kind == EnergyFeatureKind.afternoonDip)
        .toList();
    if (dip.isEmpty) return null;
    final f = dip.first;
    final local = f.atUtc.add(data.utcOffset);
    return 'Dip around ${_hhmm(local)} — mostly '
        '${f.dominantCause.plainLabel}.';
  }

  static double _nowFraction(TodayState data) {
    final l = data.localNow;
    return (l.hour * 60 + l.minute) / 1440.0;
  }

  static List<TimelineSegment> _timelineSegments(
    BuildContext context,
    TodayState data,
  ) {
    final colors = context.circa.color;
    final segments = <TimelineSegment>[];

    double fractionOf(DateTime utc) {
      final l = utc.add(data.utcOffset);
      final startOfDay = DateTime(l.year, l.month, l.day);
      return l.difference(startOfDay).inMinutes / 1440.0;
    }

    for (final e in data.events) {
      final color = switch (e.kind) {
        ProtocolEventKind.sleep => colors.twilight.withValues(alpha: 0.55),
        ProtocolEventKind.seekLight => colors.solar.withValues(alpha: 0.65),
        ProtocolEventKind.avoidLight => colors.dawn.withValues(alpha: 0.5),
        ProtocolEventKind.windDown => colors.twilight.withValues(alpha: 0.3),
        _ => null,
      };
      if (color == null) continue;

      var start = fractionOf(e.startUtc);
      var end = fractionOf(e.endUtc);
      // A window crossing midnight is drawn as two segments rather than
      // wrapping into a nonsense negative width.
      if (end < start) {
        segments.add(TimelineSegment(
          start: start,
          end: 1,
          color: color,
          label: e.title,
        ));
        start = 0;
        end = end.clamp(0.0, 1.0);
      }
      segments.add(TimelineSegment(
        start: start,
        end: end,
        color: color,
        label: e.title,
      ));
    }
    return segments;
  }

  static void _showHowCalculated(BuildContext context, TodayState data) {
    final t = context.circa;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          t.space.lg,
          t.space.sm,
          t.space.lg,
          t.space.xl + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How this is calculated',
                style: t.type.titleM.copyWith(color: t.color.textPrimary)),
            SizedBox(height: t.space.md),
            Text(
              'Sleep debt is the shortfall between the sleep you need '
              '(${(data.profile.sleepNeedMinutes / 60).toStringAsFixed(1)}h) '
              'and the sleep you logged, over the last 14 nights. Older '
              'nights count for less — a shortfall from two weeks ago '
              'contributes about 15% of its original weight.\n\n'
              'Sleeping extra repays debt at half rate, which is why one long '
              'lie-in does not undo a week of short nights.\n\n'
              'Nights you did not log contribute nothing at all. We would '
              'rather show a smaller number than invent a deficit.',
              style: t.type.bodyM.copyWith(color: t.color.textSecondary),
            ),
            SizedBox(height: t.space.lg),
            Text(
              'Confidence: ${data.profile.confidence.label}',
              style: t.type.titleS.copyWith(color: t.color.textPrimary),
            ),
            SizedBox(height: t.space.xs),
            Text(
              data.profile.confidence.explanation,
              style: t.type.bodyS.copyWith(color: t.color.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({required this.data});
  final TodayState data;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final sunrise = data.solarDay.sunriseUtc;
    final label = sunrise == null
        ? (data.solarDay.isPolarDay ? 'Midnight sun' : 'Polar night')
        : 'Sunrise ${_TodayContent._hhmm(sunrise.add(data.utcOffset))}';
    return Text(
      label,
      style: t.type.label.copyWith(color: t.color.textPrimary),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.data});
  final TodayState data;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final hour = data.localNow.hour;
    final greeting = hour < 5
        ? 'Still up'
        : hour < 12
            ? 'Good morning'
            : hour < 18
                ? 'Good afternoon'
                : 'Good evening';

    final place = data.profile.effectiveLocation.label ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: t.type.displayM.copyWith(color: t.color.textPrimary),
        ),
        SizedBox(height: t.space.xs),
        Text(
          place.isEmpty ? _dateLabel(data.localNow) : place,
          style: t.type.bodyM.copyWith(color: t.color.textTertiary),
        ),
      ],
    );
  }

  static String _dateLabel(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

/// The one action the user should take next, with a live countdown.
class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({
    required this.event,
    required this.data,
    required this.onComplete,
  });

  final ProtocolEvent event;
  final TodayState data;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final accent = _accentFor(event.kind, colors);
    final startLocal = event.startUtc.add(data.utcOffset);
    final endLocal = event.endUtc.add(data.utcOffset);
    final until = event.startUtc.difference(data.nowUtc);
    final active = event.isActiveAt(data.nowUtc);

    final countdown = active
        ? 'Now'
        : until.isNegative
            ? 'Overdue'
            : until.inMinutes < 60
                ? 'in ${until.inMinutes} min'
                : 'in ${until.inHours}h ${until.inMinutes % 60}m';

    return GlassCard(
      accentColor: accent,
      level: 2,
      padding: EdgeInsets.fromLTRB(
        t.space.lg,
        t.space.base,
        t.space.base,
        t.space.base,
      ),
      onTap: () => _showDetail(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(event.kind), size: 18, color: accent),
              SizedBox(width: t.space.sm),
              Text(
                countdown.toUpperCase(),
                style: t.type.caption.copyWith(color: accent),
              ),
            ],
          ),
          SizedBox(height: t.space.md),
          Text(
            event.title,
            style: t.type.titleM.copyWith(color: colors.textPrimary),
          ),
          SizedBox(height: t.space.xs),
          Text(
            event.kind == ProtocolEventKind.caffeineCutoff
                ? event.detail
                : '${_TodayContent._hhmm(startLocal)}'
                    '–${_TodayContent._hhmm(endLocal)} · ${event.detail}',
            style: t.type.bodyM.copyWith(color: colors.textSecondary),
          ),
          SizedBox(height: t.space.base),
          Row(
            children: [
              Expanded(
                child: CircaButton(
                  label: 'Mark done',
                  size: CircaButtonSize.sm,
                  expand: true,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    onComplete();
                  },
                ),
              ),
              SizedBox(width: t.space.sm),
              CircaButton(
                label: 'Why?',
                size: CircaButtonSize.sm,
                variant: CircaButtonVariant.secondary,
                onPressed: () => _showDetail(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final t = context.circa;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          t.space.lg,
          t.space.sm,
          t.space.lg,
          t.space.xl + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.title,
              style: t.type.titleM.copyWith(color: t.color.textPrimary),
            ),
            SizedBox(height: t.space.sm),
            Text(
              event.detail,
              style: t.type.bodyM.copyWith(color: t.color.solarInk),
            ),
            SizedBox(height: t.space.base),
            Text(
              event.why,
              style: t.type.bodyM.copyWith(color: t.color.textSecondary),
            ),
            SizedBox(height: t.space.lg),
            CircaButton(
              label: 'Mark done',
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                onComplete();
              },
            ),
          ],
        ),
      ),
    );
  }

  static Color _accentFor(ProtocolEventKind kind, CircaColors c) =>
      switch (kind) {
        ProtocolEventKind.seekLight => c.solar,
        ProtocolEventKind.avoidLight => c.dawn,
        ProtocolEventKind.caffeineCutoff => c.dawn,
        ProtocolEventKind.windDown => c.twilight,
        ProtocolEventKind.sleep => c.twilight,
        ProtocolEventKind.wake => c.solar,
      };

  static IconData _iconFor(ProtocolEventKind kind) => switch (kind) {
        ProtocolEventKind.seekLight => Icons.wb_sunny_rounded,
        ProtocolEventKind.avoidLight => Icons.nightlight_round,
        ProtocolEventKind.caffeineCutoff => Icons.local_cafe_rounded,
        ProtocolEventKind.windDown => Icons.self_improvement_rounded,
        ProtocolEventKind.sleep => Icons.bedtime_rounded,
        ProtocolEventKind.wake => Icons.alarm_rounded,
      };
}

class _CompactActionRow extends StatelessWidget {
  const _CompactActionRow({
    required this.event,
    required this.data,
    required this.onComplete,
    this.completed = false,
  });

  final ProtocolEvent event;
  final TodayState data;
  final VoidCallback onComplete;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final startLocal = event.startUtc.add(data.utcOffset);
    final accent = _PrimaryActionCard._accentFor(event.kind, colors);

    return Semantics(
      button: true,
      label: '${event.title} at ${_TodayContent._hhmm(startLocal)}'
          '${completed ? ', done' : ''}',
      child: InkWell(
        onTap: onComplete,
        borderRadius: t.radius.cardRadius,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: t.space.sm,
            vertical: t.space.md,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: t.motion.base,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: completed ? accent : Colors.transparent,
                  border: Border.all(
                    color: completed ? accent : colors.borderStrong,
                    width: 1.5,
                  ),
                ),
                child: completed
                    ? Icon(Icons.check_rounded,
                        size: 14, color: colors.onSolar)
                    : null,
              ),
              SizedBox(width: t.space.md),
              SizedBox(
                width: 52,
                child: Text(
                  _TodayContent._hhmm(startLocal),
                  style: t.type.bodyS.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  event.title,
                  style: t.type.bodyM.copyWith(
                    color:
                        completed ? colors.textTertiary : colors.textPrimary,
                    decoration:
                        completed ? TextDecoration.lineThrough : null,
                    decorationColor: colors.textTertiary,
                  ),
                ),
              ),
              Icon(
                _PrimaryActionCard._iconFor(event.kind),
                size: 16,
                color: completed ? colors.textDisabled : accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogSleepPrompt extends StatelessWidget {
  const _LogSleepPrompt({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return GlassCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.bedtime_outlined, size: 20, color: t.color.twilight),
          SizedBox(width: t.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How did you sleep?',
                  style: t.type.titleS.copyWith(color: t.color.textPrimary),
                ),
                Text(
                  'Takes five seconds',
                  style:
                      t.type.bodyS.copyWith(color: t.color.textTertiary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: t.color.textTertiary),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.data});
  final TodayState data;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final (headline, inputs) = _insight(data);

    return GlassCard(
      accentColor: colors.twilight,
      padding: EdgeInsets.fromLTRB(
        t.space.lg,
        t.space.base,
        t.space.base,
        t.space.base,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 16, color: colors.twilight),
              SizedBox(width: t.space.sm),
              Text(
                'INSIGHT',
                style: t.type.caption.copyWith(color: colors.twilight),
              ),
            ],
          ),
          SizedBox(height: t.space.md),
          Text(
            headline,
            style: t.type.bodyL.copyWith(color: colors.textPrimary),
          ),
          SizedBox(height: t.space.sm),
          Text(
            inputs,
            style: t.type.bodyS.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Every insight cites the inputs it was derived from — that is what makes it
  /// trustworthy rather than a horoscope.
  static (String, String) _insight(TodayState data) {
    final lightMin = data.lightMinutesToday;
    final caffeineAtBed = data.caffeineAtBedtime;
    final threshold = data.profile.caffeineThresholdMg;

    if (lightMin == 0) {
      return (
        'You haven’t logged any daylight today. Morning light is the single '
        'biggest lever you have on tonight’s sleep and tomorrow’s energy.',
        'From 0 min logged outdoors today.',
      );
    }
    if (caffeineAtBed > threshold) {
      return (
        'You’re on track for about ${caffeineAtBed.round()} mg of caffeine '
        'still in your system at bedtime — above your '
        '${threshold.round()} mg target.',
        'From ${data.caffeineToday.length} '
            'drink${data.caffeineToday.length == 1 ? '' : 's'} logged today.',
      );
    }
    if (data.debt.hours >= 3) {
      final nights = data.debt.nightsToClear(surplusMinutesPerNight: 60);
      return (
        'At an extra hour a night, you’d clear your sleep debt in '
        '$nights night${nights == 1 ? '' : 's'}.',
        'From ${data.debt.nightsLogged} nights logged in the last 14.',
      );
    }
    return (
      'You got $lightMin minutes of daylight today and your caffeine is '
      'clear of bedtime. That’s the pattern that keeps a rhythm stable.',
      'From today’s logged light and caffeine.',
    );
  }
}

class _QuickLogRow extends ConsumerWidget {
  const _QuickLogRow({required this.data});
  final TodayState data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.circa;
    return Row(
      children: [
        Expanded(
          child: CircaButton(
            label: 'Light',
            icon: Icons.wb_sunny_outlined,
            variant: CircaButtonVariant.secondary,
            expand: true,
            onPressed: () => showCircaSheet(context, const LogLightSheet()),
          ),
        ),
        SizedBox(width: t.space.sm),
        Expanded(
          child: CircaButton(
            label: 'Coffee',
            icon: Icons.local_cafe_outlined,
            variant: CircaButtonVariant.secondary,
            expand: true,
            onPressed: () => showCircaSheet(context, const LogCaffeineSheet()),
          ),
        ),
        SizedBox(width: t.space.sm),
        Expanded(
          child: CircaButton(
            label: 'Sleep',
            icon: Icons.bedtime_outlined,
            variant: CircaButtonVariant.secondary,
            expand: true,
            onPressed: () => showCircaSheet(context, const LogSleepSheet()),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: t.space.xs + 2),
        Text(
          label,
          style: t.type.caption.copyWith(color: t.color.textTertiary),
        ),
      ],
    );
  }
}

class _TodaySkeleton extends StatelessWidget {
  const _TodaySkeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final gutter = t.space.gutter(MediaQuery.sizeOf(context).width);
    // Scrollable: the placeholder stack is taller than a small phone's safe
    // area, and a fixed Column here overflows the moment the screen is
    // narrower or the text scale is larger than the design baseline.
    return SafeArea(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: t.space.xxl),
            const Skeleton(width: 200, height: 34, radius: 10),
            SizedBox(height: t.space.lg),
            const Center(child: Skeleton(width: 220, height: 220, radius: 110)),
            SizedBox(height: t.space.section),
            const Skeleton(width: double.infinity, height: 150, radius: 20),
            SizedBox(height: t.space.lg),
            const Skeleton(width: double.infinity, height: 210, radius: 20),
          ],
        ),
      ),
    );
  }
}
