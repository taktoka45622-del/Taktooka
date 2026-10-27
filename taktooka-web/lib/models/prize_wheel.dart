import 'dart:math' as math;

const wheelKeys = [
  'cover',
  null,
  'repair',
  null,
  'maintenance',
  null,
  'cash',
  null,
];
const wheelTitles = [
  'جادر تكتك',
  'حظ أوفر',
  'تصليح مجاني',
  'حظ أوفر',
  'إدامة مجانية',
  'حظ أوفر',
  '35,000 د.ع',
  'حظ أوفر',
];
int wheelResultIndex(String? key) => key == null ? 1 : wheelKeys.indexOf(key);

double wheelTargetAngle(double current, int index) {
  const turn = math.pi * 2;
  final desired = (turn - (index + .5) * turn / 8) % turn;
  return current + turn * 4 + (desired - current % turn + turn) % turn;
}
