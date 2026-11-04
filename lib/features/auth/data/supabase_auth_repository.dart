import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/core/config/app_config.dart';

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
    if (AppConfig.shouldSimulateLocalOtp) return;

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
    if (AppConfig.shouldSimulateLocalOtp) {
      await _verifyLocalTestOtp(phoneNumber: phoneNumber, code: code);
      return;
    }

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

  Future<void> _verifyLocalTestOtp({
    required String phoneNumber,
    required String code,
  }) async {
    if (code != AppConfig.localTestOtp) {
      throw const AuthFailure('Código inválido.');
    }

    try {
      final functions = Supabase.instance.client.functions;
      final response = await functions.invoke(
        'local-test-login',
        body: {'phone': phoneNumber, 'code': code},
      );
      final data = response.data;
      final tokenHash = data is Map ? data['token_hash'] : null;
      if (tokenHash is! String || tokenHash.isEmpty) {
        final error = data is Map ? data['error'] : null;
        throw AuthFailure(
          error is String && error.isNotEmpty
              ? error
              : 'Não foi possível abrir a sessão de teste.',
        );
      }
      final verified = await _auth.verifyOTP(
        tokenHash: tokenHash,
        type: OtpType.magiclink,
      );
      if (verified.session == null) {
        throw const AuthFailure('Não foi possível abrir a sessão de teste.');
      }
    } on AuthFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error'] : null;
      throw AuthFailure(
        message is String && message.isNotEmpty
            ? message
            : 'Não foi possível entrar no modo de teste local.',
      );
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut(scope: SignOutScope.local);
  }
}
