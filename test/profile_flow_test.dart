import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/core/config/app_config.dart';
import 'package:xofer/core/config/test_profile_seed.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_failure.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/location/domain/location_failure.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/location/domain/user_location.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/places/domain/place_search_repository.dart';
import 'package:xofer/features/profile/domain/profile_failure.dart';
import 'package:xofer/features/profile/domain/profile_repository.dart';
import 'package:xofer/features/profile/domain/user_profile.dart';
import 'package:xofer/features/profile/presentation/complete_profile_screen.dart';
import 'package:xofer/features/profile/presentation/profile_gate.dart';
import 'package:xofer/l10n/app_localizations.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.testPhone});

  @override
  final String? testPhone;
  @override
  String? get currentPhone => null;
  bool signedOut = false;

  @override
  Future<void> sendOtp(String phoneNumber) async {}

  @override
  Future<void> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    throw const AuthFailure('unused');
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({this.profile, this.fetchError, this.saveError});

  UserProfile? profile;
  Object? fetchError;
  Object? saveError;
  String? lastName;
  String? lastDocument;
  String? lastPhone;

  @override
  Future<UserProfile?> fetchCurrent() async {
    if (fetchError != null) throw fetchError!;
    return profile;
  }

  @override
  Future<UserProfile> save({
    required String fullName,
    required String document,
    String? phone,
  }) async {
    lastName = fullName;
    lastDocument = document;
    lastPhone = phone;
    if (saveError != null) throw saveError!;
    profile = UserProfile(
      id: 'user-1',
      fullName: fullName,
      document: document,
      phone: phone,
    );
    return profile!;
  }
}

class _FakeLocationRepository implements LocationRepository {
  @override
  Future<UserLocation> currentLocation() async {
    return const UserLocation(latitude: -23.5505, longitude: -46.6333);
  }

  @override
  Future<void> openSettings(LocationFailureReason reason) async {}
}

class _FakePlaceSearchRepository implements PlaceSearchRepository {
  @override
  Future<List<Place>> search(String query, {UserLocation? near}) async {
    return const [];
  }

