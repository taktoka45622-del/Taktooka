import 'package:taktooka/widgets/skeleton.dart';
import 'package:taktooka/widgets/persistent_media_image.dart';
import 'package:taktooka/services/media_url.dart';
import 'package:taktooka/widgets/food_options_editor.dart';
import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/commerce.dart';

class MealEditorPage extends StatefulWidget {
  final Backend b;
  final Json? meal;
  const MealEditorPage({super.key, required this.b, this.meal});
  @override
  State<MealEditorPage> createState() => _MealEditorPageState();
}

class _MealEditorPageState extends State<MealEditorPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, description, price, previous;
  late List<String> images;
  late String category;
  late bool discounted, available;
  late int sort;
  bool saving = false, uploading = false;
  String? error;
  List<String> categories = [];
  String? catalogCategory;
  List<Json> sizes = [], addons = [];
  bool saveCategoryAddons = true, optionsLoading = false;
  bool optionsReady = true;
  String? optionsError;
  int optionsGeneration = 0;
  @override
  void initState() {
    super.initState();
    final m = widget.meal ?? {};
    saveCategoryAddons = widget.meal == null;
    name = TextEditingController(text: m['name'] ?? '');
    description = TextEditingController(text: m['description'] ?? '');
    price = TextEditingController(text: m['price']?.toString() ?? '');
    previous = TextEditingController(
      text: m['previous_price']?.toString() ?? '',
    );
    images = List<String>.from(m['image_paths'] ?? []);
    if (images.isEmpty && (m['image_path'] ?? '').toString().isNotEmpty)
      images.add(m['image_path']);
    category = m['category'] ?? 'أخرى';
    sizes = Backend.rows((m['options'] as Map?)?['sizes'] ?? []);
    addons = Backend.rows((m['options'] as Map?)?['addons'] ?? []);
    if (widget.meal == null) loadCategoryOptions();
    catalogCategory = m['catalog_source'] == 'manual'
        ? m['catalog_category']
        : null;
    discounted = m['previous_price'] != null;
    available = m['available'] ?? true;
    sort = (m['sort_order'] as num? ?? 0).toInt();
    loadCategories();
  }

  Future<void> loadCategories() async {
    try {
      final rows = await commerceRpc(widget.b, 'categories');
      if (mounted)
        setState(
          () => categories = (rows as List).map((v) => '$v').toSet().toList(),
        );
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    }
  }

  Future<void> loadCategoryOptions() async {
    final generation = ++optionsGeneration, target = category;
    setState(() {
      optionsLoading = true;
      optionsReady = false;
      optionsError = null;
    });
    try {
      final value = Json.from(
        await commerceRpc(widget.b, 'category_options', {'category': target})
            as Map,
      );
      if (mounted && generation == optionsGeneration)
        setState(() {
          addons = Backend.rows(value['addons'] ?? []);
          optionsReady = true;
        });
    } catch (e) {
      if (mounted && generation == optionsGeneration)
        setState(() {
          optionsError = commerceError(e);
          error = optionsError;
        });
    } finally {
      if (mounted && generation == optionsGeneration)
        setState(() => optionsLoading = false);
    }
  }

  Future<void> addCategory() async {
    final text = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('إضافة قسم للوجبات'),
        content: TextField(
          controller: text,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'اسم القسم'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () {
              if (text.text.trim().isNotEmpty)
                Navigator.pop(d, text.text.trim());
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    text.dispose();
    if (v == null || !mounted) return;
    try {
      await commerceRpc(widget.b, 'category_save', {'name': v});
      if (mounted)
        setState(() {
          categories = {...categories, v}.toList();
          category = v;
        });
      await loadCategoryOptions();
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    }
  }

  @override
  void dispose() {
    for (final c in [name, description, price, previous]) {
      c.dispose();
    }
    super.dispose();
  }

  int? amount(String s) =>
      int.tryParse(westernDigits(s).replaceAll(RegExp(r'[,،٬\s]'), ''));
  Widget field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    int lines = 1,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          minLines: lines,
          maxLines: lines,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          textDirection: numeric ? TextDirection.ltr : null,
          decoration: InputDecoration(suffixText: numeric ? 'د.ع' : null),
          onChanged: numeric
              ? (_) => setState(() {
                  if (controller == price &&
                      sizes.isNotEmpty &&
                      amount(price.text) != null &&
                      amount(price.text)! > 0) {
                    sizes = [
                      {...sizes.first, 'price': amount(price.text)},
                      ...sizes.skip(1),
                    ];
                  }
                })
              : null,
          validator: (v) {
            if (required && (v ?? '').trim().isEmpty) return 'هذا الحقل مطلوب';
            if (numeric &&
                (amount(v ?? '') == null ||
                    amount(v ?? '')! <= 0 ||
                    amount(v ?? '')! > 1000000))
              return 'أدخل سعراً بين 1 و1,000,000';
            if (controller == previous &&
                discounted &&
                amount(v ?? '') != null &&
                amount(price.text) != null &&
                amount(v ?? '')! <= amount(price.text)!)
              return 'السعر السابق يجب أن يكون أكبر من الحالي';
            return null;
          },
        ),
      ],
    ),
  );
  Future<void> addImages() async {
    if (uploading || images.length >= 10) return;
    setState(() {
      uploading = true;
      error = null;
    });
    try {
      final added = await pickMealImages(
        widget.b,
        remaining: 10 - images.length,
      );
      if (mounted) setState(() => images.addAll(added));
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> save() async {
    if (saving ||
        uploading ||
        optionsLoading ||
        !optionsReady ||
        !form.currentState!.validate())
      return;
    if (images.isEmpty) {
      setState(() => error = 'أضف صورة واحدة على الأقل للوجبة');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await commerceRpc(widget.b, 'item_save', {
        'id': widget.meal?['id'],
        'name': name.text.trim(),
        'description': description.text.trim(),
        'price': sizes.isEmpty ? amount(price.text) : sizes.first['price'],
        'options': {'sizes': sizes, 'addons': addons},
        'save_category_addons': saveCategoryAddons,
        'previous_price': discounted ? amount(previous.text) : null,
        'category': category,
        'catalog_category': catalogCategory,
        'catalog_mode': catalogCategory == null ? 'auto' : 'manual',
        'image_path': images.first,
        'image_paths': images,
        'available': available,
        'sort_order': sort,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = amount(price.text), old = amount(previous.text);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.meal == null ? 'إضافة وجبة' : 'تعديل الوجبة'),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'صور الوجبة',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('${images.length} / 10', textDirection: TextDirection.ltr),
              ],
            ),
            const SizedBox(height: 6),
            const Text('أضف حتى 10 صور'),
            const SizedBox(height: 12),
            SizedBox(
              height: 125,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                itemCount: images.length + (images.length < 10 ? 1 : 0),
                onReorderItem: (a, z) {
                  if (a >= images.length) return;
                  z = z.clamp(0, images.length - 1);
                  setState(() {
                    final v = images.removeAt(a);
                    images.insert(z, v);
                  });
                },
                itemBuilder: (context, i) {
                  if (i == images.length)
                    return SizedBox(
                      key: const ValueKey('add'),
                      width: 105,
                      child: OutlinedButton(
                        onPressed: uploading || saving ? null : addImages,
                        child: uploading
                            ? const SkeletonActivity(height: 16)
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [Icon(Icons.add), Text('إضافة صور')],
                              ),
                      ),
                    );
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(images[i]),
                    index: i,
                    child: SizedBox(
                      width: 120,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            InkWell(
                              onTap: saving
                                  ? null
                                  : () => setState(() {
                                      final v = images.removeAt(i);
                                      images.insert(0, v);
                                    }),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: PersistentMediaImage(
                                  mediaUrl(
                                    supabaseUrl,
                                    'restaurant-images',
                                    images[i],
                                  ),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.restaurant),
                                ),
                              ),
                            ),
                            if (i == 0)
                              const Positioned(
                                bottom: 4,
                                right: 4,
                                left: 4,
                                child: Chip(
                                  label: Text(
                                    'الرئيسية',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 0,
                              left: 0,
                              child: IconButton.filledTonal(
                                tooltip: 'حذف الصورة',
                                onPressed: saving
                                    ? null
                                    : () => setState(() => images.removeAt(i)),
                                icon: const Icon(Icons.close, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'اضغط لتحديد الرئيسية واضغط مطولاً لتغيير الترتيب',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 22),
            field('اسم الوجبة', name, required: true),
            DropdownButtonFormField<String>(
              key: ValueKey(category),
              initialValue: category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'القسم'),
              items: {...categories, category}
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(
                        c,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: saving || optionsLoading
                  ? null
                  : (v) async {
                      setState(() => category = v!);
                      await loadCategoryOptions();
                    },
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: saving ? null : addCategory,
              icon: const Icon(Icons.add),
              label: const Text('إضافة قسم جديد للمطعم'),
            ),
            DropdownButtonFormField<String>(
              initialValue: catalogCategory ?? '__auto__',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'القسم الرئيسي بالتطبيق',
              ),
              hint: const Text('تصنيف ذكي تلقائي'),
              items:
                  const [
                        '__auto__',
                        'الأكل الشرقي',
                        'الأكل الغربي',
                        'المشويات',
                        'الأسماك',
                        'الدجاج',
                        'الكيك',
                        'الحلويات',
                        'أخرى',
                      ]
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v == '__auto__' ? 'تصنيف ذكي تلقائي' : v),
                        ),
                      )
                      .toList(),
              onChanged: (v) =>
                  setState(() => catalogCategory = v == '__auto__' ? null : v),
            ),
            const SizedBox(height: 18),
            field('وصف الوجبة', description, lines: 2),
            if (optionsLoading) const SkeletonActivity(),
            if (optionsError != null)
              TextButton.icon(
                onPressed: optionsLoading ? null : loadCategoryOptions,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة تحميل إضافات القسم'),
              ),
            FoodOptionsEditor(
              b: widget.b,
              sizes: sizes,
              addons: addons,
              disabled: saving || uploading || optionsLoading,
              changeSizes: (v) => setState(() {
                sizes = v;
                if (v.isNotEmpty) price.text = v.first['price'].toString();
              }),
              changeAddons: (v) => setState(() => addons = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('حفظ الإضافات لهذا القسم'),
              subtitle: Text(
                'تظهر تلقائيًا عند إضافة وجبة جديدة في قسم $category. تبقى خيارات الوجبات المنشورة كما هي.',
              ),
              value: saveCategoryAddons,
              onChanged: saving || optionsLoading
                  ? null
                  : (v) => setState(() => saveCategoryAddons = v),
            ),
            const SizedBox(height: 18),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('عليها خصم'),
              value: discounted,
              onChanged: saving ? null : (v) => setState(() => discounted = v),
            ),
            if (discounted)
              field('السعر السابق', previous, numeric: true, required: true),
            field(
              discounted ? 'السعر الحالي' : 'سعر الوجبة',
              price,
              numeric: true,
              required: true,
            ),
            if (discounted && old != null && current != null && old > current)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'خصم ${((old - current) * 100 / old).round()}% • توفير ${money(old - current)}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const Text('ترتيب العرض'),
            Row(
              children: [
                IconButton(
                  onPressed: saving || sort == 0
                      ? null
                      : () => setState(() => sort--),
                  icon: const Icon(Icons.remove),
                ),
                Expanded(child: Text('$sort', textAlign: TextAlign.center)),
                IconButton(
                  onPressed: saving ? null : () => setState(() => sort++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('متوفرة للطلب'),
              subtitle: const Text('تظهر للزبائن ضمن قائمة المطعم'),
              value: available,
              onChanged: saving ? null : (v) => setState(() => available = v),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving || uploading || optionsLoading || !optionsReady
                  ? null
                  : save,
              child: Text(saving ? 'جار الحفظ…' : 'حفظ الوجبة'),
            ),
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );
  }
}
