import 'package:taktooka/services/restaurant_availability.dart';
import 'persistent_media_image.dart';
import 'package:taktooka/services/restaurant_range.dart';
import 'package:taktooka/services/media_url.dart';
import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/restaurant_favorites.dart';

class FavoriteRestaurants extends StatelessWidget {
  final List<Json> restaurants;
  final ValueChanged<Json> open;
  final ValueChanged<Json>? toggle;
  final Widget Function(dynamic, {double height}) photo;
  const FavoriteRestaurants({
    super.key,
    required this.restaurants,
    required this.open,
    this.toggle,
    required this.photo,
  });
  @override
  Widget build(BuildContext context) => restaurants.isEmpty
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Text('المطاعم المفضلة', style: heading(22))),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('المطاعم المفضلة')),
                        body: ListView(
                          children: [
                            for (final r in restaurants)
                              ListTile(
                                leading: SizedBox(
                                  width: 58,
                                  child: ClipOval(
                                    child: photo(r['image_path'], height: 58),
                                  ),
                                ),
                                title: Text(r['name'] ?? ''),
                                onTap: () {
                                  open(r);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
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
                              Stack(
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
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    child: Material(
                                      color: Colors.white,
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: toggle == null
                                            ? null
                                            : () => toggle!(r),
                                        child: const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(
                                            Icons.favorite,
                                            size: 18,
                                            color: scarlet,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (!restaurantIsOpen(r))
                                const Text(
                                  'مغلق حاليًا',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 11,
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
        toggle: (r) async {
          try {
            await store.toggle(r);
          } catch (_) {
            if (mounted) setState(() => error = 'تعذر تحديث المفضلة');
          }
        },
        restaurants: store.restaurants.where((r) {
          final p = widget.b.knownPosition;
          return restaurantWithinRange(
            r,
            p == null ? null : [p.latitude, p.longitude],
          );
        }).toList(),
        open: (r) async {
          await widget.open(r);
          await refresh();
        },
        photo: (path, {double height = 80}) => PersistentMediaImage(
          mediaUrl(supabaseUrl, 'restaurant-images', '$path'),
          height: height,
          width: height,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
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
