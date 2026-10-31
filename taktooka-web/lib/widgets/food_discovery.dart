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
    required this.meals,
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
              onChanged: search,
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
                  label: Text(key),
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
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text('المطاعم', style: heading(22)),
          TextButton.icon(
            onPressed: chooseLocation,
            icon: const Icon(Icons.location_on_outlined),
            label: Text(area),
          ),
          TextButton.icon(
            onPressed: locating ? null : currentLocation,
            icon: const Icon(Icons.my_location),
            label: Text(locating ? 'جار تحديد موقعك' : 'استخدم موقعي'),
          ),
        ],
      ),
      if (meals.isNotEmpty) ...[
        Text(
          offers
              ? 'العروض'
              : selectedCategory.isNotEmpty
              ? selectedCategory
              : 'وجبات مقترحة وعروض',
          style: heading(20),
        ),
        for (final item in meals.take(30))
          Card(
            child: InkWell(
              onTap: () => openMeal(item),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 88,
                      child: photo(item['image_path'], height: 88),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['name'] ?? '', style: heading(17)),
                          Text(
                            item['restaurant_name'] ?? '',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          if (item['previous_price'] != null)
                            Text(
                              money(item['previous_price']),
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey,
                              ),
                            ),
                          Text(
                            money(item['price']),
                            style: const TextStyle(
                              color: scarlet,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_left),
                  ],
                ),
              ),
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
                      Text(shop['name'] ?? '', style: heading(20)),
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
