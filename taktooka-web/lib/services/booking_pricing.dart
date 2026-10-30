import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/core/local_fare.dart';

class BookingPricing {
  static final updates = StreamController<int>.broadcast(sync: true);
  static Map<String, dynamic> settings = Map.of(LocalFare.defaults);
  static Future<void>? _refresh;
  static bool _opened = false;
  static Future<void> syncOnce(Future<dynamic> Function() fetch) async {
    if (_opened) return;
    _opened = true;
    await restore();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final revision = settings['revision'] as int,
        seen = prefs.getInt('booking_pricing_seen_revision') ?? -1;
    if (prefs.getString('$_prefix$revision') != null && revision > seen) {
      await prefs.setInt('booking_pricing_seen_revision', revision);
      return;
    }
    await refresh(fetch);
    await prefs.setInt(
      'booking_pricing_seen_revision',
      settings['revision'] as int,
    );
  }

  static const _prefix = 'booking_pricing_revision_';
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()
        ..sort(
          (a, b) => (int.tryParse(b.substring(_prefix.length)) ?? 0).compareTo(
            int.tryParse(a.substring(_prefix.length)) ?? 0,
          ),
        );
      for (final key in [...keys, 'booking_pricing_v1']) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (!LocalFare.valid(value) || value['revision'] < settings['revision'])
          continue;
        final changed = value['revision'] != settings['revision'];
        settings = value;
        if (changed) updates.add(value['revision'] as int);
        break;
      }
    } catch (_) {}
  }

  static Future<bool> applyPayload(Map<String, dynamic> data) async {
    if (data['kind'] != 'pricing_update') return false;
    try {
      final raw = data['pricing_json'];
      final value = Map<String, dynamic>.from(
        raw is String ? jsonDecode(raw) as Map : raw as Map,
      );
      if (!LocalFare.valid(value)) return true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix${value['revision']}', jsonEncode(value));
      await restore();
      if (data['ui_visible'] == true)
        await prefs.setInt(
          'booking_pricing_seen_revision',
          settings['revision'] as int,
        );
    } catch (_) {}
    return true;
  }

  static Future<void> ensureRevision(
    dynamic revision,
    Future<dynamic> Function() fetch,
  ) async {
    await restore();
    if (revision is! num || revision <= settings['revision']) return;
    await refresh(fetch);
  }

  static Future<void> refresh(
    Future<dynamic> Function() fetch, {
    bool force = false,
  }) => _refresh ??= _load(fetch).whenComplete(() => _refresh = null);
  static Future<void> _load(Future<dynamic> Function() fetch) async {
    try {
      final value = Map<String, dynamic>.from(
        await fetch().timeout(const Duration(seconds: 6)) as Map,
      );
      await applyPayload({'kind': 'pricing_update', 'pricing_json': value});
    } catch (_) {}
  }
}
