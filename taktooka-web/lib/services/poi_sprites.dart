import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vector;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as renderer;
import 'package:taktooka/core/poi_map_style.dart';

Future<vector.SpriteStyle> buildPoiSprites(vector.SpriteStyle? base) async {
  const cell = 64;
  const icons = <String, IconData>{
    'school': Icons.school_rounded,
    'college': Icons.account_balance_rounded,
    'mosque': Icons.mosque_rounded,
    'market': Icons.shopping_basket_rounded,
    'hospital': Icons.local_hospital_rounded,
    'pharmacy': Icons.local_pharmacy_rounded,
    'mall': Icons.shopping_bag_rounded,
    'shop': Icons.storefront_rounded,
    'food': Icons.restaurant_rounded,
    'place': Icons.location_on_rounded,
  };
  ui.Image? original;
  final index = <String, renderer.Sprite>{};
  if (base != null) {
    try {
      final codec = await ui.instantiateImageCodec(
        await base.atlasProvider().timeout(const Duration(seconds: 3)),
      );
      try {
        original = (await codec.getNextFrame()).image;
        index.addAll(base.index.spriteByName);
      } finally {
        codec.dispose();
      }
    } catch (_) {}
  }
  final width = (original?.width ?? 0) > cell * icons.length
      ? original!.width
      : cell * icons.length;
  final top = original?.height ?? 0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (original != null) canvas.drawImage(original, Offset.zero, Paint());
  var column = 0;
  for (final entry in icons.entries) {
    final center = Offset(column * cell + cell / 2, top + cell / 2);
    final color = Color(
      int.parse(poiColors[entry.key]!.replaceFirst('#', 'FF'), radix: 16),
    );
    canvas.drawCircle(
      center + const Offset(0, 3),
      25,
      Paint()
        ..color = const Color(0x26000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, 25, Paint()..color = Colors.white);
    canvas.drawCircle(center, 22, Paint()..color = color);
    final icon = entry.value;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 28,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
    final name = 'tkt-${entry.key}';
    index[name] = renderer.Sprite(
      name: name,
      width: cell,
      height: cell,
      x: column * cell,
      y: top,
      pixelRatio: 2,
      stretchX: const [],
      stretchY: const [],
    );
    column++;
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, top + cell);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('MAP_ICONS_UNAVAILABLE');
    final png = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return vector.SpriteStyle(
      index: renderer.SpriteIndex(index),
      atlasProvider: () async => png,
    );
  } finally {
    image.dispose();
    picture.dispose();
    original?.dispose();
  }
}
