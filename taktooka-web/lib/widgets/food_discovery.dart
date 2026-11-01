import 'food_price_filter.dart';
import 'dart:async';

import 'favorite_restaurants.dart';

import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';

const foodCatalogCategories = [
  'الأكل الشرقي',
  'الأكل الغربي',
  'المشويات',
  'الأسماك',
  'الدجاج',
  'الكيك',
  'الحلويات',
];

class FoodDiscovery extends StatelessWidget {
  final List<Json> restaurants, meals;
  final Future<List<Json>> Function(String)? findMeals;
  final List<Json> favorites;
  final bool Function(Json)? isFavorite;
  final ValueChanged<Json>? toggleFavorite;
  final String selectedCategory, area;
  final bool offers, locating;
  final ValueChanged<String> search, category;
  final VoidCallback filter, currentLocation, chooseLocation;
  final ValueChanged<Json> openRestaurant, openMeal;
  final Widget banner;
  final Widget Function(dynamic, {double height}) photo;
  const FoodDiscovery({
    super.key,
    required this.restaurants,
    this.favorites = const [],
    this.isFavorite,
    this.toggleFavorite,
    required this.meals,
    this.findMeals,
    required this.selectedCategory,
    required this.area,
    required this.offers,
    required this.locating,
    required this.search,
    required this.category,
    required this.filter,
    required this.currentLocation,
    required this.chooseLocation,
    required this.openRestaurant,
    required this.openMeal,
    required this.banner,
    required this.photo,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('شنو مشتهي اليوم؟', style: heading(28)),
      const Text(
        'اختار مطعمك وخلّي الباقي علينا',
        style: TextStyle(color: Colors.grey),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: TextField(
              readOnly: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FoodSearchPage(
                    meals: meals,
                    restaurants: restaurants,
                    openRestaurant: openRestaurant,
                    findMeals: findMeals,
                    photo: photo,
                    open: openMeal,
                  ),
                ),
              ),
              decoration: const InputDecoration(
                hintText: 'ابحث عن مطعم أو أكلة',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'تصفية أسعار الطعام',
            onPressed: filter,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      const SizedBox(height: 16),
      banner,
      const SizedBox(height: 16),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final key in ['الكل', 'العروض', ...foodCatalogCategories])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  selectedColor: scarlet,
                  labelStyle: TextStyle(
                    color:
                        (key == 'العروض'
                            ? offers
                            : key == 'الكل'
                            ? selectedCategory.isEmpty && !offers
                            : key == selectedCategory)
                        ? Colors.white
                        : Colors.black87,
                  ),
                  label: key == 'العروض' ? const OfferNeon() : Text(key),
                  selected: key == 'العروض'
                      ? offers
                      : key == 'الكل'
                      ? selectedCategory.isEmpty && !offers
                      : key == selectedCategory,
                  onSelected: (_) => category(key),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xfffff0f2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: scarlet),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                area == 'موقعي الحالي' ? area : 'موقعي الحالي – $area',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'استخدم موقعي',
              onPressed: locating ? null : currentLocation,
              icon: const Icon(Icons.my_location, color: scarlet),
            ),
            TextButton(onPressed: chooseLocation, child: const Text('تغيير')),
          ],
        ),
      ),
      FavoriteRestaurants(
        restaurants: favorites,
        toggle: toggleFavorite,
        open: openRestaurant,
        photo: photo,
      ),
      if (meals.isNotEmpty) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                offers
                    ? 'العروض'
                    : selectedCategory.isNotEmpty
                    ? selectedCategory
                    : 'الوجبات الأكثر طلبًا',
                style: heading(20),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FoodSearchPage(
                    initialMode: 'وجبات',
                    meals: meals,
                    restaurants: restaurants,
                    openRestaurant: openRestaurant,
                    findMeals: findMeals,
                    photo: photo,
                    open: openMeal,
                  ),
                ),
              ),
              child: const Text('عرض الكل'),
            ),
          ],
        ),
        SizedBox(
          height: 370 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: meals.length.clamp(0, 30),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) {
              final item = meals[index];
              return SizedBox(
                width: 178,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => openMeal(item),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        photo(item['image_path'], height: 150),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  item['name'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: heading(18),
                                ),
                                Text(
                                  item['restaurant_name'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const Spacer(),
                                Text(
                                  money(item['price']),
                                  style: const TextStyle(
                                    color: scarlet,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 19,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton(
                                  onPressed: () => openMeal(item),
                                  child: const Text('اطلب هسه'),
                                ),
                              ],
                            ),
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
      ],
      for (final shop in restaurants)
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openRestaurant(shop),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                photo(shop['image_path'], height: 165),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(shop['name'] ?? '', style: heading(20)),
                          ),
                          if (toggleFavorite != null)
                            IconButton(
                              tooltip: isFavorite?.call(shop) == true
                                  ? 'إزالة من المفضلة'
                                  : 'حفظ المطعم',
                              onPressed: () => toggleFavorite!(shop),
                              icon: Icon(
                                isFavorite?.call(shop) == true
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: scarlet,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        shop['description'] ?? '',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      Text(shop['address'] ?? ''),
                      if (shop['distance_km'] != null)
                        Text('${shop['distance_km']} كم'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            color: Colors.green,
                            size: 10,
                          ),
                          const SizedBox(width: 5),
                          const Expanded(
                            child: Text(
                              'مفتوح الآن',
                              style: TextStyle(color: Colors.green),
                            ),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                            ),
                            onPressed: () => openRestaurant(shop),
                            child: const Text('عرض القائمة'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      if (restaurants.isEmpty && meals.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'ماكو نتائج بهالموقع أو التصفية؛ غيّر البحث أو حدد موقع التوصيل',
          ),
        ),
    ],
  );
}

class OfferNeon extends StatefulWidget {
  const OfferNeon({super.key});
  @override
  State<OfferNeon> createState() => _OfferNeonState();
}

class _OfferNeonState extends State<OfferNeon>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, __) {
      final glow = MediaQuery.disableAnimationsOf(context)
          ? .5
          : controller.value;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('العروض'),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: scarlet.withValues(alpha: .15 + glow * .3),
                  blurRadius: 3 + glow * 7,
                ),
              ],
            ),
            child: const Icon(Icons.percent_rounded, size: 18, color: scarlet),
          ),
        ],
      );
    },
  );
}

