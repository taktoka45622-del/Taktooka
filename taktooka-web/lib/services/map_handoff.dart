import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

LatLng? _coordinates(String? value) {
  if (value == null) return null;
  final match = RegExp(
    r'^\s*([-+]?\d+(?:\.\d+)?)\s*,\s*([-+]?\d+(?:\.\d+)?)(?:\s|\(|$)',
  ).firstMatch(value);
  if (match == null) return null;
  final lat = double.tryParse(match[1]!);
  final lng = double.tryParse(match[2]!);
  if (lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat < 29 ||
      lat > 38 ||
      lng < 38 ||
      lng > 49)
    return null;
  return LatLng(lat, lng);
}

bool isMapHost(String host) {
  final h = host.toLowerCase();
  return h == 'maps.app.goo.gl' ||
      h == 'goo.gl' ||
      h == 'maps.google.com' ||
      h == 'google.com' ||
      h == 'www.google.com' ||
      h == 'maps.google.iq' ||
      h == 'google.iq' ||
      h == 'www.google.iq' ||
      h == 'maps.apple.com' ||
      h == 'waze.com' ||
      h == 'www.waze.com';
}

LatLng? parseSharedLocation(String text) {
  try {
    return _parseSharedLocation(text);
  } on FormatException {
    return null;
  }
}

LatLng? _parseSharedLocation(String text) {
  final raw = text.trim();
  if (raw.length > 8192) return null;
  final direct = _coordinates(raw);
  if (direct != null) return direct;
  final links = RegExp(r'''(?:https?://|geo:)[^\s<>"']+''').allMatches(raw);
  for (final match in links) {
    final uri = Uri.tryParse(match[0]!);
    if (uri == null) continue;
    if (uri.scheme == 'geo') {
      final q = _coordinates(uri.queryParameters['q']);
      if (q != null) return q;
      final p = _coordinates(uri.path);
      if (p != null) return p;
      continue;
    }
    if (!isMapHost(uri.host)) continue;
    for (final key in ['destination', 'daddr', 'q', 'query', 'll']) {
      final point = _coordinates(uri.queryParameters[key]);
      if (point != null) return point;
    }
    final decoded = Uri.decodeFull(uri.toString());
    final data = RegExp(
      r'!3d([-\d.]+)!4d([-\d.]+)',
    ).allMatches(decoded).toList();
    if (data.isNotEmpty) {
      final point = _coordinates('${data.last[1]},${data.last[2]}');
      if (point != null) return point;
    }
    final at = RegExp(r'@([-\d.]+),([-\d.]+)').firstMatch(decoded);
    if (at != null && !uri.path.contains('/place/')) {
      final point = _coordinates('${at[1]},${at[2]}');
      if (point != null) return point;
    }
  }
  return null;
}

Future<LatLng?> resolveSharedLocation(
  String text, {
  http.Client? client,
}) async {
  final direct = parseSharedLocation(text);
  if (direct != null) return direct;
  if (text.length > 8192) return null;
  final links = RegExp(r'''https?://[^\s<>"']+''').allMatches(text);
  final ownClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    for (final link in links.take(3)) {
      var uri = Uri.tryParse(link[0]!);
      if (uri == null || !isMapHost(uri.host)) continue;
      for (var hop = 0; hop < 5; hop++) {
        if (uri!.scheme != 'https' ||
            !isMapHost(uri.host) ||
            (uri.hasPort && uri.port != 443) ||
            uri.userInfo.isNotEmpty)
          break;
        final found = parseSharedLocation(uri.toString());
        if (found != null) return found;
        final request = http.Request('GET', uri)..followRedirects = false;
        final response = await httpClient
            .send(request)
            .timeout(const Duration(seconds: 6));
        final location = response.headers['location'];
        await response.stream.listen((_) {}).cancel();
        if (response.statusCode < 300 ||
            response.statusCode >= 400 ||
            location == null)
          break;
        uri = uri.resolve(location);
      }
    }
  } finally {
    if (ownClient) httpClient.close();
  }
  return null;
}

Uri? rideWazeUri(Map<String, dynamic> ride) {
  final value =
      ride[ride['status'] == 'in_progress' && ride['round_trip_stage'] != 'returning' ? 'destination' : 'pickup'];
  if (value is! List ||
      value.length != 2 ||
      value.any((n) => n is! num || !n.isFinite))
    return null;
  final lat = (value[0] as num).toDouble(), lng = (value[1] as num).toDouble();
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  return Uri.https('waze.com', '/ul', {'ll': '$lat,$lng', 'navigate': 'yes'});
}
