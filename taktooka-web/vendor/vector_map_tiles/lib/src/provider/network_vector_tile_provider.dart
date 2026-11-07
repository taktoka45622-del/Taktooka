import 'dart:typed_data';

import 'package:http/http.dart';
import 'package:http/retry.dart';

import '../../vector_map_tiles.dart';

class NetworkVectorTileProvider extends VectorTileProvider {
  @override
  final TileProviderType type;
  final _UrlProvider _urlProvider;
  final Map<String, String>? httpHeaders;

  @override
  final int maximumZoom;

  @override
  final int minimumZoom;
  @override
  TileOffset tileOffset;

  NetworkVectorTileProvider(
      {required String urlTemplate,
      this.type = TileProviderType.vector,
      this.httpHeaders,
      this.tileOffset = TileOffset.DEFAULT,
      this.maximumZoom = 16,
      this.minimumZoom = 1})
      : _urlProvider = _UrlProvider(urlTemplate);

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    _checkTile(tile);
    final uri = Uri.parse(_urlProvider.url(tile));
    final client = RetryClient(Client());
    try {
      final response = await client.get(uri, headers: httpHeaders);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      final logSafeUri = uri.toString().split(RegExp(r'\?')).first;
      throw ProviderException(
          message:
              'Cannot retrieve tile: HTTP ${response.statusCode}: $logSafeUri ${response.body}',
          statusCode: response.statusCode,
          retryable: _isRetryable(response.statusCode)
              ? Retryable.retry
              : Retryable.none);
    } on ClientException catch (e) {
      throw ProviderException(message: e.message, retryable: Retryable.retry);
    } finally {
      client.close();
    }
  }

  void _checkTile(TileIdentity tile) {
    if (tile.z > maximumZoom || tile.z < minimumZoom || !tile.isValid()) {
      throw ProviderException(
          message: 'Invalid tile coordinates $tile',
          retryable: Retryable.none,
          statusCode: 400);
    }
  }

  _isRetryable(int statusCode) => statusCode == 503 || statusCode == 408;
}

class _UrlProvider {
  final String urlTemplate;

  _UrlProvider(this.urlTemplate);

  String url(TileIdentity identity) {
    return urlTemplate.replaceAllMapped(RegExp(r'\{(x|y|z)\}'), (match) {
      switch (match.group(1)) {
        case 'x':
          return identity.x.toInt().toString();
        case 'y':
          return identity.y.toInt().toString();
        case 'z':
          return identity.z.toInt().toString();
        default:
          throw Exception(
              'unexpected url template: $urlTemplate - token ${match.group(1)} is not supported');
      }
    });
  }
}
