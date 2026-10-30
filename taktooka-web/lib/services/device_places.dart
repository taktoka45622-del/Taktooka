import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:taktooka/core/map_config.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/core/place_text.dart';
import 'package:taktooka/services/iraq_places.dart';

class DevicePlaces {
  final http.Client client;
  DevicePlaces({http.Client? client}) : client = client ?? http.Client();
  static String normalize(String s) => PlaceText.normalize(s);
  static double quality(String label, String query) =>
      PlaceText.quality(label, query);
  Future<List<Map<String, dynamic>>> local(
    String query,
    LatLng origin, {
    bool areasOnly = false,
  }) async {
    try {
      return await IraqPlaces.shared.search(
        query,
        origin,
        areasOnly: areasOnly,
      );
    } catch (_) {
      return [];
    }
  }

  static const categories = [
    'مطعم',
    'مستشفي',
    'صيدليه',
    'جامع',
    'مسجد',
    'مدرسه',
    'اعداديه',
    'ثانويه',
    'كليه',
    'جامعه',
    'سوق',
    'اسواق',
    'مول',
    'محل',
    'محلات',
    'مكتب',
    'شارع',
    'محطه',
  ];
  static String _bounds(LatLng p) {
    final lat = 25000 / 111320,
        lon = 25000 / 111320 / math.cos(p.latitude * math.pi / 180);
    return '${math.max(38, p.longitude - lon)},${math.max(29, p.latitude - lat)},'
        '${math.min(49, p.longitude + lon)},${math.min(38, p.latitude + lat)}';
  }

