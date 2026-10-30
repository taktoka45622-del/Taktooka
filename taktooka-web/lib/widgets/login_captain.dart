import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:taktooka/widgets/captain_motion.dart';

enum CaptainMood { welcome, typing, private, checking, success, error }

class LoginCaptain extends StatefulWidget {
  const LoginCaptain({
    super.key,
    required this.mood,
    this.progress = 0,
    this.errorRevision = 0,
  });
  final CaptainMood mood;
  final double progress;
  final int errorRevision;
  @override
  State<LoginCaptain> createState() => _LoginCaptainState();
}

class _LoginCaptainState extends State<LoginCaptain>
    with TickerProviderStateMixin {
  late final AnimationController cover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    value: widget.mood == CaptainMood.private ? 1 : 0,
  );
  late final AnimationController gaze = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    lowerBound: -1,
    upperBound: 1,
    value: 0,
  );
  late final AnimationController gesture = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();
  @override
  void didUpdateWidget(LoginCaptain old) {
    super.didUpdateWidget(old);
    final reduced = MediaQuery.disableAnimationsOf(context);
    cover.animateTo(
      widget.mood == CaptainMood.private ? 1 : 0,
      duration: Duration(milliseconds: reduced ? 0 : 620),
      curve: Curves.easeInOutCubic,
    );
    gaze.animateTo(
      widget.mood == CaptainMood.typing
          ? widget.progress.clamp(0.0, 1.0) * 2 - 1
          : 0,
      duration: Duration(milliseconds: reduced ? 0 : 180),
      curve: Curves.easeOutCubic,
    );
    if (old.mood != widget.mood || old.errorRevision != widget.errorRevision)
      gesture.forward(from: 0);
  }

  @override
  void dispose() {
    cover.dispose();
    gaze.dispose();
    gesture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.sizeOf(context).height < 500;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Center(
          child: SizedBox(
            width: small ? 116 : 184,
            height: small ? 116 : 184,
            child: CustomPaint(
              painter: _CaptainRig(cover, gaze, gesture, widget.mood, reduced),
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptainRig extends CustomPainter {
  _CaptainRig(this.cover, this.gaze, this.gesture, this.mood, this.reduced)
    : super(repaint: Listenable.merge([cover, gaze, gesture]));
  final Animation<double> cover, gaze, gesture;
  final CaptainMood mood;
  final bool reduced;
  static const red = Color(0xffe52330),
      dark = Color(0xff222431),
      skin = Color(0xffeab284);
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.clipRect(Offset.zero & size);
    final scale = math.min(size.width / 240, size.height / 240);
    c.translate(
      (size.width - 240 * scale) / 2,
      (size.height - 240 * scale) / 2,
    );
    c.scale(scale);
    final p = reduced ? (mood == CaptainMood.private ? 1.0 : 0.0) : cover.value;
    final t = reduced ? 1.0 : gesture.value;
    final look = reduced ? 0.0 : gaze.value;
    final sway = mood == CaptainMood.error
        ? math.sin(t * math.pi * 6) * (1 - t) * 2
        : 0.0;
    c.translate(
      sway,
      mood == CaptainMood.success ? -math.sin(t * math.pi) * 4 : 0,
    );
    void oval(Rect r, Color color) => c.drawOval(r, Paint()..color = color);
    void line(Offset a, Offset b, Color color, double width) => c.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    final torso = Path()
      ..moveTo(64, 148)
      ..quadraticBezierTo(120, 126, 176, 148)
      ..lineTo(186, 238)
      ..lineTo(54, 238)
      ..close();
    c.drawPath(
      torso,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xfff53c49), Color(0xffc71629)],
        ).createShader(const Rect.fromLTWH(54, 140, 132, 100)),
    );
    c.drawPath(
      Path()
        ..moveTo(96, 141)
        ..lineTo(120, 158)
        ..lineTo(144, 141)
        ..lineTo(141, 238)
        ..lineTo(99, 238)
        ..close(),
      Paint()..color = dark,
    );
    line(
      const Offset(94, 151),
      const Offset(98, 238),
      const Color(0xffff7580),
      2,
    );
    line(
      const Offset(146, 151),
      const Offset(142, 238),
      const Color(0xffa61526),
      2,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(106, 119, 28, 29),
        const Radius.circular(9),
      ),
      Paint()..color = skin,
    );
    c.save();
    c.translate(look * 1.4, look.abs());
    oval(const Rect.fromLTWH(65, 68, 19, 31), skin);
    oval(const Rect.fromLTWH(156, 68, 19, 31), skin);
    oval(const Rect.fromLTWH(76, 29, 88, 108), skin);
    c.drawPath(
      Path()
        ..moveTo(76, 72)
        ..cubicTo(67, 14, 159, 7, 164, 71)
        ..lineTo(151, 49)
        ..quadraticBezierTo(120, 64, 89, 47)
        ..close(),
      Paint()..color = dark,
    );
    final eyeHeight = (1 - p * .82) * 12;
    for (final x in [99.0, 141.0]) {
      oval(
        Rect.fromCenter(center: Offset(x, 82), width: 26, height: eyeHeight),
        Colors.white,
      );
      oval(
        Rect.fromCenter(
          center: Offset(x + look * 3, 83),
          width: 9,
          height: eyeHeight * .88,
        ),
        const Color(0xff473125),
      );
      oval(
        Rect.fromCenter(
          center: Offset(x + look * 3 - 1, 81),
          width: 2.5,
          height: 2.5,
        ),
        Colors.white,
      );
      line(Offset(x - 11, 69), Offset(x + 9, 68), dark, 4.5);
    }
    c.drawPath(
      Path()
        ..moveTo(120, 85)
        ..quadraticBezierTo(115, 98, 122, 99),
      Paint()
        ..color = const Color(0xffce8b62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    c.drawPath(
      Path()
        ..moveTo(102, 110)
        ..quadraticBezierTo(120, 119, 138, 110)
        ..quadraticBezierTo(120, 129, 102, 110),
      Paint()..color = Colors.white,
    );
    final cap = Path()
      ..moveTo(73, 53)
      ..cubicTo(72, 7, 163, 7, 167, 53)
      ..close();
    c.drawPath(cap, Paint()..color = red);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(70, 46, 102, 12),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xffbd1828),
    );
    c.drawCircle(const Offset(121, 31), 8, Paint()..color = Colors.white);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(116, 27, 10, 6),
        const Radius.circular(2),
      ),
      Paint()..color = red,
    );
    c.restore();
    for (final left in [true, false]) {
      final shoulder = Offset(left ? 69 : 171, 156);
      var wrist = Offset(left ? 55 : 185, 209);
      if (mood == CaptainMood.welcome && !left) {
        final wave = math.sin(t * math.pi * 4) * (1 - t) * 5;
        wrist = Offset(187 + wave, 86 + wave * .2);
      }
      if (mood == CaptainMood.success) wrist = Offset(left ? 42 : 198, 100);
      wrist = Offset.lerp(
        wrist,
        Offset((left ? 101 : 139) + look * 1.4, 84),
        p,
      )!;
      wrist += Offset((left ? -1 : 1) * math.sin(p * math.pi) * 35, 0);
      final e = captainElbow(
        shoulder.dx,
        shoulder.dy,
        wrist.dx,
        wrist.dy,
        left,
      );
      final elbow = Offset(e.$1, e.$2);
      final cuff = Offset.lerp(elbow, wrist, .78)!;
      line(shoulder, elbow, const Color(0xffbd1828), 27);
      line(shoulder, elbow, red, 23);
      line(elbow, cuff, red, 22);
      line(cuff, wrist, skin, 17);
      c.save();
      c.translate(wrist.dx, wrist.dy);
      final natural =
          math.atan2(wrist.dy - elbow.dy, wrist.dx - elbow.dx) + math.pi / 2;
      c.rotate(natural * (1 - p) + (left ? -.18 : .18) * p);
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-11, -15, 22, 28),
          const Radius.circular(10),
        ),
        Paint()..color = skin,
      );
      for (var f = 0; f < 4; f++) {
        final x = -8.0 + f * 5;
        line(
          Offset(x, -5),
          Offset(x, -19 + (f == 0 || f == 3 ? 3 : 0)),
          skin,
          5,
        );
      }
      oval(Rect.fromLTWH(left ? 7 : -15, -2, 9, 18), skin);
      c.restore();
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_CaptainRig old) =>
      old.mood != mood || old.reduced != reduced;
}
