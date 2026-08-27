import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/circa_theme.dart';
import '../../domain/chrono/jet_lag_planner.dart';
import '../../domain/chrono/protocol_engine.dart';
import '../../domain/value_objects/geo_location.dart';
import '../../widgets/circa_widgets.dart';
import 'trip_builder_sheet.dart';

/// The Jet Lag Planner — the headline Pro feature.
///
/// Everything on this screen is derived from the light phase-response curve in
/// `LightPrc`, which is why the advice it gives is sometimes the opposite of
/// the usual "get some morning sun": after a long eastward flight the local
/// morning lands on the delay lobe of the curve and pushes the clock further
/// from where it needs to be.
class JetLagScreen extends ConsumerWidget {
  const JetLagScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.circa;
    final colors = t.color;
    final gutter = t.space.gutter(MediaQuery.sizeOf(context).width);
    final isPro = ref.watch(isProProvider);
    final plan = ref.watch(jetLagPlanProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Jet Lag'),
        actions: [
          if (isPro && plan != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete trip',
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: !isPro
          ? _GatedPreview(gutter: gutter)
          : plan == null
              ? _NoTrip(onPlan: () => _planTrip(context, ref))
              : _PlanView(
                  plan: plan,
                  gutter: gutter,
                  onReplan: () => _planTrip(context, ref),
                ),
    );
  }

  static Future<void> _planTrip(BuildContext context, WidgetRef ref) async {
    final trip = await showTripBuilder(context);
    if (trip == null) return;

    final repo = ref.read(repositoryProvider);
    await repo.saveTrip(trip);

    // Activating the protocol alongside the trip, because a plan the user has
    // to go and switch on somewhere else is a plan half of them never run.
    final profile = await repo.getProfile();
    await repo.saveProfile(
      profile.copyWith(activeProtocol: ProtocolKind.jetLag),
    );
    ref.invalidate(todayProvider);

    if (!context.mounted) return;
    showCircaSnack(context, 'Trip saved', kind: SnackKind.success);
  }

  static Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this trip?'),
        content: const Text(
          'The plan goes with it. Your sleep history and everything else stay '
          'exactly as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = ref.read(repositoryProvider);
    await repo.deleteTrip();
    final profile = await repo.getProfile();
    if (profile.activeProtocol == ProtocolKind.jetLag) {
      await repo.saveProfile(
        profile.copyWith(activeProtocol: ProtocolKind.reset),
      );
    }
    ref.invalidate(todayProvider);
    if (!context.mounted) return;
    showCircaSnack(context, 'Trip deleted');
  }
}

class _NoTrip extends StatelessWidget {
  const _NoTrip({required this.onPlan});
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.flight_takeoff_rounded,
        title: 'No trip planned',
        body: 'Tell Circa where you are flying and when. It works out how far '
            'your body clock has to move, which direction is the hard one, and '
            'what to do with light on each day either side of the flight.',
        actionLabel: 'Plan a trip',
        onAction: onPlan,
      );
}

/// What a free user sees: the real plan for a real trip, behind the gate.
/// Never a locked door with no window.
class _GatedPreview extends ConsumerWidget {
  const _GatedPreview({required this.gutter});
  final double gutter;

  static const _london = GeoLocation(
    latitude: 51.5074,
    longitude: -0.1278,
    tzId: 'Europe/London',
    label: 'London, United Kingdom',
  );
  static const _tokyo = GeoLocation(
    latitude: 35.6762,
    longitude: 139.6503,
    tzId: 'Asia/Tokyo',
    label: 'Tokyo, Japan',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider).value;
    if (today == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final tz = ref.read(timezoneServiceProvider);
    final departure = today.nowUtc.add(const Duration(days: 7));
    final sample = JetLagPlanner.build(
      trip: Trip(
        origin: _london,
        destination: _tokyo,
        departureUtc: departure,
        arrivalUtc: departure.add(const Duration(hours: 12)),
      ),
      phase: today.phase,
      sleepNeedMinutes: today.profile.sleepNeedMinutes,
      offsetFor: tz.offsetFor,
    );

    return ProGate(
      isPro: false,
      headline: 'Plan any trip, day by day',
      onUnlock: () => context.push('/paywall?source=jetlag'),
      child: _PlanView(plan: sample, gutter: gutter, onReplan: null),
    );
  }
}

