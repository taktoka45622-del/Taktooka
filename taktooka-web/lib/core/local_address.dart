import 'dart:math' as math;

class LocalAddress {
  static String _clean(dynamic v) =>
      v is String ? v.trim().substring(0, math.min(100, v.trim().length)) : '';
  static double _meters(List<double> p, dynamic xy) {
    if (xy is! List ||
        xy.length != 2 ||
        xy.any((v) => v is! num || !v.isFinite))
      return double.infinity;
    final a = ((xy[1] as num) - p[0]) * 111320,
        b = ((xy[0] as num) - p[1]) * 111320 * math.cos(p[0] * math.pi / 180);
    return math.sqrt(a * a + b * b);
  }

  static Map<String, dynamic> resolve(
    Map data,
    String road,
    Map nearby,
    List<double> point,
    Map local,
  ) {
    final features = data['features'] as List? ?? [];
    Map props(String type) {
      for (final f in features) {
        final p = f['properties'] as Map? ?? {};
        if (p['feature_type'] == type) return p;
      }
      return {};
    }

    final streetProps = props('street');
    final context =
        (streetProps.isEmpty
                ? features.isEmpty
                      ? <dynamic, dynamic>{}
                      : features.first['properties'] as Map? ?? {}
                : streetProps)['context']
            as Map? ??
        {};
    String value(String type) {
      final p = props(type), c = context[type] as Map? ?? {};
      return _clean(
        c['name_preferred'] ?? c['name'] ?? p['name_preferred'] ?? p['name'],
      );
    }

    final locals = <Map<String, dynamic>>[];
    for (final f in local['features'] as List? ?? []) {
      final p = f['properties'] as Map? ?? {};
      final distance = _meters(point, f['geometry']?['coordinates']);
      if ('${p['countrycode']}'.toLowerCase() == 'iq' && distance <= 1000)
        locals.add({'props': p, 'distance': distance});
    }
    locals.sort(
      (a, b) => (a['distance'] as double).compareTo(b['distance'] as double),
    );
    final address = locals.isEmpty
        ? <dynamic, dynamic>{}
        : locals.first['props'] as Map;
    String first(List<String> values) =>
        values.firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final province = first([
      value('region'),
      _clean(address['state']),
      value('place'),
    ]);
    final district = first([
      _clean(address['district']),
      value('locality'),
      value('district'),
      _clean(address['city']),
    ]);
    final area = [
      district,
      value('neighborhood'),
    ].where((s) => s.isNotEmpty && s != province).toSet().join('، ');
    final candidates = <Map<String, dynamic>>[];
    for (final f in nearby['features'] as List? ?? []) {
      final p = f['properties'] as Map? ?? {}, q = p['tilequery'] as Map? ?? {};
      final distance = q['distance'], name = _clean(p['name_ar'] ?? p['name']);
      if (name.isNotEmpty &&
          distance is num &&
          distance.isFinite &&
          distance >= 0 &&
          distance <= 500 &&
          ['road', 'poi_label'].contains(q['layer']))
        candidates.add({
          'name': name,
          'distance': distance,
          'layer': q['layer'],
        });
    }
    for (final f in locals) {
      final p = f['props'] as Map, name = _clean((f['props'] as Map)['name']);
      if (name.isNotEmpty &&
          (f['distance'] as num) <= 500 &&
          !['place', 'boundary', 'highway'].contains(p['osm_key']))
        candidates.add({
          'name': name,
          'distance': f['distance'],
          'layer': 'poi_label',
        });
    }
    candidates.sort(
      (a, b) => (a['distance'] as num).compareTo(b['distance'] as num),
    );
    Map<String, dynamic>? find(bool Function(Map<String, dynamic>) predicate) {
      for (final c in candidates) {
        if (predicate(c)) return c;
      }
      return null;
    }

    dynamic streetGeometry;
    for (final f in features) {
      if (f['properties']?['feature_type'] == 'street') {
        streetGeometry = f['geometry']?['coordinates'];
        break;
      }
    }
    final street = first([
      _clean(road),
      _meters(point, streetGeometry) <= 25
          ? _clean(streetProps['name_preferred'] ?? streetProps['name'])
          : '',
      find((c) => c['layer'] == 'road' && (c['distance'] as num) <= 25)?['name']
              as String? ??
          '',
    ]);
    final landmark = find(
      (c) => c['layer'] == 'poi_label' && c['name'] != street,
    );
    final closest = find((c) => c['name'] != province && c['name'] != district);
    final parts = [
      province,
      area,
      street,
    ].where((s) => s.isNotEmpty).toSet().toList();
    final detail = street.isNotEmpty
        ? landmark != null && (landmark['distance'] as num) <= 120
              ? landmark['name'] as String
              : ''
        : closest?['name'] as String? ?? '';
    if (detail.isNotEmpty &&
        !parts.contains(detail) &&
        !area.split('، ').contains(detail))
      parts.add('قرب $detail');
    final name = parts.join('، ');
    return {
      'province': province,
      'area': area,
      'street': street,
      'landmark': landmark?['name'] ?? '',
      'name': name.substring(0, math.min(240, name.length)),
      'address_complete':
          province.isNotEmpty &&
          area.isNotEmpty &&
          (street.isNotEmpty || detail.isNotEmpty),
    };
  }
}
