import 'package:taktooka/services/refresh_gate.dart';
import 'package:taktooka/services/page_snapshot_cache.dart';
import 'package:taktooka/widgets/skeleton.dart';
import 'package:taktooka/core/design.dart' show money;
import 'package:taktooka/services/food_contact.dart';

import 'dart:async';

import 'package:taktooka/core/display_format.dart';

import 'commerce_dialogs.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/commerce.dart';
import 'package:taktooka/widgets/commerce_ui.dart';

class RestaurantCouriersPage extends StatefulWidget {
  final Backend b;
  final bool enabled;
  const RestaurantCouriersPage({
    super.key,
    required this.b,
    required this.enabled,
  });
  @override
  State<RestaurantCouriersPage> createState() => _RestaurantCouriersPageState();
}

class _RestaurantCouriersPageState extends State<RestaurantCouriersPage> {
  late bool enabled;
  bool loading = true, busy = false, fetching = false;
  List<Json> couriers = [];
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    enabled = widget.enabled;
    final snapshot = PageSnapshotCache.read(widget.b, 'restaurant-couriers');
    if (snapshot != null) {
      couriers = Backend.rows(snapshot['rows']);
      loading = false;
    }
    load();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  final _manualRefreshGate = RefreshGate();
  Future<void> load() => _manualRefreshGate.run((_) => _loadOnce());

