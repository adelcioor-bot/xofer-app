import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import 'test_phone_login.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({this.authClient});

  final GoTrueClient? authClient;

  GoTrueClient get _auth => authClient ?? Supabase.instance.client.auth;

  @override
  String? get testPhone {
    final phone = currentPhone;
    return phone == null ? null : TestPhoneLogin.canonical(phone);
  }

  @override
  String? get currentPhone => _auth.currentUser?.phone;

  @override
  Future<void> sendOtp(String phoneNumber) async {
    try {
      await _auth.signInWithOtp(phone: phoneNumber);
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (_) {
      throw const AuthFailure(
        'Não foi possível enviar o código. Tenta novamente.',
      );
    }
  }

  @override
  Future<void> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    try {
      final response = await _auth.verifyOTP(
        phone: phoneNumber,
        token: code,
        type: OtpType.sms,
      );

      if (response.session == null) {
        throw const AuthFailure('Código inválido ou expirado.');
      }
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (_) {
      throw const AuthFailure(
        'Não foi possível autenticar. Confirma o código e tenta novamente.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut(scope: SignOutScope.local);
  }
}
