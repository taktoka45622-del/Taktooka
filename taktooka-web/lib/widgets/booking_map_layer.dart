import 'package:flutter/material.dart';
import 'package:taktooka/widgets/street_map_layer.dart';

class BookingMapLayer extends StatelessWidget {
  const BookingMapLayer({super.key});
  @override
  Widget build(BuildContext context) =>
      const RepaintBoundary(child: StreetMapLayer());
}
