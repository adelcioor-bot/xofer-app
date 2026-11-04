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
    this.meetingPoint,
    this.quoteId,
    this.amountCents,
    this.requesterType = 'customer',
    this.serviceType = 'rescue',
  });

  final String id;
  final String origin;
  final String destination;
  final LatLng client;
  final LatLng dropoff;
  final double distanceKm;
  final double driverFare;
  final LatLng? meetingPoint;
  final String? quoteId;
  final int? amountCents;
  final String requesterType;
  final String serviceType;
}
