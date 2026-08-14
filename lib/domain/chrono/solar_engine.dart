import 'dart:math' as math;

import '../value_objects/geo_location.dart';

/// Implements the NOAA Solar Position Algorithm (after Meeus, *Astronomical
/// Algorithms*, ch. 25) in pure Dart.
///
/// This is the reason Circa works offline: sunrise, sunset, twilight and the
/// live sky gradient are all arithmetic over a date and a coordinate. Nothing
/// here touches the network, the device, or the clock — every entry point takes
/// its time as a parameter, which is what makes the whole thing testable.
///
/// Accuracy is within ~1 minute for |latitude| < 65°, degrading near the poles
/// where the sun crosses the horizon at a shallow angle.
abstract final class SolarEngine {
  const SolarEngine._();

  // ---------------------------------------------------------------------------
  // Zenith angles for the events we care about.
  // ---------------------------------------------------------------------------

  /// Geometric sunrise/sunset, including the standard 34' refraction allowance
  /// and the 16' solar semi-diameter.
  static const double zenithSunrise = 90.833;
  static const double zenithCivil = 96.0;
  static const double zenithNautical = 102.0;
  static const double zenithAstronomical = 108.0;

  /// Our own band: the sun is low and warm. Drives the sky gradient.
  static const double zenithGolden = 84.0;

  // ---------------------------------------------------------------------------
  // Julian date
  // ---------------------------------------------------------------------------

  /// Julian Day Number for a UTC instant, including the fractional day.
  static double julianDay(DateTime utc) {
    final u = utc.toUtc();
    var year = u.year;
    var month = u.month;
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();

    final dayStart = (365.25 * (year + 4716)).floor() +
        (30.6001 * (month + 1)).floor() +
        u.day +
        b -
        1524.5;

    final fraction = (u.hour * 3600 +
            u.minute * 60 +
            u.second +
            u.millisecond / 1000.0) /
        86400.0;

    return dayStart + fraction;
  }

  /// Julian centuries since J2000.0 — the time variable every series below uses.
  static double julianCentury(double julianDay) =>
      (julianDay - 2451545.0) / 36525.0;

  // ---------------------------------------------------------------------------
  // Solar position series
  // ---------------------------------------------------------------------------

  /// Geometric mean longitude of the sun, degrees.
  static double geomMeanLongSun(double t) =>
      _mod360(280.46646 + t * (36000.76983 + t * 0.0003032));

  /// Geometric mean anomaly of the sun, degrees.
  static double geomMeanAnomSun(double t) =>
      357.52911 + t * (35999.05029 - 0.0001537 * t);

  /// Eccentricity of Earth's orbit, unitless.
  static double eccentricityEarthOrbit(double t) =>
      0.016708634 - t * (0.000042037 + 0.0000001267 * t);

  /// Equation of centre, degrees.
  static double sunEqOfCentre(double t) {
    final m = _rad(geomMeanAnomSun(t));
    return math.sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        math.sin(2 * m) * (0.019993 - 0.000101 * t) +
        math.sin(3 * m) * 0.000289;
  }

  /// True longitude of the sun, degrees.
  static double sunTrueLong(double t) => geomMeanLongSun(t) + sunEqOfCentre(t);

  /// Apparent longitude of the sun, degrees (corrected for nutation/aberration).
  static double sunApparentLong(double t) =>
      sunTrueLong(t) -
      0.00569 -
      0.00478 * math.sin(_rad(125.04 - 1934.136 * t));

  /// Mean obliquity of the ecliptic, degrees.
  static double meanObliquityOfEcliptic(double t) =>
      23.0 +
      (26.0 +
              ((21.448 - t * (46.815 + t * (0.00059 - t * 0.001813)))) / 60.0) /
          60.0;

  /// Obliquity corrected for nutation, degrees.
  static double obliquityCorrected(double t) =>
      meanObliquityOfEcliptic(t) +
      0.00256 * math.cos(_rad(125.04 - 1934.136 * t));

  /// Solar declination, degrees. Positive = sun north of the celestial equator.
  static double declination(double t) => _deg(
        math.asin(
          math.sin(_rad(obliquityCorrected(t))) *
              math.sin(_rad(sunApparentLong(t))),
        ),
      );

