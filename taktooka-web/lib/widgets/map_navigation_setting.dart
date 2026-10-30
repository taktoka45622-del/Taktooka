import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/map_navigation.dart';

class MapNavigationSetting extends StatefulWidget {
  const MapNavigationSetting({super.key});
  @override
  State<MapNavigationSetting> createState() => _MapNavigationSettingState();
}

class _MapNavigationSettingState extends State<MapNavigationSetting> {
  String? name;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(MapNavigation.preferenceKey) == null
        ? null
        : prefs.getString('${MapNavigation.preferenceKey}_name');
    if (mounted) setState(() => name = value);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.navigation_outlined),
    title: const AppText('تحديد تطبيق الخرائط'),
    subtitle: AppText(name ?? 'اختيار تطبيق الخرائط المفضّل'),
    trailing: const Icon(Icons.chevron_left),
    onTap: busy
        ? null
        : () async {
            setState(() => busy = true);
            try {
              await MapNavigation.chooseDefault(context);
              await load();
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
  );
}
