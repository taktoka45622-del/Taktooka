import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';

class LineSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const LineSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: scarlet),
              const SizedBox(width: 10),
              Expanded(
                child: AppText(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}
