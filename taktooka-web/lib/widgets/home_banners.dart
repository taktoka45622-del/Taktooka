import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/services/food_catalog_cache.dart';
import 'package:taktooka/widgets/persistent_media_image.dart';
import 'package:taktooka/services/media_url.dart';
import 'package:taktooka/services/refresh_gate.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:taktooka/services/backend.dart';

class HomeBanners extends StatefulWidget {
  final Backend backend;
  final Widget Function(BuildContext, List<Json>) builder;
  const HomeBanners({super.key, required this.backend, required this.builder});
  static final _active = Expando<Set<_HomeBannersState>>();
  static Future<void> refreshFor(Backend backend) async {
    await Future.wait([
      for (final state in _active[backend] ?? <_HomeBannersState>{})
        state._load(force: true),
    ]);
  }

  @override
  State<HomeBanners> createState() => _HomeBannersState();
}

class _HomeBannersState extends State<HomeBanners> with WidgetsBindingObserver {
  static List<Json> savedRows = [];
  static DateTime? lastChecked;
  List<Json> _rows = List<Json>.from(savedRows);
  late final FoodCatalogCache cache;
  bool receivedFresh = false;
  void changed() {
    lastChecked = null;
    unawaited(_load());
  }

  Future<void> seed() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        'home-banners-v2',
      );
      if (raw != null && mounted && _rows.isEmpty && !receivedFresh)
        setState(() => _rows = Backend.rows(jsonDecode(raw)));
    } catch (_) {}
  }

  Timer? _refresh;
  bool _loading = false, _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    (HomeBanners._active[widget.backend] ??= {}).add(this);
    cache = FoodCatalogCache.forBackend(widget.backend)..addListener(changed);
    unawaited(seed());
    unawaited(_load());
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground && TickerMode.valuesOf(context).enabled)
        unawaited(_load());
    });
  }

  final _loadGate = RefreshGate();
  Future<void> _load({bool force = false}) =>
      _loadGate.run((fresh) => _loadOnce(force: fresh), full: force);
  Future<void> _loadOnce({bool force = false}) async {
    if (_loading ||
        !force &&
            lastChecked != null &&
            DateTime.now().difference(lastChecked!).inSeconds < 60)
      return;
    _loading = true;
    try {
      final rows = await widget.backend.db
          .from('tkt_home_banners')
          .select()
          .eq('enabled', true)
          .order('sort_order')
          .order('created_at')
          .order('id')
          .limit(100)
          .timeout(const Duration(seconds: 10));
      final next = rows.map(Json.from).toList();
      receivedFresh = true;
      lastChecked = DateTime.now();
      final paths = next.map((r) => r['image_path']).toSet();
      for (final old in savedRows) {
        if (!paths.contains(old['image_path']) && old['image_path'] is String)
          unawaited(
            FoodMediaCache.shared.remove(
              mediaUrl(supabaseUrl, 'taktooka-banners', old['image_path']),
            ),
          );
      }
      savedRows = next;
      unawaited(
        SharedPreferences.getInstance().then(
          (prefs) => prefs.setString('home-banners-v2', jsonEncode(next)),
        ),
      );
      if (mounted && !sameSnapshot(_rows, next)) setState(() => _rows = next);
    } catch (_) {
    } finally {
      _loading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && TickerMode.valuesOf(context).enabled) unawaited(_load());
  }

  @override
  void dispose() {
    HomeBanners._active[widget.backend]?.remove(this);
    cache.removeListener(changed);
    _refresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _rows);
}

class BannerCarousel extends StatefulWidget {
  final List<Json> images;
  final ValueChanged<Json>? onTap;
  final Widget fallback;
  final double aspectRatio;
  final BorderRadius borderRadius;
  const BannerCarousel({
    super.key,
    required this.images,
    this.onTap,
    required this.fallback,
    this.aspectRatio = 2.19,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });
  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _index = 0;
  String? _prefetchedPath;
  bool _foreground = true, _visible = true;
  final Set<String> _failed = {};
  List<Json> get _images =>
      widget.images.where((x) => !_failed.contains(x['image_path'])).toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _start();
  }

  @override
  void didUpdateWidget(covariant BannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.images.map((x) => x['image_path']).join('|');
    final current = widget.images.map((x) => x['image_path']).join('|');
    final freshContent =
        widget.images.isNotEmpty &&
        oldWidget.images.isNotEmpty &&
        !identical(widget.images.first, oldWidget.images.first);
    if (previous != current || (_failed.isNotEmpty && freshContent)) {
      _index = 0;
      _failed.clear();
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = null;
    if (!_foreground || !_visible || _images.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _images.length < 2) return;
      setState(() => _index = (_index + 1) % _images.length);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _image(Json row) => PersistentMediaImage(
    mediaUrl(supabaseUrl, 'taktooka-banners', row['image_path']),
    key: ValueKey<String>(row['image_path'] as String),
    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
    fit: BoxFit.cover,
    cacheWidth: 1080,
    semanticLabel: (row['title'] as String?)?.isNotEmpty == true
        ? row['title']
        : null,
    loadingBuilder: (context, child, progress) =>
        progress == null ? child : widget.fallback,
    errorBuilder: (context, error, stack) {
      final path = row['image_path'] as String;
      if (!_failed.contains(path))
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _failed.add(path);
            _index = 0;
          });
          _start();
        });
      return widget.fallback;
    },
  );
  @override
  Widget build(BuildContext context) {
    final images = _images;
    if (images.isEmpty) return widget.fallback;
    final current = _index % images.length;
    if (images.length > 1) {
      final next =
          images[(current + 1) % images.length]['image_path'] as String;
      if (_prefetchedPath != next) {
        _prefetchedPath = next;
        unawaited(
          precacheImage(
            PersistentMediaProvider(
              '$supabaseUrl/storage/v1/object/public/taktooka-banners/$next',
            ),
            context,
            onError: (_, __) {},
          ),
        );
      }
    }
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              child: SizedBox.expand(
                key: ValueKey<String>(images[current]['image_path'] as String),
                child: GestureDetector(
                  onTap: widget.onTap == null
                      ? null
                      : () => widget.onTap!(images[current]),
                  child: _image(images[current]),
                ),
              ),
            ),
            if (images.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${current + 1} / ${images.length}',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
