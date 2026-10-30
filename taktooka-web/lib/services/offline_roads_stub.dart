class OfflineRoads {
  bool get isReady => false;
  Future<Map<String, dynamic>> Function(double, double)? snapOverride;
  Future<Map<String, dynamic>> Function(double, double, double, double)?
  routeOverride;

  static final shared = OfflineRoads();
  Future<void> warmUp() async {}
  Future<Map<String, dynamic>> snap(double lat, double lng) async =>
      throw StateError('OFFLINE_ROADS_UNSUPPORTED');
  Future<Map<String, dynamic>> route(
    double a,
    double b,
    double c,
    double d,
  ) async => throw StateError('OFFLINE_ROADS_UNSUPPORTED');
}
