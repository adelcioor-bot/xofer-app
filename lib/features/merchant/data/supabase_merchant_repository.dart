import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/features/merchant/domain/merchant_profile.dart';
import 'package:xofer/features/merchant/domain/merchant_repository.dart';

class SupabaseMerchantRepository implements MerchantRepository {
  SupabaseMerchantRepository({this.client});

  final SupabaseClient? client;

  SupabaseClient get _supabase => client ?? Supabase.instance.client;

  String get _userId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) {
      throw const MerchantFailure('Sessão expirada. Entre novamente.');
    }
    return id;
  }

  @override
  Future<MerchantProfile?> fetchCurrent() async {
    final userId = _userId;
    try {
      final row = await _supabase
          .from('merchant_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      return row == null
          ? null
          : MerchantProfile.fromMap(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      debugPrint('SupabaseMerchantRepository.fetchCurrent failed: $error');
      throw MerchantFailure(
        'Não foi possível carregar o estabelecimento: ${error.message}',
      );
    }
  }

  @override
  Future<MerchantProfile> register({
    required String businessName,
    required String document,
    required String phone,
    required String address,
    required String legalName,
    required String postalCode,
    required String street,
    required String buildingNumber,
    required String district,
    required String city,
    required String state,
    required String? openingTime,
    required String? closingTime,
    required List<String> operatingDays,
    required String socialLinks,
  }) async {
    try {
      final result = await _supabase.rpc(
        'rpc_register_merchant',
        params: {
          'p_business_name': businessName.trim(),
          'p_document': document.replaceAll(RegExp(r'\D'), ''),
          'p_phone': phone.trim(),
          'p_address': address.trim(),
          'p_legal_name': legalName.trim(),
          'p_postal_code': postalCode.replaceAll(RegExp(r'\D'), ''),
          'p_street': street.trim(),
          'p_building_number': buildingNumber.trim(),
          'p_district': district.trim(),
          'p_city': city.trim(),
          'p_state': state.trim().toUpperCase(),
          'p_opening_time': openingTime,
          'p_closing_time': closingTime,
          'p_operating_days': operatingDays,
          'p_social_links': socialLinks.trim(),
        },
      );
      final row = result is List && result.isNotEmpty ? result.first : result;
      if (row is! Map) {
        throw const MerchantFailure(
          'O servidor não confirmou o cadastro do estabelecimento.',
        );
      }
      return MerchantProfile.fromMap(Map<String, dynamic>.from(row));
    } on MerchantFailure {
      rethrow;
    } on PostgrestException catch (error) {
      debugPrint('SupabaseMerchantRepository.register failed: $error');
      throw MerchantFailure(error.message);
    }
  }

  @override
  Stream<List<MerchantRide>> watchRides() {
    final userId = _userId;
    return _supabase
        .from('corridas')
        .stream(primaryKey: const ['id'])
        .eq('requested_by', userId)
        .map(
          (rows) =>
              rows
                  .map(
                    (row) =>
                        MerchantRide.fromMap(Map<String, dynamic>.from(row)),
                  )
                  .toList()
                ..sort((left, right) {
                  return (right.createdAt ??
                          DateTime.fromMillisecondsSinceEpoch(0))
                      .compareTo(
                        left.createdAt ??
                            DateTime.fromMillisecondsSinceEpoch(0),
                      );
                }),
        );
  }
}
