import 'package:taktooka/services/backend.dart';
import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/numeric_localizations.dart';

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
  String amount(num n) => money(n).replaceAll('د.ع', '').trim();
  int? value(TextEditingController c) =>
      int.tryParse(westernDigits(c.text).replaceAll(RegExp(r'[,\s]'), ''));
  @override
  void initState() {
    super.initState();
    range = RangeValues(
      widget.minimum.clamp(0, 100000),
      widget.maximum.clamp(widget.minimum.clamp(0, 100000), 100000),
    );
    lower = TextEditingController(text: amount(range.start));
    upper = TextEditingController(text: amount(range.end));
  }

  @override
  void dispose() {
    lower.dispose();
    upper.dispose();
    super.dispose();
  }

  void changed() {
    final lo = value(lower), hi = value(upper);
    if (lo != null && hi != null && lo >= 0 && hi >= lo && hi <= 100000)
      setState(() {
        range = RangeValues(lo.toDouble(), hi.toDouble());
        error = null;
      });
  }

  Widget field(String label, TextEditingController controller) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 17, color: Color(0xff555555)),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        inputFormatters: const [EnglishDigitsFormatter()],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.right,
        onChanged: (_) => changed(),
        style: const TextStyle(fontSize: 19),
        decoration: InputDecoration(
          suffixText: 'د.ع',
          suffixStyle: const TextStyle(color: Color(0xffb7b7b7)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xffe2e2e2)),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
    ],
  );
  void apply() {
    changed();
    final lo = value(lower), hi = value(upper);
    if (lo == null || hi == null || lo < 0 || hi < lo || hi > 100000) {
      setState(() => error = 'أدخل نطاقًا صحيحًا بين 0 و100,000');
      return;
    }
    Navigator.pop(context, RangeValues(lo.toDouble(), hi.toDouble()));
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, color: scarlet, size: 28),
                  const SizedBox(width: 10),
                  Expanded(child: Text('تصفية الأسعار', style: heading(22))),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey, size: 28),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 40,
                    ),
                  ),
                ],
              ),
              const Text(
                'حدد السعر المناسب إلك',
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
              const SizedBox(height: 28),
              field('أقل سعر', lower),
              const SizedBox(height: 24),
              field('أعلى سعر', upper),
              const SizedBox(height: 18),
              Directionality(
                textDirection: TextDirection.ltr,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 5,
                    rangeThumbShape: const RoundRangeSliderThumbShape(
                      enabledThumbRadius: 11,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: RangeSlider(
                    values: range,
                    min: 0,
                    max: 100000,
                    divisions: 200,
                    activeColor: scarlet,
                    inactiveColor: const Color(0xffffe0e3),
                    onChanged: (v) => setState(() {
                      range = v;
                      lower.text = amount(v.start);
                      upper.text = amount(v.end);
                      error = null;
                    }),
                  ),
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '0 د.ع',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    Text(
                      '100,000 د.ع',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: scarlet)),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: apply,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: const Text(
                        'تطبيق',
                        style: TextStyle(fontSize: 21),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 54),
                        side: const BorderSide(color: scarlet, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: const Text('رجوع', style: TextStyle(fontSize: 21)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
