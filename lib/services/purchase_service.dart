import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/di/providers.dart';

/// The single entitlement everything gates on. One entitlement is deliberate —
/// multi-tier entitlements are where gating bugs are born.
const kProEntitlement = 'pro';

/// A plan as the paywall renders it.
///
/// [id] is an **app-internal** key — it drives paywall selection state and
/// nothing else. It is deliberately *not* used to look products up in the
/// store; see [packageType].
class CircaProduct {
  const CircaProduct({
    required this.id,
    required this.packageType,
    required this.title,
    required this.subtitle,
    required this.displayPrice,
    required this.periodLabel,
    this.trialDays = 0,
    this.badge,
    this.isLifetime = false,
  });

  final String id;

  /// How this plan is located in a RevenueCat offering.
  ///
  /// Matching on `storeProduct.identifier` does not survive contact with real
  /// stores. Google Play reports subscription identifiers as
  /// `subscriptionId:basePlanId` — a `circa_pro` subscription with `annual`
  /// and `monthly` base plans (the structure docs/06-revenuecat.md §8
  /// specifies) surfaces as `circa_pro:annual`, which no substring test
  /// against `circa_pro_annual` will ever match. Apple reports a flat product
  /// id. Substring matching also collides: `circa_pro_annual_winback`
  /// contains `circa_pro_annual`, so the winback package could be sold under
  /// the standard annual tile.
  ///
  /// [PackageType] is RevenueCat's own store-independent abstraction and is
  /// stable across both. It requires that offerings use the standard
  /// Annual / Monthly / Lifetime package identifiers in the dashboard.
  final PackageType packageType;

  final String title;
  final String subtitle;
  final String displayPrice;
  final String periodLabel;
  final int trialDays;
  final String? badge;
  final bool isLifetime;

  CircaProduct copyWith({String? displayPrice}) => CircaProduct(
        id: id,
        packageType: packageType,
        title: title,
        subtitle: subtitle,
        displayPrice: displayPrice ?? this.displayPrice,
        periodLabel: periodLabel,
        trialDays: trialDays,
        badge: badge,
        isLifetime: isLifetime,
      );
}

/// Bundled plan definitions.
///
/// These ship in the binary so the paywall can still render — with prices
/// clearly marked as approximate — when the store is unreachable. Live prices
/// from RevenueCat always take precedence when available.
abstract final class CircaProducts {
  static const annual = CircaProduct(
    id: 'circa_pro_annual',
    packageType: PackageType.annual,
    title: 'Annual',
    subtitle: '\$3.33 / month · save 52%',
    displayPrice: '\$39.99',
    periodLabel: 'year',
    trialDays: 7,
    badge: 'BEST VALUE',
  );

  static const monthly = CircaProduct(
    id: 'circa_pro_monthly',
    packageType: PackageType.monthly,
    title: 'Monthly',
    subtitle: 'Billed every month',
    displayPrice: '\$6.99',
    periodLabel: 'month',
  );

  static const lifetime = CircaProduct(
    id: 'circa_pro_lifetime',
    packageType: PackageType.lifetime,
    title: 'Lifetime',
    subtitle: 'One payment, no subscription',
    displayPrice: '\$89.99',
    periodLabel: 'once',
    isLifetime: true,
  );

  static const all = [annual, monthly, lifetime];

  /// Resolves the paywall's internal selection key back to a plan.
  static CircaProduct? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

enum PurchaseResult { success, cancelled, pending, failed, storeUnavailable }

/// Plans as the paywall should render them, plus the provenance of their prices.
class PlanSet {
  const PlanSet({required this.plans, required this.pricesAreLive});

  /// The bundled definitions, used whenever the store cannot price them.
  static const bundled =
      PlanSet(plans: CircaProducts.all, pricesAreLive: false);

  final List<CircaProduct> plans;

  /// False when [plans] carry the bundled approximate prices rather than the
  /// store's own. The paywall has to say so out loud — presenting a hardcoded
  /// price as if it came from the store is exactly what store review looks for.
  final bool pricesAreLive;
}

final purchaseServiceProvider = Provider<PurchaseService>(
  (ref) => PurchaseService(ref),
);

/// Available plans, priced from RevenueCat when the store can be reached.
///
/// Only ever fails when the device is genuinely offline; every other degraded
/// path resolves to [PlanSet.bundled] so the paywall still shows what Pro
/// costs. See [PurchaseService.loadOfferings].
final offeringsProvider = FutureProvider<PlanSet>((ref) async {
  return ref.watch(purchaseServiceProvider).loadOfferings();
});

/// Wraps the RevenueCat SDK.
///
/// Design note: gating reads the SDK's own cached `CustomerInfo`, never our
/// backend mirror. The SDK caches to disk, so **Pro works offline**, including
/// on a cold launch in airplane mode. A subscription that lapsed while the
/// device was offline stays honoured until the SDK can refresh — the right
/// trade-off, because locking out a paying customer over bad signal is far
/// worse than briefly over-serving one.
class PurchaseService {
  PurchaseService(this._ref);

  final Ref _ref;

  static bool _configured = false;