  @override
  Future<Place?> reverse(UserLocation location) async => null;
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
  testWidgets('pede cadastro quando o perfil está incompleto', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ProfileGate(
          authRepository: _FakeAuthRepository(),
          profileRepository: _FakeProfileRepository(
            profile: const UserProfile(id: 'user-1'),
          ),
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: _FakePlaceSearchRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('full_name_field')), findsOneWidget);
    expect(find.byKey(const Key('document_field')), findsOneWidget);
    expect(find.text('Complete o cadastro'), findsOneWidget);
  });

  testWidgets('sessão ativa sem nome continua no fluxo de cadastro', (
    tester,
  ) async {
    final auth = _FakeAuthRepository();

    await tester.pumpWidget(
      _wrap(
        ProfileGate(
          authRepository: auth,
          profileRepository: _FakeProfileRepository(
            profile: const UserProfile(id: 'user-1'),
          ),
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: _FakePlaceSearchRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(auth.signedOut, isFalse);
    expect(find.byKey(const Key('full_name_field')), findsOneWidget);
    expect(find.text('Complete o cadastro'), findsOneWidget);
  });

  testWidgets('vai para o mapa quando o perfil já tem nome', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ProfileGate(
          authRepository: _FakeAuthRepository(),
          profileRepository: _FakeProfileRepository(
            profile: const UserProfile(id: 'user-1', fullName: 'Maria Silva'),
          ),
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: _FakePlaceSearchRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Para onde vamos?'), findsOneWidget);
    expect(find.byKey(const Key('full_name_field')), findsNothing);
  });

  testWidgets('semeia o perfil de teste e abre o mapa', (tester) async {
    final profiles = _FakeProfileRepository(
      profile: const UserProfile(id: 'user-1', phone: '+55 41 4199-4141'),
    );

    await tester.pumpWidget(
      _wrap(
        ProfileGate(
          authRepository: _FakeAuthRepository(),
          profileRepository: profiles,
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: _FakePlaceSearchRepository(),
          testProfileSeed: const TestProfileSeed(
            phoneDigits: '554141994141',
            fullName: 'Teste Xofer',
            document: '123456789',
            phone: '554141994141',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(profiles.lastName, 'Teste Xofer');
    expect(profiles.lastDocument, '123456789');
    expect(profiles.lastPhone, '554141994141');
    expect(find.text('Para onde vamos?'), findsOneWidget);
    expect(find.byKey(const Key('full_name_field')), findsNothing);
  });

  testWidgets(
    'semeia o perfil quando a sessão de teste ainda não tem telefone',
    (tester) async {
      final profiles = _FakeProfileRepository(
        profile: const UserProfile(id: 'user-1'),
      );

      await tester.pumpWidget(
        _wrap(
          ProfileGate(
            authRepository: _FakeAuthRepository(testPhone: '554141994141'),
            profileRepository: profiles,
            locationRepository: _FakeLocationRepository(),
            placeSearchRepository: _FakePlaceSearchRepository(),
            testProfileSeed: AppConfig.testProfileSeed,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(profiles.lastName, 'Teste Xofer');
      expect(profiles.lastDocument, '123456789');
      expect(profiles.lastPhone, '554141994141');
      expect(find.text('Para onde vamos?'), findsOneWidget);
    },
  );

  testWidgets('perfil de teste já existente abre o mapa sem novo cadastro', (
    tester,
  ) async {
    final profiles = _FakeProfileRepository(
      profile: const UserProfile(id: 'user-1'),
      saveError: const ProfileFailure(
        'duplicate key value violates unique constraint "profiles_document_key"',
      ),
    );

    await tester.pumpWidget(
      _wrap(
        ProfileGate(
          authRepository: _FakeAuthRepository(testPhone: '554141994141'),
          profileRepository: profiles,
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: _FakePlaceSearchRepository(),
          testProfileSeed: AppConfig.testProfileSeed,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Para onde vamos?'), findsOneWidget);
    expect(find.byKey(const Key('full_name_field')), findsNothing);
    expect(find.byKey(const Key('retry_profile_button')), findsNothing);
  });

  testWidgets('mantém o cadastro manual para outros telefones', (tester) async {
    final profiles = _FakeProfileRepository(
      profile: const UserProfile(id: 'user-1', phone: '+55 11 98888-7777'),
    );

    await tester.pumpWidget(
      _wrap(
        ProfileGate(
          authRepository: _FakeAuthRepository(),
          profileRepository: profiles,
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: _FakePlaceSearchRepository(),
          testProfileSeed: const TestProfileSeed(
            phoneDigits: '554141994141',
            fullName: 'Teste Xofer',
            document: '123456789',
            phone: '554141994141',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(profiles.lastName, isNull);
    expect(find.byKey(const Key('full_name_field')), findsOneWidget);
  });

  testWidgets('salva o perfil e segue para o mapa', (tester) async {
    final profiles = _FakeProfileRepository(
      profile: const UserProfile(id: 'user-1'),
    );

    await tester.pumpWidget(
      _wrap(
        ProfileGate(
          authRepository: _FakeAuthRepository(),
          profileRepository: profiles,
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: _FakePlaceSearchRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('full_name_field')),
      'Maria Silva',
    );
    await tester.enterText(
      find.byKey(const Key('document_field')),
      '52998224725',
    );
    await tester.tap(find.byKey(const Key('save_profile_button')));
    await tester.pump();
    await tester.pump();

    expect(profiles.lastName, 'Maria Silva');
    expect(profiles.lastDocument, '529.982.247-25');
    expect(find.text('Para onde vamos?'), findsOneWidget);
    expect(find.byKey(const Key('full_name_field')), findsNothing);
  });

  testWidgets('mostra erro de validação de CPF', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CompleteProfileScreen(
          profileRepository: _FakeProfileRepository(),
          authRepository: _FakeAuthRepository(),
          onCompleted: (_) {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('full_name_field')),
      'Maria Silva',
    );
    await tester.enterText(
      find.byKey(const Key('document_field')),
      '11111111111',
    );
    await tester.tap(find.byKey(const Key('save_profile_button')));
    await tester.pumpAndSettle();

    expect(find.text('Informe um CPF válido.'), findsOneWidget);
  });

  testWidgets('mostra erro quando o cadastro não carrega', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ProfileGate(
          authRepository: _FakeAuthRepository(),
          profileRepository: _FakeProfileRepository(
            fetchError: const ProfileFailure('Falha a carregar.'),
          ),
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: _FakePlaceSearchRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Falha a carregar.'), findsOneWidget);
    expect(find.byKey(const Key('retry_profile_button')), findsOneWidget);
  });
}
