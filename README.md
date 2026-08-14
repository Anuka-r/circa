# Circa

**Your body clock, dialed in.**

A circadian coach that reads the sun and your sleep, then tells you when to get
light, when to stop caffeine, and when to wind down.

No wearable. No account. No network required.

Flutter 3.44.7 · Dart 3.12.2 · Riverpod · GoRouter · SQLite · RevenueCat

---

## What it does

Sleep apps measure, then abandon you. Circa prescribes.

It computes the actual sun at your coordinates with the NOAA solar algorithm,
estimates your circadian phase from your sleep pattern using the MCTQ construct,
models your alertness with Borbély's two-process model, and applies the light
phase-response curve to tell you the three or four things that will actually
change how tomorrow feels.

Every number is a documented, unit-tested algorithm. No AI guessing, no wearable,
no network. The home screen renders the real sky above you, right now.

## It computes rather than renders

The strongest evidence is the same build in two places. iPhone simulator, London
profile, five logged nights — against a Pixel emulator, Mumbai, 22:11 local,
fresh install:

| | London, 09:42 | Mumbai, 22:11 |
|---|---|---|
| Sky | Daylight arc, sun ~29% along | Star field, crescent moon near arc's end |
| Greeting | `Good morning` | `Good evening` |
| Sunrise | `05:09` (published 05:12 BST) | `06:11` (published 06:10 IST) |
| Sleep debt | `4h 59m · Moderate · Medium confidence` | `0h 00m · Clear · Estimated` |
| Active guidance | Caffeine cutoff `15:01` | `NOW — Dim the lights, 22:00–00:00` |

Nothing there is a fixture. Location resolves from the device time zone through a
bundled city dataset — no GPS permission, no network call.

### Solar engine vs published almanac

Computed sunrise/sunset against published civil times, 2026 solstices. Locked in
as golden tests at ±2 minutes:

| City | Date | Computed | Published | Δ |
|---|---|---|---|---|
| London | 21 Jun | 04:43 / 21:21 | 04:43 / 21:21 | 0 min |
| London | 21 Dec | 08:03 / 15:53 | 08:04 / 15:53 | ≤1 min |
| New York | 21 Jun | 05:25 / 20:30 | 05:25 / 20:31 | ≤1 min |
| New York | 21 Dec | 07:16 / 16:31 | 07:16 / 16:32 | ≤1 min |
| Sydney | 21 Jun | 07:00 / 16:53 | 07:00 / 16:54 | ≤1 min |
| Tokyo | 21 Jun | 04:25 / 19:00 | 04:25 / 19:00 | 0 min |
| Delhi | 21 Jun | 05:23 / 19:21 | 05:23 / 19:21 | 0 min |

Polar cases are first-class states, not errors: Tromsø returns midnight sun in
June and polar night in December.

## Accessibility is tested, not asserted

All 17 palette tokens are recomputed from source in `contrast_test.dart` and
checked against WCAG 2.2 AA on every run.

This caught a real error during design: the light-theme amber was published at
4.0:1 when it is actually **2.55:1** — a failure. Amber is now split into `solar`
(fills only, 3.28:1) and `solarInk` (text-safe, 5.81:1), and the test asserts
`solar` stays *below* 4.5:1 so nobody quietly starts using it for text.

Also covered: minimum tap-target height across every button size, 1.6× text
scaling without overflow, screen-reader semantics, and reduced-motion behaviour.

## Architecture

Offline-first is the architecture, not a feature. Every read is local, all engine
maths is local, and the network is an optimisation that is not yet wired.

```
lib/
  core/         theme (6 ThemeExtensions), router, DI
  domain/       models, pure chrono engine (8 modules, zero package deps)
  data/         SQLite schema + repository (optimistic writes, reactive reads)
  features/     onboarding · today · sleep · plan · profile · forecast · paywall
  widgets/      design system, sky renderer, charts, indicators
  services/     city lookup, timezone, purchases
```

Notable decisions, each with its reasoning in [docs/](docs/):

