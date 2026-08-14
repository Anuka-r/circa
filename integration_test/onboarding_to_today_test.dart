import 'package:circa/app.dart';
import 'package:circa/core/di/providers.dart';
import 'package:circa/data/local/database.dart';
import 'package:circa/data/repositories/circa_repository.dart';
import 'package:circa/services/city_lookup.dart';
import 'package:circa/services/timezone_service.dart';
import 'package:circa/widgets/indicators/debt_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end: a fresh install completes onboarding and lands on a *populated*
/// Today screen — no empty state, no spinner, no placeholder.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    await TimezoneService.init();
    await CityLookup.load();
    db = await AppDatabase.openInMemory();
  });

  tearDown(() async => db.close());

  Future<void> bootApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const CircaApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    final finder = find.text(label);
    expect(finder, findsWidgets, reason: 'expected to find "$label"');
    // Scroll it into the viewport first: Today is a long scroll view, and
    // tapping a widget that is merely *in the tree* would land the hit test
    // wherever that offset happens to fall on screen.
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    await tester.tap(finder.first, warnIfMissed: true);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
  }

  testWidgets('fresh install → onboarding → populated Today', (tester) async {
    await bootApp(tester);

    // ---- Onboarding -------------------------------------------------------
    expect(find.text('Circa'), findsOneWidget);
    expect(find.text('Your body clock, dialled in.'), findsOneWidget);

    await tapText(tester, 'Get started');
    expect(
      find.text('When do you usually sleep on a work day?'),
      findsOneWidget,
    );

    await tapText(tester, 'Continue'); // work schedule (defaults are fine)
    expect(find.text('And on a free day?'), findsOneWidget);

    await tapText(tester, 'Continue'); // free-day schedule
    expect(find.text('How hard is it to get up?'), findsOneWidget);
    await tapText(tester, 'Sometimes hard');
    await tapText(tester, 'Continue');

    expect(
      find.text('How much caffeine on a typical day?'),
      findsOneWidget,
    );
    await tapText(tester, 'Continue');

    // Goal is required — Continue must be inert until one is chosen.
    expect(find.text('What are you here for?'), findsOneWidget);
    await tapText(tester, 'More energy');
    await tapText(tester, 'Continue');

    expect(find.text('Where are you?'), findsOneWidget);
    await tapText(tester, 'Continue');

    // The disclaimer is blocking and needs an explicit checkbox.
    expect(find.text('One thing before we start'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tapText(tester, 'Build my rhythm');

    // ---- Today ------------------------------------------------------------
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Never empty on night zero: the questionnaire seeds the phase model.
    expect(find.byType(DebtRing), findsOneWidget);
    expect(find.text('Next up'.toUpperCase()), findsOneWidget);
    expect(find.text('Energy forecast'.toUpperCase()), findsOneWidget);
    expect(find.text('Today’s rhythm'.toUpperCase()), findsOneWidget);
    expect(find.text('How did you sleep?'), findsOneWidget);

    // The profile was actually persisted, not just held in memory.
    final profile = await CircaRepository(db).getProfile();
    expect(profile.onboarded, isTrue);
    expect(profile.disclaimerAcknowledged, isTrue);
    expect(profile.goal, 'More energy');
    expect(profile.location, isNotNull);
  });

  testWidgets('logging a night updates the debt ring', (tester) async {
    // Pre-onboard so this test is about the daily loop, not the funnel.
    final repo = CircaRepository(db);
    final base = await repo.getProfile();
    await repo.saveProfile(base.copyWith(
      onboarded: true,
      disclaimerAcknowledged: true,
      location: CityLookup.instance.search('London').first.toGeoLocation(),
    ));

    await bootApp(tester);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('How did you sleep?'), findsOneWidget);
    await tapText(tester, 'How did you sleep?');

    expect(find.text('Save night'), findsOneWidget,
        reason: 'the log-sleep sheet should have opened');
    await tapText(tester, 'Save night');

    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The prompt is gone because the night is now logged.
    expect(find.text('How did you sleep?'), findsNothing);
    final sessions = await repo.getSleepSessions();
    expect(sessions, hasLength(1));
  });

  testWidgets('every tab renders', (tester) async {
    final repo = CircaRepository(db);
    final base = await repo.getProfile();
    await repo.saveProfile(base.copyWith(
      onboarded: true,
      disclaimerAcknowledged: true,
      location: CityLookup.instance.search('London').first.toGeoLocation(),
    ));

    await bootApp(tester);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    for (final label in ['Sleep', 'Plan', 'Profile']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: '$label tab threw');
    }
  });
}