  Future<void> _loadOnce() async {
    if (fetching || busy) return;
    fetching = true;
    final session = widget.b.cacheEpoch;
    try {
      final rows = Backend.rows(await commerceRpc(widget.b, 'courier_list'));
      if (!mounted || session != widget.b.cacheEpoch) return;
      PageSnapshotCache.save(widget.b, 'restaurant-couriers', {'rows': rows});
      if (mounted)
        setState(() {
          couriers = rows;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      fetching = false;
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> account([Json? courier]) async {
    final name = TextEditingController(),
        phone = TextEditingController(),
        password = TextEditingController();
    final form = GlobalKey<FormState>();
    bool submitting = false;
    String? failure;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => PopScope(
          canPop: !submitting,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(sheet).bottom,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        courier == null
                            ? 'إضافة مندوب خاص'
                            : 'تغيير كلمة سر ${courier['name']}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (courier == null) ...[
                        TextFormField(
                          controller: name,
                          enabled: !submitting,
                          decoration: const InputDecoration(
                            labelText: 'اسم المندوب',
                          ),
                          validator: (v) => (v ?? '').trim().length < 2
                              ? 'اكتب اسم المندوب'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phone,
                          enabled: !submitting,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف',
                          ),
                          validator: (v) =>
                              RegExp(r'^(07\d{9}|\+?9647\d{9})$').hasMatch(
                                westernDigits(v ?? '').replaceAll(' ', ''),
                              )
                              ? null
                              : 'اكتب رقم هاتف عراقي صحيح',
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: password,
                        enabled: !submitting,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'كلمة السر',
                        ),
                        validator: (v) =>
                            (v ?? '').length < 8 ? '8 أحرف على الأقل' : null,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'يسجّل المندوب دخوله برقم هاتفه وكلمة السر. الحساب خاص بتوصيل طلبات مطعمك.',
                      ),
                      if (failure != null)
                        Text(
                          failure!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: submitting
                            ? null
                            : () async {
                                if (!form.currentState!.validate()) return;
                                update(() {
                                  submitting = true;
                                  failure = null;
                                });
                                try {
                                  final response = await widget.b.db.functions
                                      .invoke(
                                        'taktooka-restaurant-courier',
                                        body: {
                                          'op': courier == null
                                              ? 'create'
                                              : 'password',
                                          if (courier != null)
                                            'user_id': courier['user_id'],
                                          'name': name.text.trim(),
                                          'phone': westernDigits(phone.text),
                                          'password': password.text,
                                        },
                                      )
                                      .timeout(const Duration(seconds: 20));
                                  if (response.data is! Map ||
                                      response.data['ok'] != true)
                                    throw StateError('REGISTER_UNAVAILABLE');
                                  if (sheet.mounted) Navigator.pop(sheet);
                                } catch (e) {
                                  if (sheet.mounted)
                                    update(() => failure = commerceError(e));
                                } finally {
                                  if (sheet.mounted)
                                    update(() => submitting = false);
                                }
                              },
                        child: Text(
                          submitting
                              ? 'جار الحفظ…'
                              : courier == null
                              ? 'إنشاء حساب المندوب'
                              : 'حفظ كلمة السر',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    name.dispose();
    phone.dispose();
    password.dispose();
    await load();
  }

  Widget courierCard(Json c) {
    final at = DateTime.tryParse('${c['location_at']}');
    final fresh =
        c['online'] == true &&
        at != null &&
        DateTime.now().toUtc().difference(at.toUtc()).inSeconds < 90;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${c['name']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  c['active'] != true
                      ? 'موقوف'
                      : c['busy'] == true
                      ? 'يوصل طلب'
                      : fresh
                      ? 'متصل'
                      : 'غير متصل',
                  style: TextStyle(
                    color: fresh ? Colors.green.shade700 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            Text('${c['phone']}', textDirection: TextDirection.ltr),
            const Divider(height: 24),
            CommerceAmountRow('ذمة المندوب للمطعم', (c['due'] as num?) ?? 0),
            CommerceAmountRow(
              'الكاش المستلم من الزبائن',
              (c['cash_collected'] as num?) ?? 0,
            ),
            CommerceAmountRow(
              'إجمالي أجور التوصيل',
              (c['delivery_total'] as num?) ?? 0,
            ),
            Text('طلبات تم توصيلها: ${c['delivered'] ?? 0}'),
            if (at != null)
              Text(
                'آخر تحديث موقع: ${displayDateTime(c['location_at'])}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      launchUrl(Uri(scheme: 'tel', path: '${c['phone']}')),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('اتصال'),
                ),
                OutlinedButton.icon(
                  onPressed: () => openFoodWhatsApp(
                    c['phone'],
                    message:
                        'تكتوكة — مندوب المطعم\n${c['name']}\nحساب المطعم: ${money(c['due'])}\nطلبات موصلة: ${c['delivered'] ?? 0}',
                  ),
                  icon: const Icon(
                    Icons.chat_outlined,
                    color: Color(0xff128c7e),
                  ),
                  label: const Text('واتساب'),
                ),
                if (c['lat'] != null && c['lng'] != null)
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.https('www.google.com', '/maps/search/', {
                        'api': '1',
                        'query': '${c['lat']},${c['lng']}',
                      }),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.location_on_outlined),
                    label: Text(fresh ? 'موقع المندوب' : 'آخر موقع معروف'),
                  ),
                TextButton(
                  onPressed: busy ? null : () => account(c),
                  child: const Text('تغيير كلمة السر'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('الحساب فعّال'),
              subtitle: const Text('إيقاف الحساب يمنع استقبال طلبات جديدة'),
              value: c['active'] == true,
              onChanged: busy || c['busy'] == true
                  ? null
                  : (v) async {
                      await action(() async {
                        await commerceRpc(widget.b, 'courier_active', {
                          'user_id': c['user_id'],
                          'active': v,
                        });
                      });
                      await load();
                    },
            ),
            if (((c['due'] as num?) ?? 0) > 0)
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => action(() async {
                        final value = Json.from(
                          await commerceRpc(widget.b, 'settlement_request', {
                                'kind': 'captain_restaurant',
                                'captain_id': c['user_id'],
                              })
                              as Map,
                        );
                        if (mounted)
                          await showRestaurantSettlementCode(context, value);
                      }),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('استلام تسديد المندوب — إصدار كود'),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('سجل تسديدات المندوب'),
              children: [
                if (Backend.rows(c['settlements']).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('لا توجد تسديدات بعد'),
                  ),
                ...Backend.rows(c['settlements']).map(
                  (s) => SettlementRecord(
                    record: {
                      ...s,
                      'payer_name': c['name'],
                      'payer_phone': c['phone'],
                      'recipient_name':
                          widget.b.commerce['restaurant']?['name'] ?? 'المطعم',
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('التوصيل الذاتي والمندوبين'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: loading
        ? const SkeletonPage()
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (busy) const SkeletonActivity(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('استخدام مندوبين المطعم'),
                  subtitle: const Text(
                    'الطلب الخاص يصل لمندوبينك فقط، والعام يبحث عن مندوب تكتوكة',
                  ),
                  value: enabled,
                  onChanged: busy
                      ? null
                      : (v) => action(() async {
                          await commerceRpc(widget.b, 'self_delivery_save', {
                            'enabled': v,
                          });
                          if (mounted) setState(() => enabled = v);
                          await widget.b.refresh();
                        }),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : () => account(),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('إضافة مندوب خاص'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 16),
                if (couriers.isEmpty)
                  const Text(
                    'أضف حسابات مندوبينك حتى تستقبل طلبات التوصيل الخاصة.',
                  ),
                ...couriers.map(courierCard),
              ],
            ),
          ),
  );
}
