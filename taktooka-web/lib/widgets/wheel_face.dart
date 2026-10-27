import 'package:taktooka/core/display_format.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/models/prize_wheel.dart';

class WheelFace extends StatelessWidget {
  final double angle;
  const WheelFace({super.key, required this.angle});
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Positioned.fill(
        child: Transform.rotate(
          angle: angle,
          child: CustomPaint(
            painter: _WheelPainter(
              titles: wheelTitles.map(uiText).toList(),
              direction: Directionality.of(context),
            ),
          ),
        ),
      ),
      Positioned(
        top: 0,
        child: Icon(
          Icons.arrow_drop_down,
          size: 52,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xffe5b549), width: 4),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
        ),
        child: const Icon(Icons.electric_rickshaw, color: scarlet, size: 34),
      ),
    ],
  );
}

class _WheelPainter extends CustomPainter {
  final List<String> titles;
  final TextDirection direction;
  _WheelPainter({required this.titles, required this.direction});
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2),
        radius = size.shortestSide / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const colors = [
      Color(0xffbd2332),
      Color(0xfff5dfb1),
      Color(0xff802238),
      Color(0xfff5dfb1),
      Color(0xffce4934),
      Color(0xfff5dfb1),
      Color(0xffaa731d),
      Color(0xfff5dfb1),
    ];
    for (var i = 0; i < 8; i++) {
      final start = -math.pi / 2 + i * math.pi / 4;
      canvas.drawArc(
        rect,
        start,
        math.pi / 4,
        true,
        Paint()..color = colors[i],
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(start + math.pi / 8);
      final text = TextPainter(
        text: TextSpan(
          text: englishDigits(titles[i]),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: size.width < 330 ? 11 : 13,
            fontWeight: FontWeight.w800,
            color: i.isEven ? Colors.white : const Color(0xff552e28),
          ),
        ),
        textDirection: direction,
        textAlign: TextAlign.center,
        maxLines: 2,
      );
      text.layout(maxWidth: radius * .55);
      canvas.translate(radius * .65, 0);
      canvas.rotate(math.pi / 2);
      text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
      canvas.restore();
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xffe5b549)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      canvas.drawCircle(
        center + Offset(math.cos(a), math.sin(a)) * (radius + 1),
        2,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.titles.join() != titles.join() || old.direction != direction;
}
