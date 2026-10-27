import 'package:taktooka/core/numeric_localizations.dart';
import 'package:taktooka/core/display_format.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/feature_navigation.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/prize_wheel_entry.dart';
import 'package:taktooka/widgets/ticket_divider.dart';

class OffersPage extends StatefulWidget {
  final Backend b;
  final Runner run;
  final VoidCallback login;
  const OffersPage({
    super.key,
    required this.b,
    required this.run,
    required this.login,
  });
  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  final code = TextEditingController();
  Timer? expiryRefresh;
  @override
  void initState() {
    super.initState();
    expiryRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          TickerMode.valuesOf(context).enabled &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        setState(() {});
        unawaited(widget.b.refresh());
      }
    });
  }

  bool busy = false;
  String? error;
  @override
  void dispose() {
    expiryRefresh?.cancel();
    code.dispose();
    super.dispose();
  }

  Future<void> applyCoupon(String value) async {
    if (!widget.b.loggedIn) {
      widget.login();
      return;
    }
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.b.extra('coupon', {'code': value});
      await widget.b.refresh();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              value.isEmpty ? 'تم حذف الكود' : 'تم تفعيل الكود للرحلة القادمة',
            ),
          ),
        );
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coupons = (widget.b.extras['coupon_history'] as List? ?? [])
        .map((e) => Json.from(e as Map))
        .toList();
    if (coupons.isEmpty && widget.b.coupon != null)
      coupons.add({...widget.b.coupon!, 'status': 'active'});
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (widget.b.captain) ...[
          PrizeWheelEntry(backend: widget.b, login: widget.login),
          const SizedBox(height: 16),
        ],
        const SectionTitle('العروض والخصومات'),
        Row(
          children: [
            Expanded(
              child: TextField(
                inputFormatters: const [EnglishDigitsFormatter()],
                controller: code,
                textDirection: TextDirection.ltr,
                decoration: localizedInput(
                  context,
                  InputDecoration(
                    hintText: 'أدخل رمز الخصم',
                    prefixIcon: Icon(Icons.local_offer_outlined),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 88,
              child: FilledButton(
                onPressed: busy ? null : () => applyCoupon(code.text.trim()),
                child: const AppText('تفعيل'),
              ),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: AppText(error!, style: const TextStyle(color: scarlet)),
          ),
        const SizedBox(height: 26),
        for (final c in coupons)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: couponCard(c),
          ),
        if (coupons.isEmpty)
          const PaperCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  CategoryIcon(Icons.local_offer, size: 64),
                  SizedBox(height: 16),
                  AppText(
                    'ماكو عروض مفعّلة حاليًا',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                  ),
                  AppText('عندك كود؟ فعّله هنا للرحلة القادمة'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget couponCard(Json c) {
    final used = c['status'] == 'used';
    final date = DateTime.tryParse('${c['expires_at']}');
    final expired =
        !used &&
        (c['status'] == 'expired' ||
            (date != null && !date.isAfter(DateTime.now())));
    final active = c['status'] == 'active' && !expired && !used;
    final label = used
        ? 'مستخدم'
        : expired
        ? 'منتهي'
        : active
        ? 'مفعّل'
        : c['status'] == 'saved'
        ? 'غير مفعّل'
        : 'غير متاح';
    final expiry = date == null ? 'غير محدد' : displayDateTime(c['expires_at']);
    final content = couponTicket(c, active, used, label, expiry);
    return GestureDetector(
      onTap: used
          ? () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const AppText('الكود مستخدم'),
                content: SelectableText(
                  'قمت باستخدامه بالرحلة\nرقم الرحلة: ${c['ride_id']}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const AppText('إغلاق'),
                  ),
                ],
              ),
            )
          : null,
      child: content,
    );
  }

  Widget couponTicket(
    Json c,
    bool active,
    bool used,
    String label,
    String expiry,
  ) {
    return PaperCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    const CategoryIcon(Icons.local_offer, size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppText(
                        active ? 'خصم الرحلة القادمة' : 'كود الخصم',
                        style: heading(16),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xffe8f8ee)
                            : const Color(0xfff1f1f1),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check,
                            color: active ? const Color(0xff19714f) : muted,
                            size: 18,
                          ),
                          SizedBox(width: 5),
                          AppText(
                            label,
                            style: TextStyle(
                              color: active ? const Color(0xff19714f) : muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AppText(
                  c['reward_type'] == 'free_ride' ? 'رحلة مجانية' : money(c['amount']),
                  style: heading(38).copyWith(color: active ? scarlet : muted),
                ),
                AppText(
                  active ? (c['reward_type'] == 'free_ride' ? 'رحلة واحدة بدون دفع كروة' : 'خصم على كروة رحلتك القادمة') : label,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                AppText(
                  'تاريخ الانتهاء: $expiry',
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const TicketDivider(),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppText('رمز الخصم', style: TextStyle(color: muted)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: themedSurface(context, const Color(0xfff4f5f7)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppText(
                          '${c['code']}',
                          formatNumbers: false,
                          style: heading(20),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: 'نسخ رمز الخصم',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: '${c['code']}'),
                          );
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: AppText('تم نسخ الكود')),
                            );
                        },
                        icon: const Icon(Icons.copy_outlined, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppText(
                        active
                            ? 'يُطبّق تلقائيًا على الرحلة القادمة'
                            : used
                            ? 'اضغط لعرض الرحلة المستخدمة'
                            : label,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                    if (active)
                      OutlinedButton(
                        onPressed: busy ? null : () => applyCoupon(''),
                        child: const AppText('حذف الكود'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
