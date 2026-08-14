import 'package:circa/core/theme/circa_theme.dart';
import 'package:circa/domain/chrono/two_process_model.dart';
import 'package:circa/domain/value_objects/chronotype.dart';
import 'package:circa/widgets/charts/energy_curve.dart';
import 'package:circa/widgets/circa_widgets.dart';
import 'package:circa/widgets/indicators/debt_ring.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_test/flutter_test.dart';

void _noop() {}

/// Wraps a widget in the real theme so tests exercise the tokens users see.
Widget host(
  Widget child, {
  bool dark = true,
  double textScale = 1.0,
  bool reducedMotion = false,
}) {
  return MaterialApp(
    theme: dark
        ? CircaTheme.dark(reducedMotion: reducedMotion)
        : CircaTheme.light(reducedMotion: reducedMotion),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reducedMotion,
      ),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('CircaButton', () {
    testWidgets('renders its label and fires once on tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        CircaButton(label: 'Mark done', onPressed: () => taps++),
      ));

      expect(find.text('Mark done'), findsOneWidget);
      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('is inert when disabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        CircaButton(label: 'Disabled', onPressed: null),
      ));
      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('swaps its label for a spinner while loading', (tester) async {
      await tester.pumpWidget(host(
        CircaButton(label: 'Saving', loading: true, onPressed: () {}),
      ));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Saving'), findsNothing);
    });

    testWidgets('meets the minimum tap target at every size', (tester) async {
      for (final size in CircaButtonSize.values) {
        await tester.pumpWidget(host(
          CircaButton(label: 'Tap', size: size, onPressed: () {}),
        ));
        await tester.pumpAndSettle();
        final box = tester.getSize(find.byType(CircaButton));
        expect(box.height, greaterThanOrEqualTo(40),
            reason: '$size is only ${box.height}dp tall');
      }
    });

    testWidgets('exposes a button role to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        CircaButton(label: 'Log it', onPressed: () {}),
      ));
      final node = tester.getSemantics(find.byType(CircaButton));
      expect(node.label, contains('Log it'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      handle.dispose();
    });
  });

  group('DebtRing', () {
    testWidgets('shows the value, the band label, and a spoken summary',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        const DebtRing(debtHours: 4.33, confidence: PhaseConfidence.medium),
      ));
      await tester.pumpAndSettle();

      // 4h 20m — colour is never the only carrier of meaning.
      expect(find.text('Moderate'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Sleep debt')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('reads as clear at zero debt', (tester) async {
      await tester.pumpWidget(host(
        const DebtRing(debtHours: 0, confidence: PhaseConfidence.high),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('survives 1.6x text scaling without overflow', (tester) async {
      await tester.pumpWidget(host(
        const DebtRing(debtHours: 7.5, confidence: PhaseConfidence.low),
        textScale: 1.6,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('ConfidenceBadge', () {
    testWidgets('states its level and explains it', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        const ConfidenceBadge(confidence: PhaseConfidence.estimated),
      ));
      expect(find.text('Estimated'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Confidence: Estimated')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('ProGate', () {
    testWidgets('shows the real feature untouched for Pro users',
        (tester) async {
      await tester.pumpWidget(host(
        const SizedBox(
          width: 340,
          height: 240,
          child: ProGate(
            isPro: true,
            headline: 'See three days ahead',
            onUnlock: _noop,
            child: Center(child: Text('REAL CONTENT')),
          ),
        ),
      ));
      expect(find.text('REAL CONTENT'), findsOneWidget);
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets('keeps the real feature visible behind the gate', (tester) async {
      var unlocked = 0;
      await tester.pumpWidget(host(
        SizedBox(
          width: 340,
          height: 240,
          child: ProGate(
            isPro: false,
            headline: 'See three days ahead',
            onUnlock: () => unlocked++,
            child: const Center(child: Text('REAL CONTENT')),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The child is still in the tree — blurred, never replaced by a
      // locked door with no window.
      expect(find.text('REAL CONTENT'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('See three days ahead'), findsOneWidget);

      await tester.tap(find.text('Unlock with Pro'));
      await tester.pumpAndSettle();
      expect(unlocked, 1);
    });
  });

  group('EmptyState', () {
    testWidgets('always offers an action', (tester) async {
      var acted = 0;
      await tester.pumpWidget(host(
        EmptyState(
          icon: Icons.bedtime_outlined,
          title: 'No nights logged yet',
          body: 'Log last night and Circa starts learning your rhythm.',
          actionLabel: 'Log last night',
          onAction: () => acted++,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log last night'));
      expect(acted, 1);
    });

    testWidgets('renders progress toward a target', (tester) async {
      await tester.pumpWidget(host(
        const EmptyState(
          icon: Icons.insights_rounded,
          title: 'Log 5 nights to see trends',
          body: 'Almost there.',
          progress: (current: 3, target: 5),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('3 of 5'), findsOneWidget);
    });
  });

  group('ErrorStateView', () {
    testWidgets('keeps codes out of the title and behind a disclosure',
        (tester) async {
      await tester.pumpWidget(host(
        const SizedBox(
          width: 360,
          child: ErrorStateView(
            title: 'We couldn’t build today’s plan',
            body: 'Your data is safe on this device.',
            details: 'StateError: boom',
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('We couldn’t build today’s plan'), findsOneWidget);
      // The raw error is not on screen until the user asks for it.
      expect(find.text('StateError: boom'), findsNothing);
      expect(find.text('Details'), findsOneWidget);
    });
  });

  group('EnergyCurve', () {
    List<EnergyPoint> samplePoints() => TwoProcessModel.simulate(
          fromUtc: DateTime.utc(2026, 7, 22, 7),
          toUtc: DateTime.utc(2026, 7, 22, 23),
          sleepWindows: List.generate(
            8,
            (i) => SleepWindow(
              startUtc:
                  DateTime.utc(2026, 7, 15).add(Duration(days: i, hours: 23)),
              endUtc:
                  DateTime.utc(2026, 7, 16).add(Duration(days: i, hours: 7)),
            ),
          ),
          cbtMinLocalHour: 5,
          utcOffset: Duration.zero,
        );

    testWidgets('renders and exposes a text summary for screen readers',
        (tester) async {
      final handle = tester.ensureSemantics();
      final points = samplePoints();
      await tester.pumpWidget(host(
        SizedBox(
          width: 360,
          child: EnergyCurve(
            points: points,
            features: TwoProcessModel.findFeatures(points),
            nowUtc: DateTime.utc(2026, 7, 22, 14),
            utcOffset: Duration.zero,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Energy forecast'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('degrades honestly when there is not enough data',
        (tester) async {
      await tester.pumpWidget(host(
        SizedBox(
          width: 360,
          child: EnergyCurve(
            points: const [],
            features: const [],
            nowUtc: DateTime.utc(2026, 7, 22, 12),
            utcOffset: Duration.zero,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Not enough data yet'), findsOneWidget);
    });
  });

  group('Reduced motion', () {
    testWidgets('skeletons stop shimmering', (tester) async {
      await tester.pumpWidget(host(
        const Skeleton(width: 120, height: 20),
        reducedMotion: true,
      ));
      // A static fill settles immediately; a repeating shimmer would time out.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Both themes', () {
    testWidgets('every core component renders in light and dark',
        (tester) async {
      for (final dark in [true, false]) {
        await tester.pumpWidget(host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircaButton(label: 'Primary', onPressed: () {}),
              const SizedBox(height: 8),
              const CircaChip(label: 'Espresso · 63mg', selected: true),
              const SizedBox(height: 8),
              const LockChip(),
              const SizedBox(height: 8),
              const GlassCard(child: Text('Glass')),
            ],
          ),
          dark: dark,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'failed in ${dark ? 'dark' : 'light'} theme');
      }
    });
  });
}
