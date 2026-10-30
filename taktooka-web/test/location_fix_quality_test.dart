import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/core/location_fix_quality.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26, 12);
  bool usable({
    double accuracy = 10,
    double lat = 33.38,
    double lng = 44.4,
    Duration age = Duration.zero,
  }) => LocationFixQuality.usable(
    latitude: lat,
    longitude: lng,
    accuracy: accuracy,
    timestamp: now.subtract(age),
    now: now,
  );
  test(
    'accepts only recent fixes with reported accuracy of 25 meters or better',
    () {
      expect(usable(), true);
      expect(usable(accuracy: 25, age: const Duration(seconds: 15)), true);
      expect(usable(accuracy: 25.1), false);
      expect(usable(age: const Duration(seconds: 16)), false);
    },
  );
  test('map display can reuse a recent fix while accuracy improves', () {
    expect(
      LocationFixQuality.usable(
        latitude: 33.34,
        longitude: 44.4,
        accuracy: 45,
        timestamp: now.subtract(const Duration(seconds: 20)),
        now: now,
        accuracyLimit: 50,
        ageLimit: const Duration(seconds: 30),
      ),
      true,
    );
    expect(usable(accuracy: 45), false);
  });
  test('does not accept unknown accuracy or invalid coordinates', () {
    expect(usable(accuracy: 0), false);
    expect(usable(accuracy: double.nan), false);
    expect(usable(lat: 91), false);
    expect(usable(lng: 181), false);
    expect(usable(lat: double.infinity), false);
  });
  test('old and future-dated locations are rejected', () {
    expect(usable(age: const Duration(minutes: 1)), false);
    expect(usable(age: const Duration(seconds: -4)), false);
  });
}
