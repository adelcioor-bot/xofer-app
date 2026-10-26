import 'package:latlong2/latlong.dart';
import 'package:xofer/features/places/domain/place.dart';

enum TripPhase { pickup, ride, arrived }

class TripTrack {
  const TripTrack({
    required this.driverStart,
    required this.pickup,
    required this.destination,
    this.pickupSteps = 6,
    this.rideSteps = 8,
  });

  final LatLng driverStart;
  final LatLng pickup;
  final LatLng destination;
  final int pickupSteps;
  final int rideSteps;

  int get lastStep => pickupSteps + rideSteps;

  factory TripTrack.fromPlaces({
    required Place origin,
    required Place destination,
    int pickupSteps = 6,
    int rideSteps = 8,
  }) {
    return TripTrack(
      driverStart: LatLng(
        origin.latitude + 0.012,
        origin.longitude - 0.010,
      ),
      pickup: LatLng(origin.latitude, origin.longitude),
      destination: LatLng(destination.latitude, destination.longitude),
      pickupSteps: pickupSteps,
      rideSteps: rideSteps,
    );
  }

  TripPhase phaseAt(int step) {
    if (step >= lastStep) return TripPhase.arrived;
    if (step >= pickupSteps) return TripPhase.ride;
    return TripPhase.pickup;
  }

  LatLng pointAt(int step) {
    final clamped = step.clamp(0, lastStep);
    if (clamped <= pickupSteps) {
      final t = pickupSteps == 0 ? 1.0 : clamped / pickupSteps;
      return _lerp(driverStart, pickup, t);
    }
    final rideIndex = clamped - pickupSteps;
    final t = rideSteps == 0 ? 1.0 : rideIndex / rideSteps;
    return _lerp(pickup, destination, t);
  }

  LatLng glide(int step, double t) {
    return _lerp(pointAt(step), pointAt(step + 1), t.clamp(0, 1));
  }
}

LatLng _lerp(LatLng from, LatLng to, double t) {
  return LatLng(
    from.latitude + (to.latitude - from.latitude) * t,
    from.longitude + (to.longitude - from.longitude) * t,
  );
}