class FoodSearchPage extends StatefulWidget {
  final List<Json> meals;
  final String initialMode;
  final List<Json> restaurants;
  final ValueChanged<Json>? openRestaurant;
  final Future<List<Json>> Function(String)? findMeals;
  final Widget Function(dynamic, {double height}) photo;
  final ValueChanged<Json> open;
  const FoodSearchPage({
    super.key,
    required this.meals,
    this.initialMode = 'الكل',
    this.restaurants = const [],
    this.openRestaurant,
    this.findMeals,
    required this.photo,
    required this.open,
  });
  @override
  State<FoodSearchPage> createState() => _FoodSearchPageState();
}

class _FoodSearchPageState extends State<FoodSearchPage> {
  String query = '';
  String mode = 'الكل';
  RangeValues? priceRange;
  Timer? timer;
  int revision = 0;
  List<Json>? remote;
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    mode = widget.initialMode;
    fetch('');
  }

  void fetch(String value) {
    timer?.cancel();
    final request = ++revision;
    setState(() {
      query = value;
      loading = widget.findMeals != null;
      error = null;
    });
    if (widget.findMeals == null) return;
    timer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = await widget.findMeals!(value.trim());
        if (mounted && request == revision)
          setState(() {
            remote = result;
            loading = false;
          });
      } catch (_) {
        if (mounted && request == revision)
          setState(() {
            error = 'تعذر البحث؛ حاول مجدداً';
            loading = false;
          });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    revision++;
    super.dispose();
  }

  String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '');
  @override
  Widget build(BuildContext context) {
    final matches = (remote ?? widget.meals)
        .where(
          (m) => normalize(
            '${m['name']} ${m['restaurant_name']} ${m['description'] ?? ''}',
          ).contains(normalize(query.trim())),
        )
        .toList();
    final visibleMeals = mode == 'مطاعم'
        ? <Json>[]
        : matches.where((m) {
            final p = (m['price'] as num? ?? 0).toDouble();
            return priceRange == null ||
                (p >= priceRange!.start && p <= priceRange!.end);
          }).toList();
    final visibleShops = mode == 'وجبات'
        ? <Json>[]
        : widget.restaurants
              .where(
                (r) => normalize(
                  '${r['name']} ${r['description'] ?? ''}',
                ).contains(normalize(query.trim())),
              )
              .toList();
    final count = visibleMeals.length + visibleShops.length;
    return Scaffold(
      appBar: AppBar(title: const Text('البحث عن الطعام')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    autofocus: true,
                    onChanged: fetch,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن وجبة أو مطعم',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xfff5f5f7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'تصفية الأسعار',
                  color: scarlet,
                  onPressed: () async {
                    final result = await showFoodPriceFilter(
                      context,
                      minimum: priceRange?.start ?? 0,
                      maximum: priceRange?.end ?? 100000,
                    );
                    if (result != null && mounted)
                      setState(() => priceRange = result);
                  },
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final label in ['الكل', 'وجبات', 'مطاعم'])
                  ChoiceChip(
                    label: Text(label),
                    selected: mode == label,
                    selectedColor: scarlet,
                    labelStyle: TextStyle(
                      color: mode == label ? Colors.white : Colors.black,
                    ),
                    onSelected: (_) => setState(() => mode = label),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: Text('نتائج البحث', style: heading(24))),
                Text(
                  '$count نتائج',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            TextButton(onPressed: () => fetch(query), child: Text(error!)),
          Expanded(
            child: count == 0
                ? const Center(child: Text('ماكو وجبات مطابقة للبحث'))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final shop in visibleShops)
                        Card(
                          child: ListTile(
                            leading: SizedBox(
                              width: 72,
                              child: widget.photo(
                                shop['image_path'],
                                height: 72,
                              ),
                            ),
                            title: Text(shop['name'] ?? '', style: heading(18)),
                            subtitle: const Text('مطعم'),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: widget.openRestaurant == null
                                ? null
                                : () => widget.openRestaurant!(shop),
                          ),
                        ),
                      for (final item in visibleMeals)
                        Card(
                          child: InkWell(
                            onTap: () => widget.open(item),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 94,
                                    child: widget.photo(
                                      item['image_path'],
                                      height: 96,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['name'] ?? '',
                                          style: heading(19),
                                        ),
                                        Text(
                                          item['restaurant_name'] ?? '',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          money(item['price']),
                                          style: const TextStyle(
                                            color: scarlet,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 21,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton.filledTonal(
                                    tooltip: 'إضافة الوجبة',
                                    onPressed: () => widget.open(item),
                                    icon: const Icon(Icons.add, color: scarlet),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
