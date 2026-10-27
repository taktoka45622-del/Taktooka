import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/models/transport_line.dart';

void main() {
  test('excluded Friday and Saturday extend a fifteen day service', () {
    final dates = lineServiceDates(DateTime(2026, 10, 14), 15, {5, 6});
    expect(dates.length, 15);
    expect(dates.last, DateTime(2026, 11, 3));
    expect(dates.every((d) => !{5, 6}.contains(d.weekday % 7)), true);
  });
  test('all excluded weekdays are rejected instead of an endless loop', () {
    expect(
      () => lineServiceDates(DateTime(2026, 1, 1), 15, {0, 1, 2, 3, 4, 5, 6}),
      throwsArgumentError,
    );
  });
  test('service dates cross year boundaries without losing days', () {
    expect(
      lineServiceDates(DateTime(2026, 12, 31), 3, {}).last,
      DateTime(2027, 1, 2),
    );
  });
}
