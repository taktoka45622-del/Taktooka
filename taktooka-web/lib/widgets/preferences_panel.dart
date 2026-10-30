import 'package:taktooka/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/core/gender_copy.dart';

class PreferencesPanel extends StatelessWidget {
  const PreferencesPanel({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appPreferences,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListTile(
          leading: Icon(Icons.language),
          title: AppText('لغة التطبيق'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ar', label: Text('العربية')),
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'ku', label: Text('کوردی')),
            ],
            selected: {appPreferences.language},
            onSelectionChanged: (values) async {
              try {
                await appPreferences.setLanguage(values.single);
              } catch (_) {
                if (context.mounted)
                  showAppNotice(context, 'تعذّر حفظ الإعدادات، أعد المحاولة');
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        const ListTile(
          leading: Icon(Icons.brightness_6_outlined),
          title: AppText('مظهر التطبيق'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: AppText('نهاري'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: AppText('ليلي'),
              ),
            ],
            selected: {appPreferences.themeMode},
            onSelectionChanged: (values) async {
              try {
                await appPreferences.setTheme(values.single);
              } catch (_) {
                if (context.mounted)
                  showAppNotice(context, 'تعذّر حفظ الإعدادات، أعد المحاولة');
              }
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
}
