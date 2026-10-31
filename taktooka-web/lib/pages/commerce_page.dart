import 'dart:async';
import 'package:taktooka/core/display_format.dart';

import 'food_tracking_page.dart';
import 'chat_page.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/pages/favorite_place_picker_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/commerce.dart';
import 'package:taktooka/services/map_navigation.dart';

class FoodPage extends StatefulWidget {
  final Backend b;
  final bool register;
  const FoodPage({super.key, required this.b, this.register = false});
  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> with WidgetsBindingObserver {
  Backend get b => widget.b;
  Json me = {}, accounts = {};
  List<Json> shops = [], orders = [], menu = [];
  Json? selected;
  final cart = <String, int>{};
  bool busy = false, loading = true, foreground = true;
  String? error;
  Timer? timer;
  int tab = 0;
  String requestId = const Uuid().v4();
  bool get owner => me['restaurant'] is Map;
  Json get restaurant => Json.from(me['restaurant'] as Map? ?? {});
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (foreground && !busy) load(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    foreground = s == AppLifecycleState.resumed;
    if (foreground) load(silent: true);
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (busy) return;
    try {
      final values = await Future.wait([
        commerceRpc(b, 'me'),
        commerceRpc(b, 'orders'),
        commerceRpc(b, 'accounts'),
      ]);
      if (!mounted) return;
      me = Json.from(values[0] as Map);
      orders = Backend.rows(values[1]);
      accounts = Json.from(values[2] as Map);
      if (owner) {
        selected = restaurant;
        menu = Backend.rows(
          await commerceRpc(b, 'menu', {'restaurant_id': restaurant['id']}),
        );
      } else if (!b.captain) {
        var position = b.knownPosition;
        if (position == null ||
            DateTime.now().difference(position.timestamp).inMinutes >= 10) {
          if (!silent)
            position = await b.locate(fresh: true);
          else
            position = null;
        }
        shops = position == null
            ? []
            : Backend.rows(
                await commerceRpc(b, 'restaurants', {
                  'location': [position.latitude, position.longitude],
                }),
              );
      }
      if (!mounted) return;
      setState(() {
        loading = false;
        if (!silent) error = null;
      });
      if (widget.register && !owner && !_registrationOpened) {
        _registrationOpened = true;
        await editRestaurant();
      }
    } catch (e) {
      if (mounted)
        setState(() {
          loading = false;
          if (!silent) error = commerceError(e);
        });
    }
  }

  bool _registrationOpened = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await load(silent: true);
  }

