import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taktooka/widgets/keyboard_dismiss.dart';

void main() {
  testWidgets(
    'Touch outside dismisses all fields without consuming button taps or switching fields',
    (tester) async {
      final first = FocusNode(), second = FocusNode();
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => DismissKeyboardOnOutsideTap(child: child!),
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: first, key: const Key('first')),
                TextFormField(focusNode: second, key: const Key('second')),
                ElevatedButton(
                  onPressed: () => pressed = true,
                  child: const Text('حفظ'),
                ),
                const Expanded(child: SizedBox.expand(key: Key('outside'))),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('first')));
      await tester.pump();
      expect(first.hasFocus, true);
      expect(tester.testTextInput.isVisible, true);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('outside'))));
      await tester.pump();
      expect(first.hasFocus, false);
      expect(tester.testTextInput.isVisible, false);
      await tester.tap(find.byKey(const Key('first')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('second')));
      await tester.pump();
      expect(second.hasFocus, true);
      expect(tester.testTextInput.isVisible, true);
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      expect(second.hasFocus, false);
      expect(pressed, true);
      expect(tester.testTextInput.isVisible, false);
      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      second.dispose();
    },
  );
}