- **Hand-written SQL on `sqflite`, not Drift.** `drift_dev` 2.34.0 — the newest
  release compatible with the analyzer `flutter_test` pins — silently drops every
  `IntegerColumn` from generated code. Confirmed with a minimal probe table.
  Nearly every column here is an integer timestamp.
- **Riverpod without codegen.** Hand-written providers, no `build_runner` in the
  critical path.
- **A bundled city dataset instead of `geocoding`.** 4,461 cities · 361 IANA
  zones · 218 countries · 247 KB, with prefix search and haversine reverse
  geocoding, fully offline.
- **Eight dependencies, every one load-bearing.** `geolocator` was removed
  because it merges `ACCESS_FINE_LOCATION` into the manifest for a capability the
  app does not use — a Play data-safety problem before it is a code smell.
  `flutter_local_notifications` is absent until the scheduler exists.

## Running it

```bash
flutter pub get
flutter run
```

The app is fully usable with no API key — the paywall shows an honest
"connect to see plans" state rather than crashing. To transact real purchases:

```bash
flutter run --dart-define=REVENUECAT_ANDROID_KEY=goog_xxxxxxxx
```

To review gated surfaces without a store account: **Profile → Debug → Simulate
Pro** (debug builds only).

## Tests

```bash
flutter test
flutter analyze                    # 0 issues
```

**141 tests · 138 passing · 3 known failures.**

| Suite | | Covers |
|---|---|---|
| `chrono/engine_test.dart` | 62 | PRC, caffeine PK, sleep-debt ledger, two-process model, chronotype, phase |
| `chrono/solar_engine_test.dart` | 29 | NOAA algorithm, golden almanac values, polar cases, twilight ordering |
| `data/repository_test.dart` | 18 | round-trips, soft delete + undo, outbox, night counting, reactive streams |
| `widget/design_system_test.dart` | 18 | components, tap targets, 1.6× text scale, semantics, ProGate, reduced motion |
| `theme/contrast_test.dart` | 11 | WCAG AA for all 17 tokens, sky continuity |
| `services/purchase_service_test.dart` | 3 | bundled-plan fallback, live-price flagging |

Plus 3 integration tests that run against a real simulator
(`flutter test integration_test/ -d <device>`).

### The 3 known failures

The three `Light and caffeine` cases in `repository_test.dart` insert records at
a hardcoded `2026-07-22`, then read them back through `getLight()` and
`getCaffeine()` — which apply rolling 14-day and 7-day windows relative to
`DateTime.now()`. They passed on the day they were written and began failing once
wall-clock time moved past those windows.

The production code is correct; the tests are not hermetic. The fix is to inject
a clock rather than to widen the window.

## Documentation

Design and architecture were written before the code. [docs/](docs/) is the index.

| # | Document | |
|---|---|---|
| 02 | [Circadian engine](docs/02-circadian-engine.md) | ★ The core IP — every algorithm, with validation |
| 05 | [Design system](docs/05-design-system.md) | Colour with verified contrast, typography, motion, components |
| 10 | [Build report](docs/10-build-report.md) | ★ What was actually built, 12 bugs found and fixed, honest gaps |
| 03 | [Architecture](docs/03-architecture.md) | Decisions and rationale, schema, error model |
| 06 | [RevenueCat](docs/06-revenuecat.md) | Pricing, entitlements, paywall, gating matrix |

## Status

Built and working: the chrono engine, design system, local store, onboarding, and
the Today / Sleep / Plan / Profile / Forecast / Paywall screens. RevenueCat is
code-complete and needs only credentials.

Not built, stated plainly rather than stubbed:

- Jet Lag Planner UI — the engine's `daysToShift` and PRC groundwork exist; the
  trip builder and day-by-day timeline do not
- Trends screen and the consistency raster plot
- Notification scheduler — protocol events already emit stable idempotent keys;
  the reconciler into the OS queue is not written
- Sign-in, Firebase sync, Health Connect import, CI workflows

Nothing in this repo is a placeholder implementation. Every screen that exists is
fully implemented against real data. The gaps are whole features that are absent,
and they are listed above rather than papered over.

## Not a medical device

Circa is a wellness tool. It does not diagnose, treat, or prevent any condition.
If you have a sleep disorder, talk to a clinician.
