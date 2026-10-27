import 'package:taktooka/core/numeric_localizations.dart';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/tuktuk_loader.dart';

class DispatchSettingsPage extends StatefulWidget {
  final Backend b;
  const DispatchSettingsPage({super.key, required this.b});
  @override
  State<DispatchSettingsPage> createState() => _DispatchSettingsPageState();
}

class _DispatchSettingsPageState extends State<DispatchSettingsPage> {
  final eta = TextEditingController(),
      search = TextEditingController(),
      stale = TextEditingController(),
      zones = TextEditingController();
  Json settings = {};
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    eta.dispose();
    search.dispose();
    stale.dispose();
    zones.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final s = Json.from(await widget.b.dispatch('settings') as Map);
      if (!mounted) return;
      settings = s;
      eta.text = ((s['max_eta_s'] as num) / 60).toStringAsFixed(0);
      search.text = (s['search_s'] as num).toStringAsFixed(0);
      stale.text = (s['stale_s'] as num).toStringAsFixed(0);
      zones.text = const JsonEncoder.withIndent('  ').convert(s['zones']);
      error = null;
    } catch (e) {
      error = readable(e);
    }
    if (mounted) setState(() => busy = false);
  }

  int number(String text) => int.parse(
    text
        .trim()
        .replaceAll(',', '')
        .replaceAllMapped(
          RegExp('[٠-٩]'),
          (m) => '٠١٢٣٤٥٦٧٨٩'.indexOf(m[0]!).toString(),
        ),
  );
  Future<void> save({bool boundaries = false}) async {
    setState(() => busy = true);
    try {
      final data = <String, dynamic>{
        'max_eta_s': number(eta.text) * 60,
        'search_s': number(search.text),
        'stale_s': number(stale.text),
      };
      if (boundaries) data['zones'] = jsonDecode(zones.text);
      await widget.b.dispatch('configure', data);
      await load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: AppText('تم حفظ إعدادات توزيع الرحلات')),
        );
    } catch (e) {
      if (mounted)
        setState(() {
          error = e is FormatException
              ? 'اكتب أرقام وحدود JSON صحيحة'
              : readable(e);
          busy = false;
        });
    }
  }

  Widget input(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      inputFormatters: const [GroupedNumberFormatter()],
      controller: c,
      keyboardType: TextInputType.number,
      decoration: localizedInput(context, InputDecoration(labelText: label)),
    ),
  );
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      if (busy) const TuktukLoader(),
      if (error != null)
        AppText(error!, style: const TextStyle(color: Colors.red)),
      const AppText(
        'العرض حصري لكابتن واحد لمدة 30 ثانية. القبول والحجز يتحققان على السيرفر.',
        style: TextStyle(fontSize: 16),
      ),
      const SizedBox(height: 20),
      input(eta, 'أقصى وقت وصول بالدقائق (١–٦٠)'),
      const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: AppText('يستمر البحث حتى يقبل كابتن أو يلغي المستخدم طلبه.'),
      ),
      input(stale, 'صلاحية موقع GPS بالثواني (٢٠–١٢٠)'),
      FilledButton(
        onPressed: busy ? null : () => save(),
        child: const AppText('حفظ الإعدادات'),
      ),
      const SizedBox(height: 24),
      AppText('آخر تشغيل: ${settings['last_worker_at'] ?? '—'}'),
      AppText('آخر حساب طريق: ${settings['last_matrix_at'] ?? '—'}'),
      if (settings['last_error'] != null)
        AppText(
          'مشكلة خدمة الطرق: ${settings['last_error']}',
          style: const TextStyle(color: Colors.red),
        ),
      ExpansionTile(
        title: const AppText('تعديل حدود مناطق الخدمة'),
        subtitle: const AppText('GeoJSON — كل منطقة مضلع مستقل'),
        children: [
          const AppText(
            'الحدود الأولية مناطق حضرية تقريبية حول المدن السبع. عدّلها حسب المناطق التي تخدمها فعليًا. الإحداثيات: خط الطول ثم خط العرض.',
          ),
          TextField(
            inputFormatters: const [GroupedNumberFormatter()],
            controller: zones,
            minLines: 8,
            maxLines: 18,
            textDirection: TextDirection.ltr,
            decoration: localizedInput(
              context,
              InputDecoration(labelText: 'مصفوفة المناطق JSON'),
            ),
          ),
          FilledButton(
            onPressed: busy ? null : () => save(boundaries: true),
            child: const AppText('حفظ حدود الخدمة'),
          ),
        ],
      ),
    ],
  );
}
