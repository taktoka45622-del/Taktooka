import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:taktooka/services/map_handoff.dart';

void main() {
  test(
    'WhatsApp geo and Google links preserve destination rather than camera center',
    () {
      expect(
        parseSharedLocation('geo:0,0?q=33.35,44.41(مكان)'),
        const LatLng(33.35, 44.41),
      );
      expect(
        parseSharedLocation('الموقع https://maps.google.com/?q=33.35,44.41'),
        const LatLng(33.35, 44.41),
      );
      expect(
        parseSharedLocation(
          'https://www.google.com/maps/place/test/@33.4,44.5,16z/data=!3d33.35!4d44.41',
        ),
        const LatLng(33.35, 44.41),
      );
      expect(
        parseSharedLocation(
          'https://www.google.com/maps/place/test/@33.4,44.5,16z',
        ),
        isNull,
      );
      expect(parseSharedLocation('https://evil.test/?q=33.35,44.41'), isNull);
      expect(parseSharedLocation('geo:90,180'), isNull);
      expect(parseSharedLocation('https://maps.google.com/?q=%ZZ'), isNull);
    },
  );
  test('Short map links resolve only trusted redirects', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        '',
        302,
        headers: {'location': 'https://maps.google.com/?q=33.35,44.41'},
      );
    });
    expect(
      await resolveSharedLocation(
        'https://maps.app.goo.gl/test',
        client: client,
      ),
      const LatLng(33.35, 44.41),
    );
    expect(calls, 1);
    final unsafe = MockClient((request) async {
      calls++;
      return http.Response(
        '',
        302,
        headers: {'location': 'http://127.0.0.1/private'},
      );
    });
    expect(
      await resolveSharedLocation(
        'https://maps.app.goo.gl/test',
        client: unsafe,
      ),
      isNull,
    );
    expect(calls, 2);
  });
  test(
    'Waze target switches from customer pickup to destination at departure',
    () {
      final ride = {
        'status': 'accepted',
        'pickup': [33.35, 44.41],
        'destination': [33.36, 44.42],
      };
      expect(rideWazeUri(ride)!.queryParameters['ll'], '33.35,44.41');
      ride['status'] = 'arrived';
      expect(rideWazeUri(ride)!.queryParameters['ll'], '33.35,44.41');
      ride['status'] = 'in_progress';
      expect(rideWazeUri(ride)!.queryParameters['ll'], '33.36,44.42');
      expect(rideWazeUri(ride)!.queryParameters['navigate'], 'yes');
    },
  );
}
