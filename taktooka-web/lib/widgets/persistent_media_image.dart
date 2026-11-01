import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:taktooka/services/media_store.dart';

class FoodMediaCache {
  static final shared = FoodMediaCache();
  final http.Client client;
  final Map<String, Future<Uint8List>> pending = {};
  final Map<String, Uint8List> memory = {};
  FoodMediaCache({http.Client? client}) : client = client ?? http.Client();
  String key(String url) => sha256.convert(utf8.encode(url)).toString();
  Future<Uint8List> load(String url) =>
      pending[url] ??= _load(url).whenComplete(() {
        pending.remove(url);
      });
  Future<Uint8List> _load(String url) async {
    if (memory[url] case final Uint8List bytes) return bytes;
    final saved = await MediaStore.read(key(url));
    if (saved != null && saved.isNotEmpty) {
      remember(url, saved);
      return saved;
    }
    final response = await client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty)
      throw StateError('IMAGE_UNAVAILABLE');
    await MediaStore.write(key(url), response.bodyBytes);
    remember(url, response.bodyBytes);
    return response.bodyBytes;
  }

  void remember(String url, Uint8List bytes) {
    while (memory.isNotEmpty &&
        (memory.length >= 80 ||
            memory.values.fold<int>(0, (n, b) => n + b.lengthInBytes) +
                    bytes.lengthInBytes >
                32 * 1024 * 1024)) {
      memory.remove(memory.keys.first);
    }
    memory[url] = bytes;
  }

  Future<void> remove(String url) async {
    memory.remove(url);
    await MediaStore.remove(key(url));
    PersistentMediaProvider(url).evict();
  }
}

class PersistentMediaProvider extends ImageProvider<PersistentMediaProvider> {
  final String url;
  const PersistentMediaProvider(this.url);
  @override
  Future<PersistentMediaProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    PersistentMediaProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _decode(decode), scale: 1);
  Future<ui.Codec> _decode(ImageDecoderCallback decode) async => decode(
    await ui.ImmutableBuffer.fromUint8List(
      await FoodMediaCache.shared.load(url),
    ),
  );
  @override
  bool operator ==(Object other) =>
      other is PersistentMediaProvider && other.url == url;
  @override
  int get hashCode => url.hashCode;
}

class PersistentMediaImage extends StatelessWidget {
  final String url;
  final double? height, width;
  final BoxFit? fit;
  final int? cacheWidth;
  final String? semanticLabel;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final WebHtmlElementStrategy? webHtmlElementStrategy;
  const PersistentMediaImage(
    this.url, {
    super.key,
    this.height,
    this.width,
    this.fit,
    this.cacheWidth,
    this.semanticLabel,
    this.errorBuilder,
    this.loadingBuilder,
    this.webHtmlElementStrategy,
  });
  @override
  Widget build(BuildContext context) => Image(
    image: ResizeImage.resizeIfNeeded(
      cacheWidth,
      null,
      PersistentMediaProvider(url),
    ),
    height: height,
    width: width,
    fit: fit,
    gaplessPlayback: true,
    semanticLabel: semanticLabel,
    errorBuilder: errorBuilder,
    loadingBuilder: loadingBuilder,
  );
}
