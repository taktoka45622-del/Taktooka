class TileOffset {
  final int zoomOffset;

  const TileOffset({required this.zoomOffset});

  // ignore: constant_identifier_names
  static const DEFAULT = TileOffset(zoomOffset: 0);

  static final mapbox = DEFAULT.offsetBy(zoom: -1);

  TileOffset offsetBy({required int zoom}) {
    if (zoom == 0) {
      return this;
    }
    assert(zoom < 0);

    return TileOffset(zoomOffset: zoomOffset + zoom);
  }
}
