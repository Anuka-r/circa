import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/circa_theme.dart';
import '../../domain/chrono/sleep_debt_ledger.dart';
import '../../domain/entities/sleep_session.dart';
import '../../widgets/circa_widgets.dart';

/// Sleep — log, review, and understand nights over time.
class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.circa;
    final colors = t.color;
    final gutter = t.space.gutter(MediaQuery.sizeOf(context).width);
    final sessionsAsync = ref.watch(sleepSessionsProvider);
    final isPro = ref.watch(isProProvider);
    final today = ref.watch(todayProvider).value;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Sleep'),
        actions: [
          IconButton(
            onPressed: () => showCircaSheet(context, const LogSleepSheet()),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Log a night',
          ),
          SizedBox(width: t.space.sm),
        ],
      ),
      body: sessionsAsync.when(
        loading: () => Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Skeleton(width: double.infinity, height: 96, radius: 20),
              SizedBox(height: t.space.base),
              for (var i = 0; i < 4; i++) ...[
                const Skeleton(width: double.infinity, height: 64, radius: 16),
                SizedBox(height: t.space.sm),
              ],
            ],
          ),
        ),
        error: (e, _) => Padding(
          padding: EdgeInsets.all(gutter),
          child: ErrorStateView(
            title: 'Couldn’t load your nights',
            body: 'Your data is safe on this device.',
            details: e.toString(),
            onRetry: () => ref.invalidate(sleepSessionsProvider),
          ),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return EmptyState(
              icon: Icons.bedtime_outlined,
              title: 'No nights logged yet',
              body: 'Log last night and Circa starts learning your rhythm. '
                  'Five nights is enough to personalise your schedule.',
              actionLabel: 'Log last night',
              onAction: () => showCircaSheet(context, const LogSleepSheet()),
            );
          }

          // Free tier sees a week; Pro sees everything.
          final visible = isPro ? sessions : sessions.take(7).toList();
          final hidden = sessions.length - visible.length;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              t.space.base,
              gutter,
              t.space.x4,
            ),
            children: [
              _SummaryRow(sessions: sessions, needMinutes:
                  today?.profile.sleepNeedMinutes ?? 480),
              SizedBox(height: t.space.section),
              const SectionLabel('Recent nights'),
              for (final s in visible)
                _NightRow(
                  session: s,
                  utcOffset: today?.utcOffset ?? Duration.zero,
                  needMinutes: today?.profile.sleepNeedMinutes ?? 480,
                  onDelete: () async {
                    await ref.read(repositoryProvider).deleteSleep(s.id);
                    if (!context.mounted) return;
                    showCircaSnack(
                      context,
                      'Night deleted',
                      actionLabel: 'Undo',
                      onAction: () => ref
                          .read(repositoryProvider)
                          .undoDeleteSleep(s.id),
                    );
                  },
                ),
              if (hidden > 0) ...[
                SizedBox(height: t.space.base),
                GlassCard(
                  onTap: () => context.push('/paywall?source=history'),
                  child: Column(
                    children: [
                      const LockChip(),
                      SizedBox(height: t.space.md),
                      Text(
                        '$hidden more night${hidden == 1 ? '' : 's'} in your '
                        'history',
                        style: t.type.titleS
                            .copyWith(color: colors.textPrimary),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: t.space.xs),
                      Text(
                        'Free keeps the last 7 nights. Pro keeps all of them, '
                        'plus trends and consistency.',
                        style: t.type.bodyS
                            .copyWith(color: colors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: t.space.base),
                      CircaButton(
                        label: 'See everything with Pro',
                        size: CircaButtonSize.sm,
                        onPressed: () =>
                            context.push('/paywall?source=history'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.sessions, required this.needMinutes});

  final List<SleepSession> sessions;
  final double needMinutes;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final recent = sessions.take(7).toList();
    final avg = recent.isEmpty
        ? 0.0
        : recent
                .map((s) => s.duration.inMinutes)
                .reduce((a, b) => a + b) /
            recent.length;

    final consistency = _midpointSpreadMinutes(recent);

    return Row(
      children: [
        Expanded(
          child: _Stat(
            label: 'Avg nightly',
            value: _fmt(avg.round()),
            sub: 'last ${recent.length} nights',
          ),
        ),
        SizedBox(width: t.space.sm),
        Expanded(
          child: _Stat(
            label: 'Target',
            value: _fmt(needMinutes.round()),
            sub: 'your sleep need',
          ),
        ),
        SizedBox(width: t.space.sm),
        Expanded(
          child: _Stat(
            label: 'Consistency',
            value: consistency == null ? '—' : '±${consistency.round()}m',
            sub: 'mid-sleep spread',
          ),
        ),
      ],
    );
  }

  static double? _midpointSpreadMinutes(List<SleepSession> sessions) {
    if (sessions.length < 2) return null;
    final midpoints = sessions.map((s) {
      final m = s.midpointUtc;
      final minutes = m.hour * 60.0 + m.minute;
      return minutes >= 720 ? minutes - 1440 : minutes;
    }).toList();
    final mean =
        midpoints.reduce((a, b) => a + b) / midpoints.length;
    final variance = midpoints
            .map((x) => (x - mean) * (x - mean))
            .reduce((a, b) => a + b) /
        (midpoints.length - 1);
    return variance <= 0 ? 0 : _sqrt(variance);
  }

  static double _sqrt(double v) {
    var x = v;
    for (var i = 0; i < 20; i++) {
      x = 0.5 * (x + v / x);
    }
    return x;
  }

  static String _fmt(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.sub});

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return GlassCard(
      padding: EdgeInsets.symmetric(
        horizontal: t.space.md,
        vertical: t.space.base,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: t.type.caption.copyWith(color: t.color.textTertiary),
          ),
          SizedBox(height: t.space.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: t.type.displayM.copyWith(
                color: t.color.textPrimary,
                fontSize: 26,
              ),
            ),
          ),
          SizedBox(height: 2),
          Text(
            sub,
            style: t.type.caption.copyWith(color: t.color.textTertiary),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _NightRow extends StatelessWidget {
  const _NightRow({
    required this.session,
    required this.utcOffset,
    required this.needMinutes,
    required this.onDelete,
  });

  final SleepSession session;
  final Duration utcOffset;
  final double needMinutes;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final start = session.startUtc.add(utcOffset);
    final end = session.endUtc.add(utcOffset);
    final minutes = session.duration.inMinutes;
    final delta = minutes - needMinutes;

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: EdgeInsets.symmetric(horizontal: t.space.lg),
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.18),
          borderRadius: t.radius.cardRadius,
        ),
        child: Icon(Icons.delete_outline_rounded, color: colors.danger),
      ),
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: EdgeInsets.only(bottom: t.space.sm),
        child: GlassCard(
          padding: EdgeInsets.symmetric(
            horizontal: t.space.base,
            vertical: t.space.md,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _weekday(end.weekday),
                      style: t.type.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                    Text(
                      '${end.day}',
                      style: t.type.titleS
                          .copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
              SizedBox(width: t.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fmtDuration(minutes),
                      style: t.type.titleS
                          .copyWith(color: colors.textPrimary),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '${_hhmm(start)} – ${_hhmm(end)}'
                      '${session.source == SleepSource.health ? ' · Health' : ''}',
                      style: t.type.bodyS
                          .copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: t.space.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: (delta >= 0 ? colors.aurora : colors.dawn)
                      .withValues(alpha: 0.14),
                  borderRadius: t.radius.pillRadius,
                ),
                child: Text(
                  '${delta >= 0 ? '+' : '−'}${_fmtDuration(delta.abs().round())}',
                  style: t.type.caption.copyWith(
                    color: delta >= 0 ? colors.aurora : colors.dawn,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _weekday(int w) =>
      const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][w - 1];

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  static String _fmtDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

/// Sleep logging sheet — the highest-frequency write in the app, so it is built
/// for two taps and nothing more.
class LogSleepSheet extends ConsumerStatefulWidget {
  const LogSleepSheet({super.key});

  @override
  ConsumerState<LogSleepSheet> createState() => _LogSleepSheetState();
}

class _LogSleepSheetState extends ConsumerState<LogSleepSheet> {
  double? _bedMinutes;
  double? _wakeMinutes;
  int? _quality;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final today = ref.watch(todayProvider).value;

    // Defaults come from the user's habitual schedule, so confirming is enough.
    final bed = _bedMinutes ?? today?.profile.schedule.workBedMinutes ?? 1380;
    final wake = _wakeMinutes ?? today?.profile.schedule.workWakeMinutes ?? 420;
    final duration = _span(bed, wake);

    final tooLong = duration > 16 * 60;
    final isNap = duration < 180;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        t.space.lg,
        t.space.sm,
        t.space.lg,
        t.space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How did you sleep?',
            style: t.type.titleM.copyWith(color: colors.textPrimary),
          ),
          SizedBox(height: t.space.xs),
          Text(
            'Last night',
            style: t.type.bodyS.copyWith(color: colors.textTertiary),
          ),
          SizedBox(height: t.space.lg),

          _SheetTimeRow(
            label: 'Bedtime',
            minutes: bed,
            icon: Icons.bedtime_rounded,
            onChanged: (v) => setState(() => _bedMinutes = v),
          ),
          SizedBox(height: t.space.sm),
          _SheetTimeRow(
            label: 'Wake up',
            minutes: wake,
            icon: Icons.wb_twilight_rounded,
            onChanged: (v) => setState(() => _wakeMinutes = v),
          ),

          SizedBox(height: t.space.base),
          Center(
            child: Text(
              _fmtDuration(duration.round()),
              style: t.type.displayM.copyWith(color: colors.textPrimary),
            ),
          ),

          if (tooLong) ...[
            SizedBox(height: t.space.sm),
            Text(
              'That’s over 16 hours — is the date right? We’ll still log it.',
              style: t.type.bodyS.copyWith(color: colors.dawn),
              textAlign: TextAlign.center,
            ),
          ] else if (isNap) ...[
            SizedBox(height: t.space.sm),
            Text(
              'Under 3 hours counts as a nap, which repays debt at half rate.',
              style: t.type.bodyS.copyWith(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],

          SizedBox(height: t.space.lg),
          Text(
            'How was it?',
            style: t.type.label.copyWith(color: colors.textSecondary),
          ),
          SizedBox(height: t.space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 1; i <= 5; i++)
                _QualityButton(
                  value: i,
                  selected: _quality == i,
                  onTap: () => setState(() => _quality = i),
                ),
            ],
          ),

          SizedBox(height: t.space.xl),
          CircaButton(
            label: 'Save night',
            size: CircaButtonSize.lg,
            expand: true,
            loading: _saving,
            onPressed: () => _save(bed, wake),
          ),
        ],
      ),
    );
  }

  Future<void> _save(double bed, double wake) async {
    setState(() => _saving = true);
    final today = ref.read(todayProvider).value;
    final tz = ref.read(timezoneServiceProvider);
    final repo = ref.read(repositoryProvider);

    final tzId = today?.profile.effectiveLocation.tzId ?? tz.deviceTzId;
    final offset = today?.utcOffset ?? tz.currentOffset(tzId);
    final localNow = DateTime.now().toUtc().add(offset);

    // The night that just ended: wake time is today (or this morning), bedtime
    // is whatever precedes it.
    final wakeLocal = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      (wake ~/ 60) % 24,
      (wake % 60).round(),
    );
    final bedLocal = wakeLocal.subtract(
      Duration(minutes: _span(bed, wake).round()),
    );

    final startUtc = bedLocal.subtract(offset);
    final endUtc = wakeLocal.subtract(offset);
    final nightOf = SleepDebtLedger.nightOfLocal(bedLocal);

    final existing = await repo.sessionForNight(nightOf);

    await repo.logSleep(
      startUtc: startUtc,
      endUtc: endUtc,
      tzId: tzId,
      nightOf: nightOf,
      quality: _quality,
      replaceId: existing?.id,
    );

    ref.invalidate(todayProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    showCircaSnack(context, 'Night saved', kind: SnackKind.success);
  }

  static double _span(double from, double to) {
    var d = to - from;
    if (d <= 0) d += 1440;
    return d;
  }

  static String _fmtDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

class _SheetTimeRow extends StatelessWidget {
  const _SheetTimeRow({
    required this.label,
    required this.minutes,
    required this.icon,
    required this.onChanged,
  });

  final String label;
  final double minutes;
  final IconData icon;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final normalised = minutes % 1440;
    final h = (normalised ~/ 60).toInt();
    final m = (normalised % 60).round();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space.base),
      decoration: BoxDecoration(
        color: t.color.surface3.withValues(alpha: 0.5),
        borderRadius: t.radius.inputRadius,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: t.color.textTertiary),
          SizedBox(width: t.space.md),
          Expanded(
            child: Text(
              label,
              style: t.type.bodyM.copyWith(color: t.color.textSecondary),
            ),
          ),
          IconButton(
            onPressed: () => onChanged(minutes - 15),
            icon: const Icon(Icons.remove_rounded, size: 18),
            tooltip: 'Earlier',
            color: t.color.textSecondary,
          ),
          SizedBox(
            width: 74,
            child: Semantics(
              label: label,
              value: '${h.toString().padLeft(2, '0')}:'
                  '${m.toString().padLeft(2, '0')}',
              child: Text(
                '${h.toString().padLeft(2, '0')}:'
                '${m.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: t.type.titleM.copyWith(color: t.color.textPrimary),
              ),
            ),
          ),
          IconButton(
            onPressed: () => onChanged(minutes + 15),
            icon: const Icon(Icons.add_rounded, size: 18),
            tooltip: 'Later',
            color: t.color.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _QualityButton extends StatelessWidget {
  const _QualityButton({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  static const _labels = ['Awful', 'Poor', 'OK', 'Good', 'Great'];

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    return Semantics(
      button: true,
      selected: selected,
      label: _labels[value - 1],
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: t.motion.quick,
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: selected
                    ? colors.solar.withValues(alpha: 0.18)
                    : colors.surface3.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? colors.solar : colors.borderSubtle,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  '$value',
                  style: t.type.titleS.copyWith(
                    color:
                        selected ? colors.solarInk : colors.textSecondary,
                  ),
                ),
              ),
            ),
            SizedBox(height: t.space.xs),
            Text(
              _labels[value - 1],
              style: t.type.caption.copyWith(
                color: selected ? colors.solarInk : colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
