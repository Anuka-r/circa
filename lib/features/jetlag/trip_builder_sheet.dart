import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/circa_theme.dart';
import '../../domain/chrono/jet_lag_planner.dart';
import '../../domain/chrono/protocol_engine.dart';
import '../../services/city_lookup.dart';
import '../../services/timezone_service.dart';
import '../../widgets/circa_widgets.dart';

/// Collects the four facts a jet-lag plan needs, and returns the [Trip].
Future<Trip?> showTripBuilder(BuildContext context) =>
    showCircaSheet<Trip>(context, const TripBuilderSheet());

/// The trip builder.
///
/// One scrolling form rather than the four-step `PageView` in
/// docs/07-screen-specs.md §S-28. The part of that spec that carries the design
/// is not the stepper — it is the timezone labelling, which is kept in full:
/// every picker is headed with its city and the UTC offset in force *on that
/// date*, and every instant is echoed back in the other city's time. Without
/// that, "which timezone did I just type?" produces a plan that is confidently
/// wrong in a way the user cannot see.
class TripBuilderSheet extends ConsumerStatefulWidget {
  const TripBuilderSheet({super.key});

  @override
  ConsumerState<TripBuilderSheet> createState() => _TripBuilderSheetState();
}

class _TripBuilderSheetState extends ConsumerState<TripBuilderSheet> {
  City? _origin;
  City? _destination;

  /// Wall-clock times, each read on its own city's clock. They only become
  /// instants at the very last step.
  late DateTime _departureLocal;
  late DateTime _arrivalLocal;

  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;

