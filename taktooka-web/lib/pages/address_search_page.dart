import 'package:taktooka/core/numeric_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/feature_navigation.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/core/place_distance.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/services/place_search.dart';
import 'package:taktooka/pages/favorite_place_picker_page.dart';
import 'package:taktooka/services/backend.dart';

class AddressSearch extends StatefulWidget {
  final Backend b;
  final String title;
  final bool savedOnly;
  const AddressSearch({
    super.key,
    required this.b,
    this.title = 'نقطة الانطلاق',
    this.savedOnly = false,
  });
  @override
  State<AddressSearch> createState() => _AddressSearchState();
}

class _AddressSearchState extends State<AddressSearch> {
  final search = TextEditingController();
  List<AddressChoice> results = [];
  bool busy = false;
  String? error;
  int sequence = 0;
  Timer? _debounce;
  late final PlaceSearch _places = PlaceSearch(widget.b);
  @override
  void dispose() {
    sequence++;
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  List<Json> favorites = [];
  bool saving = false;
  bool favoritesLoading = true;
  @override
  void initState() {
    super.initState();
    unawaited(loadFavorites());
  }

  void report(Object e) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: AppText(readable(e))));
  }

  Future<void> loadFavorites() async {
    try {
      final rows = await widget.b.db
          .from('tkt_saved_places')
          .select()
          .eq('user_id', widget.b.db.auth.currentUser!.id)
          .order('created_at')
          .timeout(const Duration(seconds: 15));
      if (mounted) setState(() => favorites = Backend.rows(rows));
    } catch (e) {
      report(e);
    } finally {
      if (mounted) setState(() => favoritesLoading = false);
    }
  }

  Future<void> editFavorite([Json? existing]) async {
    if (saving) return;
    final choice = await Navigator.of(context).push<AddressChoice>(
      MaterialPageRoute(
        builder: (_) => FavoritePlacePicker(b: widget.b, existing: existing),
      ),
    );
    if (!mounted || choice == null) return;
    setState(() => saving = true);
    try {
      final data = <String, dynamic>{
        'user_id': widget.b.db.auth.currentUser!.id,
        'label': choice.label,
        'lat': choice.point.latitude,
        'lng': choice.point.longitude,
        if (existing != null) 'id': existing['id'],
      };
      final row = Json.from(
        await widget.b.db
            .from('tkt_saved_places')
            .upsert(data)
            .select()
            .single()
            .timeout(const Duration(seconds: 15)),
      );
      if (!mounted) return;
      setState(() {
        favorites.removeWhere((a) => a['id'] == row['id']);
        favorites.add(row);
      });
    } catch (e) {
      report(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> deleteFavorite(Json a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: AppText('حذف ${a['label']}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const AppText('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const AppText('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => saving = true);
    try {
      await widget.b.db
          .from('tkt_saved_places')
          .delete()
          .eq('id', a['id'])
          .eq('user_id', widget.b.db.auth.currentUser!.id)
          .timeout(const Duration(seconds: 15));
      if (mounted)
        setState(() => favorites.removeWhere((r) => r['id'] == a['id']));
    } catch (e) {
      report(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  List<AddressChoice> localSuggestions(String text) {
    final query = PlaceSearch.normalize(text);
    if (query.length < 2) return [];
    final choices = <AddressChoice>[];
    for (final a in favorites) {
      if (PlaceSearch.normalize(a['label'] as String).contains(query)) {
        choices.add(
          AddressChoice(
            a['label'] as String,
            LatLng((a['lat'] as num).toDouble(), (a['lng'] as num).toDouble()),
            favorite: true,
          ),
        );
      }
    }
    for (final ride in widget.b.rides) {
      for (final kind in ['pickup', 'destination']) {
        final label = ride['${kind}_name'];
        final xy = ride[kind];
        if (label is String &&
            xy is List &&
            xy.length == 2 &&
            PlaceSearch.normalize(label).contains(query) &&
            !choices.any((r) => r.label == label)) {
          choices.add(
            AddressChoice(
              label,
              LatLng((xy[0] as num).toDouble(), (xy[1] as num).toDouble()),
            ),
          );
        }
      }
    }
    return choices.take(6).toList();
  }

  void searchChanged(String value) {
    _debounce?.cancel();
    sequence++;
    final saved = _places.cached(value, searchOrigin);
    final query = PlaceSearch.normalize(value);
    final retained = query.length < 2
        ? <AddressChoice>[]
        : results
              .where((r) => PlaceSearch.normalize(r.label).contains(query))
              .toList();
    setState(() {
      results = localSuggestions(value);
      for (final item in retained) {
        if (!results.any((r) => r.label == item.label)) results.add(item);
      }
      if (saved != null) {
        for (final item in saved) {
          if (!results.any((r) => r.label == item.label)) results.add(item);
        }
      }
      error = null;
      busy = value.trim().length >= 2 && saved == null;
    });
    if (value.trim().length >= 2 && saved == null) {
      _debounce = Timer(const Duration(milliseconds: 650), () => find());
    }
  }

  Future<void> find() async {
    _debounce?.cancel();
    final text = search.text.trim();
    if (text.length < 2) return;
    final request = ++sequence;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final choices = await _places.find(
        text,
        LatLng(widget.b.pickupLat, widget.b.pickupLng),
      );
      if (!mounted || request != sequence) return;
      final merged = localSuggestions(text);
      for (final choice in choices) {
        if (!merged.any(
          (r) =>
              PlaceSearch.normalize(r.label) ==
              PlaceSearch.normalize(choice.label),
        )) {
          merged.add(choice);
        }
      }
      setState(() {
        results = merged;
        if (results.isEmpty)
          error =
              'ما لقينا نتيجة؛ جرّب اسم المنطقة ويا المكان أو حدده بالخريطة';
      });
    } catch (_) {
      if (mounted && request == sequence) {
        setState(
          () => error = results.isEmpty
              ? 'تعذّر البحث حاليًا؛ أعد المحاولة أو حدد المكان بالخريطة'
              : null,
        );
      }
    } finally {
      if (mounted && request == sequence) setState(() => busy = false);
    }
  }

  LatLng get searchOrigin => LatLng(widget.b.pickupLat, widget.b.pickupLng);

  String distanceText(LatLng point) {
    final fix = widget.b.knownPosition;
    final origin = fix == null
        ? searchOrigin
        : LatLng(fix.latitude, fix.longitude);
    final distance = const Distance().as(LengthUnit.Meter, origin, point);
    final reference = fix == null
        ? 'عن نقطة الانطلاق'
        : DateTime.now().difference(fix.timestamp).inMinutes >= 2
        ? 'عن موقعك الأخير'
        : 'عنك';
    return 'يبعد $reference تقريبًا ${formatPlaceDistance(distance)} · مسافة مباشرة';
  }

  void choose(AddressChoice result) {
    FocusScope.of(context).unfocus();
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final recent = <String, AddressChoice>{};
    for (final r in widget.b.rides) {
      for (final kind in ['pickup', 'destination']) {
        final label = r['${kind}_name'];
        final xy = r[kind];
        if (label is String && xy is List && label.isNotEmpty) {
          recent.putIfAbsent(
            label,
            () => AddressChoice(
              label,
              LatLng((xy[0] as num).toDouble(), (xy[1] as num).toDouble()),
            ),
          );
        }
      }
      if (recent.length >= 8) break;
    }
    final favoriteItems = <Widget>[
      const SizedBox(height: 16),
      const AppText(
        'العناوين المفضلة',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: saving || favoritesLoading ? null : () => editFavorite(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: AppText(saving ? 'جاري الحفظ…' : 'إضافة عنوان مفضل'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      if (favoritesLoading)
        const Padding(
          padding: EdgeInsets.all(12),
          child: AppText('جاري تحميل العناوين…'),
        ),
      if (!favoritesLoading && favorites.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: AppText('احفظ البيت أو العمل حتى تختاره مباشرة'),
        ),
      for (final a in favorites)
        ListTile(
          leading: const Icon(Icons.star, color: brandRed),
          title: AppText(a['label'] as String),
          subtitle: AppText(
            distanceText(
              LatLng(
                (a['lat'] as num).toDouble(),
                (a['lng'] as num).toDouble(),
              ),
            ),
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          onTap: saving
              ? null
              : () => choose(
                  AddressChoice(
                    a['label'] as String,
                    LatLng(
                      (a['lat'] as num).toDouble(),
                      (a['lng'] as num).toDouble(),
                    ),
                    favorite: true,
                  ),
                ),
          trailing: PopupMenuButton<String>(
            enabled: !saving,
            onSelected: (value) {
              if (value == 'edit') {
                editFavorite(a);
              } else {
                deleteFavorite(a);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: AppText('تعديل الاسم والموقع'),
              ),
              PopupMenuItem(value: 'delete', child: AppText('حذف')),
            ],
          ),
        ),
    ];
    final searchItems = <Widget>[
      AppText(
        widget.title,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      TextField(
        inputFormatters: const [EnglishDigitsFormatter()],
        controller: search,
        onChanged: searchChanged,
        onSubmitted: (_) => find(),
        maxLength: 200,
        textInputAction: TextInputAction.search,
        decoration: localizedInput(
          context,
          InputDecoration(
            hintText: 'ابحث عن شارع، منطقة أو معلم قريب',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (search.text.isNotEmpty)
                  IconButton(
                    tooltip: 'مسح البحث',
                    onPressed: () {
                      search.clear();
                      searchChanged('');
                    },
                    icon: const Icon(Icons.close, size: 20),
                  ),
                IconButton(
                  tooltip: 'بحث',
                  onPressed: busy ? null : find,
                  icon: const Icon(Icons.arrow_back),
                ),
              ],
            ),
            counterText: '',
          ),
        ),
      ),
      SizedBox(
        height: 8,
        child: AnimatedOpacity(
          opacity: busy ? 1 : 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          child: TickerMode(
            enabled: busy && !MediaQuery.disableAnimationsOf(context),
            child: LinearProgressIndicator(
              minHeight: 2,
              value: MediaQuery.disableAnimationsOf(context) ? .7 : null,
            ),
          ),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: AppText(error!, style: const TextStyle(color: brandRed)),
        ),
      for (final r in results)
        ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: AppText(r.label, maxLines: 3, overflow: TextOverflow.ellipsis),
          subtitle: AppText(
            distanceText(r.point),
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => choose(r),
        ),
      if (results.isEmpty && search.text.isNotEmpty && !busy && error == null)
        const AppText('اكتب حرفين أو أكثر حتى تظهر الاقتراحات'),
    ];
    if (widget.savedOnly) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          ...searchItems,
          if (search.text.trim().isEmpty) ...favoriteItems,
        ],
      );
    }
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                children: [
                  ...searchItems,
                  if (search.text.trim().isEmpty &&
                      !widget.savedOnly &&
                      recent.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const AppText(
                      'مواقعك السابقة',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    for (final r in recent.values.take(6))
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: AppText(r.label),
                        subtitle: AppText(
                          distanceText(r.point),
                          style: const TextStyle(fontSize: 12, height: 1.6),
                        ),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => choose(r),
                      ),
                  ],
                ],
              ),
            ),
            Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .48,
              ),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: favoriteItems,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.map_outlined, size: 26),
                      label: const AppText('حدد الموقع من الخريطة'),
                      style: FilledButton.styleFrom(
                        backgroundColor: brandRed,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(58),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
