import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xofer/features/merchant/data/cep_lookup_repository.dart';

void main() {
  test('normalizes and returns ViaCEP address fields', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/ws/01001000/json/');
      return http.Response(
        '{"cep":"01001-000","logradouro":"Praça da Sé",'
        '"bairro":"Sé","localidade":"São Paulo","uf":"SP"}',
        200,
      );
    });

    final address = await CepLookupRepository(client: client)
        .lookup('01001-000');

    expect(address.cep, '01001000');
    expect(address.street, 'Praça da Sé');
    expect(address.district, 'Sé');
    expect(address.city, 'São Paulo');
    expect(address.state, 'SP');
  });

  test('reports a CEP that ViaCEP does not recognize', () async {
    final client = MockClient((_) async => http.Response('{"erro":true}', 200));

    expect(
      () => CepLookupRepository(client: client).lookup('00000000'),
      throwsA(
        isA<CepLookupFailure>().having(
          (error) => error.message,
          'message',
          'CEP não encontrado.',
        ),
      ),
    );
  });
}
