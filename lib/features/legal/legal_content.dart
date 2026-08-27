/// Circa's legal text, kept free of any Flutter import.
///
/// Split from the screen deliberately: `tool/export_legal.dart` imports
/// this file with plain `dart run` to regenerate the hosted Markdown in
/// `docs/legal/`. One source of truth means the copy Play links to and the
/// copy in the app cannot drift apart.
library;

/// ⚠️ **Set this before the first Play upload.**
///
/// A privacy policy with no reachable contact address is rejected by Play
/// review, and it is the one field in these documents that cannot be derived
/// from the code. Use an address you actually read — Play also shows it on the
/// store listing.
const kCircaContactEmail = 'support@example.com';

/// The date these documents last changed. Shown to the user and quoted in the
/// hosted copies under `docs/legal/`; bump it whenever the text below changes.
const kLegalEffectiveDate = '25 August 2026';

/// One section of a legal document.
class LegalSection {
  const LegalSection(this.heading, this.body);

  final String heading;
  final List<String> body;
}

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.summary,
    required this.sections,
  });

  final String title;

  /// A plain-language line at the top. Legal text nobody reads is a dark
  /// pattern with extra steps; the summary is the part that actually informs.
  final String summary;

  final List<LegalSection> sections;
}

/// Circa's legal text.
///
/// Written against what the code actually does, not a template. Every claim
/// here is checkable: there is no HTTP client, no analytics SDK and no backend
/// in this project, the outbox is never drained to a server, and location is
/// resolved from the device time zone plus `assets/data/cities.json` rather
/// than GPS — which is why no location permission is declared.
///
/// The same text is mirrored in `docs/legal/` for hosting, because Play's
/// store listing requires a publicly reachable URL. Update both together.
abstract final class CircaLegal {
  static const privacy = LegalDocument(
    title: 'Privacy Policy',
    summary:
        'Circa keeps your data on your device. There is no Circa account, no '
        'Circa server, and nothing to sign in to. The only information that '
        'ever leaves your phone is what Google Play and RevenueCat need to '
        'process a purchase.',
    sections: [
      LegalSection('What Circa stores', [
        'Sleep sessions you log — bedtime, wake time, quality, latency, '
            'awakenings and any note you add.',
        'Caffeine and light exposures you log, with their time and amount.',
        'Your onboarding answers: habitual sleep schedule, wake difficulty, '
            'goal, and the chronotype estimated from them.',
        'The city you selected, and the time zone your device reports.',
        'Which protocol is active, and which protocol steps you have marked '
            'complete.',
      ]),
      LegalSection('Where it is stored', [
        'All of it lives in a SQLite database in Circa’s private storage '
            'on your device. Other apps cannot read it.',
        'Circa has no backend. None of the data above is uploaded, backed up '
            'to us, shared, sold, or used to train anything.',
        'Because it is local-only, Circa cannot recover your history if you '
            'uninstall the app or reset your device.',
      ]),
      LegalSection('Location', [
        'Circa does not request or use GPS, and declares no location '
            'permission.',
        'Sunrise and sunset are computed on-device from the city you pick and '
            'the time zone your device reports, using a coordinate list '
            'bundled inside the app.',
      ]),
      LegalSection('Purchases', [
        'Subscriptions and the one-time purchase are processed by Google '
            'Play. Circa never sees your payment details.',
        'Circa uses RevenueCat to validate purchases and to know whether your '
            'subscription is active. RevenueCat receives a randomly generated '
            'app user ID, your purchase receipt, and basic device and country '
            'information. It does not receive any of your sleep, caffeine or '
            'light data.',
        'RevenueCat’s own privacy policy applies to that processing and '
            'is published at revenuecat.com/privacy.',
      ]),
      LegalSection('What Circa does not do', [
        'No advertising, and no advertising identifiers.',
        'No analytics SDK, crash reporting SDK, or third-party tracker of any '
            'kind.',
        'No email address, phone number, or name is collected. Circa has no '
            'sign-in.',
      ]),
      LegalSection('Deleting your data', [
        'Profile → Delete all data erases every record Circa holds, '
            'immediately and permanently.',
        'Uninstalling Circa removes the database with it.',
        'To delete purchase records held by RevenueCat or Google, contact '
            'them, or write to us at $kCircaContactEmail and we will pass the '
            'request on.',
      ]),
      LegalSection('Children', [
        'Circa is not directed at children under 13 and does not knowingly '
            'collect anything from them.',
      ]),
      LegalSection('Changes', [
        'If this policy changes, the effective date above changes with it and '
            'the updated text ships in the next app update.',
      ]),
      LegalSection('Contact', [
        'Questions about this policy: $kCircaContactEmail',
      ]),
    ],
  );

  static const terms = LegalDocument(
    title: 'Terms of Use',
    summary:
        'Circa is a wellbeing tool, not a medical device. Pro is a '
        'subscription billed by Google Play that you can cancel at any time.',
    sections: [
      LegalSection('Circa is not medical advice', [
        'Circa estimates your body clock from the times you log and the '
            'position of the sun. Those are models, not measurements.',
        'It is not a medical device, it does not diagnose or treat anything, '
            'and it must not be used as a substitute for professional advice.',
        'If you have a sleep disorder, or you are struggling with sleep in a '
            'way that affects your health, speak to a doctor.',
        'Do not use Circa’s guidance to decide whether you are fit to '
            'drive or to operate machinery.',
      ]),
      LegalSection('Your licence', [
        'You may use Circa on devices you own, for your own personal use.',
        'You may not resell it, redistribute it, or attempt to circumvent the '
            'checks that separate the free and paid tiers.',
      ]),
      LegalSection('Circa Pro', [
        'Pro is offered as a monthly subscription, an annual subscription, or '
            'a one-time lifetime purchase.',
        'Subscriptions renew automatically at the price shown at purchase, '
            'charged to your Google Play account, until you cancel.',
        'Where a free trial is offered, it converts to a paid subscription at '
            'the end of the trial unless you cancel before it ends.',
        'Cancel any time in Google Play → Subscriptions. Cancelling stops the '
            'next renewal; it does not shorten the period you have paid for.',
        'The lifetime purchase is a single payment covering Pro for as long as '
            'Circa is published.',
      ]),
      LegalSection('Refunds', [
        'Purchases are handled by Google Play, so refunds follow Google '
            'Play’s policy and are requested through Google Play.',
        'If something in Circa did not work as described, write to '
            '$kCircaContactEmail and we will help.',
      ]),
      LegalSection('Your data is yours', [
        'Everything you log stays on your device. See the Privacy Policy.',
        'Because Circa stores nothing on a server, we cannot restore your '
            'history if you lose your device. Treat it as local data.',
      ]),
      LegalSection('Availability', [
        'Circa is provided as-is. We do not promise it will be free of bugs, '
            'nor that any particular feature will remain available.',
        'To the extent the law allows, our liability is limited to the amount '
            'you paid for Circa in the twelve months before the claim.',
      ]),
      LegalSection('Changes', [
        'If these terms change, the effective date above changes with them. '
            'Continuing to use Circa after an update means accepting them.',
      ]),
      LegalSection('Contact', [
        'Questions about these terms: $kCircaContactEmail',
      ]),
    ],
  );
}
