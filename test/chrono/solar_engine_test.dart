import 'package:circa/domain/chrono/solar_engine.dart';
import 'package:circa/domain/value_objects/geo_location.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper: local midnight UTC for a calendar date.
DateTime utcDate(int y, int m, int d) => DateTime.utc(y, m, d);

DateTime? sunrise(GeoLocation at, DateTime date) => SolarEngine.eventUtc(
      dateUtcMidnight: date,
      at: at,
      zenithDeg: SolarEngine.zenithSunrise,
      rising: true,
    );

DateTime? sunset(GeoLocation at, DateTime date) => SolarEngine.eventUtc(
      dateUtcMidnight: date,
      at: at,
      zenithDeg: SolarEngine.zenithSunrise,
      rising: false,
    );

const london = GeoLocation(
  latitude: 51.5074,
  longitude: -0.1278,
  tzId: 'Europe/London',
  label: 'London',
);
const newYork = GeoLocation(
  latitude: 40.7128,
  longitude: -74.0060,
  tzId: 'America/New_York',
  label: 'New York',
);
const sydney = GeoLocation(
  latitude: -33.8688,
  longitude: 151.2093,
  tzId: 'Australia/Sydney',
  label: 'Sydney',
);
const tromso = GeoLocation(
  latitude: 69.6492,
  longitude: 18.9553,
  tzId: 'Europe/Oslo',
  label: 'Tromsø',
);
const nullIsland = GeoLocation(
  latitude: 0,
  longitude: 0,
  tzId: 'UTC',
  label: 'Null Island',
);
const quito = GeoLocation(
  latitude: -0.1807,
  longitude: -78.4678,
  tzId: 'America/Guayaquil',
  label: 'Quito',
);

