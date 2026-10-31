import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/commerce_ui.dart';

Future<String?> foodCancellationReason(
  BuildContext context, {
  required bool customer,
}) async {
  final input = TextEditingController();
  String? choice;
  final choices = customer
      ? ['غيّرت رأيي', 'طلبت بالغلط', 'أريد أعدّل الطلب', 'سبب آخر']
      : [
          'الوجبة غير متوفرة',
          'تعذر تجهيز الطلب',
          'تعذر التواصل مع الزبون',
          'سبب آخر',
        ];
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, update) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            16 + MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  customer ? 'إلغاء الطلب' : 'رفض الطلب',
                  style: heading(24),
                ),
                const SizedBox(height: 10),
                const Text('اختار السبب حتى نكدر نخدمك أحسن'),
                const SizedBox(height: 16),
                for (final v in choices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: () => update(() => choice = v),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: choice == v
                              ? scarlet
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            choice == v
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(v)),
                        ],
                      ),
                    ),
                  ),
                if (choice == 'سبب آخر')
                  TextField(
                    controller: input,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 250,
                    decoration: const InputDecoration(labelText: 'اكتب السبب'),
                    onChanged: (_) => update(() {}),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      choice == null ||
                          choice == 'سبب آخر' && input.text.trim().length < 3
                      ? null
                      : () => Navigator.pop(
                          sheet,
                          choice == 'سبب آخر' ? input.text.trim() : choice,
                        ),
                  child: Text(customer ? 'تأكيد الإلغاء' : 'تأكيد الرفض'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('الاحتفاظ بالطلب'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  input.dispose();
  return result;
}

Future<void> showRestaurantSettlementCode(BuildContext context, Json value) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('كود تسديد المطعم', style: heading(24)),
                const SizedBox(height: 12),
                const Text('المبلغ المطلوب استلامه'),
                Text(money(value['amount']), style: heading(28)),
                const SizedBox(height: 24),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value['code']?.toString() ?? '',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 38,
                      letterSpacing: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: value['code'].toString()),
                    );
                    if (sheet.mounted)
                      ScaffoldMessenger.of(sheet).showSnackBar(
                        const SnackBar(content: Text('تم نسخ الكود')),
                      );
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('نسخ الكود'),
                ),
                const CommerceStatus(
                  'صالح لمدة 15 دقيقة',
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                const Text(
                  'أعطِ الكود للكابتن بعد استلام المبلغ كاملاً فقط',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('تم'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
