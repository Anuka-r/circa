import '../chrono/solar_engine.dart';
import 'geo_location.dart';

/// Everything the sun does at one place on one day, precomputed once.
///
/// Building this is cheap (a few hundred floating-point operations) and it is
/// cached per (location, date), so the sky can be sampled every minute without
/// recomputing the ephemeris.
class SolarDay {
  const SolarDay({
    required this.date,
    required this.location,
    required this.utcOffset,
    required this.solarNoonUtc,
    required this.sunriseUtc,
    required this.sunsetUtc,
    required this.civilDawnUtc,
    required this.civilDuskUtc,
    required this.nauticalDawnUtc,
    required this.nauticalDuskUtc,
    required this.astronomicalDawnUtc,
    required this.astronomicalDuskUtc,
    required this.goldenMorningEndUtc,
    required this.goldenEveningStartUtc,
  });

  /// Local calendar date this describes.
  final DateTime date;
  final GeoLocation location;

  /// UTC offset in effect locally on this date.
  final Duration utcOffset;

  final DateTime solarNoonUtc;

  /// Null during polar day or polar night — a first-class state, not an error.
  final DateTime? sunriseUtc;
  final DateTime? sunsetUtc;
  final DateTime? civilDawnUtc;
  final DateTime? civilDuskUtc;
  final DateTime? nauticalDawnUtc;
  final DateTime? nauticalDuskUtc;
  final DateTime? astronomicalDawnUtc;
  final DateTime? astronomicalDuskUtc;
  final DateTime? goldenMorningEndUtc;
  final DateTime? goldenEveningStartUtc;

  /// The sun never sets today.
  bool get isPolarDay => sunriseUtc == null && _noonAltitude > 0;

  /// The sun never rises today.
  bool get isPolarNight => sunriseUtc == null && _noonAltitude <= 0;

  bool get hasNormalDayNight => sunriseUtc != null && sunsetUtc != null;

  double get _noonAltitude =>
      SolarEngine.altitudeDeg(solarNoonUtc, location);

  Duration? get dayLength => hasNormalDayNight
      ? sunsetUtc!.difference(sunriseUtc!)
      : (isPolarDay ? const Duration(hours: 24) : Duration.zero);

  /// Solar altitude in degrees at an arbitrary instant.
  double altitudeAt(DateTime utc) => SolarEngine.altitudeDeg(utc, location);

  /// How far through the sun's arc we are, 0 at sunrise → 1 at sunset.
  /// Outside daylight this is clamped, so the marker parks at the horizon.
  double arcProgressAt(DateTime utc) {
    if (!hasNormalDayNight) {
      // During polar day the sun still circles; use hour-of-day instead.
      final local = utc.add(utcOffset);
      final minutes = local.hour * 60 + local.minute;
      return (minutes / 1440.0).clamp(0.0, 1.0);
    }
    final total = sunsetUtc!.difference(sunriseUtc!).inSeconds;
    if (total <= 0) return 0;
    final elapsed = utc.difference(sunriseUtc!).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  bool isDaylight(DateTime utc) {
    if (isPolarDay) return true;
    if (isPolarNight) return false;
    return !utc.isBefore(sunriseUtc!) && utc.isBefore(sunsetUtc!);
  }

  /// Builds a full solar day for [location] on the local calendar date [date].
  static SolarDay compute({
    required DateTime date,
    required GeoLocation location,
    required Duration utcOffset,
  }) {
    DateTime? event(double zenith, {required bool rising}) =>
        SolarEngine.eventUtc(
          dateUtcMidnight: DateTime.utc(date.year, date.month, date.day),
          at: location,
          zenithDeg: zenith,
          rising: rising,
        );

    final noonMinutes = SolarEngine.solarNoonUtcMinutes(
      DateTime.utc(date.year, date.month, date.day),
      location.longitude,
    );

    return SolarDay(
      date: DateTime(date.year, date.month, date.day),
      location: location,
      utcOffset: utcOffset,
      solarNoonUtc: DateTime.utc(date.year, date.month, date.day)
          .add(Duration(milliseconds: (noonMinutes * 60000).round())),
      sunriseUtc: event(SolarEngine.zenithSunrise, rising: true),
      sunsetUtc: event(SolarEngine.zenithSunrise, rising: false),
      civilDawnUtc: event(SolarEngine.zenithCivil, rising: true),
      civilDuskUtc: event(SolarEngine.zenithCivil, rising: false),
      nauticalDawnUtc: event(SolarEngine.zenithNautical, rising: true),
      nauticalDuskUtc: event(SolarEngine.zenithNautical, rising: false),
      astronomicalDawnUtc: event(SolarEngine.zenithAstronomical, rising: true),
      astronomicalDuskUtc: event(SolarEngine.zenithAstronomical, rising: false),
      goldenMorningEndUtc: event(SolarEngine.zenithGolden, rising: true),
      goldenEveningStartUtc: event(SolarEngine.zenithGolden, rising: false),
    );
  }
}
