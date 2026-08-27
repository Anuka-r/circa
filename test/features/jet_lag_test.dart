import 'package:circa/core/di/providers.dart';
import 'package:circa/core/theme/circa_theme.dart';
import 'package:circa/domain/chrono/circadian_phase_model.dart';
import 'package:circa/domain/chrono/jet_lag_planner.dart';
import 'package:circa/domain/value_objects/chronotype.dart';
import 'package:circa/domain/value_objects/geo_location.dart';
import 'package:circa/features/jetlag/jet_lag_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _offsets = <String, Duration>{
  'Europe/London': Duration(hours: 1),
  'Asia/Tokyo': Duration(hours: 9),
  'America/Los_Angeles': Duration(hours: -7),
};

Duration _offsetFor(DateTime utc, String tzId) =>
    _offsets[tzId] ?? Duration.zero;

const _london = GeoLocation(
  latitude: 51.5074,
  longitude: -0.1278,
  tzId: 'Europe/London',
  label: 'London, United Kingdom',
);
const _tokyo = GeoLocation(
  latitude: 35.6762,
  longitude: 139.6503,
  tzId: 'Asia/Tokyo',
  label: 'Tokyo, Japan',
);
const _la = GeoLocation(
  latitude: 34.0522,
  longitude: -118.2437,
  tzId: 'America/Los_Angeles',
  label: 'Los Angeles, United States',
);

const _phase = PhaseEstimate(
  dlmoLocalHour: 21.0,
  cbtMinLocalHour: 4.0,
  confidence: PhaseConfidence.high,
  chronotype: Chronotype.intermediate,
  msfScMinutes: 270,
  disagreementHours: 0,
);

JetLagPlan _planTo(GeoLocation destination) => JetLagPlanner.build(
      trip: Trip(
        origin: _london,
        destination: destination,
        departureUtc: DateTime.utc(2026, 9, 10, 10),
        arrivalUtc: DateTime.utc(2026, 9, 10, 22),
      ),
      phase: _phase,
      sleepNeedMinutes: 480,
      offsetFor: _offsetFor,
    );

/// The screen with only the providers it actually reads, so these stay widget
/// tests rather than a rebuild of the whole app graph.
Widget _host(JetLagPlan? plan, {bool dark = true}) => ProviderScope(
      overrides: [
        isProProvider.overrideWithValue(true),
        jetLagPlanProvider.overrideWithValue(plan),
      ],
      child: MaterialApp(
        theme: dark ? CircaTheme.dark() : CircaTheme.light(),
        home: const JetLagScreen(),
      ),
    );

void main() {
  group('JetLagScreen', () {
    testWidgets('with no trip, offers to plan one', (tester) async {
      await tester.pumpWidget(_host(null));
      await tester.pumpAndSettle();

      expect(find.text('No trip planned'), findsOneWidget);
      expect(find.text('Plan a trip'), findsOneWidget);
    });

    testWidgets('renders an eastward plan in both themes', (tester) async {
      for (final dark in [true, false]) {
        await tester.pumpWidget(_host(_planTo(_tokyo), dark: dark));
        await tester.pumpAndSettle();

        expect(find.text('London → Tokyo'), findsOneWidget);
        expect(find.text('8h east'), findsOneWidget);
        expect(find.textContaining('at least 8 days'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('states how adapted you are on landing, not that you are',
        (tester) async {
      await tester.pumpWidget(_host(_planTo(_tokyo)));
      await tester.pumpAndSettle();

      final plan = _planTo(_tokyo);
      expect(plan.adaptedPercentOnArrival, lessThan(100));
      expect(find.text('${plan.adaptedPercentOnArrival}%'), findsOneWidget);
      expect(
        find.textContaining('does not pretend jet lag is solvable in one'),
        findsOneWidget,
      );
    });

    testWidgets('names the city on every day card', (tester) async {
      // The whole point of the plan is that these times sit on a clock that
      // moves. A card without its city is a time with no meaning.
      await tester.pumpWidget(_host(_planTo(_tokyo)));
      await tester.pumpAndSettle();

      expect(find.textContaining('London'), findsWidgets);

      await tester.scrollUntilVisible(
        find.textContaining('Day 1 after landing'),
        300,
      );
      expect(find.textContaining('Tokyo'), findsWidgets);
    });

    testWidgets('labels the flight day and the days before it', (tester) async {
      await tester.pumpWidget(_host(_planTo(_tokyo)));
      await tester.pumpAndSettle();

      expect(find.text('3 days before you fly'), findsOneWidget);

      // Lazily built list: scroll each label into view rather than assuming
      // the whole plan is laid out at once.
      for (final label in ['The day before you fly', 'Flight day']) {
        await tester.scrollUntilVisible(find.text(label), 300);
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('westward reads as west, and is cheaper', (tester) async {
      await tester.pumpWidget(_host(_planTo(_la)));
      await tester.pumpAndSettle();

      expect(find.text('London → Los Angeles'), findsOneWidget);
      expect(find.text('8h west'), findsOneWidget);
      expect(find.textContaining('at least 6 days'), findsOneWidget);
    });

    testWidgets('every instruction can explain itself', (tester) async {
      await tester.pumpWidget(_host(_planTo(_tokyo)));
      await tester.pumpAndSettle();

      final instruction = find.text('Light to pull earlier').first;
      await tester.ensureVisible(instruction);
      await tester.pumpAndSettle();
      await tester.tap(instruction);
      await tester.pumpAndSettle();

      // The sheet carries the reason, in plain English and without jargon.
      expect(
        find.textContaining('advance side of your response curve'),
        findsOneWidget,
      );
    });

    testWidgets('scrolls the whole plan without overflowing', (tester) async {
      await tester.pumpWidget(_host(_planTo(_tokyo)));
      await tester.pumpAndSettle();

      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 12; i++) {
        await tester.drag(list, const Offset(0, -400));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
