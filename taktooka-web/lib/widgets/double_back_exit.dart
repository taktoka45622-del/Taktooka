import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_notice.dart';

class DoubleBackExit extends StatefulWidget {
  final Widget child;
  const DoubleBackExit({super.key, required this.child});
  @override
  State<DoubleBackExit> createState() => _DoubleBackExitState();
}

class _DoubleBackExitState extends State<DoubleBackExit> {
  DateTime? previous;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: kIsWeb || defaultTargetPlatform != TargetPlatform.android,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop || kIsWeb || defaultTargetPlatform != TargetPlatform.android)
        return;
      final now = DateTime.now();
      if (previous != null &&
          now.difference(previous!) < const Duration(seconds: 2)) {
        SystemNavigator.pop();
      } else {
        previous = now;
        showAppNotice(context, 'اضغط رجوع مرة ثانية للخروج');
      }
    },
    child: widget.child,
  );
}
