import 'package:flutter/material.dart';

import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/prize_wheel_page.dart';
import 'package:taktooka/services/backend.dart';

class PrizeWheelEntry extends StatelessWidget {
  final Backend backend;
  final VoidCallback login;
  const PrizeWheelEntry({
    super.key,
    required this.backend,
    required this.login,
  });
  @override
  Widget build(BuildContext context) => PaperCard(
    onTap: () {
      if (!backend.loggedIn) {
        login();
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PrizeWheelPage(backend: backend),
        ),
      );
    },
    child: Row(
      children: [
        const CategoryIcon(Icons.casino_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText('عجلة الجوائز', style: heading(20)),
              const AppText('لفّ العجلة وشوف جائزتك'),
            ],
          ),
        ),
        const Icon(Icons.chevron_left),
      ],
    ),
  );
}
