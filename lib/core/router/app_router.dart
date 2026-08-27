import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/forecast/forecast_screen.dart';
import '../../features/legal/legal_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/paywall/paywall_screen.dart';
import '../../features/plan/plan_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/sleep/sleep_screen.dart';
import '../../features/today/today_screen.dart';
import '../di/providers.dart';
import '../theme/circa_theme.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/today',
    debugLogDiagnostics: false,

    // Onboarding is the only hard gate. Pro-gated routes are never blocked by
    // the router — they render their real screen behind a ProGate so the user
    // can always see what they're missing rather than hitting a dead end.
    redirect: (context, state) {
      final profile = ref.read(profileProvider).value;
      if (profile == null) return null; // still loading; stay put

      // Legal text is reachable from anywhere, including mid-onboarding.
      // Bouncing someone to /onboarding when they tap "Privacy" on a consent
      // step is how you end up with a consent flow nobody can read.
      if (state.matchedLocation.startsWith('/legal')) return null;

      final onboarding = state.matchedLocation.startsWith('/onboarding');
      if (!profile.onboarded && !onboarding) return '/onboarding';
      if (profile.onboarded && onboarding) return '/today';
      return null;
    },
    refreshListenable: _ProfileRefresh(ref),

    routes: [
      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const OnboardingScreen(),
      ),

      GoRoute(
        path: '/paywall',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => MaterialPage(
          fullscreenDialog: true,
          child: PaywallScreen(
            source: state.uri.queryParameters['source'] ?? 'unknown',
          ),
        ),
      ),

      // Pushed over the shell: these are read from the paywall, from Profile,
      // and potentially from onboarding, so they cannot live inside one tab.
      GoRoute(
        path: '/legal/privacy',
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            const LegalScreen(document: CircaLegal.privacy),
      ),

      GoRoute(
        path: '/legal/terms',
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            const LegalScreen(document: CircaLegal.terms),
      ),

      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(
            path: '/today',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: TodayScreen()),
            routes: [
              GoRoute(
                path: 'forecast',
                parentNavigatorKey: _rootKey,
                builder: (context, state) => const ForecastScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/sleep',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SleepScreen()),
          ),
          GoRoute(
            path: '/plan',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PlanScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProfileScreen()),
          ),
        ],
      ),
    ],
  );
});


/// Rebuilds the router when onboarding completes.
class _ProfileRefresh extends ChangeNotifier {
  _ProfileRefresh(Ref ref) {
    ref.listen(profileProvider, (previous, next) {
      if (previous?.value?.onboarded != next.value?.onboarded) {
        notifyListeners();
      }
    });
  }
}

/// The bottom-navigation shell.
class _AppShell extends ConsumerWidget {
  const _AppShell({required this.child});

  final Widget child;

  static const _destinations = [
    ('/today', Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, 'Today'),
    ('/sleep', Icons.bedtime_outlined, Icons.bedtime_rounded, 'Sleep'),
    ('/plan', Icons.explore_outlined, Icons.explore_rounded, 'Plan'),
    ('/profile', Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  int _indexFor(String location) {
    for (var i = 0; i < _destinations.length; i++) {
      if (location.startsWith(_destinations[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.circa;
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexFor(location);

    // A dot on Sleep while last night is unlogged, and on Profile when there
    // are local writes still waiting to sync.
    final today = ref.watch(todayProvider).value;
    final needsSleepLog = today?.lastNight == null;
    final pendingSync = ref.watch(pendingSyncProvider).value ?? 0;

    final isWide = MediaQuery.sizeOf(context).width >= 600;

    if (isWide) {
      return Scaffold(
        backgroundColor: t.color.bgBase,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (i) =>
                  context.go(_destinations[i].$1),
              labelType: NavigationRailLabelType.all,
              backgroundColor: t.color.surface1,
              indicatorColor: t.color.solar.withValues(alpha: 0.16),
              selectedIconTheme: IconThemeData(color: t.color.solar),
              unselectedIconTheme:
                  IconThemeData(color: t.color.textTertiary),
              selectedLabelTextStyle:
                  t.type.caption.copyWith(color: t.color.textPrimary),
              unselectedLabelTextStyle:
                  t.type.caption.copyWith(color: t.color.textTertiary),
              destinations: [
                for (var i = 0; i < _destinations.length; i++)
                  NavigationRailDestination(
                    icon: _badged(
                      context,
                      Icon(_destinations[i].$2),
                      show: (i == 1 && needsSleepLog) ||
                          (i == 3 && pendingSync > 0),
                    ),
                    selectedIcon: Icon(_destinations[i].$3),
                    label: Text(_destinations[i].$4),
                  ),
              ],
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.color.bgBase,
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_destinations[i].$1),
        destinations: [
          for (var i = 0; i < _destinations.length; i++)
            NavigationDestination(
              icon: _badged(
                context,
                Icon(_destinations[i].$2),
                show: (i == 1 && needsSleepLog) ||
                    (i == 3 && pendingSync > 0),
              ),
              selectedIcon: Icon(_destinations[i].$3),
              label: _destinations[i].$4,
            ),
        ],
      ),
    );
  }

  Widget _badged(BuildContext context, Widget icon, {required bool show}) {
    if (!show) return icon;
    final t = context.circa;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -2,
          top: -1,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: t.color.dawn,
              shape: BoxShape.circle,
              border: Border.all(color: t.color.surface1, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
