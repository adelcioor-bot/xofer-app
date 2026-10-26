import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/ride/domain/trip_track.dart';

const _origin = Place(
  id: 'origin',
  label: 'Origem',
  description: 'Origem',
  latitude: -23.55,
  longitude: -46.63,
);

const _destination = Place(
  id: 'destination',
  label: 'Destino',
  description: 'Destino',
  latitude: -23.57,
  longitude: -46.66,
);

void main() {
  test('o motorista encontra o passageiro e depois segue ao destino', () {
    final track = TripTrack.fromPlaces(
      origin: _origin,
      destination: _destination,
      pickupSteps: 4,
      rideSteps: 4,
    );

    expect(track.phaseAt(0), TripPhase.pickup);
    expect(track.pointAt(0).latitude, closeTo(track.driverStart.latitude, 0));
    expect(track.pointAt(4).latitude, closeTo(_origin.latitude, 0.000001));
    expect(track.pointAt(4).longitude, closeTo(_origin.longitude, 0.000001));

    expect(track.phaseAt(4), TripPhase.ride);
    expect(track.phaseAt(7), TripPhase.ride);
    expect(track.phaseAt(8), TripPhase.arrived);
    expect(track.pointAt(8).latitude, closeTo(_destination.latitude, 0.000001));
    expect(
      track.pointAt(8).longitude,
      closeTo(_destination.longitude, 0.000001),
    );

    final halfway = track.glide(0, 0.5);
    expect(
      halfway.latitude,
      lessThan(track.driverStart.latitude),
    );
    expect(halfway.latitude, greaterThan(track.pointAt(1).latitude));
    expect(track.glide(0, 1).latitude, closeTo(track.glide(1, 0).latitude, 0));
  });
}
