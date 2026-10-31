import 'package:flutter/material.dart';
import 'package:taktooka/core/commerce_theme.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/commerce.dart';
import 'package:taktooka/pages/favorite_place_picker_page.dart';
import 'package:taktooka/models/address_choice.dart';

import 'chat_page.dart';
import 'restaurant_couriers_page.dart';

class RestaurantSettingsPage extends StatefulWidget {
  final Backend b;
  final Json restaurant;
  final VoidCallback? preview;
  const RestaurantSettingsPage({
    super.key,
    required this.b,
    required this.restaurant,
    this.preview,
  });
  @override
  State<RestaurantSettingsPage> createState() => _RestaurantSettingsPageState();
}

class _RestaurantSettingsPageState extends State<RestaurantSettingsPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, phone, address, description;
  late String image;
  dynamic point;
  TimeOfDay? closing;
  bool saving = false, uploading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final r = widget.restaurant;
    name = TextEditingController(text: r['name'] ?? '');
    phone = TextEditingController(
      text: r['phone'] ?? widget.b.profile?['phone'] ?? '',
    );
    address = TextEditingController(text: r['address'] ?? '');
    description = TextEditingController(text: r['description'] ?? '');
    image = r['image_path'] ?? '';
    point = r['location'];
    final parts = (r['closing_time'] ?? '').toString().split(':');
    if (parts.length >= 2)
      closing = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
  }

  @override
  void dispose() {
    for (final c in [name, phone, address, description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || uploading || !form.currentState!.validate()) return;
    if (image.isEmpty || point == null) {
      setState(() => error = 'أضف صورة المطعم وحدد موقعه');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.restaurant['open'] != false)
        await widget.b.enableOrderNotifications?.call();
      await commerceRpc(widget.b, 'restaurant_save', {
        'name': name.text.trim(),
        'phone': phone.text.trim(),
        'address': address.text.trim(),
        'description': description.text.trim(),
        'image_path': image,
        'location': point,
        'open': widget.restaurant['open'] ?? true,
        'closing_time': closing == null
            ? null
            : '${closing!.hour.toString().padLeft(2, '0')}:${closing!.minute.toString().padLeft(2, '0')}',
      });
      await widget.b.refresh();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ],
    ),
  );
  Widget field(
    String title,
    TextEditingController c, {
    bool number = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      minLines: lines,
      maxLines: lines,
      keyboardType: number ? TextInputType.phone : TextInputType.text,
      textDirection: number ? TextDirection.ltr : null,
      decoration: InputDecoration(labelText: title),
      validator: (v) => c == description
          ? null
          : (v ?? '').trim().length < (number ? 10 : 2)
          ? 'أكمل $title'
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.restaurant.isEmpty ? 'تسجيل المطعم' : 'إعدادات المطعم',
      ),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          section(
            'معلومات تسجيل الدخول',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('اسم الحساب', style: TextStyle(color: Colors.grey)),
                Text(
                  widget.b.profile?['name'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                const Text('رقم الهاتف', style: TextStyle(color: Colors.grey)),
                Text(
                  widget.b.profile?['phone'] ?? '',
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
          section(
            'معلومات المطعم',
            Column(
              children: [
                if (image.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      widget.b.db.storage
                          .from('restaurant-images')
                          .getPublicUrl(image),
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.storefront, size: 60),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: saving || uploading
                      ? null
                      : () async {
                          setState(() => uploading = true);
                          try {
                            final v = await pickRestaurantImage(widget.b);
                            if (v != null && mounted) setState(() => image = v);
                          } catch (e) {
                            if (mounted)
                              setState(() => error = commerceError(e));
                          } finally {
                            if (mounted) setState(() => uploading = false);
                          }
                        },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(uploading ? 'جار رفع الصورة…' : 'صورة المطعم'),
                ),
                const SizedBox(height: 16),
                field('اسم المطعم', name),
                field('رقم هاتف المطعم', phone, number: true),
                field('عنوان المطعم', address),
                field('وصف المطعم', description, lines: 2),
                OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final p = await Navigator.push<AddressChoice>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FavoritePlacePicker(
                                b: widget.b,
                                title: 'موقع المطعم',
                              ),
                            ),
                          );
                          if (p != null && mounted)
                            setState(() {
                              point = [p.point.latitude, p.point.longitude];
                              address.text = p.label;
                            });
                        },
                  icon: const Icon(Icons.location_on_outlined),
                  label: Text(
                    point == null ? 'حدد موقع المطعم' : 'تغيير موقع المطعم',
                  ),
                ),
              ],
            ),
          ),
          if (widget.restaurant.isNotEmpty)
            OutlinedButton.icon(
              onPressed: saving
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Theme(
                          data: commerceTheme(),
                          child: RestaurantCouriersPage(
                            b: widget.b,
                            enabled:
                                (widget
                                        .b
                                        .commerce['restaurant']?['self_delivery'] ??
                                    widget.restaurant['self_delivery']) ==
                                true,
                          ),
                        ),
                      ),
                    ),
              icon: const Icon(Icons.delivery_dining_outlined),
              label: const Text('التوصيل الذاتي وحسابات المندوبين'),
            ),
          if (widget.preview != null)
            OutlinedButton.icon(
              onPressed: saving ? null : widget.preview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('معاينة المطعم مثل ما يشوفه الزبون'),
            ),
          const SizedBox(height: 20),
          section(
            'وقت الإغلاق',
            Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('يغلق المطعم الساعة'),
                  subtitle: Text(
                    closing == null
                        ? 'بدون إغلاق تلقائي'
                        : '${(closing!.hourOfPeriod == 0 ? 12 : closing!.hourOfPeriod).toString().padLeft(2, '0')}:${closing!.minute.toString().padLeft(2, '0')} ${closing!.period == DayPeriod.am ? 'AM' : 'PM'}',
                    textDirection: TextDirection.ltr,
                  ),
                  trailing: const Icon(Icons.schedule),
                  onTap: saving
                      ? null
                      : () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime:
                                closing ?? const TimeOfDay(hour: 23, minute: 0),
                          );
                          if (t != null && mounted) setState(() => closing = t);
                        },
                ),
                const Text('يتوقف استقبال الطلبات عند الإغلاق بتوقيت بغداد'),
                if (closing != null)
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => setState(() => closing = null),
                    child: const Text('إلغاء الإغلاق التلقائي'),
                  ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('دعم تكتوكة')),
                  body: ChatPage(b: widget.b),
                ),
              ),
            ),
            icon: const Icon(Icons.headset_mic_outlined),
            label: const Text('دعم تكتوكة'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: saving || uploading ? null : save,
            child: Text(saving ? 'جار الحفظ…' : 'حفظ التغييرات'),
          ),
        ],
      ),
    ),
  );
}
