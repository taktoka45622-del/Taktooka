import 'dart:math' as math;

bool restaurantWithinRange(Map restaurant, List<double>? origin) {
  final location = restaurant['location'];
  if (origin == null ||
      location is! List ||
      location.length < 2 ||
      location[0] is! num ||
      location[1] is! num)
    return false;
  final lat = (location[0] as num).toDouble();
  final lon = (location[1] as num).toDouble();
  if (!lat.isFinite || !lon.isFinite) return false;
  const rad = math.pi / 180;
  final a =
      math.pow(math.sin((lat - origin[0]) * rad / 2), 2) +
      math.cos(origin[0] * rad) *
          math.cos(lat * rad) *
          math.pow(math.sin((lon - origin[1]) * rad / 2), 2);
  final distance =
      6371000 *
      2 *
      math.atan2(math.sqrt(a.clamp(0, 1)), math.sqrt((1 - a).clamp(0, 1)));
  return distance <= 15000;
}
