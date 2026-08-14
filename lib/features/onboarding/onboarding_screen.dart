import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/circa_theme.dart';
import '../../core/theme/sky_palette.dart';
import '../../data/repositories/circa_repository.dart';
import '../../domain/chrono/chronotype_estimator.dart';
import '../../services/city_lookup.dart';
import '../../widgets/circa_widgets.dart';

/// Onboarding: from launch to a populated Today screen in under 90 seconds.
///
/// The sky gradient is continuous across every step and progresses from deep
/// night to sunrise as the user advances, so the flow feels like one room
/// rather than nine screens.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  // Collected answers, pre-seeded with sensible defaults so no step can block.
  double _workBed = 23 * 60;
  double _workWake = 7 * 60;
  double _freeBed = 24 * 60;
  double _freeWake = 8.5 * 60;
  int _wakeDifficulty = 2;
  int _cupsPerDay = 2;
  double _lastCup = 14 * 60;
  String? _goal;
  City? _city;
  bool _disclaimerAccepted = false;

  static const _steps = 8;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_index >= _steps - 1) return;
    _controller.nextPage(
      duration: context.circa.motion.slow,
      curve: CircaMotion.emphasized,
    );
  }

  void _back() {
    if (_index == 0) return;
    _controller.previousPage(
      duration: context.circa.motion.slow,
      curve: CircaMotion.emphasized,
    );
  }

  /// Sky altitude for the current step: deep night at the start, sunrise by the
  /// end. Purely cosmetic, but it is what makes the flow feel like one place.
  double get _skyAltitude => -20 + (_index / (_steps - 1)) * 26;

  Future<void> _finish() async {
    final repo = ref.read(repositoryProvider);
    final schedule = HabitualSchedule(
      workBedMinutes: _workBed,
      workWakeMinutes: _workWake,
      freeBedMinutes: _freeBed,
      freeWakeMinutes: _freeWake,
    );
    final estimate = ChronotypeEstimator.fromQuestionnaire(schedule);

    final profile = UserProfile.defaults().copyWith(
      schedule: schedule,
      chronotype: estimate.chronotype,
      msfScMinutes: estimate.msfScMinutes,
      wakeDifficulty: _wakeDifficulty,
      goal: _goal,
      typicalCaffeineMg: (_cupsPerDay * 95).toDouble().clamp(0, 800),
      location: _city?.toGeoLocation(),
      onboarded: true,
      disclaimerAcknowledged: true,
    );

    await repo.saveProfile(profile);
    if (!mounted) return;
    ref.invalidate(todayProvider);
    context.go('/today');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final stops =
        SkyPalette.forAltitude(_skyAltitude, lightTheme: !colors.isDark);

    return Scaffold(
      body: AnimatedContainer(
        duration: t.motion.slow,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: stops.colors,
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _ProgressBar(index: _index, total: _steps, onBack: _back),
              Expanded(
                child: PageView(
                  controller: _controller,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    _WelcomeStep(onNext: _next),
                    _ScheduleStep(
                      title: 'When do you usually sleep on a work day?',
                      subtitle:
                          'Your best guess is fine — Circa refines this as you '
                          'log nights.',
                      bed: _workBed,
                      wake: _workWake,
                      onChanged: (b, w) => setState(() {
                        _workBed = b;
                        _workWake = w;
                      }),
                      onNext: _next,
                    ),
                    _ScheduleStep(
                      title: 'And on a free day?',
                      subtitle:
                          'The gap between these two is what tells us your '
                          'natural body clock.',
                      bed: _freeBed,
                      wake: _freeWake,
                      onChanged: (b, w) => setState(() {
                        _freeBed = b;
                        _freeWake = w;
                      }),
                      onNext: _next,
                    ),
                    _ChoiceStep(
                      title: 'How hard is it to get up?',
                      options: const [
                        'Easy — I wake before my alarm',
                        'Fine with an alarm',
                        'Sometimes hard',
                        'Very hard, most days',
                      ],
                      selected: _wakeDifficulty,
                      onSelected: (i) => setState(() => _wakeDifficulty = i),
                      onNext: _next,
                    ),
                    _CaffeineStep(
                      cups: _cupsPerDay,
                      lastCup: _lastCup,
                      onChanged: (c, l) => setState(() {
                        _cupsPerDay = c;
                        _lastCup = l;
                      }),
                      onNext: _next,
                    ),
                    _GoalStep(
                      selected: _goal,
                      onSelected: (g) => setState(() => _goal = g),
                      onNext: _next,
                    ),
                    _LocationStep(
                      city: _city,
                      onSelected: (c) => setState(() => _city = c),
                      onNext: _next,
                    ),
                    _DisclaimerStep(
                      accepted: _disclaimerAccepted,
                      onChanged: (v) =>
                          setState(() => _disclaimerAccepted = v),
                      onFinish: _finish,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.index,
    required this.total,
    required this.onBack,
  });

  final int index;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        t.space.base,
        t.space.md,
        t.space.lg,
        t.space.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: index == 0
                ? null
                : IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: t.color.textSecondary,
                    tooltip: 'Back',
                  ),
          ),
          Expanded(
            child: Semantics(
              label: 'Step ${index + 1} of $total',
              child: Row(
                children: [
                  for (var i = 0; i < total; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: t.motion.base,
                        height: 3,
                        margin: EdgeInsets.symmetric(horizontal: t.space.xxs),
                        decoration: BoxDecoration(
                          color: i <= index
                              ? t.color.solar
                              : t.color.textPrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// Shared scaffolding for a step: title, subtitle, body, primary action.
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.child,
    required this.actionLabel,
    required this.onAction,
    this.subtitle,
    this.actionEnabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final String actionLabel;
  final VoidCallback onAction;
  final bool actionEnabled;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final gutter = t.space.gutter(MediaQuery.sizeOf(context).width);

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, t.space.lg, gutter, t.space.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: t.space.maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: t.type.displayM.copyWith(color: t.color.textPrimary),
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: t.space.md),
                Text(
                  subtitle!,
                  style: t.type.bodyM.copyWith(color: t.color.textSecondary),
                ),
              ],
              SizedBox(height: t.space.xl),
              Expanded(child: SingleChildScrollView(child: child)),
              SizedBox(height: t.space.base),
              CircaButton(
                label: actionLabel,
                size: CircaButtonSize.lg,
                expand: true,
                onPressed: actionEnabled ? onAction : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return _StepScaffold(
      title: 'Circa',
      subtitle: 'Your body clock, dialled in.',
      actionLabel: 'Get started',
      onAction: onNext,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: t.space.lg),
          Text(
            'Circa reads the sun where you are and the way you sleep, then '
            'tells you three things each day:',
            style: t.type.bodyL.copyWith(color: t.color.textSecondary),
          ),
          SizedBox(height: t.space.xl),
          _Bullet(
            icon: Icons.wb_sunny_rounded,
            color: t.color.solar,
            title: 'When to get light',
            body: 'The strongest signal you can send your body clock.',
          ),
          _Bullet(
            icon: Icons.local_cafe_rounded,
            color: t.color.dawn,
            title: 'When to stop caffeine',
            body: 'Usually earlier than people expect.',
          ),
          _Bullet(
            icon: Icons.bedtime_rounded,
            color: t.color.twilight,
            title: 'When to wind down',
            body: 'So tonight actually works.',
          ),
          SizedBox(height: t.space.lg),
          Text(
            'No wearable. No account needed. Works without a connection.',
            style: t.type.bodyS.copyWith(color: t.color.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          SizedBox(width: t.space.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.type.titleS.copyWith(color: t.color.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  body,
                  style: t.type.bodyS.copyWith(color: t.color.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleStep extends StatelessWidget {
  const _ScheduleStep({
    required this.title,
    required this.subtitle,
    required this.bed,
    required this.wake,
    required this.onChanged,
    required this.onNext,
  });

  final String title;
  final String subtitle;
  final double bed;
  final double wake;
  final void Function(double bed, double wake) onChanged;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final duration = _span(bed, wake);

    return _StepScaffold(
      title: title,
      subtitle: subtitle,
      actionLabel: 'Continue',
      onAction: onNext,
      child: Column(
        children: [
          _TimeField(
            label: 'Bedtime',
            minutes: bed,
            icon: Icons.bedtime_rounded,
            onChanged: (v) => onChanged(v, wake),
          ),
          SizedBox(height: t.space.md),
          _TimeField(
            label: 'Wake up',
            minutes: wake,
            icon: Icons.wb_twilight_rounded,
            onChanged: (v) => onChanged(bed, v),
          ),
          SizedBox(height: t.space.lg),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: t.space.base,
              vertical: t.space.md,
            ),
            decoration: BoxDecoration(
              color: t.color.solar.withValues(alpha: 0.12),
              borderRadius: t.radius.pillRadius,
            ),
            child: Text(
              '${_fmtDuration(duration)} in bed',
              textAlign: TextAlign.center,
              style: t.type.titleS.copyWith(color: t.color.solarInk),
            ),
          ),
        ],
      ),
    );
  }

  static double _span(double from, double to) {
    var d = to - from;
    if (d <= 0) d += 1440;
    return d;
  }

  static String _fmtDuration(double minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

/// Time input with a big legible value and ±15-minute steppers.
///
/// The steppers are the primary path deliberately: they are reachable by
/// switch control and voice control, which a drag-only dial would not be.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.minutes,
    required this.icon,
    required this.onChanged,
  });

  final String label;
  final double minutes;
  final IconData icon;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final normalised = minutes % 1440;
    final h = (normalised ~/ 60).toInt();
    final m = (normalised % 60).round();

    return GlassCard(
      padding: EdgeInsets.symmetric(
        horizontal: t.space.base,
        vertical: t.space.md,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: t.color.textTertiary),
          SizedBox(width: t.space.md),
          Expanded(
            child: Text(
              label,
              style: t.type.bodyM.copyWith(color: t.color.textSecondary),
            ),
          ),
          _StepButton(
            icon: Icons.remove_rounded,
            semanticLabel: 'Earlier',
            onTap: () => onChanged(minutes - 15),
          ),
          SizedBox(
            width: 84,
            child: Semantics(
              label: label,
              value: '${h.toString().padLeft(2, '0')}:'
                  '${m.toString().padLeft(2, '0')}',
              child: Text(
                '${h.toString().padLeft(2, '0')}:'
                '${m.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: t.type.titleM.copyWith(color: t.color.textPrimary),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            semanticLabel: 'Later',
            onTap: () => onChanged(minutes + 15),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, size: 18, color: t.color.textSecondary),
        ),
      ),
    );
  }
}

class _ChoiceStep extends StatelessWidget {
  const _ChoiceStep({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.onNext,
  });

  final String title;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return _StepScaffold(
      title: title,
      actionLabel: 'Continue',
      onAction: onNext,
      child: Column(
        children: [
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.sm),
              child: _SelectableRow(
                label: options[i],
                selected: selected == i,
                onTap: () => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.description,
  });

  final String label;
  final String? description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: t.motion.quick,
          constraints: const BoxConstraints(minHeight: 56),
          padding: EdgeInsets.symmetric(
            horizontal: t.space.base,
            vertical: t.space.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.solar.withValues(alpha: 0.14)
                : colors.surface1.withValues(alpha: 0.6),
            borderRadius: t.radius.inputRadius,
            border: Border.all(
              color: selected ? colors.solar : colors.borderSubtle,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: t.type.bodyL.copyWith(
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: t.type.bodyS
                            .copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: t.motion.quick,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: colors.solar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaffeineStep extends StatelessWidget {
  const _CaffeineStep({
    required this.cups,
    required this.lastCup,
    required this.onChanged,
    required this.onNext,
  });

  final int cups;
  final double lastCup;
  final void Function(int cups, double lastCup) onChanged;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return _StepScaffold(
      title: 'How much caffeine on a typical day?',
      subtitle:
          'Circa works out when your last one should be, based on how long it '
          'actually stays in your system.',
      actionLabel: 'Continue',
      onAction: onNext,
      child: Column(
        children: [
          GlassCard(
            padding: EdgeInsets.symmetric(
              horizontal: t.space.base,
              vertical: t.space.md,
            ),
            child: Row(
              children: [
                Icon(Icons.local_cafe_rounded,
                    size: 18, color: t.color.textTertiary),
                SizedBox(width: t.space.md),
                Expanded(
                  child: Text(
                    'Drinks per day',
                    style:
                        t.type.bodyM.copyWith(color: t.color.textSecondary),
                  ),
                ),
                _StepButton(
                  icon: Icons.remove_rounded,
                  semanticLabel: 'Fewer',
                  onTap: () =>
                      onChanged(math.max(0, cups - 1), lastCup),
                ),
                SizedBox(
                  width: 40,
                  child: Semantics(
                    label: 'Drinks per day',
                    value: '$cups',
                    child: Text(
                      '$cups',
                      textAlign: TextAlign.center,
                      style: t.type.titleM
                          .copyWith(color: t.color.textPrimary),
                    ),
                  ),
                ),
                _StepButton(
                  icon: Icons.add_rounded,
                  semanticLabel: 'More',
                  onTap: () =>
                      onChanged(math.min(12, cups + 1), lastCup),
                ),
              ],
            ),
          ),
          SizedBox(height: t.space.md),
          _TimeField(
            label: 'Usual last one',
            minutes: lastCup,
            icon: Icons.schedule_rounded,
            onChanged: (v) => onChanged(cups, v),
          ),
          SizedBox(height: t.space.lg),
          Text(
            cups == 0
                ? 'No caffeine — one less thing to time.'
                : 'About ${cups * 95} mg a day. Caffeine has a half-life of '
                    'roughly 5.7 hours, so a 2pm coffee is still a third '
                    'present at 10pm.',
            style: t.type.bodyS.copyWith(color: t.color.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _GoalStep extends StatelessWidget {
  const _GoalStep({
    required this.selected,
    required this.onSelected,
    required this.onNext,
  });

  final String? selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onNext;

  static const _goals = [
    ('More energy', 'Stop the afternoon crash'),
    ('Sleep earlier', 'Shift my clock earlier, gradually'),
    ('Beat jet lag', 'Adapt before I land'),
    ('Survive shift work', 'A schedule I do not control'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return _StepScaffold(
      title: 'What are you here for?',
      actionLabel: 'Continue',
      onAction: onNext,
      actionEnabled: selected != null,
      child: Column(
        children: [
          for (final (label, description) in _goals)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.sm),
              child: _SelectableRow(
                label: label,
                description: description,
                selected: selected == label,
                onTap: () => onSelected(label),
              ),
            ),
        ],
      ),
    );
  }
}

class _LocationStep extends ConsumerStatefulWidget {
  const _LocationStep({
    required this.city,
    required this.onSelected,
    required this.onNext,
  });

  final City? city;
  final ValueChanged<City> onSelected;
  final VoidCallback onNext;

  @override
  ConsumerState<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends ConsumerState<_LocationStep> {
  final _query = TextEditingController();
  List<City> _results = const [];

  @override
  void initState() {
    super.initState();
    // Seed with the device's own zone so the common case is one tap.
    final tzId = ref.read(timezoneServiceProvider).deviceTzId;
    final guess = CityLookup.instance.byTimezone(tzId);
    if (guess != null && widget.city == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onSelected(guess);
      });
    }
    _results = CityLookup.instance.search('', limit: 6);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return _StepScaffold(
      title: 'Where are you?',
      subtitle:
          'Circa computes the real position of the sun where you are. That is '
          'all it needs — and it works offline from then on.',
      actionLabel: 'Continue',
      onAction: widget.onNext,
      actionEnabled: widget.city != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.city != null) ...[
            GlassCard(
              accentColor: t.color.solar,
              child: Row(
                children: [
                  Icon(Icons.place_rounded, size: 18, color: t.color.solar),
                  SizedBox(width: t.space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.city!.label,
                          style: t.type.titleS
                              .copyWith(color: t.color.textPrimary),
                        ),
                        Text(
                          widget.city!.tzId,
                          style: t.type.bodyS
                              .copyWith(color: t.color.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: t.space.base),
          ],
          TextField(
            controller: _query,
            onChanged: (v) => setState(
              () => _results = CityLookup.instance.search(v, limit: 6),
            ),
            decoration: const InputDecoration(
              hintText: 'Search for a city',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          SizedBox(height: t.space.md),
          for (final city in _results)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.sm),
              child: _SelectableRow(
                label: city.name,
                description: city.country,
                selected: widget.city?.label == city.label,
                onTap: () => widget.onSelected(city),
              ),
            ),
        ],
      ),
    );
  }
}

class _DisclaimerStep extends StatelessWidget {
  const _DisclaimerStep({
    required this.accepted,
    required this.onChanged,
    required this.onFinish,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    return _StepScaffold(
      title: 'One thing before we start',
      actionLabel: 'Build my rhythm',
      onAction: onFinish,
      actionEnabled: accepted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Circa is a wellness tool, not a medical device.',
                  style: t.type.titleS.copyWith(color: t.color.textPrimary),
                ),
                SizedBox(height: t.space.md),
                Text(
                  'Everything Circa shows you is an estimate built from '
                  'published chronobiology and the information you give it. '
                  'It does not diagnose, treat, or prevent anything.\n\n'
                  'If you have persistent trouble sleeping, or you regularly '
                  'feel exhausted despite sleeping enough, please talk to a '
                  'doctor. Some sleep problems have medical causes that no '
                  'app can see.',
                  style:
                      t.type.bodyM.copyWith(color: t.color.textSecondary),
                ),
              ],
            ),
          ),
          SizedBox(height: t.space.lg),
          // A real checkbox, not scroll-detection: scroll-to-end is invisible
          // to screen-reader users and does not constitute consent.
          InkWell(
            onTap: () => onChanged(!accepted),
            borderRadius: t.radius.inputRadius,
            child: Padding(
              padding: EdgeInsets.all(t.space.sm),
              child: Row(
                children: [
                  Checkbox(
                    value: accepted,
                    onChanged: (v) => onChanged(v ?? false),
                    activeColor: t.color.solar,
                    checkColor: t.color.onSolar,
                  ),
                  SizedBox(width: t.space.sm),
                  Expanded(
                    child: Text(
                      'I understand.',
                      style: t.type.bodyM
                          .copyWith(color: t.color.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
