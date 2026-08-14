import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database.dart';
import '../../data/repositories/circa_repository.dart';
import '../../domain/chrono/caffeine_model.dart';
import '../../domain/chrono/chronotype_estimator.dart';
import '../../domain/chrono/circadian_phase_model.dart';
import '../../domain/chrono/protocol_engine.dart';
import '../../domain/chrono/sleep_debt_ledger.dart';
import '../../domain/chrono/two_process_model.dart';
import '../../domain/entities/sleep_session.dart';
import '../../domain/value_objects/solar_day.dart';
import '../../services/city_lookup.dart';
import '../../services/timezone_service.dart';

// -----------------------------------------------------------------------------
// Infrastructure — all overridden in main() once boot completes.
// -----------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final timezoneServiceProvider = Provider<TimezoneService>(
  (ref) => TimezoneService.instance,
);

final cityLookupProvider = Provider<CityLookup>(
  (ref) => CityLookup.instance,
);

final repositoryProvider = Provider<CircaRepository>(
  (ref) => CircaRepository(ref.watch(databaseProvider)),
);

/// A ticking clock. The sky redraws off this, so it must not be `DateTime.now()`
/// read inline in `build` — that would never update.
///
/// One minute is deliberate: solar altitude changes by at most ~0.25° per
/// minute, which is below the perceptual threshold of the gradient, so the sky
/// appears continuous while costing one rebuild a minute.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now().toUtc();
  yield* Stream.periodic(
    const Duration(minutes: 1),
    (_) => DateTime.now().toUtc(),
  );
});

/// The current instant, without forcing a subscription to the ticker.
DateTime nowUtc(Ref ref) =>
    ref.read(clockProvider).value ?? DateTime.now().toUtc();

// -----------------------------------------------------------------------------
// Profile
// -----------------------------------------------------------------------------

final profileProvider = StreamProvider<UserProfile>(
  (ref) => ref.watch(repositoryProvider).watchProfile(),
);

/// Entitlement, kept as its own provider so every gate reads one source.
///
/// Seeded from the local profile so Pro survives a cold launch in airplane
/// mode; RevenueCat's own cached CustomerInfo updates it when available.
final isProProvider = Provider<bool>((ref) {
  final purchases = ref.watch(purchaseStateProvider);
  if (purchases.isPro) return true;
  return ref.watch(profileProvider).value?.isPro ?? false;
});

/// Purchase state, populated by [PurchaseController].
class PurchaseState {
  const PurchaseState({
    this.isPro = false,
    this.isTrial = false,
    this.expiresAt,
    this.isLoading = false,
    this.storeUnavailable = false,
  });

  final bool isPro;
  final bool isTrial;
  final DateTime? expiresAt;
  final bool isLoading;

  /// True when the store SDK could not be reached or configured — used to show
  /// an honest "connect to see plans" state rather than a broken paywall.
  final bool storeUnavailable;

  PurchaseState copyWith({
    bool? isPro,
    bool? isTrial,
    DateTime? expiresAt,
    bool? isLoading,
    bool? storeUnavailable,
  }) =>
      PurchaseState(
        isPro: isPro ?? this.isPro,
        isTrial: isTrial ?? this.isTrial,
        expiresAt: expiresAt ?? this.expiresAt,
        isLoading: isLoading ?? this.isLoading,
        storeUnavailable: storeUnavailable ?? this.storeUnavailable,
      );
}

final purchaseStateProvider =
    NotifierProvider<PurchaseController, PurchaseState>(
  PurchaseController.new,
);

/// Owns the RevenueCat lifecycle. Kept deliberately thin: gating reads the SDK
/// (or its on-disk cache), never our own backend mirror, so a paying customer
/// is never locked out by a dead network.
class PurchaseController extends Notifier<PurchaseState> {
  @override
  PurchaseState build() => const PurchaseState();

  /// Called once the store SDK reports entitlement state.
  void applyEntitlement({
    required bool isPro,
    bool isTrial = false,
    DateTime? expiresAt,
  }) {
    state = state.copyWith(
      isPro: isPro,
      isTrial: isTrial,
      expiresAt: expiresAt,
      isLoading: false,
      storeUnavailable: false,
    );
  }

