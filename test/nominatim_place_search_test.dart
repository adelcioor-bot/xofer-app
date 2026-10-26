import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xofer/features/location/domain/user_location.dart';
import 'package:xofer/features/places/data/nominatim_place_search_repository.dart';
import 'package:xofer/features/places/domain/place_search_failure.dart';

void main() {
  test('converte a resposta do Nominatim em lugares', () {
    final places = placesFromNominatim([
      {
        'place_id': 42,
        'lat': '-23.5614',
        'lon': '-46.6558',
        'name': 'Avenida Paulista',
        'display_name': 'Avenida Paulista, São Paulo, Brasil',
      },
      {'lat': 'nope', 'lon': '0', 'display_name': 'Inválido'},
    ]);

    expect(places, hasLength(1));
    expect(places.single.label, 'Avenida Paulista');
    expect(places.single.latitude, -23.5614);
    expect(places.single.longitude, -46.6558);
  });

  test('envia a busca ao Nominatim com viés da posição atual', () async {
    Uri? requested;
    String? userAgent;
    final repository = NominatimPlaceSearchRepository(
      client: MockClient((request) async {
        requested = request.url;
        userAgent = request.headers['user-agent'];
        return http.Response(
          '[{"place_id":1,"lat":"-23.5","lon":"-46.6","display_name":"Sé, São Paulo"}]',
          200,
        );
      }),
    );

    final places = await repository.search(
      'praça da sé',
      near: const UserLocation(latitude: -23.55, longitude: -46.63),
    );

    expect(places.single.label, 'Sé, São Paulo');
    expect(requested?.host, 'nominatim.openstreetmap.org');
    expect(requested?.queryParameters['q'], 'praça da sé');
    expect(requested?.queryParameters['viewbox'], isNotNull);
    expect(userAgent, contains('Xofer'));
  });

  test('falha quando o serviço responde com erro', () async {
    final repository = NominatimPlaceSearchRepository(
      client: MockClient((request) async => http.Response('nope', 500)),
    );

    expect(
      repository.search('paulista'),
      throwsA(isA<PlaceSearchFailure>()),
    );
  });
}