// -----------------------------------------------------------------------------

class _PlanView extends StatelessWidget {
  const _PlanView({
    required this.plan,
    required this.gutter,
    required this.onReplan,
  });

  final JetLagPlan plan;
  final double gutter;
  final VoidCallback? onReplan;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, t.space.base, gutter, t.space.x4),
      children: [
        _Summary(plan: plan),
        if (onReplan != null) ...[
          SizedBox(height: t.space.md),
          CircaButton(
            label: 'Plan a different trip',
            variant: CircaButtonVariant.secondary,
            size: CircaButtonSize.sm,
            expand: true,
            onPressed: onReplan,
          ),
        ],
        SizedBox(height: t.space.section),
        const SectionLabel('Day by day'),
        for (final day in plan.days)
          Padding(
            padding: EdgeInsets.only(bottom: t.space.md),
            child: _DayCard(day: day, plan: plan),
          ),
        if (plan.truncated) ...[
          SizedBox(height: t.space.sm),
          Text(
            'The plan continues past the days shown. At an hour '
            '${plan.direction.isAdvance ? '' : 'and a half '}a day, a shift '
            'this size takes ${plan.requiredDays} days in total — keep going '
            'with the last day’s pattern until you are sleeping on local '
            'time.',
            style: t.type.bodyS.copyWith(color: t.color.textTertiary),
          ),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.plan});
  final JetLagPlan plan;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final east = plan.direction.isAdvance;
    final none = plan.direction == ShiftDirection.none;

    return GlassCard(
      accentColor: colors.solar,
      padding: EdgeInsets.fromLTRB(
        t.space.lg,
        t.space.base,
        t.space.base,
        t.space.base,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_shortName(plan.trip.origin)} → '
                  '${_shortName(plan.trip.destination)}',
                  style: t.type.titleM.copyWith(color: colors.textPrimary),
                ),
              ),
              Icon(
                east ? Icons.east_rounded : Icons.west_rounded,
                size: 18,
                color: colors.solarInk,
              ),
            ],
          ),
          SizedBox(height: t.space.xs),
          Text(
            none
                ? 'No time zones to cross'
                : '${_hours(plan.requiredShiftHours.abs())} '
                    '${east ? 'east' : 'west'}',
            style: t.type.bodyM.copyWith(color: colors.solarInk),
          ),

          if (!none) ...[
            SizedBox(height: t.space.base),
            Divider(color: colors.borderSubtle, height: 1),
            SizedBox(height: t.space.base),

            _Stat(
              label: 'Full adaptation',
              value: 'at least ${plan.requiredDays} days',
              note: east
                  ? 'Moving your clock earlier tops out near an hour a day. '
                      'That ceiling is physiology, not effort.'
                  : 'Moving your clock later runs at about an hour and a half '
                      'a day — westward really is the easy direction.',
            ),
            _Stat(
              label: 'Adapted on landing',
              value: '${plan.adaptedPercentOnArrival}%',
              note: plan.preFlightDays > 0
                  ? 'From ${plan.preFlightDays} '
                      '${plan.preFlightDays == 1 ? 'day' : 'days'} of shifting '
                      'before you fly. The rest happens at the destination.'
                  : 'All of the work happens after you land.',
            ),

            SizedBox(height: t.space.sm),
            Text(
              'Circa does not pretend jet lag is solvable in one night. What '
              'this plan does is move your clock the right way at the fastest '
              'rate it will actually go, instead of leaving it to drift.',
              style: t.type.bodyS.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: t.type.bodyM.copyWith(color: t.color.textPrimary),
                ),
              ),
              Text(
                value,
                style: t.type.titleS.copyWith(color: t.color.solarInk),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            note,
            style: t.type.bodyS.copyWith(color: t.color.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.plan});

  final JetLagDay day;
  final JetLagPlan plan;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stageLabel(day),
                      style: t.type.titleS.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // The city is named on every card, because the whole
                      // point is that these times are on a moving clock.
                      '${_dateLabel(day.localDate)} · '
                      '${_shortName(day.location)}',
                      style:
                          t.type.caption.copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              if (day.isTravelDay)
                CircaChip(
                  label: 'Flight',
                  icon: Icons.flight_takeoff_rounded,
                  selected: true,
                )
              else if (day.isAdapted && plan.direction != ShiftDirection.none)
                const CircaChip(label: 'Holding')
              else if (plan.direction != ShiftDirection.none)
                CircaChip(
                  label: _signed(day.dailyShiftHours),
                ),
            ],
          ),

          if (plan.direction != ShiftDirection.none) ...[
            SizedBox(height: t.space.md),
            _Progress(day: day, plan: plan),
          ],

          SizedBox(height: t.space.md),
          for (final event in day.events)
            _EventRow(event: event, utcOffset: day.utcOffset),
        ],
      ),
    );
  }
}

