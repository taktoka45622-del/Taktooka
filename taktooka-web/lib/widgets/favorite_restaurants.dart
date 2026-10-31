import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/restaurant_favorites.dart';

class FavoriteRestaurants extends StatelessWidget {
  final List<Json> restaurants;
  final ValueChanged<Json> open;
  final Widget Function(dynamic, {double height}) photo;
  const FavoriteRestaurants({
    super.key,
    required this.restaurants,
    required this.open,
    required this.photo,
  });
  @override
  Widget build(BuildContext context) => restaurants.isEmpty
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 18),
            Text('المطاعم المفضلة', style: heading(22)),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in restaurants)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 14),
                      child: SizedBox(
                        width: 100,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => open(r),
                          child: Column(
                            children: [
                              Container(
                                width: 82,
                                height: 82,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xffffdce1),
                                    width: 2,
                                  ),
                                ),
                                child: ClipOval(
                                  child: photo(r['image_path'], height: 72),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                r['name'] ?? '',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        );
}

class HomeFavoriteRestaurants extends StatefulWidget {
  final Backend b;
  final Future<void> Function(Json) open;
  const HomeFavoriteRestaurants({
    super.key,
    required this.b,
    required this.open,
  });
  @override
  State<HomeFavoriteRestaurants> createState() =>
      _HomeFavoriteRestaurantsState();
}

class _HomeFavoriteRestaurantsState extends State<HomeFavoriteRestaurants> {
  late RestaurantFavorites store;
  String? error;
  @override
  void initState() {
    super.initState();
    store = favoritesFor(widget.b);
    store.addListener(changed);
    refresh();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> refresh() async {
    try {
      await store.load();
      if (mounted) setState(() => error = null);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر تحديث المطاعم المفضلة');
    }
  }

  @override
  void dispose() {
    store.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FavoriteRestaurants(
        restaurants: store.restaurants,
        open: (r) async {
          await widget.open(r);
          await refresh();
        },
        photo: (path, {double height = 80}) => Image.network(
          widget.b.db.storage.from('restaurant-images').getPublicUrl('$path'),
          height: height,
          width: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => SizedBox(
            height: height,
            child: const Icon(Icons.restaurant, color: scarlet),
          ),
        ),
      ),
      if (error != null)
        TextButton(onPressed: refresh, child: Text('$error — إعادة المحاولة')),
    ],
  );
}