  Future<AddressChoice?> location(String title) =>
      Navigator.of(context).push<AddressChoice>(
        MaterialPageRoute(
          builder: (_) => FavoritePlacePicker(b: b, title: title),
        ),
      );
  Future<void> editRestaurant() async {
    final name = TextEditingController(text: restaurant['name'] ?? '');
    final phone = TextEditingController(
      text: restaurant['phone'] ?? b.profile?['phone'] ?? '',
    );
    final address = TextEditingController(text: restaurant['address'] ?? '');
    final description = TextEditingController(
      text: restaurant['description'] ?? '',
    );
    String image = restaurant['image_path'] ?? '';
    dynamic point = restaurant['location'];
    bool saving = false;
    String? message;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('تسجيل المطعم ومعلوماته'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in [
                  ('اسم المطعم', name),
                  ('رقم هاتف المطعم', phone),
                  ('عنوان المطعم', address),
                  ('وصف إعلاني للمطعم', description),
                ])
                  TextField(
                    controller: entry.$2,
                    decoration: InputDecoration(labelText: entry.$1),
                  ),
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final p = await location('موقع المطعم');
                          if (p != null)
                            update(
                              () =>
                                  point = [p.point.latitude, p.point.longitude],
                            );
                        },
                  icon: const Icon(Icons.location_on),
                  label: Text(
                    point == null ? 'حدد موقع المطعم' : 'تم تحديد الموقع',
                  ),
                ),
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          try {
                            final p = await pickRestaurantImage(b);
                            if (p != null) update(() => image = p);
                          } catch (e) {
                            update(() => message = commerceError(e));
                          }
                        },
                  icon: const Icon(Icons.photo_library),
                  label: Text(
                    image.isEmpty
                        ? 'صورة المطعم من الاستوديو'
                        : 'تم اختيار صورة المطعم',
                  ),
                ),
                if (message != null)
                  Text(message!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialog),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      update(() => saving = true);
                      try {
                        if (image.isEmpty) throw StateError('FIELDS_REQUIRED');
                        await commerceRpc(b, 'restaurant_save', {
                          'name': name.text.trim(),
                          'phone': phone.text.trim(),
                          'address': address.text.trim(),
                          'description': description.text.trim(),
                          'image_path': image,
                          'location': point,
                          'open': restaurant['open'] ?? true,
                        });
                        await b.refresh();
                        if (dialog.mounted) Navigator.pop(dialog);
                      } catch (e) {
                        update(() => message = commerceError(e));
                      } finally {
                        if (dialog.mounted) update(() => saving = false);
                      }
                    },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    for (final c in [name, phone, address, description]) {
      c.dispose();
    }
    await load();
  }

  Future<void> editItem([Json? existing]) async {
    final name = TextEditingController(text: existing?['name'] ?? '');
    final description = TextEditingController(
      text: existing?['description'] ?? '',
    );
    final price = TextEditingController(
      text: existing?['price']?.toString() ?? '',
    );
    final sort = TextEditingController(
      text: existing?['sort_order']?.toString() ?? '0',
    );
    String image = existing?['image_path'] ?? '';
    bool available = existing?['available'] ?? true, saving = false;
    String? message;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('صنف الطعام'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in [
                  ('اسم الصنف', name),
                  ('الوصف', description),
                  ('السعر بالدينار', price),
                  ('ترتيب العرض', sort),
                ])
                  TextField(
                    controller: entry.$2,
                    keyboardType: [price, sort].contains(entry.$2)
                        ? TextInputType.number
                        : TextInputType.text,
                    decoration: InputDecoration(labelText: entry.$1),
                  ),
                SwitchListTile(
                  title: const Text('متوفر'),
                  value: available,
                  onChanged: saving ? null : (v) => update(() => available = v),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          try {
                            final p = await pickRestaurantImage(b);
                            if (p != null) update(() => image = p);
                          } catch (e) {
                            update(() => message = commerceError(e));
                          }
                        },
                  child: Text(
                    image.isEmpty
                        ? 'اختر صورة من الاستوديو'
                        : 'تم اختيار الصورة',
                  ),
                ),
                if (message != null) Text(message!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialog),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      update(() => saving = true);
                      try {
                        await commerceRpc(b, 'item_save', {
                          'id': existing?['id'],
                          'name': name.text.trim(),
                          'description': description.text.trim(),
                          'price': int.tryParse(westernDigits(price.text)),
                          'sort_order':
                              int.tryParse(westernDigits(sort.text)) ?? 0,
                          'available': available,
                          'image_path': image,
                        });
                        if (dialog.mounted) Navigator.pop(dialog);
                      } catch (e) {
                        update(() => message = commerceError(e));
                      } finally {
                        if (dialog.mounted) update(() => saving = false);
                      }
                    },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    for (final c in [name, description, price, sort]) {
      c.dispose();
    }
    await load();
  }

  Widget photo(dynamic path, {double height = 130}) {
    if (path is! String || path.isEmpty)
      return SizedBox(
        height: height,
        child: const Icon(Icons.restaurant, size: 48, color: scarlet),
      );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        b.db.storage.from('restaurant-images').getPublicUrl(path),
        height: height,
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            SizedBox(height: height, child: const Icon(Icons.restaurant)),
      ),
    );
  }

  Future<void> openShop(Json shop) async {
    if (selected?['id'] != shop['id']) cart.clear();
    await run(() async {
      menu = Backend.rows(
        await commerceRpc(b, 'menu', {'restaurant_id': shop['id']}),
      );
      if (mounted) setState(() => selected = shop);
    });
  }

  int get subtotal => menu.fold<int>(
    0,
    (sum, i) => sum + (i['price'] as num).toInt() * (cart[i['id']] ?? 0),
  );
  Future<void> checkout() async {
    if (subtotal <= 0) return;
    final place = await location('عنوان توصيل الطعام');
    if (place == null || !mounted) return;
    await run(() async {
      final response = await b.db.functions.invoke(
        'taktooka-quote',
        body: {
          'pickup': selected!['location'],
          'force_fresh': true,
          'destination': [place.point.latitude, place.point.longitude],
        },
      );
      if (response.data is! Map || response.data['id'] == null)
        throw StateError('QUOTE_EXPIRED');
      final quote = Json.from(response.data as Map);
      final fresh = Json.from(await commerceRpc(b, 'me') as Map);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تأكيد الطلب — الدفع كاش عند الوصول'),
          content: Text(
            'الطعام: ${money(subtotal)}\nالتوصيل: ${money(quote['fare'])}\nرسوم الخدمة: ${money(fresh['service_fee'])}\nالمجموع: ${money(subtotal + (quote['fare'] as num).toInt() + (fresh['service_fee'] as num).toInt())}\nالعنوان: ${place.label}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('تأكيد الطلب'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await commerceRpc(b, 'order_create', {
        'request_id': requestId,
        'restaurant_id': selected!['id'],
        'quote_id': quote['id'],
        'customer_address': place.label,
        'expected_service_fee': fresh['service_fee'],
        'items': [
          for (final e in cart.entries)
            if (e.value > 0) {'id': e.key, 'quantity': e.value},
        ],
      });
      requestId = const Uuid().v4();
      cart.clear();
      if (mounted) setState(() => tab = 1);
    });
  }

  Future<String?> askText(String title, {bool numeric = false}) async {
    final c = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, c.text.trim()),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    c.dispose();
    return result;
  }

  Future<bool> change(Json o, String status, {String? vehicle}) async {
    bool success = false;
    String? reason;
    if (status == 'rejected') {
      reason = await askText('سبب الرفض');
      if (reason == null || reason.isEmpty) return false;
    }
    await run(() async {
      await commerceRpc(b, 'order_update', {
        'id': o['id'],
        'status': status,
        'vehicle': vehicle,
        'reason': reason,
      });
      success = true;
    });
    return success;
  }

  Future<void> navigate(Json o, bool toRestaurant) async {
    final point =
        o[toRestaurant ? 'restaurant_location' : 'customer_location'] as List;
    await MapNavigation.open(
      context,
      (point[0] as num).toDouble(),
      (point[1] as num).toDouble(),
    );
  }

  Widget orderCard(Json o) {
    final status = o['status'] as String;
    final mine = o['captain_id'] == b.db.auth.currentUser!.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${o['restaurant_name']} · ${foodStates[status]}',
              style: heading(18),
            ),
            Text('رقم الطلب: ${o['id'].toString().substring(0, 8)}'),
            if (o['captain_id'] != null)
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FoodTrackingPage(b: b, orderId: o['id']),
                  ),
                ),
                icon: const Icon(Icons.map),
                label: const Text('الخريطة وتتبع الطلب'),
              ),
            for (final item in o['items'] as List)
              Text(
                '${item['quantity']} × ${item['name']} — ${money((item['price'] as num) * (item['quantity'] as num))}',
              ),
            const Divider(),
            Text(
              'الطعام: ${money(o['food_total'])} | التوصيل: ${money(o['delivery_fee'])}\nرسوم الخدمة: ${money(o['service_fee'])}\nالمجموع كاش: ${money((o['food_total'] as num) + (o['delivery_fee'] as num) + (o['service_fee'] as num))}',
            ),
            Text('العنوان: ${o['customer_address']}'),
            if (owner || b.captain) Text('هاتف الزبون: ${o['customer_phone']}'),
            if (o['captain_id'] != null)
              Text(
                'الكابتن: ${o['captain_name']}\nهاتف الكابتن: ${o['captain_phone']}',
              ),
            if (o['reason'] != '') Text('السبب: ${o['reason']}'),
            if (!owner && !b.captain && status == 'pending')
              TextButton(
                onPressed: busy ? null : () => change(o, 'rejected'),
                child: const Text('إلغاء الطلب مع ذكر السبب'),
              ),
            if (owner && status == 'pending') ...[
              FilledButton(
                onPressed: busy ? null : () => change(o, 'preparing'),
                child: const Text('قبول الطلب'),
              ),
              TextButton(
                onPressed: busy ? null : () => change(o, 'rejected'),
                child: const Text('رفض مع ذكر السبب'),
              ),
            ],
            if (owner && status == 'preparing')
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => change(o, 'searching', vehicle: 'tuktuk'),
                    child: const Text('طلب مندوب تكتك'),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => change(o, 'searching', vehicle: 'bike'),
                    child: const Text('طلب مندوب دراجة'),
                  ),
                ],
              ),
            if (b.captain && status == 'searching' && !mine)
              FilledButton(
                onPressed: busy ? null : () => change(o, 'accepted'),
                child: const Text('قبول توصيل الطلب'),
              ),
            if (mine && status == 'accepted')
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final success = await change(o, 'heading');
                        if (mounted && success) await navigate(o, true);
                      },
                child: const Text('التوجه للمطعم'),
              ),
            if (mine && status == 'heading')
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final success = await change(o, 'picked_up');
                        if (mounted && success) await navigate(o, false);
                      },
                child: const Text('استلمت الطلب — التوجه للزبون'),
              ),
            if (mine && status == 'picked_up')
              FilledButton(
                onPressed: busy ? null : () => change(o, 'delivered'),
                child: const Text('تم التوصيل'),
              ),
            if (mine && ['accepted', 'heading', 'picked_up'].contains(status))
              TextButton(
                onPressed: busy ? null : () => change(o, 'rejected'),
                child: const Text('رفض مع ذكر السبب'),
              ),
            if (mine && status == 'delivered')
              const Text(
                'يجب التوجه للمطعم وتسليمه الأموال',
                style: TextStyle(color: scarlet, fontWeight: FontWeight.bold),
              ),
            if (owner && o['captain_id'] != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final reason = await askText('شكوى على المندوب');
                        if (reason != null)
                          await run(() async {
                            await commerceRpc(b, 'complaint', {
                              'captain_id': o['captain_id'],
                              'body': reason,
                            });
                          });
                      },
                child: const Text('شكوى للدعم'),
              ),
            if (!owner &&
                !b.captain &&
                ['delivered', 'rejected'].contains(status))
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        final shopsNow = Backend.rows(
                          await commerceRpc(b, 'restaurants', {
                            'location': o['customer_location'],
                          }),
                        );
                        final matches = shopsNow.where(
                          (r) => r['id'] == o['restaurant_id'],
                        );
                        if (matches.isEmpty) {
                          if (mounted)
                            setState(
                              () => error =
                                  'المطعم مغلق حالياً أو غير متاح؛ جرّب لاحقاً',
                            );
                          return;
                        }
                        await openShop(matches.first);
                        final available = menu.map((i) => i['id']).toSet();
                        cart.clear();
                        for (final item in o['items'] as List) {
                          if (available.contains(item['id']))
                            cart[item['id']] = item['quantity'] as int;
                        }
                        if (mounted) setState(() => tab = 0);
                      },
                child: const Text('إعادة الطلب — مراجعة الأسعار الحالية'),
              ),
          ],
        ),
      ),
    );
  }

  Widget accountView() {
    final debts = Backend.rows(accounts['debts']);
    final settlements = Backend.rows(accounts['settlements']);
    final open = debts.where((d) => d['settled_at'] == null).toList();
    final own = b.db.auth.currentUser!.id;
    final company = open
        .where(
          (d) =>
              d['debtor_id'] == own &&
              d['kind'] == (owner ? 'restaurant_fee' : 'captain_company'),
        )
        .fold<num>(0, (s, d) => s + (d['amount'] as num));
    final statistics = Backend.rows(accounts['statistics']);
    int countFor(String key, String field) => statistics
        .where(
          (row) =>
              owner ? row['captain_id'] == key : row['restaurant_id'] == key,
        )
        .fold<int>(0, (sum, row) => sum + (row[field] as num).toInt());
    final groups = <String, List<Json>>{};
    for (final d in open.where((d) => d['kind'] == 'captain_restaurant')) {
      groups
          .putIfAbsent(owner ? d['debtor_id'] : d['restaurant_id'], () => [])
          .add(d);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (owner || b.captain)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    owner
                        ? 'نسبة التطبيق المأخوذة من الزبائن والمخزونة لديك'
                        : 'أموال الشركة — يجب تسديدها',
                    style: heading(18),
                  ),
                  Text(money(company), style: heading(26)),
                  FilledButton(
                    onPressed: busy || company <= 0
                        ? null
                        : () => run(() async {
                            await commerceRpc(b, 'settlement_request', {
                              'kind': owner
                                  ? 'restaurant_fee'
                                  : 'captain_company',
                            });
                          }),
                    child: Text(
                      owner ? 'تصفير حساب الشركة' : 'طلب تسديد أموال الشركة',
                    ),
                  ),
                  const Text(
                    'يرسل طلباً للإدارة؛ يتصفّر المبلغ بعد تأكيد استلام التسديد.',
                  ),
                ],
              ),
            ),
          ),
        for (final g in groups.entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    owner
                        ? '${g.value.first['captain_name']} — ${g.value.first['captain_phone']}'
                        : '${g.value.first['restaurant_name']}\n${g.value.first['restaurant_phone']}\n${g.value.first['restaurant_address']}',
                    style: heading(18),
                  ),
                  Text(
                    'المبلغ بالذمة: ${money(g.value.fold<num>(0, (s, d) => s + (d['amount'] as num)))}',
                  ),
                  Text(
                    'تم توصيل: ${countFor(g.key, 'delivered')} · مرفوض: ${countFor(g.key, 'rejected')}',
                  ),
                  if (owner)
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              final value = Json.from(
                                await commerceRpc(b, 'settlement_request', {
                                      'kind': 'captain_restaurant',
                                      'captain_id': g.key,
                                    })
                                    as Map,
                              );
                              if (!mounted) return;
                              await showDialog<void>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('كود تسديد المطعم'),
                                  content: SelectableText(
                                    'المبلغ: ${money(value['amount'])}\nالكود: ${value['code']}\nصالح 15 دقيقة؛ أعطه للكابتن بعد استلام المبلغ فقط.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('تم'),
                                    ),
                                  ],
                                ),
                              );
                            }),
                      child: const Text('استلمت المبلغ — إصدار كود التسديد'),
                    ),
                  if (!owner)
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final pending = settlements.where(
                                (s) =>
                                    s['kind'] == 'captain_restaurant' &&
                                    s['restaurant_id'] == g.key &&
                                    s['status'] == 'pending',
                              );
                              if (pending.isEmpty) {
                                setState(
                                  () => error =
                                      'اطلب كود التسديد من المطعم أولاً',
                                );
                                return;
                              }
                              final code = await askText(
                                'كود التسديد من المطعم',
                                numeric: true,
                              );
                              if (code == null) return;
                              await run(() async {
                                final result =
                                    await commerceRpc(b, 'settlement_confirm', {
                                      'id': pending.first['id'],
                                      'code': westernDigits(code),
                                    });
                                if (result['ok'] != true)
                                  throw StateError(result['error']);
                              });
                            },
                      child: const Text('إدخال كود التسديد — اكتمل التسديد'),
                    ),
                ],
              ),
            ),
          ),
        const Text(
          'سجل التسديدات',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final s in settlements)
          ListTile(
            title: Text(money(s['amount'])),
            subtitle: Text(
              '${displayDateTime(s['created_at'])} · ${s['status'] == 'confirmed'
                  ? 'تم التسديد'
                  : s['status'] == 'pending'
                  ? 'بانتظار التأكيد'
                  : 'منتهي'}',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        owner
            ? 'داشبورد المطعم'
            : b.captain
            ? 'طلبات الطعام'
            : 'طعام',
      ),
      actions: [
        IconButton(
          tooltip: 'الدعم',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatPage(b: b)),
          ),
          icon: const Icon(Icons.headset_mic_outlined),
        ),
        if (owner)
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: () => run(() async {
              await b.signOut();
              if (mounted)
                Navigator.of(context).popUntil((route) => route.isFirst);
            }),
            icon: const Icon(Icons.logout),
          ),
        if (owner)
          IconButton(
            onPressed: busy ? null : editRestaurant,
            icon: const Icon(Icons.edit),
          ),
        IconButton(
          onPressed: busy ? null : () => load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (busy) const LinearProgressIndicator(),
              if (b.captain)
                SwitchListTile(
                  title: const Text('استقبال طلبات التوصيل'),
                  value: b.tracking,
                  onChanged: busy || me['food_active'] == true
                      ? null
                      : (value) => run(() async {
                          if (value) {
                            await b.startTracking();
                          } else {
                            await b.stopTracking();
                          }
                        }),
                ),
              if (me['debt_blocked'] == true)
                ListTile(
                  title: const Text(
                    'يرجى تسديد حساب الشركة لاستقبال طلبات جديدة',
                  ),
                  trailing: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChatPage(b: b)),
                    ),
                    child: const Text('تجديد'),
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in [
                    (
                      0,
                      owner
                          ? 'القائمة'
                          : b.captain
                          ? 'الطلبات المتاحة'
                          : 'المطاعم',
                    ),
                    (1, 'الطلبات السابقة والحالية'),
                    (2, 'الحسابات والتسديد'),
                  ])
                    ChoiceChip(
                      label: Text(entry.$2),
                      selected: tab == entry.$1,
                      onSelected: (_) => setState(() => tab = entry.$1),
                    ),
                ],
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (tab == 2)
                        accountView()
                      else if (tab == 1 || b.captain) ...[
                        if (orders.isEmpty) const Text('لا توجد طلبات حالياً'),
                        for (final o in orders) orderCard(o),
                      ] else if (selected == null) ...[
                        Text(
                          'نطاق المطاعم: ${me['restaurant_min_distance_m'] ?? 0} – ${me['restaurant_max_distance_m'] ?? 15000} متر من موقعك',
                        ),
                        if (shops.isEmpty)
                          const Text('لا توجد مطاعم متاحة حالياً'),
                        for (final shop in shops)
                          Card(
                            child: InkWell(
                              onTap: busy ? null : () => openShop(shop),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    photo(shop['image_path']),
                                    Text(shop['name'], style: heading(21)),
                                    Text(shop['description']),
                                    Text(shop['address']),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ] else ...[
                        if (!owner)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                selected = null;
                                cart.clear();
                              });
                            },
                            child: const Text('كل المطاعم'),
                          ),
                        Text(selected!['name'], style: heading(24)),
                        if (owner) ...[
                          FilledButton(
                            onPressed: busy ? null : () => editItem(),
                            child: const Text('إضافة صنف'),
                          ),
                          SwitchListTile(
                            title: const Text('المطعم مفتوح لاستقبال الطلبات'),
                            value: restaurant['open'] ?? true,
                            onChanged: busy
                                ? null
                                : (value) => run(() async {
                                    await commerceRpc(b, 'restaurant_save', {
                                      ...restaurant,
                                      'open': value,
                                    });
                                  }),
                          ),
                        ],
                        for (final item in menu)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  photo(item['image_path']),
                                  Text(item['name'], style: heading(20)),
                                  Text(item['description']),
                                  Text(money(item['price'])),
                                  if (owner)
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => editItem(item),
                                      child: const Text(
                                        'تعديل الصنف والصورة والترتيب',
                                      ),
                                    )
                                  else
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          onPressed: busy
                                              ? null
                                              : () => setState(
                                                  () => cart[item['id']] =
                                                      (cart[item['id']] ?? 0) >
                                                          0
                                                      ? cart[item['id']]! - 1
                                                      : 0,
                                                ),
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                          ),
                                        ),
                                        Text('${cart[item['id']] ?? 0}'),
                                        IconButton(
                                          onPressed: busy
                                              ? null
                                              : () => setState(
                                                  () => cart[item['id']] =
                                                      ((cart[item['id']] ?? 0) +
                                                              1)
                                                          .clamp(0, 99)
                                                          .toInt(),
                                                ),
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (!owner && subtotal > 0) ...[
                          Text(
                            'السلة — ${money(subtotal)}',
                            style: heading(22),
                          ),
                          for (final item in menu.where(
                            (i) => (cart[i['id']] ?? 0) > 0,
                          ))
                            Text('${cart[item['id']]} × ${item['name']}'),
                          FilledButton(
                            onPressed: busy ? null : checkout,
                            child: const Text('حدد عنوانك واحسب التوصيل'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
  );
}
