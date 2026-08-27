import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/circa_theme.dart';
import '../../domain/chrono/protocol_engine.dart';
import '../../widgets/circa_widgets.dart';

/// Plan — protocols and trip planning.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.circa;
    final colors = t.color;
    final gutter = t.space.gutter(MediaQuery.sizeOf(context).width);
    final today = ref.watch(todayProvider).value;
    final isPro = ref.watch(isProProvider);
    final active = today?.profile.activeProtocol ?? ProtocolKind.reset;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(title: const Text('Plan')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, t.space.base, gutter, t.space.x4),
        children: [
          const SectionLabel('Active protocol'),
          GlassCard(
            accentColor: colors.solar,
            padding: EdgeInsets.fromLTRB(
              t.space.lg,
              t.space.base,
              t.space.base,
              t.space.base,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active.title,
                  style: t.type.titleM.copyWith(color: colors.textPrimary),
                ),
                SizedBox(height: t.space.xs),
                Text(
                  active.tagline,
                  style: t.type.bodyM.copyWith(color: colors.solarInk),
                ),
                SizedBox(height: t.space.md),
                Text(
                  active.description,
                  style: t.type.bodyM.copyWith(color: colors.textSecondary),
                ),
                if (today != null) ...[
                  SizedBox(height: t.space.base),
                  Divider(color: colors.borderSubtle, height: 1),
                  SizedBox(height: t.space.base),
                  Text(
                    'Your body clock',
                    style: t.type.label.copyWith(color: colors.textTertiary),
                  ),
                  SizedBox(height: t.space.sm),
                  _PhaseRow(
                    label: 'Melatonin onset',
                    value: _hour(today.phase.dlmoLocalHour),
                    note: 'the start of your biological night',
                  ),
                  _PhaseRow(
                    label: 'Temperature minimum',
                    value: _hour(today.phase.cbtMinLocalHour),
                    note: 'light before this delays, after this advances',
                  ),
                  _PhaseRow(
                    label: 'Chronotype',
                    value: today.phase.chronotype.plainLabel,
                    note: today.phase.chronotype.description,
                  ),
                ],
              ],
            ),
          ),

          SizedBox(height: t.space.section),
          const SectionLabel('All protocols'),
          for (final kind in ProtocolKind.values)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.sm),
              child: _ProtocolCard(
                kind: kind,
                isActive: kind == active,
                locked: kind.isPro && !isPro,
                onTap: () async {
                  // Jet Lag is a screen, not a switch: it needs a trip before
                  // it can produce a plan, and the planner gates itself. Free
                  // users land on the real plan behind ProGate rather than
                  // being bounced to the paywall with nothing to look at.
                  if (kind == ProtocolKind.jetLag) {
                    context.push('/jetlag');
                    return;
                  }
                  if (kind.isPro && !isPro) {
                    context.push('/paywall?source=protocol_${kind.name}');
                    return;
                  }
                  final repo = ref.read(repositoryProvider);
                  final profile = await repo.getProfile();
                  await repo.saveProfile(
                    profile.copyWith(activeProtocol: kind),
                  );
                  ref.invalidate(todayProvider);
                  if (!context.mounted) return;
                  showCircaSnack(
                    context,
                    '${kind.title} activated',
                    kind: SnackKind.success,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  static String _hour(double h) {
    final hh = h.floor() % 24;
    final mm = ((h - h.floor()) * 60).round();
    return '${hh.toString().padLeft(2, '0')}:'
        '${mm.toString().padLeft(2, '0')}';
  }
}

class _PhaseRow extends StatelessWidget {
  const _PhaseRow({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: t.type.bodyM.copyWith(color: t.color.textPrimary),
                ),
              ),
              Text(
                value,
                style: t.type.titleS.copyWith(color: t.color.solarInk),
              ),
            ],
          ),
          SizedBox(height: 2),
          Text(
            note,
            style: t.type.bodyS.copyWith(color: t.color.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({
    required this.kind,
    required this.isActive,
    required this.locked,
    required this.onTap,
  });

  final ProtocolKind kind;
  final bool isActive;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    return GlassCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.solar.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, size: 19, color: colors.solar),
          ),
          SizedBox(width: t.space.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        kind.title,
                        style: t.type.titleS
                            .copyWith(color: colors.textPrimary),
                      ),
                    ),
                    SizedBox(width: t.space.sm),
                    if (locked)
                      const LockChip()
                    else if (isActive)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: t.space.sm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.aurora.withValues(alpha: 0.16),
                          borderRadius: t.radius.pillRadius,
                        ),
                        child: Text(
                          'ACTIVE',
                          style: t.type.caption
                              .copyWith(color: colors.aurora),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: t.space.xs),
                Text(
                  kind.description,
                  style:
                      t.type.bodyS.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData get _icon => switch (kind) {
        ProtocolKind.reset => Icons.restart_alt_rounded,
        ProtocolKind.earlyRiser => Icons.wb_twilight_rounded,
        ProtocolKind.shiftWork => Icons.schedule_rounded,
        ProtocolKind.jetLag => Icons.flight_takeoff_rounded,
      };
}
