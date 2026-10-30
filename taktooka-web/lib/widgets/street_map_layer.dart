import 'package:flutter_map/flutter_map.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:taktooka/core/map_tile_warmup.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart' as vector;
import 'package:vector_map_tiles/src/style/uri_mapper.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as renderer;

import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/core/map_config.dart';
import 'package:taktooka/core/poi_map_style.dart';
import 'package:taktooka/services/poi_sprites.dart';
import 'package:taktooka/services/persistent_map_client.dart';
import 'package:taktooka/services/persistent_vector_provider.dart';

class StreetMapLayer extends StatefulWidget {
  const StreetMapLayer({super.key});
  static Future<vector.Style> loadStyle({
    bool dark = false,
    String language = 'ar',
  }) => _StreetMapLayerState.sharedStyle(dark: dark, language: language);
  static Future<void> warmUp() async {
    try {
      await _StreetMapLayerState.sharedStyle(
        dark: appPreferences.themeMode == ThemeMode.dark,
        language: appPreferences.language,
      );
    } catch (_) {}
  }

  static final _tileWarmup = MapTileWarmup();
  static Future<void>? _areaWarm;
  static Future<void> warmAround(
    double latitude,
    double longitude, {
    required bool Function() active,
  }) {
    return _areaWarm ??= _warmAround(latitude, longitude, active).whenComplete(
      () {
        _areaWarm = null;
      },
    );
  }

  static Future<void> _warmAround(
    double latitude,
    double longitude,
    bool Function() active,
  ) async {
    if (!active()) return;
    try {
      final style = await loadStyle(
        dark: appPreferences.themeMode == ThemeMode.dark,
        language: appPreferences.language,
      );
      if (!active()) return;
      final loads = <Future<void> Function()>[];
      final keys = <String>[];
      for (final entry
          in style.providers.tileProviderBySource.entries
              .where((e) => e.value.type == vector.TileProviderType.vector)
              .take(2)) {
        final provider = entry.value;
        final tiles = mapWarmupTiles(
          latitude,
          longitude,
          provider.minimumZoom,
          provider.maximumZoom,
        );
        if (tiles.isEmpty) continue;
        keys.add('${entry.key}:${tiles.first.key}');
        for (final tile in tiles) {
          loads.add(() async {
            await provider
                .provide(vector.TileIdentity(tile.z, tile.x, tile.y))
                .timeout(const Duration(seconds: 6));
          });
        }
      }
      await _tileWarmup.run(keys.join('|'), loads, active: active);
    } catch (_) {}
  }

  @override
  State<StreetMapLayer> createState() => _StreetMapLayerState();
}

class _StreetMapLayerState extends State<StreetMapLayer> {
  static final _cachedStyles = <String, Future<vector.Style>>{};
  static Future<List<dynamic>>? _resources;
  static Future<vector.SpriteStyle>? _sprites;
  static Future<List<dynamic>> resources(String uri) =>
      _resources ??= _readResources(uri).catchError((Object error) {
        _resources = null;
        throw error;
      });

  static Future<http.Response> _get(String uri) async {
    final response = await PersistentMapClient.shared
        .get(Uri.parse(uri))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw StateError('MAP_UNAVAILABLE');
    return response;
  }

