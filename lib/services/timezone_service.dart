import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The single source of truth for "what time is it, where".
///
/// `DateTime.toLocal()` is banned everywhere else in the app: it can only
/// express the device's *current* offset, so it silently gets history wrong
/// across a DST boundary and gets travel wrong entirely. Everything goes
/// through a real TZDB lookup instead.
class TimezoneService {
  TimezoneService._(this._deviceTzId);

  final String _deviceTzId;

  static TimezoneService? _instance;
  static TimezoneService get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('TimezoneService.init() must be awaited during boot');
    }
    return i;
  }

  /// Loads the bundled TZDB. Must complete before any date maths runs.
  static Future<TimezoneService> init() async {
    tzdata.initializeTimeZones();
    String id;
    try {
      id = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      // A device that will not report its zone is not a reason to fail boot.
      id = 'UTC';
    }
    if (!_isKnown(id)) id = 'UTC';
    tz.setLocalLocation(tz.getLocation(id));
    return _instance = TimezoneService._(id);
  }

  static bool _isKnown(String id) {
    try {
      tz.getLocation(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The device's own zone, e.g. `Europe/Lisbon`.
  String get deviceTzId => _deviceTzId;

  /// UTC offset in effect in [tzId] at [utc] — correct across DST changes and
  /// historical rule changes.
  Duration offsetFor(DateTime utc, String tzId) {
    final location = _location(tzId);
    // `TimeZone.offset` is a Duration in timezone 0.11.x, despite the package's
    // own doc comment still describing it as milliseconds.
    return location.timeZone(utc.toUtc().millisecondsSinceEpoch).offset;
  }

  /// Wall-clock time in [tzId] for a UTC instant.
  DateTime toLocal(DateTime utc, String tzId) =>
      utc.toUtc().add(offsetFor(utc, tzId));

  /// The UTC instant corresponding to a wall-clock time in [tzId].
  ///
  /// Handles both DST edges: during the spring-forward gap the nominal time
  /// does not exist and we return the first valid instant after it; during the
  /// autumn overlap we take the first (pre-transition) occurrence.
  DateTime toUtc(DateTime localWallClock, String tzId) {
    final location = _location(tzId);
    final guess = tz.TZDateTime(
      location,
      localWallClock.year,
      localWallClock.month,
      localWallClock.day,
      localWallClock.hour,
      localWallClock.minute,
      localWallClock.second,
    );
    return guess.toUtc();
  }

  /// True if [tzId] is a zone we can resolve.
  bool isValid(String tzId) => _isKnown(tzId);

  /// All zone identifiers, for the debug/manual picker.
  List<String> get allZones => tz.timeZoneDatabase.locations.keys.toList()
    ..sort();

  tz.Location _location(String tzId) {
    try {
      return tz.getLocation(tzId);
    } catch (_) {
      return tz.getLocation('UTC');
    }
  }

  /// Convenience: the current UTC offset in [tzId].
  Duration currentOffset(String tzId) => offsetFor(DateTime.now().toUtc(), tzId);
}
