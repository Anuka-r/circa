import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/di/providers.dart';
import 'data/local/database.dart';
import 'services/city_lookup.dart';
import 'services/purchase_service.dart';
import 'services/timezone_service.dart';

/// Store keys are injected at build time so no secret lives in source control.
///
/// RevenueCat public SDK keys are **per store**, not per project: Google Play
/// keys are prefixed `goog_`, Apple keys `appl_`. A single key cannot serve
/// both — passing an `appl_` key to an Android build is rejected by the SDK and
/// leaves the app permanently in free tier. So each is injected separately and
/// chosen at runtime:
///
///   flutter build appbundle --release \
///     --dart-define=REVENUECAT_ANDROID_KEY=goog_xxxxxxxx
///
///   flutter build ipa --release \
///     --dart-define=REVENUECAT_APPLE_KEY=appl_xxxxxxxx
///
/// Absent, the app runs in free tier and the paywall shows an honest
/// "connect to see plans" state rather than crashing at launch.
const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
const _appleKey = String.fromEnvironment('REVENUECAT_APPLE_KEY');

/// The original single-key define, still honoured so existing run
/// configurations and CI scripts keep working. Used only when no
/// platform-specific key was supplied.
const _legacyKey = String.fromEnvironment('REVENUECAT_KEY');

/// RevenueCat **Test Store** key, for exercising the paywall end to end before
/// the store accounts exist — real offerings, real prices, real entitlement
/// grants, and a simulated purchase sheet, with no Play Console involved.
///
///   flutter run --dart-define=REVENUECAT_TEST_KEY=test_xxxxxxxx
///
/// Read only outside release builds, by design. Shipping a Test Store key to
/// Play is the same class of failure the `goog_`/`appl_` split above exists to
/// prevent, and a worse one: the build looks healthy, the paywall renders, and
/// nothing is ever actually sold. A release build ignores this define
/// entirely — the branch is const-folded away — even if CI passes it by
/// mistake.
const _testStoreKey = String.fromEnvironment('REVENUECAT_TEST_KEY');

String _storeKey() {
  if (!kReleaseMode && _testStoreKey.isNotEmpty) return _testStoreKey;
  final key = switch (defaultTargetPlatform) {
    TargetPlatform.android => _androidKey,
    TargetPlatform.iOS || TargetPlatform.macOS => _appleKey,
    _ => '',
  };
  return key.isNotEmpty ? key : _legacyKey;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // Ordering matters: the timezone database must be loaded before any date
  // maths runs, and the local store before the first frame reads from it.
  // These three are independent, so they run concurrently — the app must never
  // block its first frame on work that can be parallelised.
  late final AppDatabase database;
  await Future.wait([
    TimezoneService.init(),
    CityLookup.load(),
    AppDatabase.open().then((db) => database = db),
  ]);

  // Purchases are configured off the critical path: a slow or unreachable
  // store must not delay launch by a single frame.
  unawaited(PurchaseService.configure(apiKey: _storeKey()));

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
      ],
      child: const CircaApp(),
    ),
  );
}
