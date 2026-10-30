import 'package:taktooka/widgets/app_notice.dart';
import 'package:taktooka/core/numeric_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/feature_navigation.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/chat_page.dart';
import 'package:taktooka/pages/recovery_inbox_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/tuktuk_loader.dart';

class AdminFeatures extends StatefulWidget {
  final Backend b;
  const AdminFeatures({super.key, required this.b});
  @override
  State<AdminFeatures> createState() => _AdminFeaturesState();
}

class _AdminFeaturesState extends State<AdminFeatures> {
  Json data = {};
  bool loading = true, busy = false;
  String? error;
  int section = 0;
  final ids = <String, String>{};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final res = Json.from(await widget.b.extra('admin_snapshot') as Map);
      if (mounted)
        setState(() {
          data = res;
          loading = false;
          error = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          loading = false;
          error = readable(e);
        });
    }
  }

  Future<String?> prompt(
    String title,
    String hint, {
    bool numeric = false,
  }) async {
    final c = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: AppText(title),
        content: TextField(
          inputFormatters: const [GroupedNumberFormatter()],
          controller: c,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          decoration: localizedInput(context, InputDecoration(hintText: hint)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const AppText('متابعة'),
          ),
        ],
      ),
    );
    c.dispose();
    return value;
  }

  Future<bool> confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const AppText('تأكيد العملية المالية'),
          content: AppText(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const AppText('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const AppText('نعم، تم فعليًا'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> money(Json p, bool settle) async {
    if (busy) return;
    final v = await prompt(
      settle ? 'المبلغ المسدّد للكابتن' : 'المبلغ المستلم لشحن المحفظة',
      'المبلغ بالدينار',
      numeric: true,
    );
    final n = readNumber(v);
    if (n == null || n <= 0) {
      if (v != null && mounted) showAppNotice(context, 'اكتب مبلغ صحيح');
      return;
    }
    if (!mounted ||
        !await confirm(
          '${settle ? 'سلّمت' : 'استلمت'} $n دينار ${settle ? 'إلى' : 'من'} ${p['name']}؟',
        ))
      return;
    final key = '${p['user_id']}:${settle ? 'settle' : 'topup'}:$n';
    ids.putIfAbsent(key, () => const Uuid().v4());
    setState(() => busy = true);
    try {
      await widget.b.extra(settle ? 'settle' : 'topup', {
        'user_id': p['user_id'],
        'amount': n,
        'id': ids[key],
      });
      ids.remove(key);
      await load();
      await widget.b.refresh();
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> coupon() async {
    final code = await prompt('إنشاء كود خصم', 'مثال TAKTOOKA');
    if (code == null || code.isEmpty || !mounted) return;
    final amount = readNumber(
      await prompt('مبلغ الخصم', 'دينار', numeric: true) ?? '',
    );
    if (amount == null || !mounted) return;
    final days = readNumber(
      await prompt('مدة الصلاحية', 'عدد الأيام', numeric: true) ?? '',
    );
    if (days == null || days < 1 || days > 365 || !mounted) return;
    final uses = readNumber(
      await prompt(
            'عدد مرات الاستخدام الإجمالي',
            'كل مستخدم يستخدمه مرة واحدة',
            numeric: true,
          ) ??
          '',
    );
    if (uses == null || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.b.extra('coupon_admin', {
        'code': code,
        'amount': amount,
        'max_uses': uses,
        'expires_at': DateTime.now()
            .toUtc()
            .add(Duration(days: days))
            .toIso8601String(),
        'active': true,
      });
      await load();
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RecoveryInbox(backend: widget.b)),
          ),
          icon: const Icon(Icons.lock_reset),
          label: const AppText('طلبات استرجاع الحساب'),
        ),
        const AppText(
          'المحافظ والعروض والدعم',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: AppText('المحافظ')),
            ButtonSegment(value: 1, label: AppText('الأكواد')),
            ButtonSegment(value: 2, label: AppText('الدعم')),
          ],
          selected: {section},
          onSelectionChanged: (s) => setState(() => section = s.first),
        ),
        if (loading || busy) const TuktukLoader(),
        if (error != null) TextButton(onPressed: load, child: AppText(error!)),
        const SizedBox(height: 16),
        if (section == 0)
          for (final p in Backend.rows(data['wallets'] ?? []))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      '${p['name']} • ${p['phone']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    AppText(
                      '${p['captain'] ? 'مستحقات الكابتن' : 'رصيد المستخدم'}: ${p['balance'] ?? 0} دينار',
                    ),
                    if (p['captain_requested_at'] != null && !p['captain'])
                      const AppText(
                        'طلب الانضمام ككابتن؛ راجعه من تسجيل المركبات بالداشبورد',
                        style: TextStyle(color: brandRed),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: busy ? null : () => money(p, false),
                          child: const AppText('شحن بعد الاستلام'),
                        ),
                        if (p['captain'])
                          FilledButton(
                            onPressed: busy ? null : () => money(p, true),
                            child: const AppText('تأكيد تسديد للكابتن'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        if (section == 1) ...[
          FilledButton.icon(
            onPressed: busy ? null : coupon,
            icon: const Icon(Icons.add),
            label: const AppText('إنشاء كود خصم'),
          ),
          for (final c in Backend.rows(data['coupons'] ?? []))
            Card(
              child: ListTile(
                title: AppText(
                  c['reward_type'] == 'free_ride'
                      ? '${c['code']} • رحلة مجانية'
                      : '${c['code']} • ${c['amount']} دينار',
                ),
                subtitle: AppText(
                  'ينتهي ${c['expires_at'].toString().substring(0, 10)} • الحد ${c['max_uses']}',
                ),
                trailing: Switch(
                  value: c['active'],
                  onChanged: busy
                      ? null
                      : (v) async {
                          setState(() => busy = true);
                          try {
                            await widget.b.extra('coupon_admin', {
                              ...c,
                              'active': v,
                            });
                            await load();
                          } catch (e) {
                            if (mounted) setState(() => error = readable(e));
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                ),
              ),
            ),
        ],
        if (section == 2) ...[
          if (Backend.rows(data['rooms'] ?? []).isEmpty)
            const AppText('لا توجد محادثات دعم بعد'),
          for (final r in Backend.rows(data['rooms'] ?? []))
            Card(
              child: ListTile(
                title: AppText('${r['name']}'),
                subtitle: AppText(r['phone'] ?? ''),
                trailing: Badge(
                  isLabelVisible: (r['unread'] ?? 0) > 0,
                  label: AppText('${r['unread']}'),
                  child: const Icon(Icons.chat_bubble_outline),
                ),
                onTap: () async {
                  await openFeature(
                    context,
                    widget.b,
                    'الدعم',
                    () => ChatPage(
                      b: widget.b,
                      room: r['user_id'],
                      title: r['name'],
                    ),
                  );
                  await load();
                },
              ),
            ),
        ],
      ],
    ),
  );
}