void main() {
  group('Julian day', () {
    test('J2000.0 epoch is exactly 2451545.0', () {
      // 2000-01-01 12:00 UTC is the definition of J2000.0.
      final jd = SolarEngine.julianDay(DateTime.utc(2000, 1, 1, 12));
      expect(jd, closeTo(2451545.0, 1e-6));
    });

    test('advances by exactly 1.0 per day', () {
      final a = SolarEngine.julianDay(DateTime.utc(2026, 3, 14, 6, 30));
      final b = SolarEngine.julianDay(DateTime.utc(2026, 3, 15, 6, 30));
      expect(b - a, closeTo(1.0, 1e-9));
    });

    test('handles the Gregorian leap day', () {
      final feb28 = SolarEngine.julianDay(DateTime.utc(2024, 2, 28));
      final feb29 = SolarEngine.julianDay(DateTime.utc(2024, 2, 29));
      final mar01 = SolarEngine.julianDay(DateTime.utc(2024, 3, 1));
      expect(feb29 - feb28, closeTo(1.0, 1e-9));
      expect(mar01 - feb29, closeTo(1.0, 1e-9));
    });
  });

  group('Physical invariants', () {
    test('solar declination stays within the tropics', () {
      for (var day = 0; day < 365; day++) {
        final date = DateTime.utc(2026, 1, 1).add(Duration(days: day));
        final decl = SolarEngine.declination(
          SolarEngine.julianCentury(SolarEngine.julianDay(date)),
        );
        expect(decl.abs(), lessThan(23.5),
            reason: 'declination out of range on $date');
      }
    });

    test('declination peaks at the solstices and is ~0 at the equinoxes', () {
      double declOn(int m, int d) => SolarEngine.declination(
            SolarEngine.julianCentury(
              SolarEngine.julianDay(DateTime.utc(2026, m, d, 12)),
            ),
          );
      expect(declOn(6, 21), closeTo(23.4, 0.2)); // northern summer solstice
      expect(declOn(12, 21), closeTo(-23.4, 0.2)); // northern winter solstice
      expect(declOn(3, 20), closeTo(0, 0.5)); // March equinox
      expect(declOn(9, 22), closeTo(0, 0.6)); // September equinox
    });

    test('equation of time stays within its known ±17 minute envelope', () {
      for (var day = 0; day < 365; day++) {
        final date = DateTime.utc(2026, 1, 1).add(Duration(days: day));
        final eot = SolarEngine.equationOfTime(
          SolarEngine.julianCentury(SolarEngine.julianDay(date)),
        );
        expect(eot.abs(), lessThan(17.0), reason: 'EoT out of range on $date');
      }
    });

    test('sunrise and sunset are symmetric about solar noon', () {
      final date = utcDate(2026, 5, 12);
      final noonMinutes =
          SolarEngine.solarNoonUtcMinutes(date, london.longitude);
      final rise = sunrise(london, date)!;
      final set = sunset(london, date)!;

      final riseMin = rise.difference(date).inSeconds / 60.0;
      final setMin = set.difference(date).inSeconds / 60.0;

      expect(noonMinutes - riseMin, closeTo(setMin - noonMinutes, 1.0),
          reason: 'sunrise/sunset should straddle solar noon evenly');
    });

    test('day length at the equator is ~12h all year', () {
      for (final (m, d) in [(1, 15), (3, 20), (6, 21), (9, 22), (12, 21)]) {
        final date = utcDate(2026, m, d);
        final rise = sunrise(nullIsland, date)!;
        final set = sunset(nullIsland, date)!;
        final hours = set.difference(rise).inMinutes / 60.0;
        // Slightly over 12h because refraction and the solar disc both help.
        expect(hours, closeTo(12.12, 0.15),
            reason: 'equator day length wrong on $m/$d');
      }
    });

    test('day length is near 12h everywhere at the equinox', () {
      final date = utcDate(2026, 3, 20);
      for (final place in [london, newYork, sydney, quito]) {
        final rise = sunrise(place, date)!;
        final set = sunset(place, date)!;
        final hours = set.difference(rise).inMinutes / 60.0;
        expect(hours, closeTo(12.15, 0.35),
            reason: '${place.label} equinox day length was ${hours}h');
      }
    });

    test('hemispheres are inverted — longest London day is shortest in Sydney',
        () {
      final june = utcDate(2026, 6, 21);
      final dec = utcDate(2026, 12, 21);

      double dayLength(GeoLocation p, DateTime d) =>
          sunset(p, d)!.difference(sunrise(p, d)!).inMinutes / 60.0;

      expect(dayLength(london, june), greaterThan(dayLength(london, dec)));
      expect(dayLength(sydney, june), lessThan(dayLength(sydney, dec)));
    });

    test('higher latitude means a longer summer day', () {
      final june = utcDate(2026, 6, 21);
      double dayLength(GeoLocation p) =>
          sunset(p, june)!.difference(sunrise(p, june)!).inMinutes / 60.0;
      expect(dayLength(london), greaterThan(dayLength(newYork)));
      expect(dayLength(newYork), greaterThan(dayLength(nullIsland)));
    });
  });

  group('Polar cases — a first-class state, not an error', () {
    test('Tromsø has midnight sun in June (no sunset)', () {
      final date = utcDate(2026, 6, 21);
      expect(sunrise(tromso, date), isNull);
      expect(sunset(tromso, date), isNull);
      // And the sun genuinely never goes below the horizon.
      var minAltitude = 90.0;
      for (var m = 0; m < 24 * 60; m += 10) {
        final alt = SolarEngine.altitudeDeg(
          date.add(Duration(minutes: m)),
          tromso,
        );
        if (alt < minAltitude) minAltitude = alt;
      }
      expect(minAltitude, greaterThan(0),
          reason: 'midnight sun means altitude never drops below 0');
    });

    test('Tromsø has polar night in December (no sunrise)', () {
      final date = utcDate(2026, 12, 21);
      expect(sunrise(tromso, date), isNull);

      var maxAltitude = -90.0;
      for (var m = 0; m < 24 * 60; m += 10) {
        final alt = SolarEngine.altitudeDeg(
          date.add(Duration(minutes: m)),
          tromso,
        );
        if (alt > maxAltitude) maxAltitude = alt;
      }
      expect(maxAltitude, lessThan(0),
          reason: 'polar night means the sun never clears the horizon');
    });
  });

  group('Solar altitude', () {
    test('peaks at solar noon', () {
      final date = utcDate(2026, 4, 10);
      final noonMinutes =
          SolarEngine.solarNoonUtcMinutes(date, london.longitude);
      final noon = date.add(Duration(minutes: noonMinutes.round()));

      final atNoon = SolarEngine.altitudeDeg(noon, london);
      for (final offset in [-180, -60, -20, 20, 60, 180]) {
        final other = SolarEngine.altitudeDeg(
          noon.add(Duration(minutes: offset)),
          london,
        );
        expect(atNoon, greaterThanOrEqualTo(other - 1e-6),
            reason: 'altitude should peak at solar noon (offset $offset min)');
      }
    });

    test('noon altitude at the equator on the equinox is ~90°', () {
      final date = utcDate(2026, 3, 20);
      final noonMinutes =
          SolarEngine.solarNoonUtcMinutes(date, nullIsland.longitude);
      final alt = SolarEngine.altitudeDeg(
        date.add(Duration(minutes: noonMinutes.round())),
        nullIsland,
      );
      expect(alt, closeTo(90, 1.0));
    });

    test('is ~0 at the moment of sunrise', () {
      final date = utcDate(2026, 8, 3);
      final rise = sunrise(london, date)!;
      final alt = SolarEngine.altitudeDeg(rise, london);
      // 90.833° zenith == −0.833° geometric altitude.
      expect(alt, closeTo(-0.833, 0.25));
    });

    test('apparent altitude exceeds geometric near the horizon', () {
      final date = utcDate(2026, 8, 3);
      final rise = sunrise(london, date)!;
      final geometric = SolarEngine.altitudeDeg(rise, london);
      final apparent = SolarEngine.apparentAltitudeDeg(rise, london);
      expect(apparent, greaterThan(geometric),
          reason: 'refraction lifts the sun near the horizon');
      expect(apparent - geometric, closeTo(0.55, 0.25));
    });
  });

  group('Twilight ordering', () {
    test('astronomical precedes nautical precedes civil precedes sunrise', () {
      final date = utcDate(2026, 4, 15);
      DateTime at(double zenith) => SolarEngine.eventUtc(
            dateUtcMidnight: date,
            at: london,
            zenithDeg: zenith,
            rising: true,
          )!;

      final astro = at(SolarEngine.zenithAstronomical);
      final nautical = at(SolarEngine.zenithNautical);
      final civil = at(SolarEngine.zenithCivil);
      final rise = at(SolarEngine.zenithSunrise);

      expect(astro.isBefore(nautical), isTrue);
      expect(nautical.isBefore(civil), isTrue);
      expect(civil.isBefore(rise), isTrue);
    });
  });

  group('Golden values against published almanac times', () {
    // Reference sunrise/sunset for 2026 solstices, in each city's local civil
    // time. Tolerance is ±2 minutes — tighter than the ±90s claimed in the
    // spec would be fragile against almanac rounding, looser would not prove
    // anything.
    const tolerance = Duration(minutes: 2);

    void expectEvent(
      String label,
      DateTime? actualUtc,
      int utcOffsetMinutes,
      int expectedHour,
      int expectedMinute,
    ) {
      expect(actualUtc, isNotNull, reason: '$label should occur');
      final local = actualUtc!.add(Duration(minutes: utcOffsetMinutes));
      final expected = DateTime.utc(
        local.year,
        local.month,
        local.day,
        expectedHour,
        expectedMinute,
      );
      final delta = local.difference(expected).abs();
      expect(
        delta,
        lessThanOrEqualTo(tolerance),
        reason: '$label was ${local.hour}:'
            '${local.minute.toString().padLeft(2, '0')}, '
            'expected $expectedHour:'
            '${expectedMinute.toString().padLeft(2, '0')}',
      );
    }

    test('London, June solstice (BST, UTC+1)', () {
      final date = utcDate(2026, 6, 21);
      expectEvent('London Jun sunrise', sunrise(london, date), 60, 4, 43);
      expectEvent('London Jun sunset', sunset(london, date), 60, 21, 21);
    });

    test('London, December solstice (GMT, UTC+0)', () {
      final date = utcDate(2026, 12, 21);
      expectEvent('London Dec sunrise', sunrise(london, date), 0, 8, 4);
      expectEvent('London Dec sunset', sunset(london, date), 0, 15, 53);
    });

    test('New York, June solstice (EDT, UTC−4)', () {
      final date = utcDate(2026, 6, 21);
      expectEvent('NY Jun sunrise', sunrise(newYork, date), -240, 5, 25);
      expectEvent('NY Jun sunset', sunset(newYork, date), -240, 20, 31);
    });

    test('New York, December solstice (EST, UTC−5)', () {
      final date = utcDate(2026, 12, 21);
      expectEvent('NY Dec sunrise', sunrise(newYork, date), -300, 7, 16);
      expectEvent('NY Dec sunset', sunset(newYork, date), -300, 16, 32);
    });

    test('Sydney, June solstice (AEST, UTC+10)', () {
      final date = utcDate(2026, 6, 21);
      expectEvent('Sydney Jun sunrise', sunrise(sydney, date), 600, 7, 0);
      expectEvent('Sydney Jun sunset', sunset(sydney, date), 600, 16, 54);
    });

    test('Tokyo, June solstice (JST, UTC+9)', () {
      const tokyo = GeoLocation(
        latitude: 35.6895,
        longitude: 139.6917,
        tzId: 'Asia/Tokyo',
        label: 'Tokyo',
      );
      final date = utcDate(2026, 6, 21);
      expectEvent('Tokyo Jun sunrise', sunrise(tokyo, date), 540, 4, 25);
      expectEvent('Tokyo Jun sunset', sunset(tokyo, date), 540, 19, 0);
    });

    test('Delhi, June solstice (IST, UTC+5:30)', () {
      const delhi = GeoLocation(
        latitude: 28.6139,
        longitude: 77.2090,
        tzId: 'Asia/Kolkata',
        label: 'Delhi',
      );
      final date = utcDate(2026, 6, 21);
      expectEvent('Delhi Jun sunrise', sunrise(delhi, date), 330, 5, 23);
      expectEvent('Delhi Jun sunset', sunset(delhi, date), 330, 19, 21);
    });
  });

  group('Illuminance estimation', () {
    test('is monotonic in solar altitude on a clear day', () {
      var previous = -1;
      for (final alt in [-20.0, -10.0, -3.0, 0.0, 5.0, 15.0, 30.0, 60.0]) {
        final lux = SolarEngine.estimatedLux(
          altitudeDeg: alt,
          condition: SkyCondition.clear,
        );
        expect(lux, greaterThanOrEqualTo(previous),
            reason: 'lux should not decrease as the sun rises (alt $alt)');
        previous = lux;
      }
    });

    test('overcast is dimmer than clear, and a window dimmer still', () {
      const alt = 30.0;
      final clear = SolarEngine.estimatedLux(
        altitudeDeg: alt,
        condition: SkyCondition.clear,
      );
      final overcast = SolarEngine.estimatedLux(
        altitudeDeg: alt,
        condition: SkyCondition.overcast,
      );
      final throughGlass = SolarEngine.estimatedLux(
        altitudeDeg: alt,
        condition: SkyCondition.clear,
        throughWindow: true,
      );

      expect(overcast, lessThan(clear));
      expect(throughGlass, lessThan(overcast));
      expect(throughGlass, lessThanOrEqualTo(2000),
          reason: 'a window caps effective illuminance at ~2000 lux');
    });

    test('is zero below astronomical twilight', () {
      expect(
        SolarEngine.estimatedLux(
          altitudeDeg: -20,
          condition: SkyCondition.clear,
        ),
        0,
      );
    });

    test('clear midday sun is in the tens of thousands of lux', () {
      final lux = SolarEngine.estimatedLux(
        altitudeDeg: 60,
        condition: SkyCondition.clear,
      );
      expect(lux, inInclusiveRange(60000, 110000));
    });
  });
}
