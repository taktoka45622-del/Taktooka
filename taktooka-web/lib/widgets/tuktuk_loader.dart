import 'package:flutter/material.dart';

import 'package:taktooka/core/gender_copy.dart';

class TuktukLoader extends StatelessWidget {
  const TuktukLoader({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'جاري التحميل',
    liveRegion: true,
    child: SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              strokeCap: StrokeCap.round,
              color: const Color(0xffe01828),
              backgroundColor: const Color(0xfffbe8eb),
              value: MediaQuery.disableAnimationsOf(context) ? .75 : null,
            ),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: AppText(
              'جاري التحميل',
              style: TextStyle(fontSize: 13, color: Color(0xff777777)),
            ),
          ),
        ],
      ),
    ),
  );
}
