import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/brand_title.dart';

const brandRed = scarlet;
const cream = Colors.white;
const cities = <String, LatLng>{
  'بغداد': LatLng(33.340, 44.401),
  'بابل': LatLng(32.472, 44.421),
  'البصرة': LatLng(30.508, 47.783),
  'ديالى': LatLng(33.748, 44.641),
  'كركوك': LatLng(35.468, 44.392),
  'كربلاء': LatLng(32.616, 44.024),
  'النجف': LatLng(32.001, 44.337),
};
int? readNumber(String? value) => int.tryParse(
  (value ?? '')
      .replaceAllMapped(
        RegExp('[٠-٩]'),
        (m) => '٠١٢٣٤٥٦٧٨٩'.indexOf(m[0]!).toString(),
      )
      .replaceAll(RegExp(r'[,،٬\s]'), ''),
);
typedef Runner = Future<void> Function(Future<void> Function());
Future<void> openFeature(
  BuildContext context,
  Backend b,
  String title,
  Widget Function() builder,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: BrandTitle(), centerTitle: true),
      body: AnimatedBuilder(animation: b, builder: (_, __) => builder()),
    ),
  ),
);