  static Future<List<dynamic>> _readResources(String uri) async {
    final response = await _get(uri);
    final document = jsonDecode(response.body) as Map<String, dynamic>;
    final mapper = StyleUriMapper(key: mapboxToken);
    final sourceEntries = (document['sources'] as Map).entries.toList();
    final providersFuture = Future.wait(
      sourceEntries.map((entry) async {
        final config = Map<String, dynamic>.from(entry.value as Map);
        final types = vector.TileProviderType.values.where(
          (type) => type.name.replaceAll('_', '-') == config['type'],
        );
        if (types.isEmpty) return null;
        final sourceUrl = config['url'] as String?;
        final metadata = sourceUrl == null
            ? config
            : jsonDecode((await _get(mapper.mapSource(uri, sourceUrl))).body)
                  as Map;
        final tiles = metadata['tiles'] as List?;
        if (tiles == null || tiles.isEmpty) return null;
        return MapEntry(
          '${entry.key}',
          PersistentVectorProvider(
            type: types.first,
            urlTemplate: mapper.mapTiles('${tiles.first}'),
            minimumZoom: (metadata['minzoom'] as num?)?.toInt() ?? 1,
            maximumZoom: (metadata['maxzoom'] as num?)?.toInt() ?? 14,
          ),
        );
      }),
    );
    final spritesFuture = () async {
      final sprite = document['sprite'];
      if (sprite is! String || sprite.isEmpty) return null;
      for (final location in mapper.mapSprite(uri, sprite)) {
        try {
          final responses = await Future.wait([
            _get(location.json),
            _get(location.image),
          ]);
          final bytes = responses[1].bodyBytes;
          return vector.SpriteStyle(
            index: renderer.SpriteIndexReader().read(
              jsonDecode(responses[0].body),
            ),
            atlasProvider: () async => bytes,
          );
        } catch (_) {}
      }
      return null;
    }();
    final results = await Future.wait<dynamic>([
      providersFuture,
      spritesFuture,
    ]);
    final providers = <String, vector.VectorTileProvider>{};
    for (final entry in results[0] as List) {
      if (entry is MapEntry<String, vector.NetworkVectorTileProvider>) {
        providers[entry.key] = entry.value;
      }
    }
    if (providers.isEmpty) throw StateError('MAP_UNAVAILABLE');
    return [vector.TileProviders(providers), results[1], response];
  }