/// How far through the shift this day gets you.
class _Progress extends StatelessWidget {
  const _Progress({required this.day, required this.plan});

  final JetLagDay day;
  final JetLagPlan plan;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final total = plan.requiredShiftHours.abs();
    final done = day.targetShiftHours.abs();
    final fraction = total == 0 ? 1.0 : (done / total).clamp(0.0, 1.0);

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              backgroundColor: colors.surface3,
              valueColor: AlwaysStoppedAnimation(colors.solar),
            ),
          ),
        ),
        SizedBox(width: t.space.md),
        Text(
          '${_hours(done)} of ${_hours(total)}',
          style: t.type.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.utcOffset});

  final ProtocolEvent event;
  final Duration utcOffset;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final accent = switch (event.kind) {
      ProtocolEventKind.seekLight => colors.solar,
      ProtocolEventKind.avoidLight => colors.dawn,
      ProtocolEventKind.sleep => colors.twilight,
      _ => colors.textTertiary,
    };
    final icon = switch (event.kind) {
      ProtocolEventKind.seekLight => Icons.wb_sunny_rounded,
      ProtocolEventKind.avoidLight => Icons.nightlight_round,
      ProtocolEventKind.sleep => Icons.bedtime_rounded,
      _ => Icons.circle_outlined,
    };

    final start = event.startUtc.add(utcOffset);
    final end = event.endUtc.add(utcOffset);

    return InkWell(
      onTap: () => _explain(context),
      borderRadius: t.radius.inputRadius,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 15, color: accent),
            ),
            SizedBox(width: t.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: t.type.bodyM.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${_hhmm(start)}–${_hhmm(end)} · ${event.detail}',
                    style:
                        t.type.bodyS.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  void _explain(BuildContext context) {
    final t = context.circa;
    showCircaSheet<void>(
      context,
      SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            t.space.lg,
            0,
            t.space.lg,
            t.space.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: t.type.titleM.copyWith(color: t.color.textPrimary),
              ),
              SizedBox(height: t.space.md),
              Text(
                event.why,
                style: t.type.bodyM.copyWith(color: t.color.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Labels
// -----------------------------------------------------------------------------

String _stageLabel(JetLagDay day) {
  if (day.isTravelDay) return 'Flight day';
  if (day.isPreFlight) {
    final n = -day.index;
    return n == 1 ? 'The day before you fly' : '$n days before you fly';
  }
  return 'Day ${day.index} after landing';
}

String _shortName(GeoLocation location) {
  final label = location.label;
  if (label == null || label.isEmpty) return location.tzId.split('/').last;
  return label.split(',').first;
}

String _signed(double hours) {
  if (hours.abs() < 1e-9) return '0h';
  final sign = hours > 0 ? '−' : '+';
  // Advancing moves the clock *earlier*, so it reads as a minus on a clock
  // face even though the shift itself is positive.
  return '$sign${_hours(hours.abs())}';
}

String _hours(double h) {
  final whole = h.floor();
  final minutes = ((h - whole) * 60).round();
  if (minutes == 0) return '${whole}h';
  if (whole == 0) return '${minutes}m';
  return '${whole}h ${minutes}m';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dateLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';
