import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/circa_theme.dart';
import 'services/purchase_service.dart';

class CircaApp extends ConsumerStatefulWidget {
  const CircaApp({super.key});

  @override
  ConsumerState<CircaApp> createState() => _CircaAppState();
}

class _CircaAppState extends ConsumerState<CircaApp> {
  @override
  void initState() {
    super.initState();
    // Start listening for entitlement changes once the tree exists. The SDK
    // seeds from its own on-disk cache, so Pro is correct on a cold offline
    // start rather than flickering to free and back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(purchaseServiceProvider).startListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Respect the platform's reduced-motion setting everywhere by threading it
    // into the theme, so no individual widget has to remember to check.
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return MaterialApp.router(
      title: 'Circa',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: CircaTheme.light(reducedMotion: reducedMotion),
      darkTheme: CircaTheme.dark(reducedMotion: reducedMotion),
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        // Clamp text scaling to a range every layout is verified against,
        // rather than letting a 3x system setting shatter the UI.
        final scale = MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.6,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
