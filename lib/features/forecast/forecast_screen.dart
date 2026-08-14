import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/circa_theme.dart';
import '../../domain/chrono/two_process_model.dart';
import '../../widgets/charts/energy_curve.dart';
import '../../widgets/circa_widgets.dart';

/// The forecast in detail — including the decomposition that explains *why*
/// the curve has the shape it does.
class ForecastScreen extends ConsumerWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.circa;
    final colors = t.color;
    final gutter = t.space.gutter(MediaQuery.sizeOf(context).width);
    final state = ref.watch(todayProvider).value;
    final isPro = ref.watch(isProProvider);

    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Energy forecast')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(title: const Text('Energy forecast')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, t.space.base, gutter, t.space.x4),
        children: [
          GlassCard(
            padding: EdgeInsets.fromLTRB(
              t.space.sm,
              t.space.base,
              t.space.sm,
              t.space.sm,
            ),
            child: EnergyCurve(
              points: state.forecast,
              features: state.features,
              nowUtc: state.nowUtc,
              utcOffset: state.utcOffset,
              height: 220,
            ),
          ),

          SizedBox(height: t.space.lg),
          if (!isPro)
            ProGate(
              isPro: false,
              headline: 'See three days ahead',
              onUnlock: () => context.push('/paywall?source=forecast_3day'),
              child: GlassCard(
                child: SizedBox(
                  height: 140,
                  child: Center(
                    child: Text(
                      '3-day forecast',
                      style: t.type.titleM
                          .copyWith(color: colors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),

          SizedBox(height: t.space.section),
          const SectionLabel('What’s driving it'),
          for (final part in _decomposition(state))
            Padding(
              padding: EdgeInsets.only(bottom: t.space.sm),
              child: GlassCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: part.color(colors),
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: t.space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            part.title,
                            style: t.type.titleS
                                .copyWith(color: colors.textPrimary),
                          ),
                          SizedBox(height: t.space.xs),
                          Text(
                            part.body,
                            style: t.type.bodyM
                                .copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          SizedBox(height: t.space.section),
          const SectionLabel('Today’s features'),
          if (state.features.isEmpty)
            GlassCard(
              child: Text(
                'Your curve is unusually flat today — no strong peaks or dips.',
                style: t.type.bodyM.copyWith(color: colors.textSecondary),
              ),
            )
          else
            for (final f in state.features)
              Padding(
                padding: EdgeInsets.only(bottom: t.space.sm),
                child: GlassCard(
                  padding: EdgeInsets.symmetric(
                    horizontal: t.space.base,
                    vertical: t.space.md,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          _hhmm(f.atUtc.add(state.utcOffset)),
                          style: t.type.titleS
                              .copyWith(color: colors.solarInk),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _label(f.kind),
                              style: t.type.bodyM
                                  .copyWith(color: colors.textPrimary),
                            ),
                            Text(
                              'mostly ${f.dominantCause.plainLabel}',
                              style: t.type.bodyS
                                  .copyWith(color: colors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(f.alertness * 100).round()}%',
                        style: t.type.titleS
                            .copyWith(color: colors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  static String _label(EnergyFeatureKind kind) => switch (kind) {
        EnergyFeatureKind.morningPeak => 'Morning peak',
        EnergyFeatureKind.afternoonDip => 'Afternoon dip',
        EnergyFeatureKind.eveningPeak => 'Evening peak',
        EnergyFeatureKind.nightLow => 'Night low',
      };

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  static List<_Part> _decomposition(TodayState s) {
    final currentS = s.forecast.isEmpty
        ? 0.5
        : s.forecast
            .reduce((a, b) =>
                (a.atUtc.difference(s.nowUtc).inMinutes).abs() <
                        (b.atUtc.difference(s.nowUtc).inMinutes).abs()
                    ? a
                    : b)
            .processS;

    return [
      _Part(
        title: 'Sleep pressure',
        body: 'Builds from the moment you wake and clears while you sleep. '
            'Right now it is at ${(currentS * 100).round()}% — the higher it '
            'goes, the harder everything feels.',
        color: (c) => c.dawn,
      ),
      _Part(
        title: 'Body clock',
        body: 'A roughly 24-hour rhythm anchored to your temperature minimum '
            'at ${_fmtHour(s.phase.cbtMinLocalHour)}. It is what makes '
            'mid-afternoon hard even after a good night.',
        color: (c) => c.twilight,
      ),
      _Part(
        title: 'Caffeine',
        body: s.caffeineToday.isEmpty
            ? 'Nothing logged today. Caffeine masks sleep pressure — it does '
                'not reduce it.'
            : '${s.caffeineToday.length} drink'
                '${s.caffeineToday.length == 1 ? '' : 's'} logged, leaving '
                'about ${s.caffeineAtBedtime.round()} mg at bedtime.',
        color: (c) => c.solar,
      ),
    ];
  }

  static String _fmtHour(double h) {
    final hh = h.floor() % 24;
    final mm = ((h - h.floor()) * 60).round();
    return '${hh.toString().padLeft(2, '0')}:'
        '${mm.toString().padLeft(2, '0')}';
  }
}

class _Part {
  const _Part({
    required this.title,
    required this.body,
    required this.color,
  });

  final String title;
  final String body;
  final Color Function(CircaColors) color;
}
