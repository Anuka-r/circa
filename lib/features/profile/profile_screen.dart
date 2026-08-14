import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/circa_theme.dart';
import '../../widgets/circa_widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.circa;
    final colors = t.color;
    final gutter = t.space.gutter(MediaQuery.sizeOf(context).width);
    final today = ref.watch(todayProvider).value;
    final isPro = ref.watch(isProProvider);
    final pending = ref.watch(pendingSyncProvider).value ?? 0;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, t.space.base, gutter, t.space.x4),
        children: [
          // Subscription status
          GlassCard(
            accentColor: isPro ? colors.aurora : colors.solar,
            onTap: isPro ? null : () => context.push('/paywall?source=profile'),
            child: Row(
              children: [
                Icon(
                  isPro ? Icons.verified_rounded : Icons.auto_awesome_rounded,
                  size: 22,
                  color: isPro ? colors.aurora : colors.solar,
                ),
                SizedBox(width: t.space.base),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPro ? 'Circa Pro' : 'Circa Free',
                        style: t.type.titleS
                            .copyWith(color: colors.textPrimary),
                      ),
                      SizedBox(height: 2),
                      Text(
                        isPro
                            ? 'Thanks for supporting Circa.'
                            : 'See 3 days ahead, keep all your history, and '
                                'plan for time zones.',
                        style: t.type.bodyS
                            .copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (!isPro)
                  Icon(Icons.chevron_right_rounded,
                      color: colors.textTertiary),
              ],
            ),
          ),

          SizedBox(height: t.space.section),
          const SectionLabel('Your rhythm'),
          if (today != null)
            GlassCard(
              child: Column(
                children: [
                  _InfoRow(
                    label: 'Chronotype',
                    value: today.phase.chronotype.plainLabel,
                  ),
                  _InfoRow(
                    label: 'Sleep need',
                    value:
                        '${(today.profile.sleepNeedMinutes / 60).toStringAsFixed(1)}h',
                    note: today.profile.sleepNeedIsPersonalised
                        ? 'personalised from your data'
                        : 'population default — log 14 nights to personalise',
                  ),
                  _InfoRow(
                    label: 'Nights logged',
                    value: '${today.profile.nightsLogged}',
                  ),
                  _InfoRow(
                    label: 'Location',
                    value: today.profile.effectiveLocation.label ?? 'Not set',
                    note: today.profile.effectiveLocation.tzId,
                    isLast: true,
                  ),
                ],
              ),
            ),

          SizedBox(height: t.space.section),
          const SectionLabel('Data'),
          GlassCard(
            child: Column(
              children: [
                _InfoRow(
                  label: 'Waiting to sync',
                  value: pending == 0 ? 'All synced' : '$pending change'
                      '${pending == 1 ? '' : 's'}',
                  note: pending == 0
                      ? null
                      : 'Everything is saved on this device already.',
                ),
                _InfoRow(
                  label: 'Cities available offline',
                  value: '${ref.watch(cityLookupProvider).count}',
                  isLast: true,
                ),
              ],
            ),
          ),

          SizedBox(height: t.space.section),
          const SectionLabel('About'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Circa is a wellness tool, not a medical device.',
                  style: t.type.titleS.copyWith(color: colors.textPrimary),
                ),
                SizedBox(height: t.space.sm),
                Text(
                  'Everything Circa shows is modelled from published '
                  'chronobiology and the data you give it — the NOAA solar '
                  'position algorithm, the Munich Chronotype Questionnaire, '
                  'the light phase-response curve, and Borbély’s two-process '
                  'model of alertness.\n\n'
                  'It does not diagnose, treat, or prevent anything. If you '
                  'regularly feel exhausted despite sleeping enough, please '
                  'talk to a doctor.',
                  style: t.type.bodyM.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),

          // A debug-only switch so gated surfaces can be reviewed without a
          // configured store account. Never present in a release build.
          if (kDebugMode) ...[
            SizedBox(height: t.space.section),
            const SectionLabel('Debug'),
            GlassCard(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Simulate Pro entitlement',
                      style: t.type.bodyM
                          .copyWith(color: colors.textSecondary),
                    ),
                  ),
                  Switch(
                    value: isPro,
                    onChanged: (v) {
                      ref
                          .read(purchaseStateProvider.notifier)
                          .debugSetPro(v);
                      ref.invalidate(todayProvider);
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.note,
    this.isLast = false,
  });

  final String label;
  final String value;
  final String? note;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : t.space.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: t.type.bodyM.copyWith(color: t.color.textSecondary),
                ),
              ),
              SizedBox(width: t.space.md),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: t.type.titleS.copyWith(color: t.color.textPrimary),
                ),
              ),
            ],
          ),
          if (note != null) ...[
            SizedBox(height: 2),
            Text(
              note!,
              style: t.type.bodyS.copyWith(color: t.color.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
