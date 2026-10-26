import 'package:geolocator/geolocator.dart';
import 'package:xofer/features/location/domain/location_failure.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/location/domain/user_location.dart';

class GeolocatorLocationRepository implements LocationRepository {
  const GeolocatorLocationRepository();

  @override
  Future<UserLocation> currentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const LocationFailure(LocationFailureReason.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw const LocationFailure(LocationFailureReason.permissionDenied);
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationFailure(
          LocationFailureReason.permissionDeniedForever,
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      return UserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on LocationFailure {
      rethrow;
    } catch (_) {
      throw const LocationFailure(LocationFailureReason.unavailable);
    }
  }

  @override
  Future<void> openSettings(LocationFailureReason reason) async {
    if (reason == LocationFailureReason.serviceDisabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    await Geolocator.openAppSettings();
  }
}