  /// Equation of time, in minutes. The difference between apparent and mean
  /// solar time — this is why solar noon drifts by up to ±16 minutes over a year.
  static double equationOfTime(double t) {
    final epsilon = _rad(obliquityCorrected(t));
    final l0 = _rad(geomMeanLongSun(t));
    final e = eccentricityEarthOrbit(t);
    final m = _rad(geomMeanAnomSun(t));

    final y = math.tan(epsilon / 2) * math.tan(epsilon / 2);

    final eTime = y * math.sin(2 * l0) -
        2 * e * math.sin(m) +
        4 * e * y * math.sin(m) * math.cos(2 * l0) -
        0.5 * y * y * math.sin(4 * l0) -
        1.25 * e * e * math.sin(2 * m);

    return _deg(eTime) * 4.0;
  }

  /// Hour angle in degrees for a given zenith, or `null` when the sun never
  /// reaches that zenith on this day (polar day or polar night).
  ///
  /// Returning null rather than throwing is deliberate — for a user in Tromsø
  /// this is an ordinary Tuesday, not an error.
  static double? hourAngle({
    required double latitudeDeg,
    required double declinationDeg,
    required double zenithDeg,
  }) {
    final lat = _rad(latitudeDeg);
    final decl = _rad(declinationDeg);
    final zenith = _rad(zenithDeg);

    final cosH = (math.cos(zenith) - math.sin(lat) * math.sin(decl)) /
        (math.cos(lat) * math.cos(decl));

    if (cosH > 1.0 || cosH < -1.0) return null;
    return _deg(math.acos(cosH));
  }

  // ---------------------------------------------------------------------------
  // Event times
  // ---------------------------------------------------------------------------

  /// Solar noon for [dateUtcMidnight] at [longitude], as minutes past 00:00 UTC.
  static double solarNoonUtcMinutes(DateTime dateUtcMidnight, double longitude) {
    // First pass at the day's midpoint, then refine once the equation of time
    // is evaluated nearer the actual noon. Two passes is enough for < 1 s.
    final jdNoon = julianDay(dateUtcMidnight) + 0.5;
    var noon = 720.0 - 4.0 * longitude - equationOfTime(julianCentury(jdNoon));

    final refinedJd = julianDay(dateUtcMidnight) + noon / 1440.0;
    noon = 720.0 - 4.0 * longitude - equationOfTime(julianCentury(refinedJd));

    return noon;
  }

  /// A solar event time as a UTC instant, or `null` if it does not occur.
  ///
  /// [dateUtcMidnight] must be midnight UTC on the day of interest.
  /// [rising] selects the morning (true) or evening (false) crossing.
  static DateTime? eventUtc({
    required DateTime dateUtcMidnight,
    required GeoLocation at,
    required double zenithDeg,
    required bool rising,
  }) {
    final noonMinutes = solarNoonUtcMinutes(dateUtcMidnight, at.longitude);

    // Evaluate declination at solar noon, then refine at the event itself.
    var tEval = julianCentury(
      julianDay(dateUtcMidnight) + noonMinutes / 1440.0,
    );

    double? offsetMinutes;
    for (var pass = 0; pass < 2; pass++) {
      final ha = hourAngle(
        latitudeDeg: at.latitude,
        declinationDeg: declination(tEval),
        zenithDeg: zenithDeg,
      );
      if (ha == null) return null;

      offsetMinutes = 4.0 * ha;
      final eventMinutes =
          rising ? noonMinutes - offsetMinutes : noonMinutes + offsetMinutes;
      tEval = julianCentury(
        julianDay(dateUtcMidnight) + eventMinutes / 1440.0,
      );
    }

    final eventMinutes =
        rising ? noonMinutes - offsetMinutes! : noonMinutes + offsetMinutes!;

    return dateUtcMidnight
        .toUtc()
        .add(Duration(milliseconds: (eventMinutes * 60000).round()));
  }

  // ---------------------------------------------------------------------------
  // Continuous position — drives the live sky
  // ---------------------------------------------------------------------------

