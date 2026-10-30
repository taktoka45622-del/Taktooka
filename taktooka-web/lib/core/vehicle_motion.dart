import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class VehiclePose {
  final LatLng point;
  final double heading;
  const VehiclePose(this.point, this.heading);
}

class VehicleMotion {
  final List<LatLng> points;
  final List<double> offsets = [0];
  VehicleMotion(List<LatLng> source) : points = List.unmodifiable(source) {
    if (points.isEmpty) throw ArgumentError('EMPTY_VEHICLE_PATH');
    for (var i = 1; i < points.length; i++)
      offsets.add(
        offsets.last +
            const Distance().as(LengthUnit.Meter, points[i - 1], points[i]),
      );
  }
  double get length => offsets.last;
  VehiclePose at(double progress, {double idleHeading = 0}) {
    if (points.length < 2 || length < .2)
      return VehiclePose(points.last, idleHeading);
    final target = length * progress.clamp(0.0, 1.0);
    var index = 1;
    while (index < offsets.length - 1 && offsets[index] < target) index++;
    final a = points[index - 1],
        b = points[index],
        distance = offsets[index] - offsets[index - 1];
    final t = distance < .01
        ? 1.0
        : ((target - offsets[index - 1]) / distance).clamp(0.0, 1.0);
    final lat1 = a.latitude * math.pi / 180,
        lat2 = b.latitude * math.pi / 180,
        dlon = (b.longitude - a.longitude) * math.pi / 180;
    final heading =
        (math.atan2(
                  math.sin(dlon) * math.cos(lat2),
                  math.cos(lat1) * math.sin(lat2) -
                      math.sin(lat1) * math.cos(lat2) * math.cos(dlon),
                ) *
                180 /
                math.pi +
            360) %
        360;
    return VehiclePose(
      LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ),
      heading,
    );
  }
}
