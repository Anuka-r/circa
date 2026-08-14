import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import '../domain/value_objects/geo_location.dart';

/// A city from the bundled dataset.
class City {
  const City({
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.tzId,
  });

  final String name;
  final String country;
  final double latitude;
  final double longitude;
  final String tzId;

  String get label => '$name, $country';

  GeoLocation toGeoLocation() => GeoLocation(
        latitude: latitude,
        longitude: longitude,
        tzId: tzId,
        label: label,
      );
}

/// Offline city search and reverse geocoding.
///
/// Deliberately not the `geocoding` package: that needs a network round-trip
/// and platform services, which would mean trip planning fails on a plane —
/// exactly when people actually do it. 4,461 cities covering 361 time zones
/// ship in the binary for about 250 KB.
class CityLookup {
  CityLookup._(this._cities);

  final List<City> _cities;

  static CityLookup? _instance;
  static CityLookup get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('CityLookup.load() must be awaited during boot');
    }
    return i;
  }

  static bool get isLoaded => _instance != null;

  static Future<CityLookup> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/data/cities.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    final cities = decoded.map((entry) {
      final row = entry as List<dynamic>;
      return City(
        name: row[0] as String,
        country: row[1] as String,
        latitude: (row[2] as num).toDouble(),
        longitude: (row[3] as num).toDouble(),
        tzId: row[4] as String,
      );
    }).toList(growable: false);
    return _instance = CityLookup._(cities);
  }

  int get count => _cities.length;

  /// Prefix-and-substring search, ranked so that a leading match wins and
  /// larger/earlier dataset entries break ties (the source list is
  /// population-ordered).
  List<City> search(String query, {int limit = 20}) {
    final q = _normalise(query);
    if (q.isEmpty) return _cities.take(limit).toList();

    final starts = <City>[];
    final contains = <City>[];

    for (final city in _cities) {
      final name = _normalise(city.name);
      if (name.startsWith(q)) {
        starts.add(city);
        if (starts.length >= limit) break;
      } else if (name.contains(q) || _normalise(city.country).startsWith(q)) {
        if (contains.length < limit) contains.add(city);
      }
    }

    return [...starts, ...contains].take(limit).toList();
  }

  /// Nearest city to a coordinate — our reverse geocoder.
  City? nearest(double latitude, double longitude) {
    City? best;
    var bestDistance = double.infinity;
    for (final city in _cities) {
      final d = _haversineKm(latitude, longitude, city.latitude, city.longitude);
      if (d < bestDistance) {
        bestDistance = d;
        best = city;
      }
    }
    return best;
  }

  /// Resolves a coordinate to a full [GeoLocation], including the IANA zone of
  /// the nearest known city.
  GeoLocation resolve(double latitude, double longitude) {
    final city = nearest(latitude, longitude);
    return GeoLocation(
      latitude: latitude,
      longitude: longitude,
      tzId: city?.tzId ?? 'UTC',
      label: city?.label,
    );
  }

  /// Best-effort match for an IANA zone, used when we know the zone but not the
  /// coordinates (e.g. the device reports `Europe/Lisbon` but location is off).
  City? byTimezone(String tzId) {
    for (final city in _cities) {
      if (city.tzId == tzId) return city;
    }
    return null;
  }

  static String _normalise(String input) {
    // Fold the accents that actually appear in the dataset so "sao paulo"
    // matches "São Paulo" and "zurich" matches "Zürich".
    const from = 'áàâäãåéèêëíìîïóòôöõúùûüñçøåæšž';
    const to = 'aaaaaaeeeeiiiiooooouuuuncoaas z';
    var s = input.toLowerCase().trim();
    final buffer = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final index = from.indexOf(ch);
      buffer.write(index >= 0 && index < to.length ? to[index] : ch);
    }
    s = buffer.toString();
    return s;
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double degrees) => degrees * math.pi / 180.0;
}