  /// Geometric solar altitude in degrees above the horizon at [utc].
  /// Negative values mean the sun is below the horizon.
  static double altitudeDeg(DateTime utc, GeoLocation at) {
    final u = utc.toUtc();
    final jd = julianDay(u);
    final t = julianCentury(jd);

    final decl = _rad(declination(t));
    final lat = _rad(at.latitude);

    final minutesUtc =
        u.hour * 60.0 + u.minute + u.second / 60.0 + u.millisecond / 60000.0;

    // True solar time in minutes, then hour angle in degrees.
    final trueSolarTime = minutesUtc + equationOfTime(t) + 4.0 * at.longitude;
    var hourAngleDeg = trueSolarTime / 4.0 - 180.0;
    // Normalise into [-180, 180].
    hourAngleDeg = ((hourAngleDeg + 180.0) % 360.0 + 360.0) % 360.0 - 180.0;

    final cosZenith = math.sin(lat) * math.sin(decl) +
        math.cos(lat) * math.cos(decl) * math.cos(_rad(hourAngleDeg));

    return 90.0 - _deg(math.acos(cosZenith.clamp(-1.0, 1.0)));
  }

  /// Solar altitude corrected for atmospheric refraction — what you'd actually
  /// see. Near the horizon refraction lifts the sun by more than its own width.
  static double apparentAltitudeDeg(DateTime utc, GeoLocation at) {
    final elevation = altitudeDeg(utc, at);
    return elevation + _refractionCorrectionDeg(elevation);
  }

  /// NOAA's piecewise refraction correction, in degrees.
  static double _refractionCorrectionDeg(double elevationDeg) {
    if (elevationDeg > 85.0) return 0.0;

    final te = math.tan(_rad(elevationDeg));
    double correctionArcSec;

    if (elevationDeg > 5.0) {
      correctionArcSec =
          58.1 / te - 0.07 / math.pow(te, 3) + 0.000086 / math.pow(te, 5);
    } else if (elevationDeg > -0.575) {
      final e = elevationDeg;
      correctionArcSec = 1735.0 +
          e * (-518.2 + e * (103.4 + e * (-12.79 + e * 0.711)));
    } else {
      correctionArcSec = -20.772 / te;
    }

    return correctionArcSec / 3600.0;
  }

  // ---------------------------------------------------------------------------
  // Illuminance
  // ---------------------------------------------------------------------------

  /// Estimated horizontal illuminance in lux for a given solar altitude and sky
  /// condition. Used to score light exposure when the user logs "I went outside"
  /// rather than carrying a lux meter.
  ///
  /// The important truth this encodes: a window destroys most of the circadian
  /// value of daylight. That is why the app insists on *outside*.
  static int estimatedLux({
    required double altitudeDeg,
    required SkyCondition condition,
    bool throughWindow = false,
  }) {
    if (altitudeDeg < -18) return 0;

    double base;
    if (altitudeDeg <= 0) {
      // Twilight: falls off fast. -0.5° ≈ 400 lx, -18° ≈ 0.
      final fraction = (1.0 + altitudeDeg / 18.0).clamp(0.0, 1.0);
      base = 400.0 * math.pow(fraction, 3).toDouble();
    } else {
      // Clear-sky horizontal illuminance rises roughly with sin(altitude)^1.2.
      final sinAlt = math.sin(_rad(altitudeDeg)).clamp(0.0, 1.0);
      base = 105000.0 * math.pow(sinAlt, 1.2).toDouble();
    }

    base *= switch (condition) {
      SkyCondition.clear => 1.0,
      SkyCondition.partlyCloudy => 0.55,
      SkyCondition.overcast => 0.18,
    };

    if (throughWindow) {
      // Glass transmission plus the geometry of standing indoors: you lose the
      // whole sky dome except the slice the window frames.
      base = math.min(base * 0.4, 2000.0);
    }

    return base.round();
  }
}

/// Sky conditions the user can report when logging light.
enum SkyCondition { clear, partlyCloudy, overcast }

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

double _rad(double degrees) => degrees * math.pi / 180.0;
double _deg(double radians) => radians * 180.0 / math.pi;
double _mod360(double value) => ((value % 360.0) + 360.0) % 360.0;
