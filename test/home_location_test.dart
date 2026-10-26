import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_failure.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/home/presentation/home_screen.dart';
import 'package:xofer/features/location/domain/location_failure.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/location/domain/user_location.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/places/domain/place_search_repository.dart';
import 'package:xofer/l10n/app_localizations.dart';

class _FakeAuthRepository implements AuthRepository {
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
  Future<void> signOut() async {}

  @override
  String? get currentPhone => null;

  @override
  String? get testPhone => null;
}

class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({this.error, this.location});

  final LocationFailure? error;
  UserLocation? location;
  int requests = 0;
  LocationFailureReason? openedSettings;

  @override
  Future<UserLocation> currentLocation() async {
    requests += 1;
    if (error != null) throw error!;
    return location!;
  }

  @override
  Future<void> openSettings(LocationFailureReason reason) async {
    openedSettings = reason;
  }
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('centraliza o mapa na posição atual ao abrir', (tester) async {
    final locations = _FakeLocationRepository(
      location: const UserLocation(latitude: -22.9068, longitude: -43.1729),
    );
    final mapController = MapController();

    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          authRepository: _FakeAuthRepository(),
          locationRepository: locations,
          placeSearchRepository: _FakePlaceSearchRepository(),
          mapController: mapController,
        ),
      ),
    );
    await _settle(tester);

    expect(locations.requests, 1);
    expect(find.byKey(const Key('user_location_marker')), findsOneWidget);
    expect(
      mapController.camera.center,
      const LatLng(-22.9068, -43.1729),
    );
    expect(mapController.camera.zoom, HomeScreen.userZoom);
  });

  testWidgets('o botão minha localização pede a posição de novo', (tester) async {
    final locations = _FakeLocationRepository(
      location: const UserLocation(latitude: -23.55, longitude: -46.63),
    );
    final mapController = MapController();

    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          authRepository: _FakeAuthRepository(),
          locationRepository: locations,
          placeSearchRepository: _FakePlaceSearchRepository(),
          mapController: mapController,
        ),
      ),
    );
    await _settle(tester);

    locations.location = const UserLocation(
      latitude: -22.9068,
      longitude: -43.1729,
    );
    await tester.tap(find.byKey(const Key('my_location_button')));
    await _settle(tester);

    expect(locations.requests, 2);
    expect(mapController.camera.center, const LatLng(-22.9068, -43.1729));
    expect(find.byKey(const Key('user_location_marker')), findsOneWidget);
  });

  testWidgets('avisa quando o GPS está desativado', (tester) async {
    final locations = _FakeLocationRepository(
      error: const LocationFailure(LocationFailureReason.serviceDisabled),
    );

    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          authRepository: _FakeAuthRepository(),
          locationRepository: locations,
          placeSearchRepository: _FakePlaceSearchRepository(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byKey(const Key('location_error')), findsOneWidget);
    expect(find.textContaining('GPS está desativado'), findsOneWidget);
    expect(find.byKey(const Key('location_settings_button')), findsOneWidget);
    expect(find.byKey(const Key('user_location_marker')), findsNothing);

    await tester.tap(find.byKey(const Key('location_settings_button')));
    await tester.pump();

    expect(locations.openedSettings, LocationFailureReason.serviceDisabled);
  });

  testWidgets('avisa quando a permissão de localização é negada', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          authRepository: _FakeAuthRepository(),
          locationRepository: _FakeLocationRepository(
            error: const LocationFailure(LocationFailureReason.permissionDenied),
          ),
          placeSearchRepository: _FakePlaceSearchRepository(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.textContaining('permissão de localização'), findsOneWidget);
    expect(find.byKey(const Key('location_retry_button')), findsOneWidget);
    expect(find.byKey(const Key('location_settings_button')), findsNothing);
  });

  testWidgets('pede para abrir as configurações quando a permissão está bloqueada', (
    tester,
  ) async {
    final locations = _FakeLocationRepository(
      error: const LocationFailure(
        LocationFailureReason.permissionDeniedForever,
      ),
    );

    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          authRepository: _FakeAuthRepository(),
          locationRepository: locations,
          placeSearchRepository: _FakePlaceSearchRepository(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.textContaining('está bloqueada'), findsOneWidget);
    await tester.tap(find.byKey(const Key('location_settings_button')));
    await tester.pump();

    expect(
      locations.openedSettings,
      LocationFailureReason.permissionDeniedForever,
    );
  });
}
