import 'package:taktooka/widgets/map_navigation_setting.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/feature_navigation.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/account_deletion.dart';
import 'package:taktooka/pages/privacy_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/preferences_panel.dart';

class SettingsPage extends StatelessWidget {
  final Backend backend;
  final VoidCallback editAccount;
  final Future<void> Function() selectCity;
  final Runner run;
  const SettingsPage({
    super.key,
    required this.backend,
    required this.editAccount,
    required this.selectCity,
    required this.run,
  });
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const AppText(
        'الإعدادات',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      ListTile(
        title: const AppText('بيانات الحساب'),
        leading: const Icon(Icons.person_outline),
        trailing: const Icon(Icons.chevron_left),
        onTap: editAccount,
      ),
      ListTile(
        title: const AppText('اختيار المدينة'),
        subtitle: AppText(backend.city),
        leading: const Icon(Icons.location_on_outlined),
        onTap: selectCity,
      ),
      if (backend.captain) const MapNavigationSetting(),
      const PreferencesPanel(),
      ListTile(
        title: const AppText('سياسة الخصوصية وشروط الاستخدام'),
        leading: const Icon(Icons.privacy_tip_outlined),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyPage())),
      ),
      if (backend.loggedIn)
        ListTile(
          title: const AppText('حذف الحساب'),
          leading: const Icon(Icons.delete_outline, color: scarlet),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AccountDeletionPage(backend: backend),
            ),
          ),
        ),
      const ListTile(
        title: AppText('إصدار التطبيق'),
        subtitle: AppText('1.6.18'),
      ),
      if (backend.loggedIn)
        TextButton(
          onPressed: () => run(backend.signOut),
          child: const AppText('تسجيل الخروج'),
        ),
    ],
  );
}
