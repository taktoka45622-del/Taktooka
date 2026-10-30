import 'dart:math' as math;
import '../lib/widgets/captain_motion.dart';

void main() {
  var checked = 0;
  for (final left in [true, false]) {
    for (final startY in [86.0, 100.0, 209.0]) {
      (double, double)? previous;
      for (var frame = 0; frame <= 120; frame++) {
        final p = frame / 120;
        final sx = left ? 69.0 : 171.0;
        const sy = 156.0;
        var wx = (left ? 55.0 : 185.0) * (1 - p) + (left ? 101.0 : 139.0) * p;
        wx += (left ? -1 : 1) * math.sin(p * math.pi) * 35;
        final wy = startY * (1 - p) + 84 * p;
        final elbow = captainElbow(sx, sy, wx, wy, left);
        final upper = math.sqrt(
          math.pow(elbow.$1 - sx, 2) + math.pow(elbow.$2 - sy, 2),
        );
        final lower = math.sqrt(
          math.pow(elbow.$1 - wx, 2) + math.pow(elbow.$2 - wy, 2),
        );
        if (!elbow.$1.isFinite ||
            !elbow.$2.isFinite ||
            (upper - 58).abs() > .001 ||
            (lower - 64).abs() > .001) {
          throw StateError('Arm geometry invalid at $frame');
        }
        if (previous != null &&
            (elbow.$1 - previous.$1).abs() + (elbow.$2 - previous.$2).abs() >
                8) {
          throw StateError('Arm discontinuity at $frame');
        }
        previous = elbow;
        checked++;
      }
    }
  }
  print(
    'PASS: $checked articulated arm positions, constant limb lengths and continuous elbow trajectories.',
  );
}
