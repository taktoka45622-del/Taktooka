import '../vector_map_tiles.dart';

class TileProviders {
  final Map<String, VectorTileProvider> tileProviderBySource;

  const TileProviders(this.tileProviderBySource);

  VectorTileProvider get(String source) {
    final provider = tileProviderBySource[source];
    if (provider == null) {
      throw 'no VectorTileProvider for source $source';
    }
    return provider;
  }
}
