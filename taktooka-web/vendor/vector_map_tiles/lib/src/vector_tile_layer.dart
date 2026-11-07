import 'package:flutter/material.dart' hide Theme;
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

import 'extensions.dart';
import 'grid/grid_layer.dart';
import 'io/io.dart';
import 'options.dart';
import 'style/style.dart';
import 'tile_offset.dart';
import 'tile_providers.dart';
import 'vector_tile_layer_mode.dart';
import 'vector_tile_provider.dart';

class VectorTileLayer extends StatelessWidget {
  final TileProviders tileProviders;

  final Theme theme;

  final SpriteStyle? sprites;

  final Duration fileCacheTtl;

  static const defaultCacheTtl = Duration(days: 30);

  final int fileCacheMaximumSizeInBytes;

  static const defaultCacheMaxSize = 50 * 1024 * 1024;

  final int memoryTileCacheMaxSize;

  static const defaultTileCacheMaxSize = 1024 * 1024 * 10;

  final int memoryTileDataCacheMaxSize;

  static const defaultTileDataCacheMaxSize = 20;

  final int textCacheMaxSize;

  static const defaultTextCacheMaxSize = 100;

  final bool showTileDebugInfo;

  final bool logCacheStats;

  final Theme? backgroundTheme;

  final Duration tileDelay;

  final int concurrency;

  final int maximumTileSubstitutionDifference;

  static const defaultMaxTileSubstitutionDifference = 2;

  static const defaultConcurrency = 4;

  final TileOffset tileOffset;

  final VectorTileLayerMode layerMode;

  final double? maximumZoom;

  final Future<Directory> Function()? cacheFolder;

  VectorTileLayer(
      {super.key,
      required this.tileProviders,
      required this.theme,
      this.sprites,
      this.fileCacheTtl = defaultCacheTtl,
      this.memoryTileCacheMaxSize = defaultTileCacheMaxSize,
      this.memoryTileDataCacheMaxSize = defaultTileDataCacheMaxSize,
      this.fileCacheMaximumSizeInBytes = defaultCacheMaxSize,
      this.textCacheMaxSize = defaultTextCacheMaxSize,
      this.concurrency = defaultConcurrency,
      this.tileOffset = TileOffset.DEFAULT,
      this.maximumTileSubstitutionDifference =
          defaultMaxTileSubstitutionDifference,
      this.backgroundTheme,
      this.showTileDebugInfo = false,
      this.logCacheStats = false,
      this.layerMode = VectorTileLayerMode.raster,
      this.maximumZoom,
      this.tileDelay = const Duration(milliseconds: 0),
      this.cacheFolder}) {
    assert(concurrency >= 0 && concurrency <= 100);
    final providers = theme.tileSources
        .map((source) => tileProviders.tileProviderBySource[source])
        .whereType<VectorTileProvider>();
    assert(
        providers.isNotEmpty,
        '''
tileProviders must provide at least one provider that matches the given theme. 
Usually this is an indication that TileProviders in the code doesn't match the sources
required by the theme. 
The theme uses the following sources: ${theme.tileSources.toList().sorted().join(', ')}.
'''
            .trim());
    assert(
        maximumTileSubstitutionDifference >= 0 &&
            maximumTileSubstitutionDifference <= 3,
        'maximumTileSubstitutionDifference must be >= 0 and <= 3');
    assert(memoryTileDataCacheMaxSize >= 0 && memoryTileDataCacheMaxSize < 100);
  }

  @override
  Widget build(BuildContext context) {
    final mapCamera = MapCamera.maybeOf(context)!;
    return VectorTileCompositeLayer(VectorTileLayerOptions(this), mapCamera);
  }
}
