import 'package:taktooka/core/numeric_localizations.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/feature_navigation.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';

class CityPage extends StatefulWidget {
  final Backend b;
  const CityPage({super.key, required this.b});
  @override
  State<CityPage> createState() => _CityPageState();
}

class _CityPageState extends State<CityPage> {
  String query = '';
  bool busy = false;
  String? error;
  void pick(String name, LatLng p) {
    widget.b.city = name;
    widget.b.pickupLat = p.latitude;
    widget.b.pickupLng = p.longitude;
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const AppText(
        'اختيار المدينة',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 18),
      TextField(
        inputFormatters: const [EnglishDigitsFormatter()],
        onChanged: (s) => setState(() => query = s),
        decoration: localizedInput(
          context,
          InputDecoration(
            hintText: 'ابحث عن مدينة',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ),
      if (error != null)
        AppText(error!, style: const TextStyle(color: brandRed)),
      ListTile(
        leading: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(),
              )
            : const Icon(Icons.my_location),
        title: const AppText('موقعك الحالي'),
        onTap: busy
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  final p = await widget.b.locate();
                  if (!mounted) return;
                  String nearest = cities.keys.first;
                  double distance = double.infinity;
                  for (final c in cities.entries) {
                    final d = const Distance()(
                      LatLng(p.latitude, p.longitude),
                      c.value,
                    );
                    if (d < distance) {
                      distance = d;
                      nearest = c.key;
                    }
                  }
                  pick(nearest, LatLng(p.latitude, p.longitude));
                } catch (e) {
                  if (mounted) setState(() => error = readable(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
      ),
      for (final c in cities.entries.where((e) => e.key.contains(query)))
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          tileColor: widget.b.city == c.key ? const Color(0xffffeeee) : null,
          leading: Icon(
            Icons.location_on,
            color: widget.b.city == c.key ? brandRed : Colors.grey,
          ),
          title: AppText(c.key),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => pick(c.key, c.value),
        ),
    ],
  );
}
