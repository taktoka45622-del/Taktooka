import 'package:flutter/material.dart';

class PickupPin extends StatelessWidget {
  final bool moving;
  const PickupPin({super.key, this.moving = false});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: moving ? 6.0 : 0.0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : const Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
    builder: (context, lift, child) =>
        CustomPaint(size: const Size(48, 64), painter: _PickupPinPainter(lift)),
  );
}

class _PickupPinPainter extends CustomPainter {
  final double lift;
  const _PickupPinPainter(this.lift);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 64);
    final paint = Paint()..isAntiAlias = true;
    paint.color = const Color(0x22000000);
    canvas.drawOval(const Rect.fromLTWH(19, 60, 10, 4), paint);
    final center = Offset(24, 19 - lift);
    paint
      ..color = const Color(0xff535661)
      ..strokeWidth = 2.8;
    canvas.drawLine(Offset(24, center.dy + 13), const Offset(24, 62), paint);
    paint.color = Colors.white;
    canvas.drawCircle(center, 15, paint);
    paint.color = const Color(0xffe56516);
    canvas.drawCircle(center, 12.5, paint);
    paint.color = Colors.white;
    canvas.drawCircle(center, 4.3, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PickupPinPainter oldDelegate) =>
      oldDelegate.lift != lift;
}
