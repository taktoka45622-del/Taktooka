import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taktooka/core/vehicle_motion.dart';

void main() {
  test('vehicle follows a right-angle road rather than cutting across it', () {
    final path = VehicleMotion([
      const LatLng(33, 44),
      const LatLng(33, 44.001),
      const LatLng(33.001, 44.001),
    ]);
    for (var i = 0; i <= 20; i++) {
      final p = path.at(i / 20).point;
      expect(
        (p.latitude - 33).abs() < 1e-8 || (p.longitude - 44.001).abs() < 1e-8,
        true,
      );
    }
    expect(path.at(.2).heading, closeTo(90, .01));
    expect(path.at(.9).heading, closeTo(0, .01));
  });
  test('progress is clamped and stopped vehicles retain their direction', () {
    final path = VehicleMotion([
      const LatLng(33, 44),
      const LatLng(33.001, 44),
    ]);
    expect(path.at(-1).point, const LatLng(33, 44));
    expect(path.at(2).point, const LatLng(33.001, 44));
    expect(
      VehicleMotion([const LatLng(33, 44)]).at(.5, idleHeading: 275).heading,
      275,
    );
  });
}