  /// Configures the SDK. Safe to call when no API key is present: the app then
  /// runs in free tier with an honest "store unavailable" paywall state rather
  /// than crashing at boot.
  static Future<void> configure({
    required String apiKey,
    String? appUserId,
  }) async {
    if (apiKey.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          'RevenueCat: no API key supplied — running without store access. '
          'Pass --dart-define=REVENUECAT_KEY=... to enable purchases.',
        );
      }
      return;
    }
    try {
      await Purchases.setLogLevel(
        kDebugMode ? LogLevel.warn : LogLevel.error,
      );
      // Aligning appUserID with our own user id means the webhook can write
      // straight to that user's document with no lookup table, and an
      // anonymous user who subscribes then signs in keeps their subscription
      // with zero aliasing work.
      await Purchases.configure(
        PurchasesConfiguration(apiKey)..appUserID = appUserId,
      );
      _configured = true;
    } catch (e) {
      if (kDebugMode) debugPrint('RevenueCat configure failed: $e');
    }
  }

  bool get isConfigured => _configured;

  /// Starts listening for entitlement changes and pushes them into state.
  void startListening() {
    if (!_configured) {
      _ref.read(purchaseStateProvider.notifier).markStoreUnavailable();
      return;
    }
    Purchases.addCustomerInfoUpdateListener(_apply);
    // Seed immediately from the on-disk cache so a cold offline start is right.
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      _apply(await Purchases.getCustomerInfo());
    } catch (_) {
      _ref.read(purchaseStateProvider.notifier).markStoreUnavailable();
    }
  }

  void _apply(CustomerInfo info) {
    final entitlement = info.entitlements.active[kProEntitlement];
    final expires = entitlement?.expirationDate;
    _ref.read(purchaseStateProvider.notifier).applyEntitlement(
          isPro: entitlement != null,
          isTrial: entitlement?.periodType == PeriodType.trial,
          expiresAt: expires == null ? null : DateTime.tryParse(expires),
        );
  }

  /// Live plans, falling back to the bundled definitions when the store cannot
  /// price them so the paywall is never blank.
  ///
  /// Only a genuine connectivity failure throws. That distinction is the whole
  /// point: every degraded path used to collapse to an empty list, and the
  /// paywall renders an empty list as "Connect to see plans" — so a build with
  /// no API key, or a misconfigured dashboard, blamed the user's network for a
  /// problem on our side, while the bundled prices this class carries for
  /// exactly this purpose went unused.
  Future<PlanSet> loadOfferings() async {
    // No store credentials in this build. Not a network problem, so don't let
    // the paywall claim it is.
    if (!_configured) return PlanSet.bundled;

    final Offerings offerings;
    try {
      offerings = await Purchases.getOfferings();
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.networkError ||
          code == PurchasesErrorCode.offlineConnectionError) {
        rethrow; // Actually offline — the paywall's offline state is honest.
      }
      return PlanSet.bundled;
    } catch (_) {
      return PlanSet.bundled;
    }

    final current = offerings.current;
    if (current == null || current.availablePackages.isEmpty) {
      // Store reached, but this build has no current offering — a dashboard
      // problem (see docs/06-revenuecat.md §8), not a connectivity one.
      return PlanSet.bundled;
    }

    var pricedFromStore = 0;
    final priced = <CircaProduct>[];
    for (final template in CircaProducts.all) {
      final match = _packageFor(template, current.availablePackages);
      if (match == null) {
        priced.add(template);
      } else {
        pricedFromStore++;
        priced.add(
          template.copyWith(displayPrice: match.storeProduct.priceString),
        );
      }
    }
    // Partial matches still count as approximate: one bundled price shown
    // beside two live ones is the case most likely to mislead.
    return PlanSet(
      plans: priced,
      pricesAreLive: pricedFromStore == priced.length,
    );
  }

  /// Locates the package for a plan within an offering.
  ///
  /// Matches on [CircaProduct.packageType] rather than store product ids —
  /// see the note on that field for why substring matching is unsafe.
  static Package? _packageFor(CircaProduct template, List<Package> packages) {
    for (final p in packages) {
      if (p.packageType == template.packageType) return p;
    }
    return null;
  }

  Future<PurchaseResult> purchase(String productId) async {
    if (!_configured) return PurchaseResult.storeUnavailable;

    final template = CircaProducts.byId(productId);
    if (template == null) return PurchaseResult.failed;

    try {
      final offerings = await Purchases.getOfferings();
      final packages = offerings.current?.availablePackages ?? const [];
      final target = _packageFor(template, packages);
      if (target == null) return PurchaseResult.storeUnavailable;

      final result =
          await Purchases.purchase(PurchaseParams.package(target));
      _apply(result.customerInfo);
      // No entitlement yet is not a failure — Ask-to-Buy and SCA both land
      // here, and the entitlement arrives via the listener once approved.
      return result.customerInfo.entitlements.active
                  .containsKey(kProEntitlement)
          ? PurchaseResult.success
          : PurchaseResult.pending;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      return switch (code) {
        PurchasesErrorCode.purchaseCancelledError => PurchaseResult.cancelled,
        PurchasesErrorCode.paymentPendingError => PurchaseResult.pending,
        PurchasesErrorCode.productAlreadyPurchasedError =>
          await restore() ? PurchaseResult.success : PurchaseResult.failed,
        PurchasesErrorCode.networkError ||
        PurchasesErrorCode.offlineConnectionError =>
          PurchaseResult.storeUnavailable,
        _ => PurchaseResult.failed,
      };
    } catch (_) {
      return PurchaseResult.failed;
    }
  }

  Future<bool> restore() async {
    if (!_configured) return false;
    try {
      final info = await Purchases.restorePurchases();
      _apply(info);
      return info.entitlements.active.containsKey(kProEntitlement);
    } catch (_) {
      return false;
    }
  }
}
