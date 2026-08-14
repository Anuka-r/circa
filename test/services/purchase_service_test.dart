import 'package:circa/services/purchase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('loadOfferings without store credentials', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    // The regression this guards: every degraded path used to return an empty
    // list, and the paywall renders an empty list as "Connect to see plans".
    // A build with no API key therefore blamed the user's network for a missing
    // credential, while the bundled prices that exist for this exact case went
    // unused.
    test('falls back to the bundled plans rather than an empty list', () async {
      final set = await container.read(purchaseServiceProvider).loadOfferings();

      expect(set.plans, isNotEmpty);
      expect(
        set.plans.map((p) => p.id),
        CircaProducts.all.map((p) => p.id),
      );
    });

    test('flags the bundled prices as not live', () async {
      final set = await container.read(purchaseServiceProvider).loadOfferings();

      // Drives the "Approximate prices" line on the paywall. If this ever
      // reported true, hardcoded prices would be presented as the store's.
      expect(set.pricesAreLive, isFalse);
    });

    test('every bundled plan carries a price to display', () async {
      final set = await container.read(purchaseServiceProvider).loadOfferings();

      for (final plan in set.plans) {
        expect(plan.displayPrice, isNotEmpty, reason: '${plan.id} has no price');
      }
    });
  });
}
