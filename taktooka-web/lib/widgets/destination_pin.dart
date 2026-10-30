import 'package:flutter/material.dart';

class DestinationPin extends StatelessWidget {
  final bool moving;
  const DestinationPin({super.key, this.moving = false});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: moving ? 4.0 : 0.0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 130),
    curve: Curves.easeOutCubic,
    builder: (context, lift, child) => CustomPaint(
      size: const Size(48, 72),
      painter: _DestinationPinPainter(lift),
    ),
  );
}

class _DestinationPinPainter extends CustomPainter {
  final double lift;
  const _DestinationPinPainter(this.lift);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 72);
    final paint = Paint()..isAntiAlias = true;
    paint.color = const Color(0x10000000);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(24, 70),
        width: 19 + lift,
        height: 10 + lift * .5,
      ),
      paint,
    );
    paint.color = const Color(0xff555555);
    canvas.drawCircle(const Offset(24, 70), 2.2, paint);
    paint
      ..color = const Color(0xff535661)
      ..strokeWidth = 2.6;
    canvas.drawLine(Offset(24, 33 - lift), Offset(24, 68 - lift), paint);
    paint.color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(9, 10 - lift, 30, 30),
        const Radius.circular(7),
      ),
      paint,
    );
    paint.color = const Color(0xffe01828);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(11, 12 - lift, 26, 26),
        const Radius.circular(5.5),
      ),
      paint,
    );
    paint.color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(20, 21 - lift, 8, 8),
        const Radius.circular(1.8),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DestinationPinPainter oldDelegate) =>
      oldDelegate.lift != lift;
}
