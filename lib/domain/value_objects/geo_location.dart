/// A point on Earth, plus the IANA zone that applies there.
///
/// Latitude/longitude are the only inputs the solar engine needs — GPS precision
/// is irrelevant, a city centroid is more than accurate enough (1° of longitude
/// is 4 minutes of solar time; 0.1° is 24 seconds).
class GeoLocation {
  const GeoLocation({
    required this.latitude,
    required this.longitude,
    required this.tzId,
    this.label,
  })  : assert(latitude >= -90 && latitude <= 90, 'latitude out of range'),
        assert(longitude >= -180 && longitude <= 180, 'longitude out of range');

  /// Degrees north, positive = northern hemisphere.
  final double latitude;

  /// Degrees east, positive = east of Greenwich.
  final double longitude;

  /// IANA time zone identifier, e.g. `Europe/Lisbon`.
  final String tzId;

  /// Human-readable name shown in the UI, e.g. `Lisbon, Portugal`.
  final String? label;

  /// True above the Arctic Circle or below the Antarctic Circle, where the sun
  /// can stay up or down for a full day. Callers must handle null solar events.
  bool get isPolar => latitude.abs() > 66.5;

  GeoLocation copyWith({
    double? latitude,
    double? longitude,
    String? tzId,
    String? label,
  }) =>
      GeoLocation(
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        tzId: tzId ?? this.tzId,
        label: label ?? this.label,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoLocation &&
          other.latitude == latitude &&
          other.longitude == longitude &&
          other.tzId == tzId;

  @override
  int get hashCode => Object.hash(latitude, longitude, tzId);

  @override
  String toString() =>
      'GeoLocation(${latitude.toStringAsFixed(4)}, '
      '${longitude.toStringAsFixed(4)}, $tzId)';
}
