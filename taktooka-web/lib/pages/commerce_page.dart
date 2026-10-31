import 'package:taktooka/models/food_cart.dart';
import 'package:taktooka/services/restaurant_favorites.dart';
import 'package:taktooka/widgets/food_order_item.dart';
import 'meal_details_page.dart';
import 'food_checkout_page.dart';

import 'package:taktooka/widgets/food_discovery.dart';
import 'package:taktooka/widgets/home_banners.dart';

import 'dart:async';

import 'package:taktooka/core/commerce_theme.dart';

import 'package:taktooka/services/refresh_gate.dart';

import 'package:taktooka/services/restaurant_courier_tracking.dart';

import 'food_tracking_page.dart';
import 'food_order_details_page.dart';
import 'chat_page.dart';
import 'meal_editor_page.dart';
import 'restaurant_settings_page.dart';
import 'commerce_dialogs.dart';
import 'captain_service_preferences.dart';

import 'package:taktooka/widgets/commerce_ui.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final String? initialOrderId;
  final Json? initialRestaurant;
  const FoodPage({
    super.key,
    required this.b,
    this.register = false,
    this.initialOrderId,
    this.initialRestaurant,
  });
  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> with WidgetsBindingObserver {
  Backend get b => widget.b;
  Json me = {}, accounts = {};
  List<Json> shops = [], orders = [], menu = [], catalog = [];
  String foodSearch = '', cuisine = '';
  int minFoodPrice = 0, maxFoodPrice = 1000000;
  bool offersOnly = false, locatingArea = false;
  Timer? searchTimer;
  Json? selected;
  final cart = FoodCart();
  final foodScroll = ScrollController();
  late final RestaurantFavorites favorites;
  bool busy = false, loading = true, foreground = true;
  String? error;
  Timer? timer;
  final _loadGate = RefreshGate();
  int _dataRevision = 0;
  int tab = 0;
  List<double>? _restaurantArea;
  bool _manualRestaurantArea = false;
  bool requestedLocation = false;
  String _restaurantAreaLabel = 'موقعي الحالي';
  String categoryFilter = 'الكل';
  String orderFilter = 'الكل';
  String requestId = const Uuid().v4();
  bool get privateCourier =>
      me['self_courier'] is Map || b.commerce['self_courier'] is Map;
  bool get courier => b.captain || privateCourier;
  late final RestaurantCourierTracking privateTracking;
  bool get owner => me['restaurant'] is Map;
  Json get restaurant => Json.from(me['restaurant'] as Map? ?? {});
  @override
  void initState() {
    super.initState();
    me = Json.from(b.commerce);
    selected = widget.initialRestaurant;
    favorites = favoritesFor(b)..addListener(_favoritesChanged);
    if (!b.captain &&
        b.commerce['restaurant'] == null &&
        b.commerce['self_courier'] == null)
      unawaited(refreshFavorites());
    cart.addListener(_favoritesChanged);
    if (widget.initialOrderId != null)
      tab = b.captain || b.commerce['self_courier'] is Map ? 0 : 1;
    privateTracking = RestaurantCourierTracking(b)
      ..addListener(_trackingChanged);
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (foreground && !busy && ModalRoute.of(context)?.isCurrent == true)
        load(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    foreground = s == AppLifecycleState.resumed;
    if (foreground) load(silent: true);
  }

  void _favoritesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> refreshFavorites() async {
    try {
      await favorites.load();
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    }
  }

  void _trackingChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    favorites.removeListener(_favoritesChanged);
    cart.removeListener(_favoritesChanged);
    cart.dispose();
    foodScroll.dispose();
    privateTracking.removeListener(_trackingChanged);
    privateTracking.dispose();
    timer?.cancel();
    searchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load({bool silent = false}) =>
      _loadGate.run((_) => _loadOnce(silent: silent), queue: !silent);

  Future<void> _loadOnce({bool silent = false}) async {
    if (busy || !mounted) return;
    final revision = _dataRevision;
    try {
      final values = await Future.wait([
        commerceRpc(b, 'me'),
        commerceRpc(b, 'orders'),
        tab == 2 ? commerceRpc(b, 'accounts') : Future.value(accounts),
      ]);
      if (!mounted || revision != _dataRevision) return;
      final nextMe = Json.from(values[0] as Map);
      final nextRestaurant = nextMe['restaurant'] is Map
          ? Json.from(nextMe['restaurant'])
          : null;
      setState(() => me = nextMe);
      final nextSelected = nextRestaurant ?? selected;
      List<Json>? nextMenu, nextShops, nextCatalog;
      if (tab == 0 && nextSelected != null && !courier) {
        nextMenu = Backend.rows(
          await commerceRpc(b, 'menu', {'restaurant_id': nextSelected['id']}),
        );
      } else if (tab == 0 && nextRestaurant == null && !courier) {
        if (!_manualRestaurantArea) {
          var position = b.knownPosition;
          if ((position == null ||
                  DateTime.now().difference(position.timestamp).inMinutes >=
                      10 ||
                  position.accuracy > 500) &&
              !requestedLocation) {
            requestedLocation = true;
            try {
              position = await b.locate(fresh: true);
            } catch (_) {}
          }
          _restaurantArea =
              position != null &&
                  DateTime.now().difference(position.timestamp).inMinutes <
                      10 &&
                  position.accuracy <= 500
              ? [position.latitude, position.longitude]
              : null;
        }
        nextShops = _restaurantArea == null
            ? []
            : Backend.rows(
                await commerceRpc(b, 'restaurants', {
                  'location': _restaurantArea,
                }),
              );
      }
      if (tab == 0 &&
          nextRestaurant == null &&
          !courier &&
          _restaurantArea != null &&
          selected == null) {
        nextCatalog = Backend.rows(
          await commerceRpc(b, 'catalog', {
            'location': _restaurantArea,
            'search': foodSearch,
            'category': cuisine,
            'min_price': minFoodPrice,
            'max_price': maxFoodPrice,
            'offers':
                offersOnly ||
                (foodSearch.isEmpty &&
                    cuisine.isEmpty &&
                    minFoodPrice == 0 &&
                    maxFoodPrice == 1000000),
          }),
        );
      }
      if (!mounted || revision != _dataRevision) return;
      setState(() {
        me = nextMe;
        orders = Backend.rows(values[1]);
        accounts = Json.from(values[2] as Map);
        if (nextRestaurant != null) selected = nextRestaurant;
        if (nextMenu != null) menu = nextMenu;
        if (nextShops != null) shops = nextShops;
        if (nextCatalog != null) catalog = nextCatalog;
        loading = false;
        error = null;
      });
      if (privateCourier &&
          (nextMe['self_courier'] as Map?)?['active'] == false &&
          privateTracking.online)
        unawaited(privateTracking.stop());
      if (widget.initialOrderId != null && !_notifiedOrderOpened) {
        _notifiedOrderOpened = true;
        final matching = orders.where((o) => o['id'] == widget.initialOrderId);
        if (matching.isNotEmpty) {
          final target = matching.first;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(openOrder(target));
          });
        } else {
          setState(() => error = 'الطلب لم يعد متاحًا؛ حدّث قائمة الطلبات');
        }
      }
      if (widget.register && !owner && !_registrationOpened) {
        _registrationOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(editRestaurant());
        });
      }
    } catch (e) {
      if (mounted && revision == _dataRevision)
        setState(() {
          loading = false;
          if (!silent || orders.isEmpty && shops.isEmpty && menu.isEmpty)
            error = commerceError(e);
        });
    }
  }

  bool _registrationOpened = false;
  bool _notifiedOrderOpened = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    _dataRevision++;
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
    await load();
  }

  Future<AddressChoice?> location(String title) =>
      Navigator.of(context).push<AddressChoice>(
        MaterialPageRoute(
          builder: (_) => FavoritePlacePicker(b: b, title: title),
        ),
      );
  Future<void> editRestaurant() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: commerceTheme(),
          child: RestaurantSettingsPage(
            b: b,
            restaurant: restaurant,
            preview: owner ? previewRestaurant : null,
          ),
        ),
      ),
    );
    await load();
  }

  Future<void> previewRestaurant() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Theme(
          data: commerceTheme(),
          child: Scaffold(
            appBar: AppBar(title: const Text('معاينة المطعم')),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                photo(restaurant['image_path'], height: 180),
                const SizedBox(height: 16),
                Text(restaurant['name'] ?? '', style: heading(24)),
                Text(restaurant['description'] ?? ''),
                Text(restaurant['address'] ?? ''),
                const SizedBox(height: 16),
                for (final item in menu.where((m) => m['available'] == true))
                  mealCard(item, preview: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> editItem([Json? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: commerceTheme(),
          child: MealEditorPage(b: b, meal: existing),
        ),
      ),
    );
    await load();
  }

  Future<void> showMealPhotos(Json item) async {
    final paths = List<String>.from(item['image_paths'] ?? []);
    if (paths.isEmpty && (item['image_path'] ?? '').toString().isNotEmpty)
      paths.add(item['image_path']);
    if (paths.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(title: Text(item['name'] ?? 'صور الوجبة')),
          body: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  itemCount: paths.length,
                  itemBuilder: (_, index) => Column(
                    children: [
                      Expanded(
                        child: InteractiveViewer(
                          child: Center(
                            child: Image.network(
                              b.db.storage
                                  .from('restaurant-images')
                                  .getPublicUrl(paths[index]),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Text(
                                'تعذر تحميل الصورة؛ أعد فتح المعرض',
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('${index + 1} / ${paths.length}'),
                      ),
                    ],
                  ),
                ),
              ),
              if (paths.length > 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Text('اسحب لمشاهدة باقي الصور'),
                ),
            ],
          ),
        ),
      ),
    );
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
        fit: BoxFit.cover,
        cacheWidth: height <= 100 ? 300 : 1000,
        errorBuilder: (_, __, ___) =>
            SizedBox(height: height, child: const Icon(Icons.restaurant)),
      ),
    );
  }

  bool get restaurantAvailable {
    if (restaurant['open'] != true) return false;
    final parts = '${restaurant['closing_time'] ?? ''}'.split(':');
    if (parts.length < 2) return true;
    final hour = int.tryParse(parts[0]), minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return true;
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    return now.hour * 60 + now.minute < hour * 60 + minute;
  }

  Future<void> setRestaurantOpen(bool value) => run(() async {
    if (value && b.enableOrderNotifications != null)
      unawaited(
        b.enableOrderNotifications!().catchError((Object e) {
          if (mounted)
            setState(
              () => error = 'تم فتح المطعم؛ فعّل إذن الإشعارات حتى يوصلك الجرس',
            );
        }),
      );
    final updated = Json.from(
      await commerceRpc(b, 'restaurant_open', {'open': value}) as Map,
    );
    if (mounted)
      setState(() {
        me['restaurant'] = updated;
        selected = updated;
      });
  });

  Widget ownerOverview() {
    final stats = Json.from(me['restaurant_stats'] as Map? ?? {});
    final count = stats['today_orders'] ?? 0;
    final sales = (stats['today_sales'] as num?) ?? 0;
    Widget metric(String label, String value, IconData icon) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: scarlet, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(value, style: heading(20)),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(restaurant['name'] ?? '', style: heading(22)),
                          const SizedBox(height: 8),
                          Text(
                            restaurantAvailable ? 'مفتوح الآن' : 'مغلق الآن',
                            style: TextStyle(
                              color: restaurantAvailable
                                  ? Colors.green.shade700
                                  : muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 100,
                      child: photo(restaurant['image_path'], height: 100),
                    ),
                  ],
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('استقبال الطلبات'),
                  value: restaurant['open'] == true,
                  onChanged: busy ? null : setRestaurantOpen,
                ),
              ],
            ),
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              metric('طلبات اليوم', '$count', Icons.shopping_bag_outlined),
              const SizedBox(width: 12),
              metric('مبيعات اليوم', money(sales), Icons.bar_chart_outlined),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Text('قائمة الطعام', style: heading(22))),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: busy ? null : () => editItem(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة وجبة'),
            ),
          ],
        ),
      ],
    );
  }

  Widget mealCard(Json item, {bool preview = false, int? reorderIndex}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: InkWell(
              onTap: () =>
                  !owner && !preview ? openMeal(item) : showMealPhotos(item),
              child: Column(
                children: [
                  photo(item['image_path'], height: 100),
                  if ((item['image_paths'] as List?)?.length
                      case final int count when count > 1)
                    Text(
                      '$count صور',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] ?? '', style: heading(18)),
                Text(
                  item['description'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey),
                ),
                if (item['available'] == false)
                  const Text(
                    'غير متوفرة حاليًا',
                    style: TextStyle(color: Colors.orange),
                  ),
                if (item['previous_price'] != null)
                  Text(
                    money(item['previous_price']),
                    style: const TextStyle(
                      color: Colors.grey,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                Text(
                  money(item['price']),
                  style: const TextStyle(
                    color: scarlet,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (!preview && !owner)
                  TextButton.icon(
                    onPressed: busy ? null : () => openMeal(item),
                    icon: const Icon(Icons.add_circle, color: scarlet),
                    label: const Text('اختيار الوجبة'),
                  ),
              ],
            ),
          ),
          if (!preview && owner)
            Column(
              children: [
                IconButton(
                  tooltip: 'تعديل الوجبة',
                  onPressed: busy ? null : () => editItem(item),
                  icon: const Icon(Icons.edit_outlined),
                ),
                if (reorderIndex != null)
                  ReorderableDragStartListener(
                    index: reorderIndex,
                    enabled: !busy,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.drag_indicator, color: Colors.grey),
                    ),
                  ),
              ],
            ),
        ],
      ),
    ),
  );

  Future<void> reorderMenu(int oldIndex, int newIndex) async {
    if (busy) return;
    final visible = menu
        .where(
          (m) =>
              categoryFilter == 'الكل' ||
              (m['category'] ?? 'أخرى') == categoryFilter,
        )
        .toList();
    final item = visible.removeAt(oldIndex);
    visible.insert(newIndex, item);
    final ids = visible.map((m) => m['id']).toSet();
    var index = 0;
    final ordered = [
      for (final m in menu)
        if (ids.contains(m['id'])) visible[index++] else m,
    ];
    setState(() => menu = ordered);
    await run(() async {
      await commerceRpc(b, 'items_reorder', {
        'ids': ordered.map((m) => m['id']).toList(),
      });
    });
  }

  Future<void> openShop(Json shop) async {
    await run(() async {
      menu = Backend.rows(
        await commerceRpc(b, 'menu', {'restaurant_id': shop['id']}),
      );
      if (mounted) {
        setState(() => selected = shop);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && foodScroll.hasClients) foodScroll.jumpTo(0);
        });
      }
    });
  }

  Future<void> openMeal(Json item, {Json? previous}) async {
    if (selected == null || busy) return;
    final shop = Json.from(selected!);
    final result = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) => Theme(
          data: commerceTheme(),
          child: MealDetailsPage(
            meal: item,
            restaurant: shop,
            favorite: favorites.contains(shop['id']),
            toggleFavorite: () => favorites.toggle(shop),
            photo: photo,
            initial: previous,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (!cart.accepts(shop['id'])) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('سلتك من مطعم آخر'),
          content: Text(
            'السلة الحالية من ${cart.restaurant?['name']}. تريد تبدأ سلة جديدة من ${shop['name']}؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('الاحتفاظ بالسلة'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('بدء سلة جديدة'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
      cart.clear();
    }
    try {
      cart.add(shop, result);
      requestId = const Uuid().v4();
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    }
  }

  int get subtotal => cart.total;
  Future<void> checkout() async {
    if (subtotal <= 0) return;
    final place = await location('عنوان توصيل الطعام');
    if (place == null || !mounted) return;
    var changeAddress = false;
    await run(() async {
      final response = await b.db.functions.invoke(
        'taktooka-quote',
        body: {
          'pickup': cart.restaurant!['location'],
          'force_fresh': true,
          'destination': [place.point.latitude, place.point.longitude],
        },
      );
      if (response.data is! Map || response.data['id'] == null)
        throw StateError('QUOTE_EXPIRED');
      final quote = Json.from(
        await commerceRpc(b, 'food_quote', {'quote_id': response.data['id']})
            as Map,
      );
      final fresh = Json.from(await commerceRpc(b, 'me') as Map);
      if (!mounted) return;
      final confirmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => Theme(
            data: commerceTheme(),
            child: FoodCheckoutPage(
              restaurant: cart.restaurant!,
              items: cart.items,
              onQuantityChanged: (index, value) {
                cart.setQuantity(index, value);
                requestId = const Uuid().v4();
              },
              place: place,
              delivery: quote['fare'] as num,
              serviceFee: fresh['service_fee'] as num,
              photo: photo,
            ),
          ),
        ),
      );
      if (confirmed != true) {
        changeAddress = confirmed == false;
        return;
      }
      await commerceRpc(b, 'order_create', {
        'request_id': requestId,
        'restaurant_id': cart.restaurant!['id'],
        'quote_id': quote['id'],
        'expected_delivery_fee': quote['fare'],
        'expected_food_total': subtotal,
        'customer_address': place.label,
        'expected_service_fee': fresh['service_fee'],
        'items': cart.requestItems,
      });
      requestId = const Uuid().v4();
      cart.clear();
      if (mounted) setState(() => tab = 1);
    });
    if (changeAddress && mounted) await checkout();
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

  Future<void> requestPublicCourier(Json order) async {
    final vehicle = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'اختَر المندوب العام',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.electric_rickshaw),
              title: const Text('مندوب تكتك'),
              onTap: () => Navigator.pop(sheet, 'tuktuk'),
            ),
            ListTile(
              leading: const Icon(Icons.delivery_dining),
              title: const Text('مندوب دراجة'),
              onTap: () => Navigator.pop(sheet, 'bike'),
            ),
          ],
        ),
      ),
    );
    if (vehicle != null && mounted)
      await change(
        order,
        'searching',
        vehicle: vehicle,
        deliveryMode: 'public',
      );
  }

  Future<bool> change(
    Json o,
    String status, {
    String? vehicle,
    String? deliveryMode,
  }) async {
    bool success = false;
    String? reason;
    if (status == 'rejected') {
      reason = await foodCancellationReason(
        context,
        customer: !owner && !courier,
      );
      if (reason == null || reason.isEmpty) return false;
    }
    await run(() async {
      await commerceRpc(b, 'order_update', {
        'id': o['id'],
        'status': status,
        'vehicle': vehicle,
        if (deliveryMode != null) 'delivery_mode': deliveryMode,
        'reason': reason,
      });
      if (o['request_offer_id'] != null)
        await b.silenceOffer?.call(o['request_offer_id']);
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

  Future<void> chooseRestaurantArea({bool current = false}) async {
    if (busy) return;
    if (current) {
      await run(() async {
        final position = await b.locate();
        _restaurantArea = [position.latitude, position.longitude];
        _manualRestaurantArea = true;
        _restaurantAreaLabel = 'موقعي الحالي';
      });
    } else {
      final choice = await location('موقع توصيل الطعام');
      if (choice != null && mounted) {
        _restaurantArea = [choice.point.latitude, choice.point.longitude];
        _manualRestaurantArea = true;
        _restaurantAreaLabel = choice.label;
        await load();
      }
    }
  }

  Future<void> openOrder(Json order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Theme(
          data: commerceTheme(),
          child: FoodOrderDetailsPage(b: b, initial: order),
        ),
      ),
    );
    await load();
  }

  Future<void> filterFoodPrices() async {
    final lower = TextEditingController(text: '$minFoodPrice'),
        upper = TextEditingController(text: '$maxFoodPrice');
    final form = GlobalKey<FormState>();
    final applied = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تصفية أسعار الطعام'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: lower,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'أقل سعر بالدينار',
                  ),
                  validator: (v) => int.tryParse(westernDigits(v ?? '')) == null
                      ? 'أدخل سعرًا صحيحًا'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: upper,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'أعلى سعر بالدينار',
                  ),
                  validator: (v) {
                    final lo = int.tryParse(westernDigits(lower.text)),
                        hi = int.tryParse(westernDigits(v ?? ''));
                    return lo == null ||
                            hi == null ||
                            lo < 0 ||
                            hi < lo ||
                            hi > 1000000
                        ? 'أدخل نطاقًا بين 0 و1,000,000'
                        : null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(d, true);
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        minFoodPrice = int.parse(westernDigits(lower.text));
        maxFoodPrice = int.parse(westernDigits(upper.text));
      });
      _dataRevision++;
      await load();
    }
    lower.dispose();
    upper.dispose();
  }

  Widget orderCard(Json o) {
    final status = o['status'] as String;
    final mine = o['captain_id'] == b.db.auth.currentUser!.id;
    return Card(
      key: ValueKey(o['id']),
      child: InkWell(
        onTap: () => openOrder(o),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o['restaurant_name'] ?? '', style: heading(18)),
                        Text(
                          '#${o['id'].toString().split('-').first.toUpperCase()}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: CommerceStatus(
                      foodStates[status] ?? status,
                      color: status == 'delivered'
                          ? Colors.green
                          : status == 'rejected'
                          ? Colors.red
                          : status == 'pending'
                          ? Colors.orange
                          : Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (final item in o['items'] as List? ?? [])
                FoodOrderItem(item: Json.from(item), photo: photo),
              if (courier)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scarlet.withValues(alpha: .05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: Text('أجرة التوصيل')),
                      Text(
                        money(o['delivery_fee']),
                        style: const TextStyle(
                          color: scarlet,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => openOrder(o),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('تفاصيل الطلب والمواقع'),
              ),
              if (o['captain_id'] != null &&
                  ['accepted', 'heading', 'picked_up'].contains(status)) ...[
                SizedBox(
                  height: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: FoodTrackingPage(
                      key: ValueKey('map-${o['id']}'),
                      b: b,
                      orderId: o['id'],
                      compact: true,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FoodTrackingPage(b: b, orderId: o['id']),
                    ),
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('الخريطة وتتبع الطلب'),
                ),
              ],
              for (final item in (o['items'] as List? ?? []))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item['name']} × ${item['quantity']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        money(
                          (item['price'] as num) * (item['quantity'] as num),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),
              CommerceAmountRow('الطعام', o['food_total'] as num),
              CommerceAmountRow('التوصيل', o['delivery_fee'] as num),
              CommerceAmountRow('رسوم الخدمة', o['service_fee'] as num),
              const Divider(),
              CommerceAmountRow(
                'المجموع',
                (o['food_total'] as num) +
                    (o['delivery_fee'] as num) +
                    (o['service_fee'] as num),
                total: true,
              ),
              const Text(
                'كاش عند الاستلام',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 24),
              if (owner || courier)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('عنوان الزبون'),
                  subtitle: Text(o['customer_address'] ?? ''),
                ),
              if ((owner || courier) && o['customer_phone'] != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('هاتف الزبون'),
                  subtitle: Text(
                    o['customer_phone'].toString(),
                    textDirection: TextDirection.ltr,
                  ),
                  trailing: IconButton(
                    tooltip: 'اتصال بالزبون',
                    onPressed: () => callPhone(o['customer_phone']),
                    icon: const Icon(Icons.call_outlined),
                  ),
                ),
              if ((owner || courier) && o['captain_id'] != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delivery_dining),
                  title: Text(o['captain_name'] ?? 'الكابتن'),
                  subtitle: Text(
                    o['captain_phone'] ?? '',
                    textDirection: TextDirection.ltr,
                  ),
                  trailing: IconButton(
                    tooltip: 'اتصال بالكابتن',
                    onPressed: () => callPhone(o['captain_phone']),
                    icon: const Icon(Icons.call_outlined),
                  ),
                ),
              if ((o['reason'] ?? '').toString().isNotEmpty)
                Text('السبب: ${o['reason']}'),
              if (!owner && !courier && status == 'pending')
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
                  child: const Text('رفض الطلب — مع ذكر السبب'),
                ),
              ],
              if (owner && ['preparing', 'searching'].contains(status))
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy ? null : () => requestPublicCourier(o),
                      child: const Text('طلب مندوب عام'),
                    ),
                    if (restaurant['self_delivery'] == true)
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => change(
                                o,
                                'searching',
                                deliveryMode: 'private',
                              ),
                        child: const Text('طلب مندوب خاص'),
                      ),
                  ],
                ),
              if (courier && status == 'searching' && !mine)
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
                  child: const Text('رفض الطلب — مع ذكر السبب'),
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
                  !courier &&
                  ['delivered', 'rejected'].contains(status))
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final shopsNow = Backend.rows(
                            await commerceRpc(b, 'restaurants', {
                              'location':
                                  _restaurantArea ?? o['customer_location'],
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
                          for (final old in o['items'] as List) {
                            final matches = menu.where(
                              (i) => i['id'] == old['id'],
                            );
                            if (matches.isNotEmpty && mounted)
                              await openMeal(
                                matches.first,
                                previous: Json.from(old),
                              );
                          }
                          if (mounted) setState(() => tab = 0);
                        },
                  child: const Text('إعادة الطلب — مراجعة الأسعار الحالية'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Json> get visibleOrders {
    final own = b.db.auth.currentUser?.id;
    final candidates = courier
        ? orders.where(
            (o) => tab == 0
                ? o['status'] == 'searching' && o['captain_id'] != own
                : o['captain_id'] == own,
          )
        : orders;
    return candidates
        .where(
          (o) => switch (orderFilter) {
            'الجديدة' => o['status'] == 'pending' || o['status'] == 'searching',
            'الجارية' => [
              'preparing',
              'accepted',
              'heading',
              'picked_up',
            ].contains(o['status']),
            'السابقة' => ['delivered', 'rejected'].contains(o['status']),
            _ => true,
          },
        )
        .toList();
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
                    owner ? 'مستحقات تكتوكة' : 'مستحقات تكتوكة',
                    style: heading(18),
                  ),
                  Text(money(company), style: heading(26)),
                  if (company == 0)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text(
                        'لا توجد مبالغ مستحقة',
                        style: TextStyle(color: Colors.green),
                      ),
                    ),
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
                    child: Text('طلب تسديد للشركة'),
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
                              await showRestaurantSettlementCode(
                                context,
                                value,
                              );
                            }),
                      child: const Text('إصدار كود التسديد'),
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
                      child: const Text('إدخال كود التسديد'),
                    ),
                ],
              ),
            ),
          ),
        const Text(
          'سجل التسديدات',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (settlements.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('لا توجد تسديدات سابقة')),
          ),
        for (final s in settlements) SettlementRecord(record: s),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: openSupport,
          icon: const Icon(Icons.headset_mic_outlined),
          label: const Text('دعم تكتوكة'),
        ),
      ],
    );
  }

  Future<void> openSupport() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('دعم تكتوكة')),
        body: ChatPage(b: b),
      ),
    ),
  );

  Future<void> callPhone(dynamic raw) async {
    final phone = (raw ?? '').toString().replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) return;
    try {
      if (!await launchUrl(Uri(scheme: 'tel', path: phone)) && mounted) {
        setState(() => error = 'تعذر فتح تطبيق الاتصال');
      }
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر فتح تطبيق الاتصال');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: commerceTheme(),
      child: Builder(builder: (context) => _screen(context)),
    );
  }

  Widget _screen(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        owner
            ? 'داشبورد المطعم'
            : courier
            ? 'طلبات الطعام'
            : 'طعام',
        style: heading(21),
      ),
      centerTitle: true,
      leading: owner
          ? IconButton(
              tooltip: 'إعدادات المطعم',
              onPressed: busy ? null : editRestaurant,
              icon: const Icon(Icons.settings_outlined),
            )
          : null,
      actions: [
        if (owner)
          IconButton(
            tooltip: 'الطلبات الجديدة',
            onPressed: () {
              setState(() => tab = 1);
              load();
            },
            icon: Badge(
              isLabelVisible: orders.any((o) => o['status'] == 'pending'),
              label: Text(
                '${orders.where((o) => o['status'] == 'pending').length}',
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
          )
        else ...[
          IconButton(
            tooltip: 'دعم تكتوكة',
            onPressed: openSupport,
            icon: const Icon(Icons.headset_mic_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'المزيد',
            onSelected: (key) async {
              if (key == 'services') {
                await showCaptainServicePreferences(context, b);
                await load();
              } else if (key == 'refresh') {
                await load();
              } else if (key == 'support') {
                await openSupport();
              } else {
                await run(() async {
                  await b.signOut();
                  if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                });
              }
            },
            itemBuilder: (_) => [
              if (b.captain)
                const PopupMenuItem(
                  value: 'services',
                  child: Text('اختيار الخدمات'),
                ),
              const PopupMenuItem(value: 'refresh', child: Text('تحديث')),
              const PopupMenuItem(value: 'support', child: Text('دعم تكتوكة')),
              if (privateCourier)
                const PopupMenuItem(
                  value: 'logout',
                  child: Text('تسجيل الخروج'),
                ),
            ],
          ),
        ],
      ],
    ),
    bottomNavigationBar: !owner && !courier && subtotal > 0
        ? SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: busy ? null : checkout,
                child: Wrap(
                  spacing: 24,
                  runSpacing: 4,
                  children: [
                    const Text('عرض السلة'),
                    Text('${cart.quantity} وجبة'),
                    Text(money(subtotal)),
                  ],
                ),
              ),
            ),
          )
        : null,
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: CustomScrollView(
              controller: foodScroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      if (busy) const LinearProgressIndicator(),
                      if (privateCourier) ...[
                        SwitchListTile(
                          title: const Text('استقبال طلبات مطعمي'),
                          subtitle: const Text('تظهر طلبات مطعمك الخاصة فقط'),
                          value: privateTracking.online,
                          onChanged:
                              busy ||
                                  privateTracking.working ||
                                  me['food_active'] == true ||
                                  (me['self_courier'] as Map?)?['active'] !=
                                      true
                              ? null
                              : (value) async {
                                  if (value) {
                                    await privateTracking.start();
                                  } else {
                                    await privateTracking.stop();
                                  }
                                  await load(silent: true);
                                },
                        ),
                        if (privateTracking.error != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              privateTracking.error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                      if (b.captain)
                        SwitchListTile(
                          title: const Text('جاهز لاستقبال الطلبات'),
                          subtitle: Text(
                            b.commissionPlan && b.commerce['vehicle'] != 'bike'
                                ? 'نظام النسبة: رحلات الزبائن فقط'
                                : 'حسب الخدمات اللي فعلتها من اختيار الخدمات',
                          ),
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
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: const Text('دعم تكتوكة'),
                                  ),
                                  body: ChatPage(b: b),
                                ),
                              ),
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
                      Row(
                        children: [
                          for (final entry in [
                            (
                              0,
                              owner
                                  ? 'القائمة'
                                  : courier
                                  ? 'المتاحة'
                                  : 'المطاعم',
                            ),
                            (1, owner ? 'الطلبات' : 'طلباتي'),
                            if (owner || courier) (2, 'الحسابات'),
                          ])
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  setState(() => tab = entry.$1);
                                  load();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: tab == entry.$1
                                            ? scarlet
                                            : const Color(0xFFE5E7EB),
                                        width: tab == entry.$1 ? 3 : 1,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    entry.$2,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: tab == entry.$1
                                          ? scarlet
                                          : Colors.grey,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (tab == 2)
                        accountView()
                      else if (tab == 1 || courier) ...[
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final label in [
                              'الكل',
                              'الجديدة',
                              'الجارية',
                              'السابقة',
                            ])
                              ChoiceChip(
                                label: Text(label),
                                selected: orderFilter == label,
                                onSelected: (_) =>
                                    setState(() => orderFilter = label),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (visibleOrders.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('لا توجد طلبات في هذا القسم'),
                          ),
                        for (final o in visibleOrders) orderCard(o),
                      ] else if (selected == null) ...[
                        FoodDiscovery(
                          restaurants: shops
                              .where(
                                (r) =>
                                    foodSearch.isEmpty ||
                                    '${r['name']} ${r['description']}'.contains(
                                      foodSearch,
                                    ) ||
                                    catalog.any(
                                      (i) => i['restaurant_id'] == r['id'],
                                    ),
                              )
                              .toList(),
                          meals: catalog,
                          favorites: favorites.restaurants,
                          isFavorite: (r) => favorites.contains(r['id']),
                          toggleFavorite: (r) => run(() async {
                            await favorites.toggle(r);
                          }),
                          selectedCategory: cuisine,
                          offers: offersOnly,
                          area: _restaurantArea == null
                              ? 'تحديد موقع التوصيل'
                              : _restaurantAreaLabel,
                          locating: locatingArea,
                          search: (v) {
                            searchTimer?.cancel();
                            searchTimer = Timer(
                              const Duration(milliseconds: 350),
                              () {
                                if (!mounted) return;
                                setState(() => foodSearch = v.trim());
                                _dataRevision++;
                                load();
                              },
                            );
                          },
                          category: (k) {
                            setState(() {
                              offersOnly = k == 'العروض';
                              cuisine = k == 'الكل' || k == 'العروض' ? '' : k;
                            });
                            _dataRevision++;
                            load();
                          },
                          filter: filterFoodPrices,
                          currentLocation: () async {
                            setState(() => locatingArea = true);
                            try {
                              await chooseRestaurantArea(current: true);
                            } finally {
                              if (mounted) setState(() => locatingArea = false);
                            }
                          },
                          chooseLocation: () => chooseRestaurantArea(),
                          openRestaurant: openShop,
                          openMeal: (i) async {
                            final match = shops.where(
                              (r) => r['id'] == i['restaurant_id'],
                            );
                            if (match.isNotEmpty) {
                              await openShop(match.first);
                              final meal = menu.where(
                                (m) => m['id'] == i['id'],
                              );
                              if (meal.isNotEmpty) await openMeal(meal.first);
                            }
                          },
                          photo: photo,
                          banner: HomeBanners(
                            backend: b,
                            builder: (c, rows) => BannerCarousel(
                              images: rows
                                  .where((r) => r['slot'] == 3)
                                  .toList(),
                              fallback: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xfffff1f2),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.restaurant,
                                      color: scarlet,
                                      size: 44,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        'أكلك المفضّل يوصل لبابك',
                                        style: heading(22),
                                      ),
                                    ),
                                  ],
                                ),
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
                              });
                              if (foodScroll.hasClients) foodScroll.jumpTo(0);
                            },
                            child: const Text('كل المطاعم'),
                          ),
                        if (owner)
                          ownerOverview()
                        else ...[
                          photo(selected!['image_path'], height: 160),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  selected!['name'],
                                  style: heading(24),
                                ),
                              ),
                              IconButton(
                                tooltip: favorites.contains(selected!['id'])
                                    ? 'إزالة من المفضلة'
                                    : 'حفظ المطعم',
                                onPressed:
                                    busy ||
                                        favorites.pending.contains(
                                          selected!['id'],
                                        )
                                    ? null
                                    : () => run(() async {
                                        await favorites.toggle(selected!);
                                      }),
                                icon: Icon(
                                  favorites.contains(selected!['id'])
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: scarlet,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            selected!['address'] ?? '',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final c in [
                              'الكل',
                              ...menu
                                  .map(
                                    (m) => (m['category'] ?? 'أخرى').toString(),
                                  )
                                  .toSet(),
                            ])
                              ChoiceChip(
                                label: Text(c),
                                selected: categoryFilter == c,
                                onSelected: (_) =>
                                    setState(() => categoryFilter = c),
                              ),
                          ],
                        ),
                        if (owner)
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            onReorderItem: reorderMenu,
                            itemCount: menu
                                .where(
                                  (m) =>
                                      categoryFilter == 'الكل' ||
                                      (m['category'] ?? 'أخرى') ==
                                          categoryFilter,
                                )
                                .length,
                            itemBuilder: (context, index) {
                              final item = menu
                                  .where(
                                    (m) =>
                                        categoryFilter == 'الكل' ||
                                        (m['category'] ?? 'أخرى') ==
                                            categoryFilter,
                                  )
                                  .elementAt(index);
                              return KeyedSubtree(
                                key: ValueKey(item['id']),
                                child: mealCard(item, reorderIndex: index),
                              );
                            },
                          )
                        else
                          for (final item in menu.where(
                            (m) =>
                                categoryFilter == 'الكل' ||
                                (m['category'] ?? 'أخرى') == categoryFilter,
                          ))
                            mealCard(item),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          ),
  );
}
