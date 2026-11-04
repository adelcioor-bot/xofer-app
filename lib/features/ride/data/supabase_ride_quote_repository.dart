import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';
import 'package:xofer/features/ride/domain/ride_quote_repository.dart';

class SupabaseRideQuoteRepository implements RideQuoteRepository {
  SupabaseRideQuoteRepository({this.client});

  final SupabaseClient? client;

  SupabaseClient get _supabase => client ?? Supabase.instance.client;

  @override
  Future<RideQuote> generate({
    required Place origin,
    required Place destination,
    String requesterType = 'customer',
  }) async {
    if (requesterType != 'customer' && requesterType != 'merchant') {
      throw const RideQuoteFailure('Tipo de solicitante inválido.');
    }

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw const RideQuoteFailure(
        'Sua sessão expirou. Entre novamente para calcular a corrida.',
      );
    }

    try {
      final result = await _supabase.rpc(
        'rpc_generate_ride_quote',
        params: {
          'p_requester_id': userId,
          'p_requester_type': requesterType,
          'p_origin_lat': origin.latitude,
          'p_origin_lng': origin.longitude,
          'p_dest_lat': destination.latitude,
          'p_dest_lng': destination.longitude,
        },
      );
      final row = result is List && result.isNotEmpty ? result.first : result;
      if (row is! Map) {
        throw const RideQuoteFailure(
          'O servidor retornou uma cotação inválida. Tente novamente.',
        );
      }

      final id = row['quote_id'];
      final amount = row['amount_cents'];
      final expiresAt = row['expires_at'];
      final amountCents = amount is int
          ? amount
          : amount is num && amount == amount.toInt()
          ? amount.toInt()
          : null;
      final expiration = expiresAt is String
          ? DateTime.tryParse(expiresAt)?.toLocal()
          : null;
      if (id is! String ||
          id.isEmpty ||
          amountCents == null ||
          amountCents <= 0 ||
          amountCents > 9007199254740991 ||
          expiration == null ||
          !expiration.isAfter(DateTime.now())) {
        throw const RideQuoteFailure(
          'O servidor retornou uma cotação inválida ou expirada.',
        );
      }
      return RideQuote(id: id, amountCents: amountCents, expiresAt: expiration);
    } on RideQuoteFailure {
      rethrow;
    } on PostgrestException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('configuração') || message.contains('preços')) {
        throw const RideQuoteFailure(
          'Não há uma configuração de preços ativa. Tente novamente mais tarde.',
        );
      }
      if (error.code == '42501') {
        throw const RideQuoteFailure(
          'Sua sessão não permite calcular esta cotação. Entre novamente.',
        );
      }
      throw const RideQuoteFailure(
        'Não foi possível calcular o preço agora. Verifique sua conexão e tente novamente.',
      );
    } catch (_) {
      throw const RideQuoteFailure(
        'Não foi possível calcular o preço agora. Verifique sua conexão e tente novamente.',
      );
    }
  }
}
