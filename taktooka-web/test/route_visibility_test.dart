import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/core/route_visibility.dart';

void main() {
  test(
    'customer sees no route before captain acceptance in booking and lines',
    () {
      for (final status in [null, 'pending', 'cancelled', 'rejected']) {
        expect(showTripRoute(captainView: false, status: status), false);
      }
    },
  );
  test('customer sees route once captain accepts', () {
    for (final status in ['accepted', 'arrived', 'in_progress', 'completed']) {
      expect(showTripRoute(captainView: false, status: status), true);
    }
  });
  test('captain can inspect an offer route before accepting', () {
    expect(showTripRoute(captainView: true, status: 'pending'), true);
  });
}
