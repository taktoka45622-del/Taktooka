import 'package:flutter/material.dart';
import 'skeleton.dart';

class TuktukLoader extends StatelessWidget {
  const TuktukLoader({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    child: SkeletonContent(count: 1, images: false),
  );
}
