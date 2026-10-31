import 'package:flutter/material.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/commerce.dart';

Future<void> showCaptainServicePreferences(
  BuildContext context,
  Backend b,
) async {
  final foodAllowed = b.commerce['vehicle'] == 'bike' || !b.commissionPlan;
  var food = foodAllowed && b.commerce['receive_food'] != false;
  var rides =
      b.commerce['receive_rides'] != false && b.commerce['vehicle'] != 'bike';
  var saving = false;
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, update) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'طلباتك على كيفك',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const Text('حدد الخدمات اللي تريد تستقبل طلباتها'),
                if (b.commerce['vehicle'] != 'bike')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('رحلات الزبائن'),
                    value: rides,
                    onChanged: saving ? null : (v) => update(() => rides = v),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('توصيل طلبات المطاعم'),
                  value: food,
                  onChanged: saving || !foodAllowed
                      ? null
                      : (v) => update(() => food = v),
                ),
                if (!foodAllowed)
                  const Text(
                    'نظام النسبة يشمل رحلات الزبائن فقط. توصيل المطاعم متاح بالاشتراك الأسبوعي.',
                  ),
                if (!food && !rides)
                  const Text('الخدمتان متوقفتان؛ لن تصلك طلبات جديدة'),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          update(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await commerceRpc(b, 'captain_preferences', {
                              'receive_food': food,
                              'receive_rides': rides,
                            });
                            await b.refresh();
                            if (!food &&
                                !rides &&
                                b.activeRide == null &&
                                b.commerce['food_active'] != true)
                              await b.stopTracking();
                            if (sheet.mounted) Navigator.pop(sheet);
                          } catch (e) {
                            if (sheet.mounted)
                              update(() => error = commerceError(e));
                          } finally {
                            if (sheet.mounted) update(() => saving = false);
                          }
                        },
                  child: Text(saving ? 'جار الحفظ…' : 'حفظ الاختيارات'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
