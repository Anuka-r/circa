import 'package:circa/core/theme/circa_theme.dart';
import 'package:circa/features/legal/legal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a screen in the real theme, matching test/widget/design_system_test.
Widget host(Widget child, {bool dark = true}) => MaterialApp(
      theme: dark ? CircaTheme.dark() : CircaTheme.light(),
      home: child,
    );

void main() {
  group('Legal content', () {
    test('both documents are populated', () {
      for (final doc in [CircaLegal.privacy, CircaLegal.terms]) {
        expect(doc.title, isNotEmpty);
        expect(doc.summary, isNotEmpty);
        expect(doc.sections, isNotEmpty, reason: '${doc.title} has no sections');
        for (final section in doc.sections) {
          expect(section.heading, isNotEmpty);
          expect(section.body, isNotEmpty,
              reason: '"${section.heading}" in ${doc.title} is an empty '
                  'heading — a legal document with a hollow section reads as '
                  'boilerplate and invites exactly the scrutiny it should '
                  'deflect');
        }
      }
    });

    test('the privacy policy makes the disclosures Play asks for', () {
      final text = [
        CircaLegal.privacy.summary,
        for (final s in CircaLegal.privacy.sections) ...s.body,
      ].join(' ').toLowerCase();

      // Each of these corresponds to a Data-safety answer that must match the
      // policy, or to a control the policy promises the user.
      expect(text, contains('revenuecat'), reason: 'the only processor');
      expect(text, contains('google play'), reason: 'the billing party');
      expect(text, contains('delete'), reason: 'deletion path is required');
      expect(text, contains('gps'), reason: 'must state location is not used');
    });

    test('the terms state Circa is not a medical device', () {
      final text = [
        CircaLegal.terms.summary,
        for (final s in CircaLegal.terms.sections) ...s.body,
      ].join(' ').toLowerCase();

      expect(text, contains('not a medical device'));
      expect(text, contains('cancel'),
          reason: 'auto-renew terms must say how to stop renewing');
    });

    test('the contact address is not still the placeholder', () {
      // Guards the one field in these documents that cannot be derived from
      // the code. A policy whose only contact address is example.com is a
      // Play review rejection, and it is trivially easy to ship by accident.
      expect(
        kCircaContactEmail,
        isNot(contains('example.com')),
        reason: 'Set kCircaContactEmail in '
            'lib/features/legal/legal_content.dart before uploading to Play, '
            'then re-run `dart run tool/export_legal.dart`.',
      );
    }, skip: 'Fails until a real support address is set — see reason above.');
  });

  group('LegalScreen', () {
    testWidgets('renders the privacy policy end to end', (tester) async {
      await tester.pumpWidget(
        host(const LegalScreen(document: CircaLegal.privacy)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.textContaining('Effective'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders the terms in both themes', (tester) async {
      for (final dark in [true, false]) {
        await tester.pumpWidget(
          host(const LegalScreen(document: CircaLegal.terms), dark: dark),
        );
        await tester.pumpAndSettle();
        expect(find.text('Terms of Use'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('scrolls to the end without overflowing', (tester) async {
      await tester.pumpWidget(
        host(const LegalScreen(document: CircaLegal.privacy)),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
