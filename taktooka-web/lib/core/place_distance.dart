String formatPlaceDistance(double meters) {
  if (!meters.isFinite || meters < 0) return 'غير متاحة';
  if (meters < 10) return 'أقل من 10 أمتار';
  if (meters.round() < 1000) return '${meters.round()} متر';
  final km = (meters / 1000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$km كم';
}
