import 'dart:developer';

import '../vector_map_tiles.dart';

const _timelineTaskFilterKey = 'VectorMapTiles';

const _timelinePrefix = 'VMT';

TimelineTask tileRenderingTask(TileIdentity tile) =>
    TimelineTask(filterKey: _timelineTaskFilterKey)..start(_name('TileDelay'));

String _name(String name) {
  return '$_timelinePrefix::$name';
}
