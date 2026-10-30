import 'dart:math' as math;

class MapTileAddress {
  final int z, x, y;
  const MapTileAddress(this.z, this.x, this.y);
  String get key => '$z/$x/$y';
}

List<MapTileAddress> nearbyMapTiles(
  double latitude,
  double longitude,
  int zoom,
) {
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude.abs() > 90 ||
      longitude.abs() > 180 ||
      zoom < 0 ||
      zoom > 18)
    return [];
  final n = 1 << zoom;
  final lat = latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  final x = ((longitude + 180) / 360 * n).floor().clamp(0, n - 1);
  final y =
      ((1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n)
          .floor()
          .clamp(0, n - 1);
  final result = <MapTileAddress>[];
  final seen = <String>{};
  for (final offset in const [
    [0, 0],
    [-1, 0],
    [1, 0],
    [0, -1],
    [0, 1],
    [-1, -1],
    [1, -1],
    [-1, 1],
    [1, 1],
  ]) {
    final row = y + offset[1];
    if (row < 0 || row >= n) continue;
    final tile = MapTileAddress(zoom, (x + offset[0]) % n, row);
    if (seen.add(tile.key)) result.add(tile);
  }
  return result;
}

List<MapTileAddress> mapWarmupTiles(
  double latitude,
  double longitude,
  int minimumZoom,
  int maximumZoom,
) {
  if (minimumZoom < 0 || maximumZoom > 18 || minimumZoom > maximumZoom)
    return [];
  final native = 16.clamp(minimumZoom, maximumZoom);
  final levels = <int>{
    native,
    (native - 3).clamp(minimumZoom, maximumZoom),
    (native - 6).clamp(minimumZoom, maximumZoom),
    5.clamp(minimumZoom, maximumZoom),
  };
  return [
    for (final zoom in levels) ...nearbyMapTiles(latitude, longitude, zoom),
  ];
}

class MapTileWarmup {
  final DateTime Function() now;
  final _nextAttempt = <String, DateTime>{};
  bool _busy = false;
  MapTileWarmup({DateTime Function()? now}) : now = now ?? DateTime.now;

  Future<void> run(
    String key,
    List<Future<void> Function()> loads, {
    required bool Function() active,
  }) async {
    if (_busy ||
        !active() ||
        loads.isEmpty ||
        (_nextAttempt[key]?.isAfter(now()) ?? false))
      return;
    _busy = true;
    if (_nextAttempt.length >= 16) _nextAttempt.remove(_nextAttempt.keys.first);
    _nextAttempt[key] = now().add(const Duration(seconds: 15));
    var cursor = 0, failed = false;
    Future<void> worker() async {
      while (active() && !failed && cursor < loads.length) {
        final load = loads[cursor++];
        try {
          await load();
        } catch (_) {
          failed = true;
        }
      }
    }

    try {
      await Future.wait([worker(), worker()]);
      if (!failed && cursor == loads.length && active())
        _nextAttempt[key] = now().add(const Duration(minutes: 15));
    } finally {
      _busy = false;
    }
  }
}
