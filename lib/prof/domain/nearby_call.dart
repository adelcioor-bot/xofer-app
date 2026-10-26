import 'package:latlong2/latlong.dart';

class NearbyCall {
  const NearbyCall({
    required this.id,
    required this.origin,
    required this.destination,
    required this.client,
    required this.dropoff,
    required this.distanceKm,
    required this.driverFare,
  });

  final String id;
  final String origin;
  final String destination;
  final LatLng client;
  final LatLng dropoff;
  final double distanceKm;
  final double driverFare;
}
