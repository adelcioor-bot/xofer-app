import 'package:xofer/features/location/domain/user_location.dart';
import 'package:xofer/features/places/domain/place.dart';

abstract class PlaceSearchRepository {
  Future<List<Place>> search(String query, {UserLocation? near});

  Future<Place?> reverse(UserLocation location);
}