  Future<List<Map<String, dynamic>>> _request(Uri uri, String provider) async {
    final response = await client
        .get(uri, headers: {'Accept-Language': 'ar'})
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) throw StateError('SEARCH_UNAVAILABLE');
    final data = jsonDecode(response.body) as Map;
    final rows = <Map<String, dynamic>>[];
    for (final f in data['features'] as List? ?? []) {
      final p = f['properties'] as Map? ?? {},
          xy = f['geometry']?['coordinates'];
      if (xy is! List ||
          xy.length != 2 ||
          xy.any((n) => n is! num || !n.isFinite) ||
          xy[1] < 29 ||
          xy[1] > 38 ||
          xy[0] < 38 ||
          xy[0] > 49)
        continue;
      if (provider == 'photon' && '${p['countrycode']}'.toLowerCase() != 'iq')
        continue;
      final title =
          p['name_preferred'] ?? p['name'] ?? p['street'] ?? p['city'];
      if (title is! String || title.trim().isEmpty) continue;
      final c = p['context'] as Map? ?? {};
      final parts = provider == 'photon'
          ? [title, p['state'], p['city'], p['district'], p['street']]
          : [
              title,
              c['region']?['name'],
              c['place']?['name'],
              c['locality']?['name'],
              c['neighborhood']?['name'],
              c['street']?['name'],
            ];
      rows.add({
        'title': title.trim(),
        'label': parts
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .join('، '),
        'point': LatLng((xy[1] as num).toDouble(), (xy[0] as num).toDouble()),
        'area':
            p['osm_key'] == 'place' ||
            p['osm_key'] == 'boundary' ||
            [
              'neighborhood',
              'locality',
              'place',
              'district',
              'region',
            ].contains(p['feature_type']),
      });
    }
    return rows;
  }

  static List<Map<String, dynamic>> rank(
    List<Map<String, dynamic>> rows,
    String query,
    LatLng origin,
  ) {
    double distance(Map r) =>
        const Distance().as(LengthUnit.Meter, origin, r['point'] as LatLng);
    final category = normalize(query).split(' ').any(categories.contains);
    final candidates = rows
        .where(
          (r) =>
              quality('${r['label']} ${r['aliases'] ?? ''}', query) >= .7 &&
              (!category ||
                  quality('${r['title']} ${r['aliases'] ?? ''}', query) >= .7),
        )
        .toList();
    final local = candidates.any((r) => distance(r) <= 25000);
    final q = normalize(query);
    double score(Map r) {
      final title = normalize(r['title'] as String);
      return quality('${r['title']} ${r['aliases'] ?? ''}', query) * 130 +
          quality('${r['label']} ${r['aliases'] ?? ''}', query) * 40 +
          (title == q
              ? 35
              : title.startsWith(q)
              ? 20
              : 0) -
          math.min(distance(r) / 3000, 55);
    }

    candidates.sort((a, b) {
      if (local && (distance(a) <= 25000) != (distance(b) <= 25000))
        return distance(a) <= 25000 ? -1 : 1;
      return score(b).compareTo(score(a));
    });
    final unique = <Map<String, dynamic>>[];
    for (final row in candidates) {
      if (unique.any(
        (r) =>
            normalize(r['title'] as String) ==
                normalize(row['title'] as String) &&
            const Distance().as(
                  LengthUnit.Meter,
                  r['point'] as LatLng,
                  row['point'] as LatLng,
                ) <
                110,
      ))
        continue;
      unique.add(row);
    }
    return unique.take(10).toList();
  }

  Future<List<AddressChoice>> find(String query, LatLng origin) async {
    query = query.trim().replaceAll('السوك', 'السوق');
    if (query.length < 2 || query.length > 200) return [];
    var succeeded = false;
    Future<List<Map<String, dynamic>>> get(Uri u, String provider) async {
      try {
        final rows = await _request(u, provider);
        succeeded = true;
        return rows;
      } catch (_) {
        return [];
      }
    }

    Uri mapbox(String q, LatLng p, {String? bounds, bool area = false}) =>
        Uri.https('api.mapbox.com', '/search/geocode/v6/forward', {
          'q': q,
          'country': 'iq',
          'language': 'ar',
          'limit': '10',
          'autocomplete': 'true',
          'access_token': mapboxToken,
          'proximity': '${p.longitude},${p.latitude}',
          if (bounds != null) 'bbox': bounds,
          if (area) 'types': 'neighborhood,locality,place,district,region',
        });
    Uri photon(String q, LatLng p, {String? bounds}) =>
        Uri.https('photon.komoot.io', '/api/', {
          'q': q,
          'lat': '${p.latitude}',
          'lon': '${p.longitude}',
          'limit': '20',
          'bbox': bounds ?? '38,29,49,38',
        });
    final directLocal = await local(query, origin);
    final fast = rank(directLocal, query, origin);
    if (fast.isNotEmpty &&
        const Distance().as(
              LengthUnit.Meter,
              origin,
              fast.first['point'] as LatLng,
            ) <=
            25000) {
      return fast
          .map((r) => AddressChoice(r['label'] as String, r['point'] as LatLng))
          .toList();
    }
    final words = normalize(query).split(' ');
    final marker = words.indexWhere(categories.contains);
    String? area, target;
    if (marker > 0) {
      area = words
          .take(marker)
          .join(' ')
          .replaceFirst(RegExp(r'^(?:بغداد\s+)?(?:منطقه|حي)\s+'), '');
      target = words.skip(marker).join(' ');
    } else {
      final match = RegExp(
        r'^(.+?)\s+(?:في|بمنطقه)\s+(.+)$',
      ).firstMatch(normalize(query));
      if (match != null) {
        target = match.group(1);
        area = match.group(2);
      }
    }
    var point = origin, search = query;
    if (area != null && area.isNotEmpty && target != null) {
      var areaRows = await local(area, origin, areasOnly: true);
      if (areaRows.isEmpty) {
        final groups = await Future.wait([
          get(mapbox(area, origin, area: true), 'mapbox'),
          get(photon(area, origin), 'photon'),
        ]);
        areaRows = groups.expand((g) => g).toList();
      }
      final areas = rank(
        areaRows
            .where(
              (r) =>
                  r['area'] == true &&
                  quality(r['title'] as String, area!) >= .85,
            )
            .toList(),
        area,
        origin,
      );
      if (areas.isNotEmpty) point = areas.first['point'] as LatLng;
      search = target;
    }
    final scopedLocal = [...directLocal, ...await local(search, point)];
    final localResults = rank(scopedLocal, search, point);
    if (localResults.isNotEmpty &&
        const Distance().as(
              LengthUnit.Meter,
              point,
              localResults.first['point'] as LatLng,
            ) <=
            25000) {
      return localResults
          .map((r) => AddressChoice(r['label'] as String, r['point'] as LatLng))
          .toList();
    }
    final full = area == null ? search : '$search $area';
    final groups = await Future.wait([
      get(
        mapbox(full, point, bounds: area == null ? null : _bounds(point)),
        'mapbox',
      ),
      get(
        photon(full, point, bounds: area == null ? null : _bounds(point)),
        'photon',
      ),
      get(photon(search, point, bounds: _bounds(point)), 'photon'),
    ]);
    final rows = [...scopedLocal, ...groups.expand((g) => g)];
    final searchWords = search.split(' ');
    if (searchWords.last.length >= 5 &&
        !rows.any(
          (r) =>
              quality(r['title'] as String, search) >= .7 &&
              const Distance().as(
                    LengthUnit.Meter,
                    point,
                    r['point'] as LatLng,
                  ) <=
                  25000,
        )) {
      final last = searchWords.last;
      searchWords[searchWords.length - 1] = last.substring(0, last.length - 2);
      rows.addAll(
        await get(
          photon(searchWords.join(' '), point, bounds: _bounds(point)),
          'photon',
        ),
      );
    }
    if (!succeeded && rows.isEmpty) throw StateError('SEARCH_UNAVAILABLE');
    return rank(rows, search, point)
        .map((r) => AddressChoice(r['label'] as String, r['point'] as LatLng))
        .toList();
  }
}
