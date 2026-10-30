import 'package:flutter/material.dart';

import 'package:taktooka/core/gender_copy.dart';

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const AppText(
        'تكتوكة',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: Colors.black,
          fontSize: 26,
        ),
      ),
      const SizedBox(width: 4),
      Image.asset('assets/brand.png', cacheWidth: 144, height: 40, width: 48),
    ],
    ),
  );
}
