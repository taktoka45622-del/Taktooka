import 'package:flutter/material.dart';

import 'package:taktooka/core/gender_copy.dart';

class FlipCardHint extends StatefulWidget {
  const FlipCardHint({super.key});
  @override
  State<FlipCardHint> createState() => _FlipCardHintState();
}

class _FlipCardHintState extends State<FlipCardHint>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);
  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      children: [
        AnimatedBuilder(
          animation: animation,
          builder: (_, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .001)
              ..rotateY(animation.value * 3.14159),
            child: child,
          ),
          child: Container(
            width: 130,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xffffca28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.credit_card, size: 44),
          ),
        ),
        const SizedBox(height: 10),
        const AppText('اقلب البطاقة، ثم اضغط زر الكاميرا لتصوير الخلف'),
      ],
    ),
  );
}
