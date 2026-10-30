import 'dart:math' as math;

(double, double) captainElbow(
  double sx,
  double sy,
  double wx,
  double wy,
  bool left,
) {
  const upper = 58.0, lower = 64.0;
  final dx = wx - sx, dy = wy - sy;
  final raw = math.sqrt(dx * dx + dy * dy);
  final distance = raw.clamp(6.01, upper + lower - .01);
  final along =
      (upper * upper - lower * lower + distance * distance) / (2 * distance);
  final across = math.sqrt(math.max(0, upper * upper - along * along));
  final nx = dx / raw, ny = dy / raw;
  final side = left ? 1.0 : -1.0;
  return (
    sx + along * nx - side * across * ny,
    sy + along * ny + side * across * nx,
  );
}
