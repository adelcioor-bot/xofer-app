import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xofer/features/merchant/domain/cep_address.dart';

class CepLookupRepository {
  CepLookupRepository({this._client});

  final http.Client? _client;

  Future<CepAddress> lookup(String cep) async {
    final digits = cep.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) {
      throw const CepLookupFailure('Informe um CEP com 8 dígitos.');
    }

    final uri = Uri.https('viacep.com.br', '/ws/$digits/json/');
    try {
      final response = await (_client?.get(uri) ?? http.get(uri)).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        throw const CepLookupFailure(
          'O serviço de CEP está indisponível. Tente novamente.',
        );
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['erro'] == true) {
        throw const CepLookupFailure('CEP não encontrado.');
      }

      final street = (data['logradouro'] as String? ?? '').trim();
      final district = (data['bairro'] as String? ?? '').trim();
      final city = (data['localidade'] as String? ?? '').trim();
      final state = (data['uf'] as String? ?? '').trim();
      if (street.isEmpty || district.isEmpty || city.isEmpty || state.isEmpty) {
        throw const CepLookupFailure(
          'O CEP não retornou o endereço completo. Confira os dados.',
        );
      }

      return CepAddress(
        cep: (data['cep'] as String? ?? digits).replaceAll(RegExp(r'\D'), ''),
        street: street,
        district: district,
        city: city,
        state: state,
      );
    } on CepLookupFailure {
      rethrow;
    } catch (error) {
      throw CepLookupFailure('Não foi possível consultar o CEP: $error');
    }
  }
}

class CepLookupFailure implements Exception {
  const CepLookupFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
