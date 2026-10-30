import 'dart:math' as math;

class LocalFare {
  final Map<String, dynamic> settings;
  LocalFare(this.settings);
  static const defaults = <String, dynamic>{
    'revision': 10,
    'tiers': [
      {'up_to_m': 500, 'fare': 500},
      {'up_to_m': 2800, 'fare': 1000},
      {'up_to_m': 3800, 'fare': 1500},
      {'up_to_m': 4800, 'fare': 2000},
      {'up_to_m': 5800, 'fare': 3000},
      {'up_to_m': 6800, 'fare': 3500},
      {'up_to_m': 7800, 'fare': 4000},
      {'up_to_m': 8800, 'fare': 4250},
      {'up_to_m': 9800, 'fare': 5000},
      {'up_to_m': 10800, 'fare': 6000},
      {'up_to_m': 11800, 'fare': 6250},
      {'up_to_m': 13000, 'fare': 7500},
      {'up_to_m': 20000, 'fare': 8250},
      {'up_to_m': 25000, 'fare': 8500},
    ],
    'night_start': 21,
    'night_end': 6,
    'night_min_m': 1200,
    'night_amount': 500,
    'overflow_amount': 500,
    'overflow_step_m': 3000,
    'max_fare': 0,
  };

  static bool valid(Map<String, dynamic> s) {
    final tiers = s['tiers'];
    if (tiers is! List || tiers.isEmpty || tiers.length > 30) return false;
    var last = 0;
    for (final t in tiers) {
      if (t is! Map ||
          t['up_to_m'] is! int ||
          t['fare'] is! int ||
          t['up_to_m'] <= last ||
          t['fare'] < 0)
        return false;
      last = t['up_to_m'] as int;
    }
    for (final key in [
      'night_start',
      'night_end',
      'night_min_m',
      'night_amount',
      'overflow_amount',
      'overflow_step_m',
      'max_fare',
      'revision',
    ]) {
      if (s[key] is! int || (s[key] as int) < 0) return false;
    }
    return s['night_start'] <= 23 &&
        s['night_end'] <= 23 &&
        s['overflow_step_m'] > 0;
  }

  Map<String, dynamic> calculate(
    double meters,
    DateTime at, {
    bool roundTrip = false,
    int waitMinutes = 0,
  }) {
    if (!meters.isFinite ||
        meters <= 0 ||
        meters > 2147483647 ||
        !valid(settings)) {
      throw StateError('ROUTE_UNAVAILABLE');
    }
    if ((roundTrip && (waitMinutes < 1 || waitMinutes > 15)) ||
        (!roundTrip && waitMinutes != 0))
      throw StateError('WAIT_MINUTES_REQUIRED');
    int? base;
    final tiers = settings['tiers'] as List;
    for (final t in tiers) {
      if (meters <= (t['up_to_m'] as num)) {
        base = t['fare'] as int;
        break;
      }
    }
    base ??= math.min(
      1000000,
      (tiers.last['fare'] as int) +
          (settings['overflow_amount'] as int) *
              ((meters - (tiers.last['up_to_m'] as int)) /
                      (settings['overflow_step_m'] as int))
                  .ceil(),
    );
    final hour = at.toUtc().add(const Duration(hours: 3)).hour;
    final start = settings['night_start'] as int,
        end = settings['night_end'] as int;
    final nightTime = start < end
        ? hour >= start && hour < end
        : start > end && (hour >= start || hour < end);
    var night = meters >= (settings['night_min_m'] as int) && nightTime
        ? settings['night_amount'] as int
        : 0;
    final cap = settings['max_fare'] as int;
    if (cap > 0) {
      base = math.min(base, cap);
      night = math.min(night, math.max(0, cap - base));
    }
    final multiplier = roundTrip ? 2 : 1;
    final waiting = !roundTrip
        ? 0
        : waitMinutes <= 10
        ? 250
        : 500;
    return {
      'base_fare': base * multiplier,
      'night_surcharge': night * multiplier,
      'waiting_fee': waiting,
      'fare': (base + night) * multiplier + waiting,
      'priced_at': at.toUtc().toIso8601String(),
      'pricing_version': 'iqd-distance-v2',
      'pricing_revision': settings['revision'],
      'round_trip': roundTrip,
      'wait_minutes': waitMinutes,
    };
  }
}
