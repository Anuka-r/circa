import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/circa_theme.dart';
import '../../domain/chrono/caffeine_model.dart';
import '../../domain/chrono/light_prc.dart';
import '../../domain/chrono/solar_engine.dart';
import '../../widgets/circa_widgets.dart';

/// Log a light exposure.
///
/// The live lux estimate is the point of this sheet: it makes visible that
/// "I sat by the window" is worth a fraction of "I went outside", which is the
/// single most useful thing a user can learn here.
class LogLightSheet extends ConsumerStatefulWidget {
  const LogLightSheet({super.key});

  @override
  ConsumerState<LogLightSheet> createState() => _LogLightSheetState();
}

class _LogLightSheetState extends ConsumerState<LogLightSheet> {
  LightKind _kind = LightKind.directSun;
  int _minutes = 10;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final today = ref.watch(todayProvider).value;

    // Estimate from the real sun where the user is, not a fixed table.
    final lux = _estimateLux(today);
    final shiftContribution = _shiftPreview(today, lux);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        t.space.lg,
        t.space.sm,
        t.space.lg,
        t.space.lg + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Log light',
              style: t.type.titleM.copyWith(color: colors.textPrimary)),
          SizedBox(height: t.space.lg),

          Wrap(
            spacing: t.space.sm,
            runSpacing: t.space.sm,
            children: [
              for (final kind in LightKind.values)
                CircaChip(
                  label: kind.label,
                  selected: _kind == kind,
                  onTap: () => setState(() => _kind = kind),
                ),
            ],
          ),
          SizedBox(height: t.space.md),
          Text(
            _kind.note,
            style: t.type.bodyS.copyWith(color: colors.textTertiary),
          ),

          SizedBox(height: t.space.lg),
          Row(
            children: [
              Expanded(
                child: Text('How long?',
                    style: t.type.bodyM
                        .copyWith(color: colors.textSecondary)),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _minutes = (_minutes - 5).clamp(5, 240)),
                icon: const Icon(Icons.remove_rounded),
                tooltip: 'Less',
                color: colors.textSecondary,
              ),
              SizedBox(
                width: 76,
                child: Text(
                  '$_minutes min',
                  textAlign: TextAlign.center,
                  style: t.type.titleM.copyWith(color: colors.textPrimary),
                ),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _minutes = (_minutes + 5).clamp(5, 240)),
                icon: const Icon(Icons.add_rounded),
                tooltip: 'More',
                color: colors.textSecondary,
              ),
            ],
          ),

          SizedBox(height: t.space.base),
          GlassCard(
            child: Row(
              children: [
                Icon(Icons.light_mode_rounded, size: 18, color: colors.solar),
                SizedBox(width: t.space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '≈ ${_formatLux(lux)} lux',
                        style: t.type.titleS
                            .copyWith(color: colors.textPrimary),
                      ),
                      Text(
                        shiftContribution,
                        style: t.type.bodyS
                            .copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: t.space.xl),
          CircaButton(
            label: 'Log it',
            size: CircaButtonSize.lg,
            expand: true,
            loading: _saving,
            onPressed: () => _save(lux),
          ),
        ],
      ),
    );
  }

  int _estimateLux(TodayState? today) {
    if (today == null) return _kind.typicalLux;
    if (_kind == LightKind.lightBox) return 10000;
    if (_kind == LightKind.indoor) return 150;

    final altitude = today.solarDay.altitudeAt(today.nowUtc);
    return SolarEngine.estimatedLux(
      altitudeDeg: altitude,
      condition: _kind == LightKind.overcast
          ? SkyCondition.overcast
          : SkyCondition.clear,
      throughWindow: _kind == LightKind.window,
    );
  }

  String _shiftPreview(TodayState? today, int lux) {
    if (today == null) return 'Effect depends on when you got it.';

    final cbtHour = today.phase.cbtMinLocalHour;
    final local = today.localNow;
    final hoursFromCbt =
        (local.hour + local.minute / 60.0) - cbtHour;

    final response = LightPrc.responseAt(hoursFromCbt) *
        LightPrc.intensityFactor(lux) *
        LightPrc.durationFactor(_minutes);

    if (response.abs() < 0.02) {
      return 'Right now this barely moves your clock — a dead zone.';
    }
    final minutes = (response * 60).abs().round();
    return response > 0
        ? 'Right now this pulls your clock about $minutes min earlier.'
        : 'Right now this pushes your clock about $minutes min later.';
  }

  Future<void> _save(int lux) async {
    setState(() => _saving = true);
    final today = ref.read(todayProvider).value;
    final tz = ref.read(timezoneServiceProvider);
    final tzId = today?.profile.effectiveLocation.tzId ?? tz.deviceTzId;

    await ref.read(repositoryProvider).logLight(
          atUtc: DateTime.now().toUtc(),
          tzId: tzId,
          durationMinutes: _minutes,
          kind: _kind,
          lux: lux,
        );

    ref.invalidate(todayProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    showCircaSnack(context, 'Light logged', kind: SnackKind.success);
  }

  static String _formatLux(int lux) =>
      lux >= 1000 ? '${(lux / 1000).toStringAsFixed(lux >= 10000 ? 0 : 1)}k' : '$lux';
}