  void markStoreUnavailable() {
    state = state.copyWith(isLoading: false, storeUnavailable: true);
  }

  void setLoading(bool loading) => state = state.copyWith(isLoading: loading);

  /// Debug-only override so the gated surfaces can be reviewed without a
  /// configured store account. Never compiled into a release build.
  void debugSetPro(bool value) {
    assert(() {
      state = state.copyWith(isPro: value);
      return true;
    }());
    if (kReleaseMode) return;
  }
}

// -----------------------------------------------------------------------------
// Derived circadian state
// -----------------------------------------------------------------------------

/// Everything the Today screen needs, computed in one place.
class TodayState {
  const TodayState({
    required this.profile,
    required this.solarDay,
    required this.phase,
    required this.debt,
    required this.events,
    required this.forecast,
    required this.features,
    required this.completions,
    required this.utcOffset,
    required this.lastNight,
    required this.caffeineToday,
    required this.lightToday,
    required this.nowUtc,
  });

  final UserProfile profile;
  final SolarDay solarDay;
  final PhaseEstimate phase;
  final SleepDebt debt;
  final List<ProtocolEvent> events;
  final List<EnergyPoint> forecast;
  final List<EnergyFeature> features;
  final Set<String> completions;
  final Duration utcOffset;

  /// Last night's logged sleep, if any. Null drives the "How did you sleep?"
  /// prompt.
  final SleepSession? lastNight;

  final List<LoggedCaffeine> caffeineToday;
  final List<LoggedLight> lightToday;
  final DateTime nowUtc;

  DateTime get localNow => nowUtc.add(utcOffset);

  String get localDateKey => SleepDebtLedger.formatNight(
        DateTime(localNow.year, localNow.month, localNow.day),
      );

  /// The night we would be asking the user to log right now.
  String get lastNightKey => SleepDebtLedger.nightOfLocal(
        localNow.subtract(const Duration(hours: 12)),
      );

  ProtocolEvent? get nextUp => ProtocolEngine.nextUp(
        events,
        nowUtc,
        completedKeys: completions,
        localDate: localDateKey,
      );

  bool isCompleted(ProtocolEvent e) =>
      completions.contains(e.keyFor(localDateKey));

  /// Caffeine still on board when the user intends to go to bed.
  double get caffeineAtBedtime {
    final bed = events.where((e) => e.kind == ProtocolEventKind.sleep);
    if (bed.isEmpty) return 0;
    return CaffeineModel.onBoardMg(
      doses: caffeineToday.map((c) => c.toDose()).toList(),
      atUtc: bed.first.startUtc,
      halfLifeMinutes: profile.caffeineHalfLifeMinutes,
    );
  }

  int get lightMinutesToday =>
      lightToday.fold(0, (sum, l) => sum + l.durationMinutes);
}

final todayProvider = AsyncNotifierProvider<TodayController, TodayState>(
  TodayController.new,
);

