bool restaurantIsOpen(Map restaurant, {DateTime? now}) {
  if (restaurant['open'] == false) return false;
  final deadline = DateTime.tryParse('${restaurant['closing_at'] ?? ''}');
  if (deadline != null) return (now ?? DateTime.now()).isBefore(deadline);
  final parts = '${restaurant['closing_time'] ?? ''}'.split(':');
  if (parts.length >= 2) {
    final hour = int.tryParse(parts[0]), minute = int.tryParse(parts[1]);
    if (hour != null && minute != null) {
      final local = (now ?? DateTime.now()).toUtc().add(
        const Duration(hours: 3),
      );
      return local.hour * 60 + local.minute < hour * 60 + minute;
    }
  }
  return true;
}

bool catalogMealAvailable(Map meal, {DateTime? now}) =>
    meal['available'] != false &&
    restaurantIsOpen({
      'open': meal['restaurant_open'],
      'closing_time': meal['restaurant_closing_time'],
    }, now: now);
