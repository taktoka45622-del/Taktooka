import 'dart:math' as math;

class LocalRouteMetrics {
  static double meters(Map<String, dynamic> geometry) {
    final points = geometry['coordinates'];
    if (geometry['type'] != 'LineString' ||
        points is! List ||
        points.length < 2) {
      throw StateError('ROUTE_UNAVAILABLE');
    }
    double radians(num v) => v.toDouble() * math.pi / 180;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1] as List, b = points[i] as List;
      final lat = radians((b[1] as num) - (a[1] as num));
      final lon = radians((b[0] as num) - (a[0] as num));
      final h =
          math.pow(math.sin(lat / 2), 2) +
          math.cos(radians(a[1] as num)) *
              math.cos(radians(b[1] as num)) *
              math.pow(math.sin(lon / 2), 2);
      total +=
          6371008.8 *
          2 *
          math.atan2(math.sqrt(h.clamp(0, 1)), math.sqrt((1 - h).clamp(0, 1)));
    }
    if (!total.isFinite || total <= 0) throw StateError('ROUTE_UNAVAILABLE');
    return total;
  }
}
