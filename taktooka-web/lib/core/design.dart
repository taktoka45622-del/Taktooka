import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/gender_copy.dart';

const ink = Color(0xff111111),
    scarlet = Color(0xffe01828),
    pink = Color(0xffffedef),
    muted = Color(0xff777777);
String money(dynamic value) =>
    '${NumberFormat('#,##0', 'en').format(num.tryParse('$value') ?? 0)} ${uiText('د.ع')}';
double uiScale(BuildContext context) =>
    (MediaQuery.sizeOf(context).width / 390).clamp(.85, 1.3);
TextStyle heading(double size) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w900,
  color: ink,
  height: 1.5,
);

class PaperCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.radius = 16,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x09000000),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class CategoryIcon extends StatelessWidget {
  final IconData icon;
  final bool circle;
  final double size;
  final Color color, background;
  const CategoryIcon(
    this.icon, {
    super.key,
    this.circle = false,
    this.size = 48,
    this.color = scarlet,
    this.background = pink,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(14),
    ),
    child: Center(
      child: icon == Icons.account_balance_wallet_outlined
          ? SizedBox(
              width: size * .58,
              height: size * .58,
              child: CustomPaint(painter: WalletLinePainter(color)),
            )
          : icon == Icons.confirmation_number_outlined && color == scarlet
          ? SizedBox(
              width: size * .58,
              height: size * .58,
              child: CustomPaint(painter: CouponLinePainter(color)),
            )
          : Icon(icon, color: color, size: size * .53),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: AppText(text, style: heading(28 * uiScale(context))),
  );
}

class WalletLinePainter extends CustomPainter {
  final Color color;
  const WalletLinePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 44, size.height / 44);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(5, 11, 33, 26),
        const Radius.circular(5),
      ),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(9, 11)
        ..lineTo(28, 5)
        ..quadraticBezierTo(31, 4, 32, 7)
        ..lineTo(33, 11),
      p,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(27, 20, 12, 10),
        const Radius.circular(3),
      ),
      p,
    );
    canvas.drawCircle(const Offset(31, 25), 1.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(WalletLinePainter old) => old.color != color;
}

class CouponLinePainter extends CustomPainter {
  final Color color;
  const CouponLinePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 44, size.height / 44);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(9, 7)
      ..lineTo(35, 7)
      ..quadraticBezierTo(39, 7, 39, 11)
      ..lineTo(39, 17)
      ..quadraticBezierTo(31, 22, 39, 27)
      ..lineTo(39, 33)
      ..quadraticBezierTo(39, 37, 35, 37)
      ..lineTo(9, 37)
      ..quadraticBezierTo(5, 37, 5, 33)
      ..lineTo(5, 27)
      ..quadraticBezierTo(13, 22, 5, 17)
      ..lineTo(5, 11)
      ..quadraticBezierTo(5, 7, 9, 7);
    canvas.drawPath(path, p);
    canvas.drawLine(const Offset(18, 29), const Offset(27, 15), p);
    canvas.drawCircle(const Offset(17, 16), 2.4, p);
    canvas.drawCircle(const Offset(28, 28), 2.4, p);
  }

  @override
  bool shouldRepaint(CouponLinePainter old) => old.color != color;
}

Color themedSurface(BuildContext context, Color light) =>
    Theme.of(context).brightness == Brightness.dark
    ? Theme.of(context).colorScheme.surfaceContainerHighest
    : light;
