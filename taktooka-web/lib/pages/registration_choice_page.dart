import 'package:flutter/material.dart';
import 'package:taktooka/core/commerce_theme.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';

import 'captain_registration_page.dart';
import 'commerce_page.dart';

class RegistrationChoicePage extends StatelessWidget {
  final Backend b;
  const RegistrationChoicePage({super.key, required this.b});
  @override
  Widget build(BuildContext context) => Theme(
    data: commerceTheme(),
    child: Scaffold(
      appBar: AppBar(title: const Text('تسجيل')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('انضم إلى عائلة تكتوكة', style: heading(28)),
          const SizedBox(height: 8),
          const Text(
            'اختار نوع التسجيل وابدأ ويانا',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          for (final e in [
            (
              'كابتن تكتك',
              'وصّل الركاب واربح بطريقتك',
              'tuktuk',
              Icons.electric_rickshaw,
            ),
            (
              'صاحب مطعم',
              'اعرض أكلاتك واستقبل الطلبات',
              'restaurant',
              Icons.storefront_outlined,
            ),
          ])
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xfffff1f2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(e.$4, color: scarlet, size: 34),
                  ),
                  title: Text(e.$1, style: heading(21)),
                  subtitle: Text(e.$2),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => e.$3 == 'restaurant'
                          ? FoodPage(b: b, register: true)
                          : CaptainRegistrationPage(backend: b, vehicle: e.$3),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 28),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset('assets/hero.png', fit: BoxFit.cover),
          ),
        ],
      ),
    ),
  );
}
