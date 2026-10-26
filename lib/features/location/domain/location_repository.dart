import 'package:xofer/features/location/domain/location_failure.dart';
import 'package:xofer/features/location/domain/user_location.dart';

abstract class LocationRepository {
  Future<UserLocation> currentLocation();

  Future<void> openSettings(LocationFailureReason reason);
}
