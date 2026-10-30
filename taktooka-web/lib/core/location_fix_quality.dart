class LocationFixQuality {
  static const maximumAccuracyMeters = 25.0;
  static const maximumAge = Duration(seconds: 15);
  static bool usable({
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime timestamp,
    DateTime? now,
    double accuracyLimit = maximumAccuracyMeters,
    Duration ageLimit = maximumAge,
  }) {
    final age = (now ?? DateTime.now()).toUtc().difference(timestamp.toUtc());
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180 &&
        accuracy.isFinite &&
        accuracy > 0 &&
        accuracy <= accuracyLimit &&
        age >= const Duration(seconds: -2) &&
        age <= ageLimit;
  }
}
