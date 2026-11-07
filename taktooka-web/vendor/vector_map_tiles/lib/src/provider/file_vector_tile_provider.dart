import 'dart:io';
import 'dart:typed_data';

import '../../vector_map_tiles.dart';

class FileVectorTileProvider extends VectorTileProvider {
  @override
  final TileProviderType type;

  final String extension;

  final String root;

  @override
  final int maximumZoom;

  @override
  final int minimumZoom;
  @override
  final TileOffset tileOffset;

  FileVectorTileProvider(
      {required this.root,
      required this.extension,
      required this.type,
      this.tileOffset = TileOffset.DEFAULT,
      required this.maximumZoom,
      required this.minimumZoom});

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    File file = File('$root/${tile.z}/${tile.x}/${tile.y}.$extension');
    try {
      return await file.readAsBytes();
    } catch (e) {
      throw ProviderException(
          message: "$e", retryable: Retryable.none, statusCode: 404);
    }
  }
}