  String? _appearance;
  late Future<vector.Style> _style;
  static Future<vector.Style> sharedStyle({
    bool dark = false,
    String language = 'ar',
  }) {
    final key = '$dark:$language';
    return _cachedStyles[key] ??= _load(dark, language).catchError((
      Object error,
    ) {
      _cachedStyles.remove(key);
      throw error;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final language = PreferencesScope.of(context).language;
    final key = '$dark:$language';
    if (_appearance != key) {
      _appearance = key;
      _style = sharedStyle(dark: dark, language: language);
    }
  }

  static Future<vector.Style> _load(bool dark, String language) async {
    await ensureMapConfiguration();
    final uri =
        'https://api.mapbox.com/styles/v1/$mapboxStyle?access_token=$mapboxToken';
    final results = await resources(uri);
    final providers = results[0] as vector.TileProviders;
    final baseSprites = results[1] as vector.SpriteStyle?;
    final response = results[2] as http.Response;
    if (response.statusCode != 200) throw StateError('MAP_UNAVAILABLE');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    json['id'] = 'taktooka-${dark ? 'dark' : 'light'}-$language';
    final layers = (json['layers'] as List).cast<Map<String, dynamic>>();
    json['layers'] = layers
        .where((layer) {
          return layer['type'] != 'fill-extrusion';
        })
        .map((layer) {
          final id = '${layer['id']}'.toLowerCase();
          final paint = Map<String, dynamic>.from(layer['paint'] as Map? ?? {});
          if (layer['type'] == 'background')
            paint['background-color'] = '#f1efef';
          if (layer['type'] == 'fill' &&
              (id.contains('building') ||
                  layer['source-layer'] == 'building')) {
            paint['fill-color'] = dark ? '#333842' : '#e7e7e7';
            paint['fill-opacity'] = 1;
          }
          if (layer['type'] == 'fill' && id.contains('water'))
            paint['fill-color'] = dark ? '#183744' : '#86d1e0';
          if (layer['type'] == 'fill' &&
              (id.contains('park') || id.contains('landuse')))
            paint['fill-color'] = dark ? '#263d33' : '#d3e7d2';
          if (layer['type'] == 'line' &&
              id.contains('road') &&
              !id.contains('label')) {
            paint['line-color'] = dark ? '#555e6e' : '#ffffff';
          }
          if (layer['type'] == 'symbol') {
            final layout = Map<String, dynamic>.from(
              layer['layout'] as Map? ?? {},
            );
            if (layout.containsKey('text-field')) {
              layout['text-font'] = ['Cairo'];
              layout['text-field'] = mapNameExpression(language);
              paint['text-color'] = dark ? '#e0e5ec' : '#787b83';
              paint['text-halo-color'] = dark ? '#20252d' : '#f1efef';
              paint['text-halo-width'] = 1.5;
              layout['text-letter-spacing'] = 0;
              if (layer['source-layer'] == 'poi_label') {
                layer['minzoom'] = 13;
                layer['filter'] = poiVisibilityFilter();
                layout['text-allow-overlap'] = false;
                layout['icon-allow-overlap'] = false;
                layout['text-size'] = [
                  'step',
                  ['zoom'],
                  13,
                  16,
                  14,
                  18,
                  15,
                ];
                paint['text-color'] = dark
                    ? '#f0e7c8'
                    : poiStyleValue(icon: false);
                paint['text-halo-color'] = dark ? '#20252d' : '#ffffff';
                paint['text-halo-width'] = 2;
                layout['text-max-width'] = 20;
                layout['text-padding'] = 3;
                layout['icon-padding'] = 2;
                layout['text-anchor'] = 'top';
                layout['icon-anchor'] = 'bottom';
                layout['icon-size'] = [
                  'step',
                  ['zoom'],
                  0.75,
                  16,
                  0.85,
                  18,
                  0.95,
                ];
                layout['icon-image'] = poiStyleValue(icon: true);
              }
              if (layer['source-layer'] == 'road') {
                layer['filter'] = [
                  'any',
                  ['has', 'name_ar'],
                  ['has', 'name'],
                ];
                layout['text-size'] = [
                  'step',
                  ['zoom'],
                  12,
                  16,
                  14,
                  18,
                  15,
                ];
                paint['text-color'] = dark ? '#e0e5ec' : '#515862';
                paint['text-halo-color'] = dark ? '#20252d' : '#ffffff';
                paint['text-halo-width'] = 2;
              }
            }
            layer['layout'] = layout;
          }
          if (dark && layer['type'] == 'background')
            paint['background-color'] = '#20252d';
          layer['paint'] = paint;
          return layer;
        })
        .toList();
    final orderedLayers = (json['layers'] as List).cast<Map<String, dynamic>>();
    final places = orderedLayers
        .where((layer) => layer['source-layer'] == 'poi_label')
        .toList();
    orderedLayers.removeWhere((layer) => layer['source-layer'] == 'poi_label');
    final firstSymbol = orderedLayers.indexWhere(
      (layer) => layer['type'] == 'symbol',
    );
    orderedLayers.insertAll(
      firstSymbol < 0 ? orderedLayers.length : firstSymbol,
      places,
    );
    return vector.Style(
      theme: renderer.ThemeReader().read(json),
      providers: providers,
      sprites: await (_sprites ??= buildPoiSprites(baseSprites).catchError((
        Object error,
      ) {
        _sprites = null;
        throw error;
      })),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<vector.Style>(
    future: _style,
    builder: (context, snapshot) {
      final style = snapshot.data;
      if (style != null)
        return vector.VectorTileLayer(
          theme: style.theme,
          tileProviders: style.providers,
          sprites: style.sprites,
          tileOffset: vector.TileOffset.mapbox,
          layerMode: vector.VectorTileLayerMode.raster,
          maximumZoom: 20,
          maximumTileSubstitutionDifference: 3,
          memoryTileDataCacheMaxSize: 64,
          memoryTileCacheMaxSize: 32 * 1024 * 1024,
          fileCacheMaximumSizeInBytes: 80 * 1024 * 1024,
        );
      return Stack(
        children: [
          ColorFiltered(
            colorFilter: Theme.of(context).brightness == Brightness.dark
                ? const ColorFilter.matrix([
                    -0.8,
                    0,
                    0,
                    0,
                    230,
                    0,
                    -0.8,
                    0,
                    0,
                    233,
                    0,
                    0,
                    -0.8,
                    0,
                    240,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ])
                : const ColorFilter.mode(Colors.transparent, BlendMode.srcOver),
            child: TileLayer(
              urlTemplate: mapTileUrl,
              tileProvider: NetworkTileProvider(
                httpClient: PersistentMapClient.shared,
                cachingProvider: const DisabledMapCachingProvider(),
              ),
              maxNativeZoom: 20,
              maxZoom: 20,
              userAgentPackageName: 'com.taktooka.app',
            ),
          ),
          if (snapshot.hasError)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Center(
                child: Card(
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _style = sharedStyle(
                        dark: Theme.of(context).brightness == Brightness.dark,
                        language: PreferencesScope.of(context).language,
                      ),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const AppText('تعذر تحميل الخريطة، إعادة المحاولة'),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
