import 'dart:typed_data';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vector;
import 'package:taktooka/services/persistent_map_client.dart';

class PersistentVectorProvider extends vector.NetworkVectorTileProvider {
  final String template;
  PersistentVectorProvider({
    required String urlTemplate,
    required super.type,
    required super.minimumZoom,
    required super.maximumZoom,
  }) : template = urlTemplate,
       super(urlTemplate: urlTemplate);

  @override
  Future<Uint8List> provide(vector.TileIdentity tile) async {
    if (!tile.isValid() || tile.z < minimumZoom || tile.z > maximumZoom) {
      throw StateError('INVALID_MAP_TILE');
    }
    final url = template
        .replaceAll('{z}', '${tile.z}')
        .replaceAll('{x}', '${tile.x}')
        .replaceAll('{y}', '${tile.y}');
    try {
      final response = await PersistentMapClient.shared.get(Uri.parse(url));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw vector.ProviderException(
          message: 'MAP_UNAVAILABLE',
          statusCode: response.statusCode,
          retryable:
              [408, 429, 500, 502, 503, 504].contains(response.statusCode)
              ? vector.Retryable.retry
              : vector.Retryable.none,
        );
      }
      return response.bodyBytes;
    } on vector.ProviderException {
      rethrow;
    } catch (_) {
      throw vector.ProviderException(
        message: 'MAP_UNAVAILABLE',
        retryable: vector.Retryable.retry,
      );
    }
  }
}
