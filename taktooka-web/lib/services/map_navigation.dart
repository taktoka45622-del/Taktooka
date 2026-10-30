import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taktooka/widgets/app_notice.dart';

class MapNavigation {
  static const channel = MethodChannel('taktooka/map_navigation');
  static const androidNavigationApps = <String>{
    'com.google.android.apps.maps', 'com.google.android.apps.mapslite',
    'com.waze', 'com.here.app.maps', 'net.osmand', 'net.osmand.plus',
    'app.organicmaps', 'com.mapswithme.maps.pro', 'com.sygic.aura',
  };
  static const preferenceKey = 'navigation_app_v1';

  static Uri uri(String id, double lat, double lng) {
    final point = '$lat,$lng';
    if (id == 'com.waze' || id == 'waze') {
      return Uri.parse('waze://?ll=$point&navigate=yes');
    }
    if (id == 'google') {
      return Uri.parse('comgooglemaps://?daddr=$point&directionsmode=driving');
    }
    return Uri.https('maps.apple.com', '/', {'daddr': point, 'dirflg': 'd'});
  }

  static Future<List<Map<String, String>>> installedApps() async {
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final apps = <Map<String, String>>[];
    if (android) {
      final rows = await channel.invokeListMethod<dynamic>('apps');
      for (final row in rows ?? []) {
        if (row is Map && androidNavigationApps.contains(row['id']) &&
            row['name'] is String) {
          apps.add({'id': row['id'] as String, 'name': row['name'] as String});
        }
      }
    } else {
      apps.add({'id': 'apple', 'name': 'Apple Maps'});
      for (final app in [
        {'id': 'waze', 'name': 'Waze'},
        {'id': 'google', 'name': 'Google Maps'},
      ]) {
        if (await canLaunchUrl(uri(app['id']!, 33.3, 44.4))) apps.add(app);
      }
    }
    return apps;
  }

  static Future<void> chooseDefault(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apps = await installedApps();
      if (!context.mounted) return;
      if (apps.isEmpty) {
        showAppNotice(
          context,
          'ماكو تطبيق خرائط مثبت؛ ثبّت تطبيق خرائط وحاول مجدداً',
          messenger: messenger,
        );
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (!context.mounted) return;
      final selected = prefs.getString(preferenceKey);
      final app = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('تحديد تطبيق الخرائط'),
          children: [
            for (final app in apps)
              ListTile(
                title: Text(app['name']!),
                trailing: app['id'] == selected
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: () => Navigator.pop(context, app),
              ),
          ],
        ),
      );
      if (app == null) return;
      await prefs.setString(preferenceKey, app['id']!);
      await prefs.setString('${preferenceKey}_name', app['name']!);
    } catch (_) {
      showAppNotice(
        context,
        'تعذّر حفظ تطبيق الخرائط، أعد المحاولة',
        messenger: messenger,
      );
    }
  }

  static Future<void> open(
    BuildContext context,
    double lat,
    double lng, {
    bool choose = false,
  }) async {
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180)
      return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final android =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final apps = await installedApps();
      if (apps.isEmpty) {
        showAppNotice(
          context,
          'ماكو تطبيق خرائط مثبت؛ ثبّت تطبيق خرائط وحاول مجدداً',
          messenger: messenger,
        );
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      var selected = prefs.getString(preferenceKey);
      if (!apps.any((app) => app['id'] == selected)) {
        await prefs.remove(preferenceKey);
        selected = null;
      }
      var remember = false;
      if (choose || selected == null) {
        if (!context.mounted) return;
        var choice = selected ?? apps.first['id']!;
        final result = await showDialog<({String id, bool remember})>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: const Text('فتح الملاحة باستخدام'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final app in apps)
                      ListTile(
                        title: Text(app['name']!),
                        leading: Icon(
                          choice == app['id']
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        onTap: () => update(() => choice = app['id']!),
                      ),
                    const Text(
                      'يمكنك تغيير الاختيار من الإعدادات: تحديد تطبيق الخرائط',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, (id: choice, remember: false)),
                  child: const Text('لمرة واحدة'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, (id: choice, remember: true)),
                  child: const Text('دائماً'),
                ),
              ],
            ),
          ),
        );
        if (result == null) return;
        selected = result.id;
        remember = result.remember;
      }
      final opened = android
          ? await channel.invokeMethod<bool>('open', {
                  'id': selected,
                  'lat': lat,
                  'lng': lng,
                }) ==
                true
          : await launchUrl(
              uri(selected, lat, lng),
              mode: LaunchMode.externalApplication,
            );
      if (opened) {
        if (remember) {
          await prefs.setString(preferenceKey, selected);
          await prefs.setString(
            '${preferenceKey}_name',
            apps.firstWhere((app) => app['id'] == selected)['name']!,
          );
        }
        if (choose && !remember) await prefs.remove(preferenceKey);
      } else {
        await prefs.remove(preferenceKey);
        showAppNotice(
          context,
          'تعذّر فتح تطبيق الخرائط؛ حاول اختيار تطبيق آخر',
          messenger: messenger,
        );
      }
    } catch (_) {
      showAppNotice(
        context,
        'تعذّر فتح تطبيق الخرائط؛ حاول مجدداً',
        messenger: messenger,
      );
    }
  }
}
