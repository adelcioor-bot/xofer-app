import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/features/profile/data/cpf.dart';
import 'package:xofer/features/profile/domain/profile_failure.dart';
import 'package:xofer/features/profile/domain/profile_repository.dart';
import 'package:xofer/features/profile/domain/user_profile.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository({this._client});

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  @override
  Future<UserProfile?> fetchCurrent() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const ProfileFailure('Sessão expirada. Entre novamente.');
    }

    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data == null) return UserProfile(id: user.id, phone: user.phone);
      final profile = UserProfile.fromMap(data);
      return UserProfile(
        id: profile.id,
        fullName: profile.fullName,
        document: profile.document,
        phone: user.phone ?? profile.phone,
      );
    } on PostgrestException catch (error) {
      throw ProfileFailure(error.message);
    } catch (_) {
      throw const ProfileFailure(
        'Não foi possível carregar o cadastro. Tente novamente.',
      );
    }
  }

  @override
  Future<UserProfile> save({
    required String fullName,
    required String document,
    String? phone,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const ProfileFailure('Sessão expirada. Entre novamente.');
    }

    final payload = {
      'id': user.id,
      'full_name': fullName.trim(),
      'document': Cpf.digitsOnly(document),
      'phone': phone ?? user.phone,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final data = await _supabase
          .from('profiles')
          .upsert(payload, onConflict: 'id')
          .select()
          .single();

      return UserProfile.fromMap(data);
    } on PostgrestException catch (error) {
      throw ProfileFailure(error.message);
    } catch (_) {
      throw const ProfileFailure(
        'Não foi possível salvar o cadastro. Tente novamente.',
      );
    }
  }
}
