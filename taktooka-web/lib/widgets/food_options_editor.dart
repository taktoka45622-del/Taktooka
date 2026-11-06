import 'persistent_media_image.dart';
import 'package:taktooka/services/media_url.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/commerce.dart';

class FoodOptionsEditor extends StatelessWidget {
  final Backend b;
  final List<Json> sizes, addons;
  final ValueChanged<List<Json>> changeSizes, changeAddons;
  final bool disabled;
  const FoodOptionsEditor({
    super.key,
    required this.b,
    required this.sizes,
    required this.addons,
    required this.changeSizes,
    required this.changeAddons,
    this.disabled = false,
  });
  Future<void> edit(BuildContext context, bool size, [int? index]) async {
    final list = size ? sizes : addons;
    final result = await showDialog<Json>(
      context: context,
      builder: (_) => _OptionDialog(
        b: b,
        size: size,
        initial: index == null ? null : list[index],
      ),
    );
    if (result == null) return;
    final rows = [...list];
    if (index == null) {
      rows.add(result);
    } else {
      rows[index] = result;
    }
    (size ? changeSizes : changeAddons)(rows);
  }

  Widget group(BuildContext context, bool size) {
    final rows = size ? sizes : addons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Text(size ? 'أحجام الوجبة' : 'إضافات الوجبة', style: heading(20)),
        Text(
          size
              ? 'اختياري: السعر الكامل لكل حجم. سعر أول حجم هو السعر الأساسي.'
              : 'تُضاف أجرة كل إضافة إلى سعر كل وجبة مختارة.',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        for (var i = 0; i < rows.length; i++)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: !size && rows[i]['image_path'] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PersistentMediaImage(
                        mediaUrl(
                          supabaseUrl,
                          'restaurant-images',
                          rows[i]['image_path'],
                        ),
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.fastfood_outlined),
                      ),
                    )
                  : null,
              title: Text(rows[i]['name']),
              subtitle: Text(money(rows[i]['price'])),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'تعديل ${rows[i]['name']}',
                    onPressed: disabled ? null : () => edit(context, size, i),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'حذف ${rows[i]['name']}',
                    onPressed: disabled
                        ? null
                        : () {
                            final result = [...rows]..removeAt(i);
                            (size ? changeSizes : changeAddons)(result);
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        TextButton.icon(
          onPressed: disabled || rows.length >= (size ? 10 : 30)
              ? null
              : () => edit(context, size),
          icon: const Icon(Icons.add),
          label: Text(size ? 'إضافة حجم' : 'إضافة مع صورة وسعر'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      Column(children: [group(context, true), group(context, false)]);
}

class _OptionDialog extends StatefulWidget {
  final Backend b;
  final bool size;
  final Json? initial;
  const _OptionDialog({required this.b, required this.size, this.initial});
  @override
  State<_OptionDialog> createState() => _OptionDialogState();
}

class _OptionDialogState extends State<_OptionDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, price;
  String? image, error;
  bool uploading = false;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial?['name'] ?? '');
    price = TextEditingController(
      text: widget.initial?['price']?.toString() ?? '',
    );
    image = widget.initial?['image_path'];
  }

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    super.dispose();
  }

  int? get amount => int.tryParse(
    westernDigits(price.text).replaceAll(RegExp(r'[,،٬\s]'), ''),
  );
  Future<void> pick() async {
    setState(() => uploading = true);
    try {
      final rows = await pickMealImages(widget.b, remaining: 1);
      if (mounted && rows.isNotEmpty) setState(() => image = rows.first);
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.size ? 'حجم الوجبة' : 'إضافة للوجبة'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: widget.size ? 'اسم الحجم' : 'اسم الإضافة',
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'أدخل الاسم' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: widget.size ? 'سعر الحجم الكامل' : 'سعر الإضافة',
                suffixText: 'د.ع',
              ),
              validator: (_) =>
                  amount == null ||
                      amount! < (widget.size ? 1 : 0) ||
                      amount! > 1000000
                  ? 'تحقق من السعر'
                  : null,
            ),
            if (!widget.size) ...[
              const SizedBox(height: 12),
              if (image != null)
                PersistentMediaImage(
                  mediaUrl(supabaseUrl, 'restaurant-images', image!),
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.fastfood),
                ),
              TextButton.icon(
                onPressed: uploading ? null : pick,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  uploading
                      ? 'جار رفع الصورة…'
                      : image == null
                      ? 'صورة الإضافة'
                      : 'تغيير صورة الإضافة',
                ),
              ),
              if (image != null)
                TextButton(
                  onPressed: uploading
                      ? null
                      : () => setState(() => image = null),
                  child: const Text('إزالة الصورة'),
                ),
            ],
            if (error != null)
              Text(error!, style: const TextStyle(color: scarlet)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: uploading ? null : () => Navigator.pop(context),
        child: const Text('رجوع'),
      ),
      FilledButton(
        onPressed: uploading
            ? null
            : () {
                if (form.currentState!.validate())
                  Navigator.pop(context, <String, dynamic>{
                    'id': widget.initial?['id'] ?? const Uuid().v4(),
                    'name': name.text.trim(),
                    'price': amount,
                    if (image != null) 'image_path': image,
                  });
              },
        child: const Text('حفظ'),
      ),
    ],
  );
}
