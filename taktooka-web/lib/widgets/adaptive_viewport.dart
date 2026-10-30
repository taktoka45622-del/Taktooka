import 'dart:math' as math;

import 'package:flutter/material.dart';

class AdaptiveViewport extends StatelessWidget {
  final Widget child;
  const AdaptiveViewport({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(constraints.maxWidth, 600.0);
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(size: Size(width, constraints.maxHeight)),
                child: child,
              ),
            ),
          );
        },
      ),
    ),
  );
}
