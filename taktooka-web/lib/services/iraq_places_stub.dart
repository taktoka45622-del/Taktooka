import 'package:latlong2/latlong.dart';

class IraqPlaces {
  static final shared = IraqPlaces();
  Future<void> warmUp() async {}
  Future<List<Map<String, dynamic>>> search(
    String query,
    LatLng origin, {
    bool areasOnly = false,
  }) async => [];
}
