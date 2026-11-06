import 'package:flutter/material.dart';

class SkeletonShimmer extends StatefulWidget {
  final Widget child;
  const SkeletonShimmer({super.key, required this.child});
  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool running = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (enabled != running) {
      running = enabled;
      if (enabled) {
        animation.repeat();
      } else {
        animation.stop();
      }
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xff303238) : const Color(0xffe7e8eb);
    final highlight = dark ? const Color(0xff494c54) : const Color(0xfffafafa);
    return Semantics(
      label: 'جاري التحميل',
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: animation,
              child: widget.child,
              builder: (context, child) => ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  final position = running ? animation.value * 4 - 2 : 0.0;
                  final rtl = Directionality.of(context) == TextDirection.rtl;
                  return LinearGradient(
                    begin: Alignment(rtl ? -position : position, 0),
                    end: Alignment(rtl ? -position - 1.5 : position + 1.5, 0),
                    colors: [base, highlight, base],
                    stops: const [0, .5, 1],
                  ).createShader(bounds);
                },
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SkeletonBlock extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBlock({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class SkeletonContent extends StatelessWidget {
  final int count;
  final bool images;
  const SkeletonContent({super.key, this.count = 4, this.images = true});
  @override
  Widget build(BuildContext context) => SkeletonShimmer(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        count,
        (index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              if (images) ...[
                const SkeletonBlock(width: 72, height: 72, radius: 14),
                const SizedBox(width: 14),
              ],
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: .65,
                      child: SkeletonBlock(),
                    ),
                    SizedBox(height: 12),
                    SkeletonBlock(height: 12),
                    SizedBox(height: 10),
                    FractionallySizedBox(
                      widthFactor: .4,
                      child: SkeletonBlock(height: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: const [
      SkeletonShimmer(child: SkeletonBlock(height: 150, radius: 18)),
      SizedBox(height: 20),
      SkeletonContent(),
    ],
  );
}

class SkeletonActivity extends StatelessWidget {
  final double height;
  const SkeletonActivity({super.key, this.height = 4});
  @override
  Widget build(BuildContext context) => SkeletonShimmer(
    child: SkeletonBlock(height: height, radius: height / 2),
  );
}
