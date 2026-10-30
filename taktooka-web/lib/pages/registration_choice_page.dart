import 'package:flutter/material.dart';
import 'package:taktooka/services/backend.dart';

import 'captain_registration_page.dart';
import 'commerce_page.dart';

class RegistrationChoicePage extends StatelessWidget {
  final Backend b;
  const RegistrationChoicePage({super.key, required this.b});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تسجيل')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final entry in [
          ('تسجيل كابتن تكتك', 'tuktuk', Icons.electric_rickshaw),
          ('تسجيل كابتن دراجة', 'bike', Icons.delivery_dining),
        ])
          Card(
            child: ListTile(
              leading: Icon(entry.$3),
              title: Text(entry.$1),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CaptainRegistrationPage(backend: b, vehicle: entry.$2),
                ),
              ),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.restaurant),
            title: const Text('لدي مطعم — تسجيل'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FoodPage(b: b, register: true)),
            ),
          ),
        ),
      ],
    ),
  );
}
