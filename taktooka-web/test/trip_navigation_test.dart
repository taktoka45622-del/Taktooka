import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taktooka/core/trip_navigation.dart';

Map<String, dynamic> route(LatLng a, LatLng b) => {
  'geometry': {
    'type': 'LineString',
    'coordinates': [
      [a.longitude, a.latitude],
      [b.longitude, b.latitude],
    ],
  },
};
Map<String, dynamic> ride(String status) => {
  'id': 'ride',
  'status': status,
  'pickup': [33.34, 44.4],
  'destination': [33.35, 44.41],
  'destination_revision': 0,
};
void main() {
  test('passed route is removed as captain approaches the customer', () {
    final path = [
      const LatLng(33.34, 44.4),
      const LatLng(33.341, 44.4),
      const LatLng(33.342, 44.4),
    ];
    final result = RouteProgress.remaining(path, const LatLng(33.3415, 44.4));
    expect(result.distanceToRoute, lessThan(1));
    expect(result.points.length, 2);
    expect(result.points.first.latitude, closeTo(33.3415, .000001));
    expect(result.points.last, path.last);
    expect(RouteProgress.remaining(path, path.last).points.length, 1);
  });
  test(
    'approach targets pickup then switches to destination after departure',
    () async {
      final targets = <LatLng>[];
      final published = <Map<String, dynamic>>[];
      final navigation = TripNavigation(
        load: (a, b) async {
          targets.add(b);
          return route(a, b);
        },
        publish: (data) async {
          published.add(data);
        },
      );
      await navigation.update(
        ride('accepted'),
        const LatLng(33.339, 44.4),
        DateTime.now(),
        isCurrent: () => true,
      );
      await navigation.update(
        ride('in_progress'),
        const LatLng(33.34, 44.4),
        DateTime.now(),
        isCurrent: () => true,
      );
      expect(targets, [const LatLng(33.34, 44.4), const LatLng(33.35, 44.41)]);
      expect(published.length, 2);
      expect(published.last.containsKey('fare'), false);
    },
  );
  test(
    'deviation rebuilds a shared road route while movement on it reuses it',
    () async {
      var calls = 0;
      final r = ride('accepted');
      r['navigation'] = {
        'ride_id': 'ride',
        'phase': TripNavigation.phase(r),
        'geometry': route(
          const LatLng(33.338, 44.4),
          const LatLng(33.34, 44.4),
        )['geometry'],
      };
      Map<String, dynamic>? published;
      final navigation = TripNavigation(
        load: (a, b) async {
          calls++;
          return route(a, b);
        },
        publish: (data) async {
          published = data;
        },
      );
      await navigation.update(
        r,
        const LatLng(33.339, 44.4),
        DateTime.now(),
        isCurrent: () => true,
      );
      expect(calls, 0);
      await navigation.update(
        r,
        const LatLng(33.339, 44.402),
        DateTime.now(),
        isCurrent: () => true,
      );
      expect(calls, 1);
      expect(published?['geometry'], isNotNull);
    },
  );
  test('late routing response cannot overwrite a changed trip', () async {
    final gate = Completer<Map<String, dynamic>>();
    var current = true;
    var writes = 0;
    final navigation = TripNavigation(
      load: (a, b) => gate.future,
      publish: (_) async {
        writes++;
      },
    );
    final pending = navigation.update(
      ride('accepted'),
      const LatLng(33.339, 44.4),
      DateTime.now(),
      isCurrent: () => current,
    );
    current = false;
    gate.complete(route(const LatLng(33.339, 44.4), const LatLng(33.34, 44.4)));
    await pending;
    expect(writes, 0);
  });
  test(
    'return trip targets pickup and changed destination invalidates shared geometry',
    () {
      final r = ride('in_progress')..['round_trip_stage'] = 'returning';
      expect(TripNavigation.target(r), const LatLng(33.34, 44.4));
      r['navigation'] = {'ride_id': 'ride', 'phase': TripNavigation.phase(r)};
      expect(TripNavigation.shared(r), isNotNull);
      r['destination_revision'] = 1;
      expect(TripNavigation.shared(r), isNull);
    },
  );
}
