import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/features/auth/domain/auth_failure.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/location/domain/location_failure.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/location/domain/user_location.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/provider_account.dart';
import 'package:xofer/prof/domain/provider_failure.dart';
import 'package:xofer/prof/domain/provider_repository.dart';
import 'package:xofer/prof/prof_app.dart';

class _Auth implements AuthRepository {
  @override
  Future<void> sendOtp(String phoneNumber) async {}

  @override
  Future<void> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  String? get currentPhone => null;

  @override
  String? get testPhone => null;
}

Session _session() {
  return Session.fromJson({
    'access_token': 'test-access-token',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'test-refresh-token',
    'user': {
      'id': 'user-1',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  })!;
}

class _Providers implements ProviderRepository {
  ProviderAccount? current;
  Object? findError;
  bool ensured = false;

  @override
  Future<ProviderAccount?> findCurrent(PartnerRole role) async {
    final error = findError;
    if (error != null) throw error;
    return current;
  }

  @override
  Future<ProviderAccount> saveApplication(ProviderApplication application) {
    throw const AuthFailure('unused');
  }

  @override
  Future<ProviderAccount> ensureActiveTestPartner({
    required PartnerRole role,
    required String phone,
  }) async {
    ensured = true;
    return ProviderAccount(
      id: 'test',
      role: role,
      fullName: 'Teste Xofer',
      document: '123456789',
      phone: phone,
      email: 'teste@xofer.app',
      status: ProviderStatus.ativo,
    );
  }
}

class _Location implements LocationRepository {
  @override
  Future<UserLocation> currentLocation() async {
    return const UserLocation(latitude: -23.55, longitude: -46.63);
  }

  @override
  Future<void> openSettings(LocationFailureReason reason) async {}
}

class _Capture implements DocumentCapture {
  @override
  Future<CapturedDocument?> pick(DocumentSource source) async => null;
}

void main() {
  testWidgets('a tela inicial oferece motorista e motoboy', (tester) async {
    await tester.pumpWidget(
      XoferProfApp(
        authRepository: _Auth(),
        providerRepository: _Providers(),
        locationRepository: _Location(),
        documentCapture: _Capture(),
      ),
    );

    expect(find.text('Motorista (Xofer)'), findsOneWidget);
    expect(find.text('Motoboy (Resgatador)'), findsOneWidget);
    expect(find.byKey(const Key('partner_phone_field')), findsNothing);
  });

  testWidgets('sessão restaurada abre o radar sem novo OTP', (tester) async {
    final providers = _Providers()
      ..current = ProviderAccount(
        id: 'user-1',
        role: PartnerRole.driver,
        fullName: 'Motorista',
        document: '123456789',
        phone: '+554141004141',
        email: 'motorista@xofer.app',
        status: ProviderStatus.ativo,
      );

    await tester.pumpWidget(
      XoferProfApp(
        authRepository: _Auth(),
        providerRepository: providers,
        locationRepository: _Location(),
        documentCapture: _Capture(),
        currentSession: _session(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('radar_screen')), findsOneWidget);
    expect(find.byKey(const Key('partner_phone_field')), findsNothing);
  });

  testWidgets('o telefone de teste entra no radar se for parceiro ativo', (
    tester,
  ) async {
    final providers = _Providers();
    await tester.pumpWidget(
      XoferProfApp(
        authRepository: _Auth(),
        providerRepository: providers,
        locationRepository: _Location(),
        documentCapture: _Capture(),
      ),
    );

    await tester.tap(find.byKey(const Key('role_driver')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_phone_field')),
      '4141004141',
    );
    await tester.tap(find.byKey(const Key('partner_send_otp')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_otp_field')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('partner_verify_otp')));
    await tester.pump();
    await tester.pump();

    expect(providers.ensured, isTrue);
    expect(find.byKey(const Key('radar_screen')), findsOneWidget);
    expect(find.text('Chamadas próximas'), findsOneWidget);
    expect(find.byKey(const Key('calls_empty')), findsOneWidget);
  });

  testWidgets('o celular do passageiro não abre o radar do motorista', (
    tester,
  ) async {
    final providers = _Providers();
    await tester.pumpWidget(
      XoferProfApp(
        authRepository: _Auth(),
        providerRepository: providers,
        locationRepository: _Location(),
        documentCapture: _Capture(),
      ),
    );

    await tester.tap(find.byKey(const Key('role_driver')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_phone_field')),
      '4141994141',
    );
    await tester.tap(find.byKey(const Key('partner_send_otp')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_otp_field')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('partner_verify_otp')));
    await tester.pump();
    await tester.pump();

    expect(providers.ensured, isFalse);
    expect(find.byKey(const Key('registration_name')), findsOneWidget);
    expect(find.byKey(const Key('radar_screen')), findsNothing);
  });

  testWidgets('o celular do motoboy entra no radar', (tester) async {
    final providers = _Providers();
    await tester.pumpWidget(
      XoferProfApp(
        authRepository: _Auth(),
        providerRepository: providers,
        locationRepository: _Location(),
        documentCapture: _Capture(),
      ),
    );

    await tester.tap(find.byKey(const Key('role_courier')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_phone_field')),
      '4141014141',
    );
    await tester.tap(find.byKey(const Key('partner_send_otp')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_otp_field')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('partner_verify_otp')));
    await tester.pump();
    await tester.pump();

    expect(providers.ensured, isTrue);
    expect(find.byKey(const Key('radar_screen')), findsOneWidget);
  });

  testWidgets('motorista de teste abre o radar mesmo sem a tabela providers', (
    tester,
  ) async {
    final providers = _Providers()
      ..findError = const ProviderFailure(
        '{"code":"PGRST205","message":"Could not find the table \'public.providers\' in the schema cache"}',
      );

    await tester.pumpWidget(
      XoferProfApp(
        authRepository: _Auth(),
        providerRepository: providers,
        locationRepository: _Location(),
        documentCapture: _Capture(),
      ),
    );

    await tester.tap(find.byKey(const Key('role_driver')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_phone_field')),
      '4141004141',
    );
    await tester.tap(find.byKey(const Key('partner_send_otp')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_otp_field')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('partner_verify_otp')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('radar_screen')), findsOneWidget);
    expect(find.textContaining('PGRST205'), findsNothing);
  });

  testWidgets('celular sem cadastro abre o formulário do parceiro', (
    tester,
  ) async {
    await tester.pumpWidget(
      XoferProfApp(
        authRepository: _Auth(),
        providerRepository: _Providers(),
        locationRepository: _Location(),
        documentCapture: _Capture(),
      ),
    );

    await tester.tap(find.byKey(const Key('role_courier')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_phone_field')),
      '11988887777',
    );
    await tester.tap(find.byKey(const Key('partner_send_otp')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_otp_field')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('partner_verify_otp')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('registration_name')), findsOneWidget);
    expect(find.byKey(const Key('radar_screen')), findsNothing);
  });

  testWidgets('parceiro em análise não vê o radar', (tester) async {
    final providers = _Providers()
      ..current = const ProviderAccount(
        id: 'user-1',
        role: PartnerRole.driver,
        fullName: 'Ana Costa',
        document: '39053344705',
        phone: '+5511988887777',
        email: 'ana@xofer.app',
        status: ProviderStatus.analise,
      );

    await tester.pumpWidget(
      XoferProfApp(
        authRepository: _Auth(),
        providerRepository: providers,
        locationRepository: _Location(),
        documentCapture: _Capture(),
      ),
    );

    await tester.tap(find.byKey(const Key('role_driver')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_phone_field')),
      '11988887777',
    );
    await tester.tap(find.byKey(const Key('partner_send_otp')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner_otp_field')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('partner_verify_otp')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Cadastro em análise'), findsOneWidget);
    expect(providers.ensured, isFalse);
    expect(find.byKey(const Key('radar_screen')), findsNothing);
  });
}
