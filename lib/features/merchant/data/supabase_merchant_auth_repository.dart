import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/features/auth/domain/auth_failure.dart';
import 'package:xofer/features/merchant/domain/merchant_auth_repository.dart';

class SupabaseMerchantAuthRepository implements MerchantAuthRepository {
  SupabaseMerchantAuthRepository({this.client});

  final SupabaseClient? client;

  SupabaseClient get _supabase => client ?? Supabase.instance.client;

  @override
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    final normalized = identifier.trim();
    try {
      if (_isCnpj(normalized)) {
        final response = await _supabase.functions.invoke(
          'merchant-cnpj-login',
          body: {
            'document': normalized.replaceAll(RegExp(r'\D'), ''),
            'password': password,
          },
        );
        final data = response.data;
        if (data is! Map ||
            data['access_token'] is! String ||
            data['refresh_token'] is! String) {
          throw const AuthFailure('CNPJ ou senha inválidos.');
        }
        final session = await _supabase.auth.setSession(
          data['refresh_token'] as String,
        );
        if (session.session == null) {
          throw const AuthFailure('CNPJ ou senha inválidos.');
        }
        return;
      }

      final response = await _supabase.auth.signInWithPassword(
        email: normalized,
        password: password,
      );
      if (response.session == null) {
        throw const AuthFailure('E-mail ou senha inválidos.');
      }
    } on AuthFailure {
      rethrow;
    } on FunctionException {
      throw const AuthFailure('CNPJ ou senha inválidos.');
    } on AuthException {
      throw const AuthFailure('E-mail ou senha inválidos.');
    } catch (_) {
      throw const AuthFailure(
        'Não foi possível entrar. Verifique seus dados e tente novamente.',
      );
    }
  }

  @override
  Future<bool> signUp({
    required String businessName,
    required String email,
    required String document,
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: {
          'merchant_business_name': businessName.trim(),
          'merchant_document': document.replaceAll(RegExp(r'\D'), ''),
          'merchant_phone': phone.trim(),
        },
        emailRedirectTo: Uri.base.origin,
      );
      return response.session != null;
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (_) {
      throw const AuthFailure(
        'Não foi possível criar a conta. Tente novamente.',
      );
    }
  }

  @override
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: Uri.base.origin,
      );
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (_) {
      throw const AuthFailure(
        'Não foi possível enviar o e-mail de recuperação.',
      );
    }
  }

  bool _isCnpj(String value) =>
      value.replaceAll(RegExp(r'\D'), '').length == 14;
}
