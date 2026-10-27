import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String mapboxToken = const String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
const mapboxStyle = String.fromEnvironment(
  'MAPBOX_STYLE',
  defaultValue: 'mapbox/light-v11',
);
String get mapTileUrl =>
    'https://api.mapbox.com/styles/v1/$mapboxStyle/tiles/256/{z}/{x}/{y}@2x?access_token=$mapboxToken';
Future<void>? _configuration;
Future<void> ensureMapConfiguration() async {
  if (!kIsWeb || mapboxToken.isNotEmpty) return;
  final pending = _configuration;
  if (pending != null) return pending;
  final request = () async {
    final result = await Supabase.instance.client.functions.invoke(
      'taktooka-web-map-config',
    );
    final token = result.data is Map ? result.data['public_token'] : null;
    if (token is! String || !token.startsWith('pk.'))
      throw StateError('MAP_UNAVAILABLE');
    mapboxToken = token;
  }();
  _configuration = request;
  try {
    await request;
  } finally {
    if (identical(_configuration, request)) _configuration = null;
  }
}
