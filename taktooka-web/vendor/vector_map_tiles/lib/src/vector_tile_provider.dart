import 'dart:typed_data';

import '../vector_map_tiles.dart';

enum TileProviderType {
  vector,
  raster,

// ignore: constant_identifier_names
  raster_dem
}

abstract class VectorTileProvider {
  Future<Uint8List> provide(TileIdentity tile);

  int get maximumZoom;

  int get minimumZoom;

  TileOffset get tileOffset;

  TileProviderType get type => TileProviderType.vector;
}
