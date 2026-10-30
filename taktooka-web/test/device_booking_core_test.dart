import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/core/local_fare.dart';
import 'package:taktooka/core/local_address.dart';
import 'package:taktooka/core/local_route_metrics.dart';
import 'package:taktooka/services/device_booking.dart';
import 'package:taktooka/services/device_places.dart';

Map<String, dynamic> road({
  double distance = 1200,
  double duration = 300,
  List<dynamic> steps = const [],
}) => {
  'distance': distance,
  'duration': duration,
  'geometry': {
    'type': 'LineString',
    'coordinates': [
      [44.40, 33.34],
      [44.41, 33.35],
    ],
  },
  'legs': [
    {'steps': steps},
  ],
};
void main() {
  Map<String, dynamic> reverseName() => {
    'features': [
      {
        'geometry': {
          'coordinates': [44.4, 33.34],
        },
        'properties': {
          'feature_type': 'street',
          'name': 'شارع أبو جلال',
          'context': {
            'region': {'name': 'بغداد'},
            'locality': {'name': 'القاهرة'},
          },
        },
      },
    ],
  };
  test('area publishes before a slow optional provider completes', () async {
    final slow = Completer<http.Response>();
    final updates = <Map<String, dynamic>>[];
    final booking = DeviceBooking(
      client: MockClient((request) async {
        if (request.url.host == 'photon.komoot.io') return slow.future;
        return http.Response(
          jsonEncode(
            request.url.path.contains('geocode')
                ? reverseName()
                : {'features': []},
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    var complete = false;
    final result = booking
        .address(const LatLng(33.34, 44.4), '', onUpdate: updates.add)
        .whenComplete(() => complete = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(updates.last['area'], 'القاهرة');
    expect(complete, false);
    final returning = <Map<String, dynamic>>[];
    final same = booking.address(
      const LatLng(33.34, 44.4),
      '',
      onUpdate: returning.add,
    );
    expect(returning.last['area'], 'القاهرة');
    slow.complete(http.Response('{"features":[]}', 200));
    await Future.wait([result, same]);
  });
  test('revisiting a resolved point uses the address cache', () async {
    var calls = 0;
    final booking = DeviceBooking(
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode(
            request.url.path.contains('geocode')
                ? reverseName()
                : {'features': []},
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final first = await booking.address(const LatLng(33.34, 44.4), '');
    final second = await booking.address(const LatLng(33.34, 44.4), '');
    expect(first['area'], 'القاهرة');
    expect(second['name'], first['name']);
    expect(calls, 3);
  });
  test(
    'a failed address lookup can retry instead of caching an empty area',
    () async {
      var fail = true, calls = 0;
      final booking = DeviceBooking(
        client: MockClient((request) async {
          calls++;
          return fail
              ? http.Response('{}', 503)
              : http.Response(
                  jsonEncode(
                    request.url.path.contains('geocode')
                        ? reverseName()
                        : {'features': []},
                  ),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
        }),
      );
      await booking.address(const LatLng(33.34, 44.4), 'شارع');
      fail = false;
      final recovered = await booking.address(
        const LatLng(33.34, 44.4),
        'شارع',
      );
      expect(recovered['area'], 'القاهرة');
      expect(calls, 6);
    },
  );

  final day = DateTime.parse('2026-10-26T12:00:00Z');
  final fare = LocalFare(Map.of(LocalFare.defaults));
  test('address keeps province, area, street and nearest landmark', () {
    final result = LocalAddress.resolve(
      {
        'features': [
          {
            'properties': {
              'feature_type': 'street',
              'name': 'شارع القاهرة',
              'context': {
                'region': {'name': 'بغداد'},
                'locality': {'name': 'القاهرة'},
              },
            },
            'geometry': {
              'coordinates': [44.40, 33.34],
            },
          },
        ],
      },
      'شارع القاهرة',
      {
        'features': [
          {
            'properties': {
              'name_ar': 'جامع النداء',
              'tilequery': {'distance': 50, 'layer': 'poi_label'},
            },
          },
        ],
      },
      [33.34, 44.40],
      {},
    );
    expect(result['name'], 'بغداد، القاهرة، شارع القاهرة، قرب جامع النداء');
    expect(result['address_complete'], true);
  });
  test('street distance sums the full route geometry on the device', () {
    final m = LocalRouteMetrics.meters({
      'type': 'LineString',
      'coordinates': [
        [0, 0],
        [0, .01],
        [.01, .01],
      ],
    });
    expect(m, closeTo(2223.9, 1));
  });
  test('distance boundaries retain the current dashboard tariff', () {
    expect(fare.calculate(500, day)['fare'], 500);
    expect(fare.calculate(500.01, day)['fare'], 1000);
    expect(fare.calculate(2800, day)['fare'], 1000);
    expect(fare.calculate(2800.01, day)['fare'], 1500);
    expect(fare.calculate(25000.01, day)['fare'], 9000);
  });
  test('Baghdad night boundaries and minimum distance', () {
    final before = DateTime.parse('2026-10-26T17:59:59Z');
    final night = DateTime.parse('2026-10-26T18:00:00Z');
    final morning = DateTime.parse('2026-10-26T03:00:00Z');
    expect(fare.calculate(1200, before)['night_surcharge'], 0);
    expect(fare.calculate(1200, night)['night_surcharge'], 500);
    expect(fare.calculate(1199.99, night)['night_surcharge'], 0);
    expect(fare.calculate(1200, morning)['night_surcharge'], 0);
  });
  test('round trips use outbound tariff twice and correct waiting bands', () {
    expect(
      fare.calculate(1200, day, roundTrip: true, waitMinutes: 10)['fare'],
      2250,
    );
    expect(
      fare.calculate(1200, day, roundTrip: true, waitMinutes: 11)['fare'],
      2500,
    );
    expect(() => fare.calculate(1200, day, roundTrip: true), throwsStateError);
    expect(() => fare.calculate(double.nan, day), throwsStateError);
    expect(() => fare.calculate(0, day), throwsStateError);
  });
  test('updated settings, cap, and night-only cap are applied locally', () {
    final settings = {
      ...LocalFare.defaults,
      'max_fare': 1100,
      'night_start': 8,
      'night_end': 20,
    };
    final f = LocalFare(settings).calculate(1200, day);
    expect(f['fare'], 1100);
    expect(f['base_fare'], 1000);
    expect(f['night_surcharge'], 100);
  });
  test(
    'route rejects paths and routing violations instead of drawing a straight line',
    () {
      final foot = road(
        steps: [
          {'mode': 'walking', 'distance': 500},
        ],
      );
      final violation = {
        ...road(),
        'notifications': [
          {'type': 'violation'},
        ],
      };
      expect(
        () => DeviceBooking.selectRoute([foot, violation]),
        throwsStateError,
      );
      expect(DeviceBooking.selectRoute([foot, road()])['distance'], 1200);
    },
  );
  test('prefers main streets without accepting a large detour', () {
    final alley = road(
      steps: [
        {
          'distance': 1200,
          'intersections': [
            {
              'mapbox_streets_v8': {'class': 'service'},
            },
          ],
        },
      ],
    );
    final main = road(
      distance: 1230,
      steps: [
        {
          'distance': 1230,
          'intersections': [
            {
              'mapbox_streets_v8': {'class': 'primary'},
            },
          ],
        },
      ],
    );
    expect(DeviceBooking.selectRoute([alley, main])['distance'], 1230);
    expect(
      DeviceBooking.selectRoute([alley, road(distance: 2000)])['distance'],
      1200,
    );
  });
  test(
    'preview calls map provider only and prices outbound/return locally',
    () async {
      final urls = <Uri>[];
      final device = DeviceBooking(
        client: MockClient((request) async {
          urls.add(request.url);
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [road()],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final q = await device.quote(
        const LatLng(33.34, 44.40),
        const LatLng(33.35, 44.41),
        day,
        roundTrip: true,
        waitMinutes: 15,
      );
      expect(q['fare'], 2500);
      expect(
        q['distance_m'],
        (2 *
                LocalRouteMetrics.meters(
                  Map<String, dynamic>.from(road()['geometry'] as Map),
                ))
            .ceil(),
      );
      expect(q['duration_s'], 1500);
      expect(q['local_preview'], true);
      expect(q.containsKey('id'), false);
      expect(urls.length, 4);
      expect(urls.every((u) => u.host == 'api.mapbox.com'), true);
      expect(urls.any((u) => u.path.endsWith('44.41,33.35;44.4,33.34')), true);
    },
  );
  test('snap does not accept a road further than 150 meters', () async {
    final device = DeviceBooking(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [road()],
            'waypoints': [
              {
                'location': [44.5, 33.5],
              },
            ],
          }),
          200,
        ),
      ),
    );
    await expectLater(device.snap(const LatLng(33.34, 44.4)), throwsStateError);
  });
  test('offline route loader avoids the network directions service', () async {
    var localCalls = 0;
    final device = DeviceBooking(
      client: MockClient((_) async {
        throw StateError('NETWORK_MUST_NOT_BE_USED');
      }),
    );
    final q = await device.quote(
      const LatLng(33.34, 44.40),
      const LatLng(33.35, 44.41),
      day,
      roundTrip: false,
      waitMinutes: 0,
      routeLoader: (a, b) async {
        localCalls++;
        return road();
      },
    );
    expect(localCalls, 1);
    expect(q['local_preview'], true);
  });
  test('search retains Arabic correction and local category ranking', () {
    expect(DevicePlaces.normalize('السوك'), 'السوق');
    expect(DevicePlaces.quality('مطعم الأمير', 'مطعم الامير'), 1);
    final rows = [
      {
        'title': 'مطعم الأمير',
        'label': 'مطعم الأمير، بغداد',
        'point': const LatLng(33.34, 44.40),
      },
      {
        'title': 'مطعم الأمير',
        'label': 'مطعم الأمير، البصرة',
        'point': const LatLng(30.5, 47.8),
      },
      {
        'title': 'شارع الأمير',
        'label': 'شارع الأمير قرب مطعم',
        'point': const LatLng(33.34, 44.40),
      },
    ];
    final result = DevicePlaces.rank(
      rows,
      'مطعم الامير',
      const LatLng(33.34, 44.40),
    );
    expect(result.length, 2);
    expect(result.first['point'], const LatLng(33.34, 44.40));
  });
}
