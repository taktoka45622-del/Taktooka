import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/core/poi_map_style.dart';
import 'package:vector_tile_renderer/src/themes/expression/expression.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

void main() {
  final parser = ExpressionParser(const Logger.noop());
  dynamic evaluate(
    List<dynamic> value,
    Map<String, dynamic> properties, {
    double zoom = 14,
  }) => parser
      .parse(value)
      .evaluate(
        EvaluationContext(
          () => properties,
          TileFeatureType.point,
          const Logger.noop(),
          zoom: zoom,
          zoomScaleFactor: 1,
          hasImage: (_) => true,
        ),
      );
  test('higher rank places remain visible when the map is zoomed in', () {
    expect(evaluate(poiVisibilityFilter(), {'filterrank': 5}), isTrue);
    expect(
      evaluate(poiVisibilityFilter(), {'filterrank': 5}, zoom: 13),
      isFalse,
    );
    expect(
      evaluate(poiVisibilityFilter(), {'filterrank': 2}, zoom: 13),
      isTrue,
    );
  });
  test('uses the real mosque and educational categories from map tiles', () {
    for (final category in {
      'religious-muslim': 'mosque',
      'school': 'school',
      'college': 'college',
      'hospital': 'hospital',
      'grocery': 'market',
      'shop': 'shop',
    }.entries) {
      expect(
        evaluate(poiStyleValue(icon: true), {'maki': category.key}),
        'tkt-${category.value}',
      );
    }
    expect(
      evaluate(poiStyleValue(icon: true), {'maki': 'unknown'}),
      'tkt-place',
    );
  });
  test('empty translations fall back to the existing place name', () {
    expect(
      evaluate(mapNameExpression('ar'), {'name_ar': '', 'name': 'مدرسة'}),
      'مدرسة',
    );
    expect(
      evaluate(mapNameExpression('ar'), {'name_ar': 'جامع', 'name': 'Mosque'}),
      'جامع',
    );
    expect(evaluate(mapNameExpression('ku'), {'name': 'School'}), 'School');
    expect(
      evaluate(mapNameExpression('en'), {
        'name_en': 'Hospital',
        'name': 'مستشفى',
      }),
      'Hospital',
    );
    expect(evaluate(mapNameExpression('ar'), {}), '');
  });
}
