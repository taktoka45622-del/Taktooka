import 'package:flutter/material.dart';

class TicketDivider extends StatelessWidget {
  const TicketDivider();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 18,
    child: Row(
      children: [
        Container(
          width: 12,
          height: 18,
          decoration: BoxDecoration(
            color: Color(0xfffafafa),
            borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (_, c) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                (c.maxWidth / 7).floor(),
                (_) => const SizedBox(
                  width: 2,
                  height: 2,
                  child: ColoredBox(color: Color(0xffdddddd)),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: 12,
          height: 18,
          decoration: BoxDecoration(
            color: Color(0xfffafafa),
            borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
          ),
        ),
      ],
    ),
  );
}
