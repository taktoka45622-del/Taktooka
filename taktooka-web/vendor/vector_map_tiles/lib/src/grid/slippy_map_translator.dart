import 'dart:math';

import '../tile_identity.dart';

class TileTranslation {
  final TileIdentity original;

  final TileIdentity translated;

  final int fraction;

  final int xOffset;

  final int yOffset;

  int get zoomDifference => original.z.toInt() - translated.z.toInt();
  bool get isTranslated => fraction > 1;

  TileTranslation(this.original, this.translated, this.fraction, this.xOffset,
      this.yOffset);
  TileTranslation.identity(this.original)
      : translated = original,
        fraction = 1,
        xOffset = 0,
        yOffset = 0;
}

class SlippyMapTranslator {
  final int maxZoom;
  SlippyMapTranslator(this.maxZoom);

  TileTranslation translate(TileIdentity tile) {
    if (tile.z <= maxZoom) {
      return TileTranslation.identity(tile);
    }
    return _translate(tile, maxZoom);
  }

  TileTranslation lowerZoomAlternative(TileIdentity tile,
      {required int levels}) {
    return _translate(tile, tile.z.toInt() - levels);
  }

  TileTranslation specificZoomTranslation(TileIdentity tile,
      {required int zoom}) {
    return _translate(tile, zoom);
  }

  TileTranslation _translate(TileIdentity tile, int targetZoom) {
    final zoomDifference = tile.z - targetZoom;
    if (zoomDifference == 0) {
      return TileTranslation.identity(tile);
    }
    final divisor = pow(2, zoomDifference).toInt();
    final translatedX = tile.x ~/ divisor;
    final translatedY = tile.y ~/ divisor;
    final xOffset = (tile.x % divisor).toInt();
    final yOffset = (tile.y % divisor).toInt();
    final translated = TileIdentity(targetZoom, translatedX, translatedY);
    return TileTranslation(tile, translated, divisor, xOffset, yOffset);
  }
}
