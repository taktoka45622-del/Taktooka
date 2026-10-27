import 'package:latlong2/latlong.dart';

class AddressChoice {
  final String label;
  final LatLng point;
  final bool favorite;
  const AddressChoice(this.label, this.point, {this.favorite = false});
}
