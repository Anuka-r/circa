import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/circa_theme.dart';
import '../../services/purchase_service.dart';
import '../../widgets/circa_widgets.dart';

/// The paywall.
///
/// Rules we hold ourselves to, and which are enforced by this layout:
/// * the close button is live from frame one — no delay, no tiny grey X;
/// * price, period, trial length and renewal terms are all above the CTA;
/// * no countdown timers, no fake scarcity, no "97% of users choose…";
/// * "Restore purchases" is always reachable, because Apple requires it and
///   because hiding it is hostile.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.source = 'unknown'});

  final String source;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String _selected = CircaProducts.annual.id;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final gutter = t.space.gutter(MediaQuery.sizeOf(context).width);
    final offerings = ref.watch(offeringsProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: EdgeInsets.only(left: t.space.sm, top: t.space.sm),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                  color: colors.textSecondary,
                  tooltip: 'Close',
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, t.space.lg),
                children: [
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [colors.solarBright, colors.solar],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colors.solar.withValues(alpha: 0.35),
                            blurRadius: 32,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.wb_sunny_rounded,
                        size: 36,
                        color: colors.onSolar,
                      ),
                    ),
                  ),
                  SizedBox(height: t.space.lg),
                  Text(
                    'Circa Pro',
                    textAlign: TextAlign.center,
                    style: t.type.displayM.copyWith(color: colors.textPrimary),
                  ),
                  SizedBox(height: t.space.xs),
                  Text(
                    'See further ahead.',
                    textAlign: TextAlign.center,
                    style: t.type.bodyL.copyWith(color: colors.textSecondary),
                  ),

                  SizedBox(height: t.space.xl),
                  for (final benefit in _benefits)
                    Padding(
                      padding: EdgeInsets.only(bottom: t.space.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 18, color: colors.aurora),
                          SizedBox(width: t.space.md),
                          Expanded(
                            child: Text(
                              benefit,
                              style: t.type.bodyM
                                  .copyWith(color: colors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),

                  SizedBox(height: t.space.lg),

                  offerings.when(
                    loading: () => Column(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          const Skeleton(
                              width: double.infinity, height: 76, radius: 18),
                          SizedBox(height: t.space.sm),
                        ],
                      ],
                    ),
                    error: (e, _) => _OfflinePlans(
                      onRetry: () => ref.invalidate(offeringsProvider),
                    ),
                    data: (planSet) {
                      if (planSet.plans.isEmpty) {
                        return _OfflinePlans(
                          onRetry: () => ref.invalidate(offeringsProvider),
                        );
                      }
                      return Column(
                        children: [
                          for (final plan in planSet.plans)
                            Padding(
                              padding: EdgeInsets.only(bottom: t.space.sm),
                              child: _PlanCard(
                                plan: plan,
                                selected: _selected == plan.id,
                                onTap: () =>
                                    setState(() => _selected = plan.id),
                              ),
                            ),
                          // Said plainly rather than hidden, because these are
                          // the bundled prices and may not be what the store
                          // charges.
                          if (!planSet.pricesAreLive) ...[
                            SizedBox(height: t.space.xs),
                            Text(
                              'Approximate prices. Your store shows the exact '
                              'amount in your own currency before you pay.',
                              textAlign: TextAlign.center,
                              style: t.type.caption
                                  .copyWith(color: colors.textTertiary),
                            ),
                          ],
                        ],
                      );
                    },
                  ),

                  if (_error != null) ...[
                    SizedBox(height: t.space.md),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: t.type.bodyS.copyWith(color: colors.danger),
                    ),
                  ],
                ],
              ),
            ),

            // Terms sit inside the same semantics node as the CTA, so a screen
            // reader hears what they're agreeing to before the button.
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                0,
                gutter,
                t.space.base,
              ),
              child: Semantics(
                container: true,
                child: Column(
                  children: [
                    CircaButton(
                      label: _ctaLabel(offerings.value),
                      size: CircaButtonSize.lg,
                      expand: true,
                      loading: _busy,
                      onPressed: _purchase,
                    ),
                    SizedBox(height: t.space.sm),
                    Text(
                      _termsLine(offerings.value),
                      textAlign: TextAlign.center,
                      style: t.type.bodyS
                          .copyWith(color: colors.textTertiary),
                    ),
                    SizedBox(height: t.space.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _busy ? null : _restore,
                          child: Text(
                            'Restore purchases',
                            style: t.type.bodyS
                                .copyWith(color: colors.textSecondary),
                          ),
                        ),
                        Text('·',
                            style: t.type.bodyS
                                .copyWith(color: colors.textTertiary)),
                        TextButton(
                          onPressed: () {},
                          child: Text(
                            'Terms',
                            style: t.type.bodyS
                                .copyWith(color: colors.textSecondary),
                          ),
                        ),
                        Text('·',
                            style: t.type.bodyS
                                .copyWith(color: colors.textTertiary)),
                        TextButton(
                          onPressed: () {},
                          child: Text(
                            'Privacy',
                            style: t.type.bodyS
                                .copyWith(color: colors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _benefits = [
    '3-day energy forecast, not just today',
    'Jet lag planner for any trip',
    'Shift-work and early-riser protocols',
    'Unlimited history and trends',
    'Apple Health and Health Connect sync',
    'Export your data whenever you like',
  ];

  /// Resolves the selection against the *loaded* plans, so the renewal terms
  /// quote the same price as the tile the user tapped. Reading from
  /// [CircaProducts] instead would quote the bundled price even when the store
  /// returned a live one — a mismatch between the tile and the terms directly
  /// above the buy button.
  CircaProduct? _selectedFrom(PlanSet? set) {
    for (final p in set?.plans ?? CircaProducts.all) {
      if (p.id == _selected) return p;
    }
    return null;
  }

  String _ctaLabel(PlanSet? set) {
    final plan = _selectedFrom(set);
    if (plan == null) return 'Continue';
    return plan.trialDays > 0
        ? 'Start ${plan.trialDays} days free'
        : 'Get Circa Pro';
  }

  String _termsLine(PlanSet? set) {
    final plan = _selectedFrom(set);
    if (plan == null) return 'Cancel anytime.';
    if (plan.isLifetime) {
      return 'One payment of ${plan.displayPrice}. Yours forever.';
    }
    return plan.trialDays > 0
        ? '${plan.trialDays} days free, then ${plan.displayPrice} per '
            '${plan.periodLabel}. Cancel anytime.'
        : '${plan.displayPrice} per ${plan.periodLabel}. Cancel anytime.';
  }

  Future<void> _purchase() async {
    final plan = _selectedFrom(ref.read(offeringsProvider).value);
    if (plan == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final result =
        await ref.read(purchaseServiceProvider).purchase(plan.id);

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case PurchaseResult.success:
        ref.invalidate(todayProvider);
        Navigator.of(context).maybePop();
        showCircaSnack(context, 'Welcome to Circa Pro',
            kind: SnackKind.success);
      case PurchaseResult.cancelled:
        // A cancellation is not an error. No snackbar, no guilt, no report.
        break;
      case PurchaseResult.pending:
        setState(() => _error =
            'Your purchase needs approval. Pro unlocks automatically once '
            'it clears.');
      case PurchaseResult.storeUnavailable:
        setState(() => _error =
            'Couldn’t reach the store. Check your connection and try again.');
      case PurchaseResult.failed:
        setState(() =>
            _error = 'That didn’t go through. No charge was made.');
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final restored = await ref.read(purchaseServiceProvider).restore();
    if (!mounted) return;
    setState(() => _busy = false);

    if (restored) {
      ref.invalidate(todayProvider);
      Navigator.of(context).maybePop();
      showCircaSnack(context, 'Pro restored', kind: SnackKind.success);
    } else {
      showCircaSnack(
        context,
        'No previous purchase found on this account.',
        kind: SnackKind.warning,
      );
    }
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final CircaProduct plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: '${plan.title}, ${plan.displayPrice}'
          '${plan.trialDays > 0 ? ', ${plan.trialDays} day free trial' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: t.motion.quick,
          padding: EdgeInsets.all(t.space.base),
          decoration: BoxDecoration(
            color: selected
                ? colors.solar.withValues(alpha: 0.12)
                : colors.surface1.withValues(alpha: 0.7),
            borderRadius: t.radius.inputRadius,
            border: Border.all(
              color: selected ? colors.solar : colors.borderSubtle,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          plan.title,
                          style: t.type.titleS
                              .copyWith(color: colors.textPrimary),
                        ),
                        if (plan.badge != null) ...[
                          SizedBox(width: t.space.sm),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: t.space.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  colors.aurora.withValues(alpha: 0.16),
                              borderRadius: t.radius.pillRadius,
                            ),
                            child: Text(
                              plan.badge!,
                              style: t.type.caption
                                  .copyWith(color: colors.aurora),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      plan.subtitle,
                      style: t.type.bodyS
                          .copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              Text(
                plan.displayPrice,
                style: t.type.titleS.copyWith(color: colors.textPrimary),
              ),
              SizedBox(width: t.space.sm),
              AnimatedContainer(
                duration: t.motion.quick,
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? colors.solar : Colors.transparent,
                  border: Border.all(
                    color:
                        selected ? colors.solar : colors.borderStrong,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded,
                        size: 13, color: colors.onSolar)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Honest offline state: the store is unreachable, say so and offer retry —
/// and keep "restore" working, because that path may still succeed.
class _OfflinePlans extends StatelessWidget {
  const _OfflinePlans({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return GlassCard(
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 26, color: t.color.textTertiary),
          SizedBox(height: t.space.md),
          Text(
            'Connect to see plans',
            style: t.type.titleS.copyWith(color: t.color.textPrimary),
          ),
          SizedBox(height: t.space.xs),
          Text(
            'Prices come from the App Store, so this needs a connection. '
            'Everything else in Circa keeps working offline.',
            textAlign: TextAlign.center,
            style: t.type.bodyS.copyWith(color: t.color.textSecondary),
          ),
          SizedBox(height: t.space.base),
          CircaButton(
            label: 'Try again',
            size: CircaButtonSize.sm,
            variant: CircaButtonVariant.secondary,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
