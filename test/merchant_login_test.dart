import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/merchant/domain/merchant_auth_repository.dart';
import 'package:xofer/features/merchant/presentation/merchant_login_screen.dart';

class _FakeMerchantAuthRepository implements MerchantAuthRepository {
  String? identifier;
  String? signedUpBusinessName;
  String? signedUpEmail;
  String? signedUpDocument;
  String? signedUpPhone;
  String? resetEmail;

  @override
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    this.identifier = identifier;
  }

  @override
  Future<void> resetPassword(String email) async {
    resetEmail = email;
  }

  @override
  Future<bool> signUp({
    required String businessName,
    required String email,
    required String document,
    required String phone,
    required String password,
  }) async {
    signedUpBusinessName = businessName;
    signedUpEmail = email;
    signedUpDocument = document.replaceAll(RegExp(r'\D'), '');
    signedUpPhone = phone;
    return false;
  }
}

void main() {
  testWidgets('merchant login accepts an email and password', (tester) async {
    final repository = _FakeMerchantAuthRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MerchantLoginScreen(authRepository: repository),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('merchant_identifier_field')),
      'loja@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('merchant_password_field')),
      'secret123',
    );
    await tester.ensureVisible(find.byKey(const Key('merchant_submit_button')));
    await tester.tap(find.byKey(const Key('merchant_submit_button')));
    await tester.pump();

    expect(repository.identifier, 'loja@example.com');
  });

  testWidgets('merchant login accepts a formatted CNPJ', (tester) async {
    final repository = _FakeMerchantAuthRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MerchantLoginScreen(authRepository: repository),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('merchant_identifier_field')),
      '12.345.678/0001-90',
    );
    await tester.enterText(
      find.byKey(const Key('merchant_password_field')),
      'secret123',
    );
    await tester.tap(find.byKey(const Key('merchant_submit_button')));
    await tester.pump();

    expect(repository.identifier, '12.345.678/0001-90');
  });

  testWidgets(
    'merchant account creation requires email and matching passwords',
    (tester) async {
      final repository = _FakeMerchantAuthRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MerchantLoginScreen(authRepository: repository),
        ),
      );

      await tester.tap(find.text('Criar conta do estabelecimento'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('merchant_identifier_field')),
        'loja@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('merchant_signup_cnpj_field')),
        '11222333000181',
      );
      await tester.enterText(
        find.byKey(const Key('merchant_signup_business_name_field')),
        'Mercado Teste',
      );
      await tester.enterText(
        find.byKey(const Key('merchant_signup_phone_field')),
        '11999998888',
      );
      await tester.enterText(
        find.byKey(const Key('merchant_password_field')),
        'secret123',
      );
      await tester.enterText(
        find.byKey(const Key('merchant_password_confirmation_field')),
        'secret123',
      );
      await tester.ensureVisible(
        find.byKey(const Key('merchant_submit_button')),
      );
      await tester.tap(find.byKey(const Key('merchant_submit_button')));
      await tester.pump();

      expect(repository.signedUpEmail, 'loja@example.com');
      expect(repository.signedUpBusinessName, 'Mercado Teste');
      expect(repository.signedUpDocument, '11222333000181');
      expect(repository.signedUpPhone, '11999998888');
      expect(find.byKey(const Key('merchant_auth_message')), findsOneWidget);
    },
  );
}
