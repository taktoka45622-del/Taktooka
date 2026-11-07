import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/services/refresh_gate.dart';
import 'package:taktooka/services/restaurant_availability.dart';
import 'package:taktooka/models/food_cart.dart';

void main() {
  test('manual refresh queues a fresh read and waits for completion', () async {
    final gate = RefreshGate();
    final oldRead = Completer<void>();
    final freshRead = Completer<void>();
    final calls = <bool>[];
    Future<void> task(bool force) async {
      calls.add(force);
      await (force ? freshRead.future : oldRead.future);
    }

    final first = gate.run(task, full: false);
    var completed = false;
    final manual = gate.run(task, full: true).then((_) => completed = true);
    oldRead.complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(calls, [false, true]);
    expect(completed, false);
    freshRead.complete();
    await manual;
    expect(completed, true);
  });
  test('failed refresh permits a subsequent retry', () async {
    final gate = RefreshGate();
    await expectLater(
      gate.run((_) async => throw StateError('network')),
      throwsStateError,
    );
    var ran = false;
    await gate.run((_) async {
      ran = true;
    });
    expect(ran, true);
  });
  test('manual and scheduled closure prevent ordering', () {
    final now = DateTime.parse('2026-11-07T12:00:00Z');
    expect(restaurantIsOpen({'open': false}, now: now), false);
    expect(
      restaurantIsOpen({'open': true, 'closing_time': '15:00:00'}, now: now),
      false,
    );
    expect(
      restaurantIsOpen({'open': true, 'closing_time': '15:01:00'}, now: now),
      true,
    );
    expect(
      catalogMealAvailable({
        'available': false,
        'restaurant_open': true,
      }, now: now),
      false,
    );
    expect(
      catalogMealAvailable({
        'available': true,
        'restaurant_open': false,
      }, now: now),
      false,
    );
    expect(
      catalogMealAvailable({
        'available': true,
        'restaurant_open': true,
      }, now: now),
      true,
    );
  });
  test('cart refuses mixing restaurants', () {
    final cart = FoodCart();
    cart.add(
      {'id': 'one', 'name': 'one'},
      {'id': 'meal', 'quantity': 1, 'price': 1000},
    );
    expect(cart.accepts('one'), true);
    expect(cart.accepts('two'), false);
    expect(
      () => cart.add(
        {'id': 'two'},
        {'id': 'other', 'quantity': 1, 'price': 2000},
      ),
      throwsStateError,
    );
    expect(cart.restaurant?['id'], 'one');
    cart.dispose();
  });
}
