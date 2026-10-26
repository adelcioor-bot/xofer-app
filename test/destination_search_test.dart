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
import 'package:xofer/features/places/domain/place_search_failure.dart';
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
  @override
  Future<UserLocation> currentLocation() async {
    return const UserLocation(latitude: -23.55, longitude: -46.63);
  }

  @override
  Future<void> openSettings(LocationFailureReason reason) async {}
}

class _FakePlaceSearchRepository implements PlaceSearchRepository {
  _FakePlaceSearchRepository({this.results = const [], this.error});

  final List<Place> results;
  final Object? error;
  String? lastQuery;
  UserLocation? lastNear;
  int requests = 0;

  @override
  Future<List<Place>> search(String query, {UserLocation? near}) async {
    requests += 1;
    lastQuery = query;
    lastNear = near;
    if (error != null) throw error!;
    return results;
  }

  @override
  Future<Place?> reverse(UserLocation location) async {
    return Place(
      id: 'origin',
      label: 'Praça da Sé',
      description: 'Praça da Sé, São Paulo',
      latitude: location.latitude,
      longitude: location.longitude,
    );
  }
}

const _paulista = Place(
  id: '1',
  label: 'Avenida Paulista',
  description: 'Avenida Paulista, São Paulo, Brasil',
  latitude: -23.5614,
  longitude: -46.6558,
);

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('pt'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

Future<void> _searchFor(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const Key('destination_search_field')), query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  testWidgets('mostra endereços e marca o destino escolhido', (tester) async {
    final places = _FakePlaceSearchRepository(results: const [_paulista]);
    final mapController = MapController();

    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          authRepository: _FakeAuthRepository(),
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: places,
          mapController: mapController,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await _searchFor(tester, 'paulista');

    expect(places.requests, 1);
    expect(places.lastQuery, 'paulista');
    expect(places.lastNear?.latitude, -23.55);
    expect(find.byKey(const Key('destination_result_0')), findsOneWidget);
    expect(find.text('Avenida Paulista'), findsWidgets);
    expect(find.text('Avenida Paulista, São Paulo, Brasil'), findsOneWidget);

    final result = find.byKey(const Key('destination_result_0'));
    final gesture = await tester.startGesture(tester.getCenter(result));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final field = tester.widget<TextField>(
      find.byKey(const Key('destination_search_field')),
    );
    expect(field.controller?.text, _paulista.description);
    expect(find.byKey(const Key('destination_results')), findsNothing);
    expect(find.byKey(const Key('advance_route_button')), findsNothing);
    expect(find.byKey(const Key('ride_price')), findsOneWidget);
    expect(find.text('Praça da Sé, São Paulo'), findsWidgets);
    expect(find.text('Avenida Paulista, São Paulo, Brasil'), findsWidgets);
    expect(find.text('Confirmar Motorista + Resgate'), findsOneWidget);

    final price = tester.widget<Text>(find.byKey(const Key('ride_price')));
    expect(price.style?.fontWeight, FontWeight.w800);
    expect(price.data, startsWith('R\$'));

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('destination_marker')), findsOneWidget);

    final route = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(
      route.polylines.single.points,
      const [
        LatLng(-23.55, -46.63),
        LatLng(-23.5614, -46.6558),
      ],
    );
    expect(mapController.camera.center.latitude, isNot(HomeScreen.fallbackCenter.latitude));
  });

  testWidgets('não busca com menos de 3 caracteres', (tester) async {
    final places = _FakePlaceSearchRepository();

    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          authRepository: _FakeAuthRepository(),
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: places,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await _searchFor(tester, 'av');

    expect(places.requests, 0);
    expect(find.byKey(const Key('destination_results')), findsNothing);
  });

  testWidgets('avisa quando a busca não encontra endereço', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          authRepository: _FakeAuthRepository(),
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: _FakePlaceSearchRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await _searchFor(tester, 'lugar nenhum');

    expect(find.byKey(const Key('destination_search_empty')), findsOneWidget);
    expect(find.text('Nenhum endereço encontrado.'), findsOneWidget);
  });

  testWidgets('avisa quando a geocodificação falha', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          authRepository: _FakeAuthRepository(),
          locationRepository: _FakeLocationRepository(),
          placeSearchRepository: _FakePlaceSearchRepository(
            error: const PlaceSearchFailure(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await _searchFor(tester, 'paulista');

    expect(find.byKey(const Key('destination_search_error')), findsOneWidget);
    expect(find.textContaining('Não foi possível buscar'), findsOneWidget);
  });
}