class TodayController extends AsyncNotifier<TodayState> {
  @override
  Future<TodayState> build() async {
    // Re-run whenever any input changes.
    final profile = await ref.watch(profileProvider.future);
    final completions =
        await ref.watch(_completionsProvider.future);
    final sessions = await ref.watch(_sessionsProvider.future);
    final caffeine = await ref.watch(_caffeineProvider.future);
    final light = await ref.watch(_lightProvider.future);
    ref.watch(clockProvider);

    final tz = ref.watch(timezoneServiceProvider);
    final now = nowUtc(ref);

    final location = profile.effectiveLocation;
    final offset = tz.offsetFor(now, location.tzId);
    final local = now.add(offset);

    final solarDay = SolarDay.compute(
      date: DateTime(local.year, local.month, local.day),
      location: location,
      utcOffset: offset,
    );

    // Re-estimate chronotype from real data once it exists, falling back to the
    // onboarding questionnaire.
    final chronotype = ChronotypeEstimator.fromSessions(
      sessions: sessions,
      fallback: profile.schedule,
      utcOffsetFor: (utc) => tz.offsetFor(utc, location.tzId),
    );

    final phase = CircadianPhaseModel.estimate(
      chronotype: chronotype,
      schedule: profile.schedule,
    );

    final byNight = SleepDebtLedger.aggregate(
      sessions,
      utcOffsetFor: (utc) => tz.offsetFor(utc, location.tzId),
    );
    final debt = SleepDebtLedger.compute(
      sleepByNight: byNight,
      needMinutes: profile.sleepNeedMinutes,
      asOfDateLocal: DateTime(local.year, local.month, local.day),
    );

    final events = ProtocolEngine.buildDay(
      protocol: profile.activeProtocol,
      phase: phase,
      solarDay: solarDay,
      sleepNeedMinutes: profile.sleepNeedMinutes,
      caffeineThresholdMg: profile.caffeineThresholdMg,
      caffeineHalfLifeMinutes: profile.caffeineHalfLifeMinutes,
      plannedCaffeineMg: profile.typicalCaffeineMg,
    );

    // Forecast horizon is the paywall's job, not the engine's.
    final isPro = ref.watch(isProProvider);
    final horizon = isPro ? const Duration(days: 3) : const Duration(hours: 24);

    final sleepWindows = <SleepWindow>[
      for (final s in sessions)
        SleepWindow(startUtc: s.startUtc, endUtc: s.endUtc),
      // The night the user intends to have, so the curve reflects the plan.
      for (final e in events)
        if (e.kind == ProtocolEventKind.sleep)
          SleepWindow(startUtc: e.startUtc, endUtc: e.endUtc),
    ];

    final startOfLocalDay =
        DateTime.utc(local.year, local.month, local.day).subtract(offset);

    final forecast = TwoProcessModel.simulate(
      fromUtc: startOfLocalDay,
      toUtc: startOfLocalDay.add(horizon),
      sleepWindows: sleepWindows,
      cbtMinLocalHour: phase.cbtMinLocalHour,
      utcOffset: offset,
      caffeine: caffeine.map((c) => c.toDose()).toList(),
      caffeineHalfLifeMinutes: profile.caffeineHalfLifeMinutes,
    );

    final lastNightKey = SleepDebtLedger.nightOfLocal(
      local.subtract(const Duration(hours: 12)),
    );
    SleepSession? lastNight;
    for (final s in sessions) {
      if (s.nightOf == lastNightKey) {
        lastNight = s;
        break;
      }
    }

    bool isToday(DateTime utc) {
      final l = utc.add(offset);
      return l.year == local.year && l.month == local.month && l.day == local.day;
    }

    return TodayState(
      profile: profile,
      solarDay: solarDay,
      phase: phase,
      debt: debt,
      events: events,
      forecast: forecast,
      features: TwoProcessModel.findFeatures(forecast),
      completions: completions,
      utcOffset: offset,
      lastNight: lastNight,
      caffeineToday: caffeine.where((c) => isToday(c.atUtc)).toList(),
      lightToday: light.where((l) => isToday(l.atUtc)).toList(),
      nowUtc: now,
    );
  }

  Future<void> completeEvent(ProtocolEvent event) async {
    final current = state.value;
    if (current == null) return;
    await ref
        .read(repositoryProvider)
        .completeEvent(event.keyFor(current.localDateKey));
  }

  Future<void> uncompleteEvent(ProtocolEvent event) async {
    final current = state.value;
    if (current == null) return;
    await ref
        .read(repositoryProvider)
        .uncompleteEvent(event.keyFor(current.localDateKey));
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

// Private input providers, so TodayController can await each independently.
final _completionsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(repositoryProvider).watchCompletions(),
);

final _sessionsProvider = StreamProvider<List<SleepSession>>(
  (ref) => ref.watch(repositoryProvider).watchSleepSessions(),
);

final _caffeineProvider = StreamProvider<List<LoggedCaffeine>>(
  (ref) => ref.watch(repositoryProvider).watchCaffeine(),
);

final _lightProvider = StreamProvider<List<LoggedLight>>(
  (ref) => ref.watch(repositoryProvider).watchLight(),
);

/// Public aliases for screens that only need one slice.
final sleepSessionsProvider = _sessionsProvider;
final caffeineLogProvider = _caffeineProvider;
final lightLogProvider = _lightProvider;

final pendingSyncProvider = StreamProvider<int>(
  (ref) => ref.watch(repositoryProvider).watchPendingSyncCount(),
);
