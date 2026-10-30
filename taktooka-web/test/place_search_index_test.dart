import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taktooka/core/local_place_index.dart';
import 'package:taktooka/core/place_text.dart';
import 'package:taktooka/services/device_places.dart';
import 'package:taktooka/services/iraq_places.dart';

class StubPlaces extends DevicePlaces {
  final Future<List<Map<String, dynamic>>> Function(String, bool) loader;
  StubPlaces(this.loader, http.Client client) : super(client: client);
  @override
  Future<List<Map<String, dynamic>>> local(
    String query,
    LatLng origin, {
    bool areasOnly = false,
  }) => loader(query, areasOnly);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const origin = LatLng(33.54844, 44.41179);
  test(
    'Arabic matching tolerates spelling and letter variants without inventing places',
    () {
      expect(
        PlaceText.quality(
          'مستشفى الشهيد ضاري الفياظ',
          'مستشفى الشهيد ضاري الفياط',
        ),
        greaterThan(.85),
      );
      expect(PlaceText.quality('مطعم الأمير', 'مطعم الامير'), 1);
      expect(PlaceText.quality('صيدلية النور', 'مطعم النور'), 0);
      expect(PlaceText.normalize('  مَدرَسَة / الأمل  '), 'مدرسه الامل');
    },
  );
  test('index matches aliases and nearby places before distant names', () {
    final index = LocalPlaceIndex([
      [
        'مستشفى الشهيد ضاري الفياظ',
        'مستشفى ضاري الفياض',
        33.515726,
        44.39175,
        'hospital',
        'بغداد',
        false,
      ],
      [
        'مستشفى الشهيد ضاري الفياظ',
        '',
        30.5,
        47.8,
        'hospital',
        'البصرة',
        false,
      ],
      ['الحسينية', '', 33.54844, 44.41179, 'suburb', 'بغداد', true],
    ]);
    final results = index.search('مستشفى ضاري الفياط', origin);
    expect(results, hasLength(2));
    expect(results.first['point'], const LatLng(33.515726, 44.39175));
    expect(index.search('الحسينيه', origin, areasOnly: true), hasLength(1));
    expect(index.search('مطعم غير موجود', origin), isEmpty);
  });
  test(
    'bundled Iraq data finds the hospital in the screenshot even with provider outage',
    () async {
      final watch = Stopwatch()..start();
      await IraqPlaces.shared.warmUp();
      final warm = watch.elapsedMilliseconds;
      var requests = 0;
      final places = DevicePlaces(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 503);
        }),
      );
      for (final query in [
        'مستشفى الشهيد ضاري الفياط',
        'مستشفى الشهيد ضاري الفياض',
        'ضاري الفياض',
      ]) {
        final found = await places.find(query, origin);
        expect(found, isNotEmpty, reason: query);
        expect(found.first.label, contains('ضاري'));
        expect(
          const Distance().as(
            LengthUnit.Meter,
            found.first.point,
            const LatLng(33.515726, 44.39175),
          ),
          lessThan(200),
        );
      }
      expect(requests, 0);
      print(
        'Iraq place index cold load ${warm}ms, three searches ${watch.elapsedMilliseconds - warm}ms',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
  test('unresolved area does not discard a valid nearby place', () async {
    final places = StubPlaces(
      (q, area) async => !area && q == 'مستشفي الامير'
          ? [
              {
                'title': 'مستشفى الأمير',
                'label': 'مستشفى الأمير',
                'point': origin,
                'area': false,
              },
            ]
          : [],
      MockClient(
        (_) async => http.Response(
          '{"features":[]}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final found = await places.find('الحي الجديد مستشفى الامير', origin);
    expect(found, hasLength(1));
    expect(found.single.label, 'مستشفى الأمير');
  });
  test(
    'provider outage remains an unavailable-search error instead of a false no-results claim',
    () async {
      final places = StubPlaces(
        (_, _) async => [],
        MockClient((_) async => http.Response('{}', 503)),
      );
      await expectLater(
        places.find('مكان للتجربة', origin),
        throwsA(isA<StateError>()),
      );
    },
  );
}
