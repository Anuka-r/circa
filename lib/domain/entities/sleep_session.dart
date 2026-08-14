/// Where a sleep record came from. Ordering matters: on a conflict for the same
/// night, a higher-precedence source wins regardless of which was written last.
enum SleepSource {
  /// Typed in by the user.
  manual('Your entry', 1),

  /// Read from Apple Health / Health Connect.
  health('Health', 2),

  /// Inferred from the habitual schedule because nothing was logged. Never
  /// counted towards debt — only used to keep the forecast continuous.
  estimated('Estimated', 0);

  const SleepSource(this.label, this.precedence);
  final String label;
  final int precedence;
}

/// One night (or nap) of sleep.
///
/// Stored in UTC with the IANA zone that applied at the time, because a session
/// logged in Lisbon and reviewed in Tokyo must still render at the wall-clock
/// time it actually happened.
class SleepSession {
  const SleepSession({
    required this.id,
    required this.startUtc,
    required this.endUtc,
    required this.tzId,
    required this.nightOf,
    required this.source,
    this.quality,
    this.latencyMin,
    this.awakenings,
    this.note,
    this.parentId,
    this.deletedAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime startUtc;
  final DateTime endUtc;
  final String tzId;

  /// `yyyy-MM-dd` of the night this belongs to, anchored noon-to-noon so a
  /// session crossing midnight is never split across two calendar days.
  final String nightOf;

  final SleepSource source;

  /// Subjective 1–5, if the user gave one.
  final int? quality;

  /// Minutes taken to fall asleep.
  final int? latencyMin;

  final int? awakenings;
  final String? note;

  /// Set on secondary segments of a biphasic night; the primary session's id.
  final String? parentId;

  final DateTime? deletedAt;
  final DateTime updatedAt;

  Duration get duration => endUtc.difference(startUtc);
  double get durationHours => duration.inMinutes / 60.0;

  /// Mid-sleep as a UTC instant — the anchor for chronotype and phase.
  DateTime get midpointUtc =>
      startUtc.add(Duration(milliseconds: duration.inMilliseconds ~/ 2));

  /// A nap is short and starts in the daytime. Naps repay debt at half rate and
  /// are excluded from chronotype maths.
  bool isNap(Duration utcOffset) {
    if (duration.inMinutes >= 180) return false;
    final localHour = startUtc.add(utcOffset).hour;
    return localHour >= 10 && localHour < 18;
  }

  bool get isDeleted => deletedAt != null;

  SleepSession copyWith({
    String? id,
    DateTime? startUtc,
    DateTime? endUtc,
    String? tzId,
    String? nightOf,
    SleepSource? source,
    int? quality,
    int? latencyMin,
    int? awakenings,
    String? note,
    String? parentId,
    DateTime? deletedAt,
    DateTime? updatedAt,
  }) =>
      SleepSession(
        id: id ?? this.id,
        startUtc: startUtc ?? this.startUtc,
        endUtc: endUtc ?? this.endUtc,
        tzId: tzId ?? this.tzId,
        nightOf: nightOf ?? this.nightOf,
        source: source ?? this.source,
        quality: quality ?? this.quality,
        latencyMin: latencyMin ?? this.latencyMin,
        awakenings: awakenings ?? this.awakenings,
        note: note ?? this.note,
        parentId: parentId ?? this.parentId,
        deletedAt: deletedAt ?? this.deletedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SleepSession && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
