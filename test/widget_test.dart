import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_failure.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/auth/presentation/login_screen.dart';
import 'package:xofer/l10n/app_localizations.dart';

class _FakeAuthRepository implements AuthRepository {
  String? lastPhone;
  String? lastCode;
  bool failSend = false;
  bool failVerify = false;

  @override
  Future<void> sendOtp(String phoneNumber) async {
    lastPhone = phoneNumber;
    if (failSend) {
      throw const AuthFailure('Falha a enviar código.');
    }
  }

  @override
  Future<void> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    lastCode = code;
    if (failVerify || code != '123456') {
      throw const AuthFailure('Código inválido.');
    }
  }

  @override
  Future<void> signOut() async {}

  @override
  String? get currentPhone => null;

  @override
  String? get testPhone => null;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('pt'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

void main() {
  testWidgets('mostra o campo OTP após enviar o código', (tester) async {
    final fake = _FakeAuthRepository();

    await tester.pumpWidget(
      _wrap(LoginScreen(authRepository: fake)),
    );

    expect(find.byKey(const Key('phone_field')), findsOneWidget);
    expect(find.byKey(const Key('otp_field')), findsNothing);

    await tester.enterText(find.byKey(const Key('phone_field')), '912345678');
    await tester.tap(find.byKey(const Key('send_otp_button')));
    await tester.pumpAndSettle();

    expect(fake.lastPhone, '+55912345678');
    expect(find.byKey(const Key('otp_field')), findsOneWidget);
    expect(find.byKey(const Key('verify_otp_button')), findsOneWidget);
  });

  testWidgets('mostra erro quando o OTP é inválido', (tester) async {
    final fake = _FakeAuthRepository();

    await tester.pumpWidget(
      _wrap(LoginScreen(authRepository: fake)),
    );

    await tester.enterText(find.byKey(const Key('phone_field')), '912345678');
    await tester.tap(find.byKey(const Key('send_otp_button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('otp_field')), '000000');
    await tester.tap(find.byKey(const Key('verify_otp_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth_error')), findsOneWidget);
    expect(find.text('Código inválido.'), findsOneWidget);
  });
}
