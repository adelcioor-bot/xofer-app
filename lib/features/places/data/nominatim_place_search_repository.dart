import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xofer/features/location/domain/user_location.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/places/domain/place_search_failure.dart';
import 'package:xofer/features/places/domain/place_search_repository.dart';

class NominatimPlaceSearchRepository implements PlaceSearchRepository {
  // ignore: prefer_initializing_formals
  NominatimPlaceSearchRepository({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const _userAgent = 'Xofer/1.0 (com.xofer.app)';

  @override
  Future<List<Place>> search(String query, {UserLocation? near}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];

    final parameters = <String, String>{
      'q': trimmed,
      'format': 'jsonv2',
      'limit': '6',
      'addressdetails': '0',
      'accept-language': 'pt-BR,pt,en',
    };

    if (near != null) {
      const delta = 0.45;
      parameters['viewbox'] =
          '${near.longitude - delta},${near.latitude + delta},'
          '${near.longitude + delta},${near.latitude - delta}';
      parameters['bounded'] = '0';
    }

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      parameters,
    );

    try {
      const headers = {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      };
      final client = _client;
      final response = await (client == null
              ? http.get(uri, headers: headers)
              : client.get(uri, headers: headers))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw const PlaceSearchFailure();
      }

      return placesFromNominatim(jsonDecode(response.body));
    } on PlaceSearchFailure {
      rethrow;
    } catch (_) {
      throw const PlaceSearchFailure();
    }
  }

  @override
  Future<Place?> reverse(UserLocation location) async {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      {
        'lat': location.latitude.toString(),
        'lon': location.longitude.toString(),
        'format': 'jsonv2',
        'addressdetails': '0',
        'accept-language': 'pt-BR,pt,en',
      },
    );

    try {
      const headers = {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      };
      final client = _client;
      final response = await (client == null
              ? http.get(uri, headers: headers)
              : client.get(uri, headers: headers))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final places = placesFromNominatim([decoded]);
      return places.isEmpty ? null : places.first;
    } catch (_) {
      return null;
    }
  }
}

List<Place> placesFromNominatim(Object? json) {
  if (json is! List) throw const PlaceSearchFailure();

  final places = <Place>[];
  for (final item in json) {
    if (item is! Map) continue;
    final latitude = double.tryParse('${item['lat']}');
    final longitude = double.tryParse('${item['lon']}');
    if (latitude == null || longitude == null) continue;

    final displayName = (item['display_name'] as String?)?.trim() ?? '';
    final name = (item['name'] as String?)?.trim() ?? '';
    final label = name.isNotEmpty ? name : displayName;
    if (label.isEmpty) continue;

    places.add(
      Place(
        id: '${item['place_id']}',
        label: label,
        description: displayName.isEmpty ? label : displayName,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }
  return places;
}