/// Log a caffeine intake. Shows what it will still be doing at bedtime.
class LogCaffeineSheet extends ConsumerStatefulWidget {
  const LogCaffeineSheet({super.key});

  @override
  ConsumerState<LogCaffeineSheet> createState() => _LogCaffeineSheetState();
}

class _LogCaffeineSheetState extends ConsumerState<LogCaffeineSheet> {
  DrinkPreset _drink = DrinkPreset.all[2]; // filter coffee
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final today = ref.watch(todayProvider).value;
    final residual = _residualAtBedtime(today);
    final threshold = today?.profile.caffeineThresholdMg ?? 30;
    final overBudget = residual != null && residual > threshold;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        t.space.lg,
        t.space.sm,
        t.space.lg,
        t.space.lg + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Log caffeine',
              style: t.type.titleM.copyWith(color: colors.textPrimary)),
          SizedBox(height: t.space.lg),

          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: t.space.sm,
                runSpacing: t.space.sm,
                children: [
                  for (final d in DrinkPreset.all)
                    CircaChip(
                      label: '${d.label} · ${d.mg}mg',
                      selected: _drink.key == d.key,
                      onTap: () => setState(() => _drink = d),
                    ),
                ],
              ),
            ),
          ),

          SizedBox(height: t.space.lg),
          GlassCard(
            accentColor: overBudget ? colors.dawn : colors.aurora,
            child: Row(
              children: [
                Icon(
                  overBudget
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: overBudget ? colors.dawn : colors.aurora,
                ),
                SizedBox(width: t.space.md),
                Expanded(
                  child: Text(
                    residual == null
                        ? 'Log a night first and Circa can time this for you.'
                        : overBudget
                            ? 'This leaves about ${residual.round()} mg in '
                                'your system at bedtime — above your '
                                '${threshold.round()} mg target.'
                            : 'This leaves about ${residual.round()} mg at '
                                'bedtime, within your '
                                '${threshold.round()} mg target.',
                    style: t.type.bodyS
                        .copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: t.space.xl),
          CircaButton(
            label: 'Log it',
            size: CircaButtonSize.lg,
            expand: true,
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  double? _residualAtBedtime(TodayState? today) {
    if (today == null) return null;
    final bedtime = today.events
        .where((e) => e.kind.name == 'sleep')
        .map((e) => e.startUtc)
        .firstOrNull;
    if (bedtime == null) return null;

    final doses = [
      ...today.caffeineToday.map((c) => c.toDose()),
      CaffeineDose(atUtc: today.nowUtc, mg: _drink.mg.toDouble()),
    ];
    return CaffeineModel.onBoardMg(
      doses: doses,
      atUtc: bedtime,
      halfLifeMinutes: today.profile.caffeineHalfLifeMinutes,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final today = ref.read(todayProvider).value;
    final tz = ref.read(timezoneServiceProvider);
    final tzId = today?.profile.effectiveLocation.tzId ?? tz.deviceTzId;

    await ref.read(repositoryProvider).logCaffeine(
          atUtc: DateTime.now().toUtc(),
          tzId: tzId,
          mg: _drink.mg,
          drinkKey: _drink.key,
        );

    ref.invalidate(todayProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    showCircaSnack(context, '${_drink.label} logged', kind: SnackKind.success);
  }
}
