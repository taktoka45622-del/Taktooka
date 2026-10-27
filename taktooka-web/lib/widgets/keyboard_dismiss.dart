import 'package:flutter/material.dart';

class DismissKeyboardOnOutsideTap extends StatelessWidget {
  final Widget child;
  const DismissKeyboardOnOutsideTap({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      EditableTextTapOutsideIntent:
          CallbackAction<EditableTextTapOutsideIntent>(
            onInvoke: (intent) {
              intent.focusNode.unfocus();
              return null;
            },
          ),
    },
    child: child,
  );
}
