import 'dart:math' as math;
import 'package:flutter/material.dart';

class MapVehicle extends StatefulWidget {
  final double heading;
  const MapVehicle({super.key, this.heading = 0});
  @override
  State<MapVehicle> createState() => _MapVehicleState();
}

class _MapVehicleState extends State<MapVehicle> {
  late double _target, _shown;
  @override
  void initState() {
    super.initState();
    _target = _shown = widget.heading;
  }

  @override
  void didUpdateWidget(covariant MapVehicle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heading != widget.heading) {
      final difference = ((widget.heading - _shown + 540) % 360) - 180;
      _target = _shown + difference;
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: _shown, end: _target),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Image.asset(
        'assets/map_tuktuk_3d.png',
        cacheWidth: 192,
        filterQuality: FilterQuality.medium,
        fit: BoxFit.contain,
      ),
      builder: (_, angle, child) {
        _shown = angle;
        return Transform.rotate(angle: angle * math.pi / 180, child: child);
      },
    ),
  );
}
