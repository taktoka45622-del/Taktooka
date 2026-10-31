import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/keyboard_dismiss.dart';

class MealDetailsPage extends StatefulWidget {
  final Json meal, restaurant;
  final bool favorite;
  final Future<bool> Function() toggleFavorite;
  final Widget Function(dynamic, {double height}) photo;
  final Json? initial;
  const MealDetailsPage({
    super.key,
    required this.meal,
    required this.restaurant,
    required this.favorite,
    required this.toggleFavorite,
    required this.photo,
    this.initial,
  });
  @override
  State<MealDetailsPage> createState() => _MealDetailsPageState();
}

class _MealDetailsPageState extends State<MealDetailsPage> {
  late final List<Json> sizes, addons;
  late final TextEditingController notes;
  final Set<String> selected = {};
  String? sizeId;
  int quantity = 1, photoIndex = 0;
  bool savingFavorite = false;
  late bool favorite;
  String? error;
  @override
  void initState() {
    super.initState();
    final config = widget.meal['options'] as Map? ?? {};
    sizes = [for (final v in config['sizes'] as List? ?? []) Json.from(v)];
    addons = [for (final v in config['addons'] as List? ?? []) Json.from(v)];
    sizeId = sizes.isEmpty ? null : sizes.first['id'];
    final previousSize = widget.initial?['size']?['id'];
    if (sizes.any((s) => s['id'] == previousSize)) sizeId = previousSize;
    final previousAddons = [
      for (final a in widget.initial?['addons'] as List? ?? []) a['id'],
    ];
    selected.addAll(
      addons
          .where((a) => previousAddons.contains(a['id']))
          .map((a) => a['id'].toString()),
    );
    quantity = (widget.initial?['quantity'] as num? ?? 1).toInt().clamp(1, 99);
    notes = TextEditingController(text: widget.initial?['notes'] ?? '');
    favorite = widget.favorite;
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Json? get size => sizes.where((s) => s['id'] == sizeId).firstOrNull;
  List<Json> get extras =>
      addons.where((a) => selected.contains(a['id'])).toList();
  int get basePrice =>
      (size?['price'] as num? ?? widget.meal['price'] as num).toInt();
  int get unitPrice =>
      basePrice +
      extras.fold<int>(0, (s, a) => s + (a['price'] as num).toInt());
  bool get available =>
      widget.meal['available'] != false && widget.restaurant['open'] != false;
  Future<void> toggle() async {
    if (savingFavorite) return;
    setState(() => savingFavorite = true);
    try {
      final v = await widget.toggleFavorite();
      if (mounted) setState(() => favorite = v);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر تحديث المفضلة؛ أعد المحاولة');
    } finally {
      if (mounted) setState(() => savingFavorite = false);
    }
  }

  Widget section(String title, String badge) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(child: Text(title, style: heading(21))),
        Chip(label: Text(badge, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final images = List<String>.from(widget.meal['image_paths'] ?? []);
    if (images.isEmpty) images.add(widget.meal['image_path'] ?? '');
    return DismissKeyboardOnOutsideTap(
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  SizedBox(
                    height:
                        MediaQuery.sizeOf(context).width.clamp(240, 430) * .85,
                    child: PageView.builder(
                      itemCount: images.length,
                      onPageChanged: (i) => setState(() => photoIndex = i),
                      itemBuilder: (_, i) =>
                          widget.photo(images[i], height: 430),
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 12,
                    right: 16,
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 12,
                    left: 16,
                    child: IconButton.filled(
                      tooltip: favorite
                          ? 'إزالة المطعم من المفضلة'
                          : 'حفظ المطعم في المفضلة',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: scarlet,
                      ),
                      onPressed: savingFavorite ? null : toggle,
                      icon: Icon(
                        favorite ? Icons.favorite : Icons.favorite_border,
                      ),
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < images.length; i++)
                            Container(
                              margin: const EdgeInsets.all(3),
                              height: 7,
                              width: i == photoIndex ? 18 : 7,
                              decoration: BoxDecoration(
                                color: i == photoIndex ? scarlet : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(18),
              sliver: SliverList.list(
                children: [
                  Text(widget.meal['name'] ?? '', style: heading(28)),
                  const SizedBox(height: 8),
                  Text(
                    widget.meal['description'] ?? '',
                    style: const TextStyle(color: Colors.grey, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.storefront_outlined, color: scarlet),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.restaurant['name'] ?? '',
                          style: heading(16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (widget.meal['previous_price'] != null)
                    Text(
                      money(widget.meal['previous_price']),
                      style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey,
                      ),
                    ),
                  Text(
                    money(unitPrice),
                    style: const TextStyle(
                      fontSize: 30,
                      color: scarlet,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (sizes.isNotEmpty) ...[
                    section('اختر الحجم', 'مطلوب'),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final single =
                            constraints.maxWidth < 340 ||
                            MediaQuery.textScalerOf(context).scale(16) > 22;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final s in sizes)
                              SizedBox(
                                width: single
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth - 10) / 2,
                                child: Semantics(
                                  selected: s['id'] == sizeId,
                                  button: true,
                                  child: InkWell(
                                    onTap: () =>
                                        setState(() => sizeId = s['id']),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: s['id'] == sizeId
                                            ? const Color(0xfffff2f3)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: s['id'] == sizeId
                                              ? scarlet
                                              : const Color(0xffe6e6e8),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  s['name'],
                                                  style: heading(17),
                                                ),
                                                Text(
                                                  money(s['price']),
                                                  style: TextStyle(
                                                    color: s['id'] == sizeId
                                                        ? scarlet
                                                        : Colors.black,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            s['id'] == sizeId
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_off,
                                            color: s['id'] == sizeId
                                                ? scarlet
                                                : Colors.grey,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  if (addons.isNotEmpty) ...[
                    section('إضافات', 'اختياري'),
                    for (final a in addons)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: () => setState(
                            () => selected.contains(a['id'])
                                ? selected.remove(a['id'])
                                : selected.add(a['id']),
                          ),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: selected.contains(a['id']),
                                  onChanged: (_) => setState(
                                    () => selected.contains(a['id'])
                                        ? selected.remove(a['id'])
                                        : selected.add(a['id']),
                                  ),
                                ),
                                if (a['image_path'] != null)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 10,
                                    ),
                                    child: SizedBox(
                                      width: 44,
                                      child: widget.photo(
                                        a['image_path'],
                                        height: 44,
                                      ),
                                    ),
                                  ),
                                Expanded(child: Text(a['name'])),
                                const SizedBox(width: 8),
                                Text(
                                  '+ ${money(a['price'])}',
                                  style: const TextStyle(
                                    color: scarlet,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                  section('ملاحظاتك للمطعم', 'اختياري'),
                  TextField(
                    controller: notes,
                    maxLength: 250,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'مثال: بدون بصل',
                      prefixIcon: Icon(Icons.edit_outlined),
                    ),
                  ),
                  if (!available)
                    const Text(
                      'الوجبة أو المطعم غير متاح للطلب حاليًا',
                      style: TextStyle(color: Colors.orange),
                    ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: scarlet)),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: LayoutBuilder(
              builder: (context, c) {
                final buttons = [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xffefc6cc)),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      textDirection: TextDirection.ltr,
                      children: [
                        IconButton(
                          tooltip: 'تقليل الكمية',
                          onPressed: quantity > 1
                              ? () => setState(() => quantity--)
                              : null,
                          icon: const Icon(Icons.remove),
                          color: scarlet,
                        ),
                        Text('$quantity', style: heading(18)),
                        IconButton(
                          tooltip: 'زيادة الكمية',
                          onPressed: quantity < 99
                              ? () => setState(() => quantity++)
                              : null,
                          icon: const Icon(Icons.add),
                          color: scarlet,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: !available
                        ? null
                        : () => Navigator.pop(context, <String, dynamic>{
                            ...widget.meal,
                            'quantity': quantity,
                            'price': unitPrice,
                            'base_price': basePrice,
                            'size_id': sizeId,
                            'size': size,
                            'addon_ids': selected.toList()..sort(),
                            'addons': extras,
                            'notes': notes.text.trim(),
                          }),
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: Text('أضف للسلة — ${money(unitPrice * quantity)}'),
                  ),
                ];
                return c.maxWidth < 330 ||
                        MediaQuery.textScalerOf(context).scale(16) > 22
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(alignment: Alignment.center, child: buttons[0]),
                          const SizedBox(height: 8),
                          buttons[1],
                        ],
                      )
                    : Row(
                        children: [
                          buttons[0],
                          const SizedBox(width: 10),
                          Expanded(child: buttons[1]),
                        ],
                      );
              },
            ),
          ),
        ),
      ),
    );
  }
}
