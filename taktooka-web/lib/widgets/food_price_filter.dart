import 'package:taktooka/services/backend.dart';
import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';

Future<RangeValues?> showFoodPriceFilter(
  BuildContext context, {
  double minimum = 0,
  double maximum = 100000,
}) => showDialog<RangeValues>(
  context: context,
  builder: (_) => _FoodPriceFilter(minimum: minimum, maximum: maximum),
);

class _FoodPriceFilter extends StatefulWidget {
  final double minimum, maximum;
  const _FoodPriceFilter({required this.minimum, required this.maximum});
  @override
  State<_FoodPriceFilter> createState() => _FoodPriceFilterState();
}

class _FoodPriceFilterState extends State<_FoodPriceFilter> {
  late RangeValues range;
  late TextEditingController lower, upper;
  String? error;
  @override
  void initState() {
    super.initState();
    range = RangeValues(
      widget.minimum.clamp(0, 100000),
      widget.maximum.clamp(widget.minimum.clamp(0, 100000), 100000),
    );
    lower = TextEditingController(text: '${range.start.toInt()}');
    upper = TextEditingController(text: '${range.end.toInt()}');
  }

  @override
  void dispose() {
    lower.dispose();
    upper.dispose();
    super.dispose();
  }

  void changed() {
    final lo = int.tryParse(westernDigits(lower.text).replaceAll(',', '')),
        hi = int.tryParse(westernDigits(upper.text).replaceAll(',', ''));
    if (lo != null && hi != null && lo >= 0 && hi >= lo && hi <= 100000)
      setState(() {
        range = RangeValues(lo.toDouble(), hi.toDouble());
        error = null;
      });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    title: Row(
      children: [
        const Icon(Icons.tune, color: scarlet),
        const SizedBox(width: 8),
        const Expanded(child: Text('تصفية الأسعار')),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'حدد السعر المناسب إلك',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 22),
          for (final entry in [(lower, 'أقل سعر'), (upper, 'أعلى سعر')])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: entry.$1,
                keyboardType: TextInputType.number,
                onChanged: (_) => changed(),
                decoration: InputDecoration(
                  labelText: entry.$2,
                  suffixText: 'د.ع',
                ),
              ),
            ),
          RangeSlider(
            values: range,
            min: 0,
            max: 100000,
            divisions: 200,
            activeColor: scarlet,
            labels: RangeLabels(money(range.start), money(range.end)),
            onChanged: (v) => setState(() {
              range = v;
              lower.text = '${v.start.toInt()}';
              upper.text = '${v.end.toInt()}';
              error = null;
            }),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(money(0)), Text(money(100000))],
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
        ],
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('رجوع'),
      ),
      FilledButton(
        onPressed: () {
          changed();
          final lo = int.tryParse(
                westernDigits(lower.text).replaceAll(',', ''),
              ),
              hi = int.tryParse(westernDigits(upper.text).replaceAll(',', ''));
          if (lo == null || hi == null || lo < 0 || hi < lo || hi > 100000) {
            setState(() => error = 'أدخل نطاقًا صحيحًا بين 0 و100,000');
            return;
          }
          Navigator.pop(context, RangeValues(lo.toDouble(), hi.toDouble()));
        },
        child: const Text('تطبيق'),
      ),
    ],
  );
}
