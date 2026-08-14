/// Chronotype, classified from mid-sleep on free days corrected for sleep debt
/// (MSFsc) — the Munich Chronotype Questionnaire construct.
enum Chronotype {
  extremeEarly('Extreme early', 'Extreme lark'),
  moderateEarly('Moderate early', 'Lark'),
  slightEarly('Slight early', 'Slight lark'),
  intermediate('Intermediate', 'Neither'),
  slightLate('Slight late', 'Slight owl'),
  moderateLate('Moderate late', 'Owl'),
  extremeLate('Extreme late', 'Extreme owl');

  const Chronotype(this.label, this.plainLabel);

  /// Clinical-ish label used in detail views.
  final String label;

  /// Friendlier label used in headline copy.
  final String plainLabel;

  /// MSFsc boundaries, in minutes past local midnight.
  /// Boundaries follow Roenneberg's published MCTQ cut-points.
  static Chronotype fromMsfSc(double msfScMinutes) {
    final m = _wrapToDay(msfScMinutes);
    if (m < 137) return Chronotype.extremeEarly; // < 02:17
    if (m < 197) return Chronotype.moderateEarly; // < 03:17
    if (m < 257) return Chronotype.slightEarly; // < 04:17
    if (m < 317) return Chronotype.intermediate; // < 05:17
    if (m < 377) return Chronotype.slightLate; // < 06:17
    if (m < 437) return Chronotype.moderateLate; // < 07:17
    return Chronotype.extremeLate;
  }

  /// MSFsc values live in the small hours, so a value of 1500 (25:00) is really
  /// 60 (01:00). Wrapping keeps classification stable across midnight.
  static double _wrapToDay(double minutes) {
    var m = minutes % 1440.0;
    if (m < 0) m += 1440.0;
    // A mid-sleep after 18:00 is really a pre-midnight one; express it as a
    // negative offset from midnight so it classifies as extremely early rather
    // than wrapping round to extremely late.
    return m >= 1080 ? m - 1440.0 : m;
  }

  /// A one-line description used on the profile screen.
  String get description => switch (this) {
        Chronotype.extremeEarly =>
          'You wake naturally very early and fade early in the evening.',
        Chronotype.moderateEarly =>
          'You are at your best in the morning and wind down early.',
        Chronotype.slightEarly => 'You lean slightly towards mornings.',
        Chronotype.intermediate =>
          'You sit in the middle — neither a lark nor an owl.',
        Chronotype.slightLate => 'You lean slightly towards evenings.',
        Chronotype.moderateLate =>
          'You hit your stride later in the day and prefer a late bedtime.',
        Chronotype.extremeLate =>
          'You are strongly evening-oriented; early starts are genuinely hard.',
      };
}

/// How much the engine trusts its own phase estimate.
///
/// Surfaced next to every modelled number. Showing a confident wrong number is
/// the fastest way to lose a user who knows their own body.
enum PhaseConfidence {
  /// Questionnaire only — no logged nights yet.
  estimated('Estimated', 0),

  /// 1–4 nights.
  low('Low', 1),

  /// 5–13 nights.
  medium('Medium', 2),

  /// 14+ nights with a stable mid-sleep.
  high('High', 3);

  const PhaseConfidence(this.label, this.filledSegments);

  final String label;

  /// Segments lit in the 4-segment micro-meter of `ConfidenceBadge`.
  final int filledSegments;

  static PhaseConfidence fromNights(int nights, {double? midpointSdMinutes}) {
    if (nights <= 0) return PhaseConfidence.estimated;
    if (nights < 5) return PhaseConfidence.low;
    if (nights < 14) return PhaseConfidence.medium;
    if (midpointSdMinutes != null && midpointSdMinutes >= 60) {
      return PhaseConfidence.medium;
    }
    return PhaseConfidence.high;
  }

  String get explanation => switch (this) {
        PhaseConfidence.estimated =>
          'Based on your answers during setup. Log a few nights to improve it.',
        PhaseConfidence.low =>
          'Based on a handful of nights. It will sharpen as you log more.',
        PhaseConfidence.medium =>
          'Based on a week or two of your data.',
        PhaseConfidence.high =>
          'Based on two weeks or more of consistent data.',
      };
}