    // Origin defaults to where Circa already thinks the user is, so the common
    // case is two taps and a date.
    final profile = ref.read(profileProvider).value;
    final lookup = ref.read(cityLookupProvider);
    final home = profile?.effectiveLocation;
    if (home != null) {
      _origin = lookup.nearest(home.latitude, home.longitude) ??
          lookup.byTimezone(home.tzId);
    }

    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day).add(
      const Duration(days: 7, hours: 10),
    );
    _departureLocal = base;
    _arrivalLocal = base.add(const Duration(hours: 8));
  }

  TimezoneService get _tz => ref.read(timezoneServiceProvider);

  DateTime? get _departureUtc => _origin == null
      ? null
      : _tz.toUtc(_departureLocal, _origin!.tzId);

  DateTime? get _arrivalUtc => _destination == null
      ? null
      : _tz.toUtc(_arrivalLocal, _destination!.tzId);

  Trip? get _trip {
    final origin = _origin;
    final destination = _destination;
    final dep = _departureUtc;
    final arr = _arrivalUtc;
    if (origin == null || destination == null || dep == null || arr == null) {
      return null;
    }
    return Trip(
      origin: origin.toGeoLocation(),
      destination: destination.toGeoLocation(),
      departureUtc: dep,
      arrivalUtc: arr,
    );
  }

  /// The one blocking problem, in the order a user would hit it.
  String? get _problem {
    if (_origin == null) return 'Choose where you are flying from.';
    if (_destination == null) return 'Choose where you are flying to.';
    if (_origin!.tzId == _destination!.tzId &&
        _origin!.name == _destination!.name) {
      return 'Origin and destination are the same place.';
    }
    final trip = _trip;
    if (trip == null) return null;
    if (!trip.arrivalUtc.isAfter(trip.departureUtc)) {
      return 'Arrival is before departure. Check which city each time is in — '
          'landing "earlier" than you left is normal westbound, but only on '
          'the clock, never in real time.';
    }
    if (trip.flightDuration < const Duration(minutes: 30)) {
      return 'That is a ${_duration(trip.flightDuration)} flight. Check the '
          'arrival time is in ${_destination!.name} local time.';
    }
    if (trip.flightDuration > const Duration(hours: 24)) {
      return 'That is a ${_duration(trip.flightDuration)} flight. Circa plans '
          'single flights — enter the leg that crosses the time zones.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final trip = _trip;
    final problem = _problem;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          t.space.lg,
          0,
          t.space.lg,
          t.space.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Plan a trip',
              style: t.type.titleM.copyWith(color: colors.textPrimary),
            ),
            SizedBox(height: t.space.xs),
            Text(
              'Circa shifts your clock toward the destination before you fly, '
              'so you land part-adapted instead of starting from zero.',
              style: t.type.bodyS.copyWith(color: colors.textSecondary),
            ),

            SizedBox(height: t.space.lg),
            const SectionLabel('Route'),
            _CityRow(
              label: 'From',
              city: _origin,
              hint: 'Where you are now',
              onTap: () async {
                final picked = await _pickCity(context, 'Flying from');
                if (picked != null) setState(() => _origin = picked);
              },
            ),
            SizedBox(height: t.space.sm),
            _CityRow(
              label: 'To',
              city: _destination,
              hint: 'Where you are going',
              onTap: () async {
                final picked = await _pickCity(context, 'Flying to');
                if (picked != null) setState(() => _destination = picked);
              },
            ),

            if (_origin != null && _destination != null) ...[
              SizedBox(height: t.space.section),
              const SectionLabel('Flight'),

              // Both pickers carry their city and that date's offset. This is
              // the whole point: a departure time is meaningless until you
              // know whose clock it is on.
              _TimeField(
                heading: 'Departure',
                city: _origin!,
                offsetLabel: _offsetLabel(_departureUtc, _origin!.tzId),
                value: _departureLocal,
                echo: _echoIn(_departureUtc, _destination!),
                onChanged: (v) => setState(() => _departureLocal = v),
              ),
              SizedBox(height: t.space.base),
              _TimeField(
                heading: 'Arrival',
                city: _destination!,
                offsetLabel: _offsetLabel(_arrivalUtc, _destination!.tzId),
                value: _arrivalLocal,
                echo: _echoIn(_arrivalUtc, _origin!),
                onChanged: (v) => setState(() => _arrivalLocal = v),
              ),
            ],

            if (trip != null && problem == null) ...[
              SizedBox(height: t.space.section),
              _ShiftPreview(trip: trip),
            ],

            if (problem != null) ...[
              SizedBox(height: t.space.base),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: colors.solarInk),
                  SizedBox(width: t.space.sm),
                  Expanded(
                    child: Text(
                      problem,
                      style:
                          t.type.bodyS.copyWith(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],

            SizedBox(height: t.space.lg),
            CircaButton(
              label: 'Build the plan',
              expand: true,
              size: CircaButtonSize.lg,
              onPressed: problem == null && trip != null
                  ? () => Navigator.of(context).pop(trip)
                  : null,
            ),
            SizedBox(height: t.space.sm),
            Text(
              'Not a medical device. Circa estimates your body clock from what '
              'you log; it does not measure it.',
              textAlign: TextAlign.center,
              style: t.type.caption.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Future<City?> _pickCity(BuildContext context, String title) =>
      showCircaSheet<City>(context, _CityPicker(title: title));

  /// `UTC+1`, `UTC+5:30`, `UTC−7` — resolved on the date in question, so a plan
  /// spanning a DST change is labelled with the offset that will actually be in
  /// force rather than today's.
  String _offsetLabel(DateTime? utc, String tzId) {
    final at = utc ?? DateTime.now().toUtc();
    final offset = _tz.offsetFor(at, tzId);
    final sign = offset.isNegative ? '−' : '+';
    final abs = offset.abs();
    final minutes = abs.inMinutes % 60;
    return minutes == 0
        ? 'UTC$sign${abs.inHours}'
        : 'UTC$sign${abs.inHours}:${minutes.toString().padLeft(2, '0')}';
  }

  /// The same instant, read on the other city's clock.
  String? _echoIn(DateTime? utc, City other) {
    if (utc == null) return null;
    final local = _tz.toLocal(utc, other.tzId);
    return '${_dateLabel(local)}, ${_hhmm(local)} in ${other.name}';
  }
}

// -----------------------------------------------------------------------------

class _CityRow extends StatelessWidget {
  const _CityRow({
    required this.label,
    required this.city,
    required this.hint,
    required this.onTap,
  });

  final String label;
  final City? city;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    return GlassCard(
      onTap: onTap,
      padding: EdgeInsets.symmetric(
        horizontal: t.space.base,
        vertical: t.space.md,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: t.type.label.copyWith(color: colors.textTertiary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  city?.label ?? hint,
                  style: t.type.bodyM.copyWith(
                    color:
                        city == null ? colors.textTertiary : colors.textPrimary,
                  ),
                ),
                if (city != null)
                  Text(
                    city!.tzId,
                    style: t.type.caption.copyWith(color: colors.textTertiary),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.heading,
    required this.city,
    required this.offsetLabel,
    required this.value,
    required this.echo,
    required this.onChanged,
  });

  final String heading;
  final City city;
  final String offsetLabel;
  final DateTime value;
  final String? echo;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Departure — London (UTC+1)". Never a bare "Departure".
        Text(
          '$heading — ${city.name} ($offsetLabel)',
          style: t.type.label.copyWith(color: colors.solarInk),
        ),
        SizedBox(height: t.space.sm),
        Row(
          children: [
            Expanded(
              child: _PickerButton(
                icon: Icons.calendar_today_rounded,
                label: _dateLabel(value),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: value,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 1),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    helpText: '$heading date — ${city.name}',
                  );
                  if (picked == null) return;
                  onChanged(DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    value.hour,
                    value.minute,
                  ));
                },
              ),
            ),
            SizedBox(width: t.space.sm),
            Expanded(
              child: _PickerButton(
                icon: Icons.schedule_rounded,
                label: _hhmm(value),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(value),
                    helpText: '$heading time — ${city.name}',
                  );
                  if (picked == null) return;
                  onChanged(DateTime(
                    value.year,
                    value.month,
                    value.day,
                    picked.hour,
                    picked.minute,
                  ));
                },
              ),
            ),
          ],
        ),
        if (echo != null) ...[
          SizedBox(height: t.space.xs + 2),
          Text(
            'That is $echo',
            style: t.type.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.inputRadius,
      child: Container(
        height: 48,
        padding: EdgeInsets.symmetric(horizontal: t.space.md),
        decoration: BoxDecoration(
          color: colors.surface2.withValues(alpha: 0.7),
          borderRadius: t.radius.inputRadius,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.textTertiary),
            SizedBox(width: t.space.sm),
            Expanded(
              child: Text(
                label,
                style: t.type.bodyM.copyWith(color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The live "you'll shift 8h east" readout.
class _ShiftPreview extends ConsumerWidget {
  const _ShiftPreview({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.circa;
    final colors = t.color;
    final tz = ref.read(timezoneServiceProvider);

    final delta = (tz.offsetFor(trip.arrivalUtc, trip.destination.tzId) -
                tz.offsetFor(trip.departureUtc, trip.origin.tzId))
            .inMinutes /
        60.0;
    final shift = JetLagPlanner.shortWayHours(delta);
    final days = ProtocolEngine.daysToShift(shift);
    final east = shift > 0;

    if (days == 0) {
      return GlassCard(
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 20, color: colors.aurora),
            SizedBox(width: t.space.md),
            Expanded(
              child: Text(
                'No time zones to cross. Your clock stays where it is.',
                style: t.type.bodyM.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

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
              Icon(
                east
                    ? Icons.arrow_forward_rounded
                    : Icons.arrow_back_rounded,
                size: 20,
                color: colors.solarInk,
              ),
              SizedBox(width: t.space.sm),
              Text(
                'You will shift ${_hours(shift.abs())} '
                '${east ? 'east' : 'west'}',
                style: t.type.titleS.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          SizedBox(height: t.space.sm),
          Text(
            east
                ? 'Eastward means moving your clock earlier, which your body '
                    'does at about an hour a day at best — so this takes at '
                    'least $days days.'
                : 'Westward means moving your clock later, which is the easier '
                    'direction at about an hour and a half a day — so this '
                    'takes at least $days days.',
            style: t.type.bodyS.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Offline city search over the bundled dataset, so a trip can be planned on
/// the plane — which is when people actually plan them.
class _CityPicker extends ConsumerStatefulWidget {
  const _CityPicker({required this.title});

  final String title;

  @override
  ConsumerState<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends ConsumerState<_CityPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final results = ref.read(cityLookupProvider).search(_query, limit: 40);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          t.space.lg,
          0,
          t.space.lg,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: t.type.titleM.copyWith(color: colors.textPrimary),
            ),
            SizedBox(height: t.space.base),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search cities',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: colors.surface2.withValues(alpha: 0.7),
                border: OutlineInputBorder(
                  borderRadius: t.radius.inputRadius,
                  borderSide: BorderSide(color: colors.borderSubtle),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            SizedBox(height: t.space.md),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.45,
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        'No city called "$_query" in the bundled list.\n'
                        'Try the nearest large city — Circa needs the time '
                        'zone, not the exact airport.',
                        textAlign: TextAlign.center,
                        style: t.type.bodyS
                            .copyWith(color: colors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final city = results[i];
                        return ListTile(
                          title: Text(
                            city.label,
                            style: t.type.bodyM
                                .copyWith(color: colors.textPrimary),
                          ),
                          subtitle: Text(
                            city.tzId,
                            style: t.type.caption
                                .copyWith(color: colors.textTertiary),
                          ),
                          onTap: () => Navigator.of(context).pop(city),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Formatting
// -----------------------------------------------------------------------------

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

String _hours(double h) {
  final whole = h.floor();
  final minutes = ((h - whole) * 60).round();
  return minutes == 0 ? '${whole}h' : '${whole}h ${minutes}m';
}

String _duration(Duration d) {
  final h = d.inMinutes ~/ 60;
  final m = d.inMinutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
