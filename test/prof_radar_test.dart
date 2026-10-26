import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/location/domain/location_failure.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/location/domain/user_location.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/data/memory_corrida_repository.dart';
import 'package:xofer/prof/domain/corrida.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/incident_report.dart';
import 'package:xofer/prof/domain/rescue_offer.dart';
import 'package:xofer/prof/domain/ride_status.dart';
import 'package:xofer/prof/presentation/active_rescue_screen.dart';
import 'package:xofer/prof/presentation/radar_screen.dart';
import 'package:xofer/prof/domain/nearby_call.dart';

class _Location implements LocationRepository {
  @override
  Future<UserLocation> currentLocation() async {
    return const UserLocation(latitude: -23.55, longitude: -46.63);
  }

  @override
  Future<void> openSettings(LocationFailureReason reason) async {}
}

void main() {
  testWidgets('radar vazio não inventa chamadas para o motorista', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('pt'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: RadarScreen(
          role: PartnerRole.driver,
          locationRepository: _Location(),
          partnerId: 'authenticated-driver',
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('calls_empty')), findsOneWidget);
    expect(find.text('Avenida Paulista, 1000'), findsNothing);
  });

  testWidgets('motorista aceita chamada real com a sessão ativa', (
    tester,
  ) async {
    const call = NearbyCall(
      id: 'ride-1',
      origin: 'Praça da Sé',
      destination: 'Avenida Paulista',
      client: LatLng(-23.55, -46.63),
      dropoff: LatLng(-23.56, -46.64),
      distanceKm: 3.2,
      driverFare: 18.50,
    );
    final corridas = MemoryCorridaRepository();
    await corridas.requestRide(call: call);
    final corridaId = corridas.current!.id;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('pt'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: RadarScreen(
          role: PartnerRole.driver,
          locationRepository: _Location(),
          corridaRepository: corridas,
          partnerId: 'authenticated-driver',
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(Key('nearby_call_$corridaId')), findsOneWidget);
    await tester.ensureVisible(find.byKey(Key('accept_call_$corridaId')));
    await tester.tap(find.byKey(Key('accept_call_$corridaId')));
    await tester.pump();
    await tester.pump();

    expect(corridas.acceptedDrivers, [corridaId]);
    expect(corridas.current?.acceptedBy, 'authenticated-driver');
    expect(corridas.current?.status, RideStatus.procurandoMotoboy);
    expect(find.byKey(const Key('active_rescue_screen')), findsOneWidget);
    expect(find.text('Aguardando um Motoboy para resgate...'), findsOneWidget);
    expect(find.byKey(const Key('rescue_search_active')), findsOneWidget);
    expect(find.byKey(const Key('rescue_motoboy_marker')), findsNothing);
  });

  testWidgets('motoboy aceita apenas oferta de corrida real', (tester) async {
    const call = NearbyCall(
      id: 'ride-2',
      origin: 'Avenida Paulista, 1000',
      destination: 'Pinheiros',
      client: LatLng(-23.54, -46.62),
      dropoff: LatLng(-23.53, -46.61),
      distanceKm: 4.2,
      driverFare: 22.50,
    );
    final corridas = MemoryCorridaRepository();
    await corridas.requestRide(call: call);
    expect(await corridas.loadOffers(role: PartnerRole.courier), isEmpty);
    await corridas.acceptCall(
      corridas.current!.id,
      driver: const LatLng(-23.54, -46.62),
    );
    expect(await corridas.loadOffers(role: PartnerRole.driver), isEmpty);
    expect(await corridas.loadOffers(role: PartnerRole.courier), hasLength(1));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('pt'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: RadarScreen(
          role: PartnerRole.courier,
          locationRepository: _Location(),
          corridaRepository: corridas,
          partnerId: 'motoboy-1',
          partnerName: 'Carlos Souza',
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Encontro com o motorista'), findsOneWidget);
    expect(find.byKey(const Key('offer_rescue_distance')), findsOneWidget);
    const courierPosition = LatLng(-23.55, -46.63);
    const driverPosition = LatLng(-23.54, -46.62);
    const geoDistance = Distance();
    final rescueDistance = geoDistance.as(
      LengthUnit.Kilometer,
      courierPosition,
      driverPosition,
    );
    expect(
      find.text(
        'Distância até o motorista: ${formatKilometers(rescueDistance)}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(formatBrl(rescuePayoutForDistance(rescueDistance))),
      findsOneWidget,
    );
    expect(find.text('Pinheiros'), findsNothing);
    expect(find.text('R\$ 10,13'), findsNothing);
    expect(find.text('Aceitar'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('accept_offer')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('accept_offer')));
    await tester.pump();
    await tester.pump();

    expect(corridas.current?.motoboyId, 'motoboy-1');
    expect(corridas.current?.motoboyNome, 'Carlos Souza');
    expect(corridas.current?.status, RideStatus.motoboyACaminho);
    expect(corridas.current?.rescueDistanceKm, closeTo(rescueDistance, 0.001));
    expect(
      corridas.current?.rescueFare,
      rescuePayoutForDistance(rescueDistance),
    );
    expect(find.text('Indo ao encontro do motorista'), findsOneWidget);
  });

  testWidgets('motoboy não vê ofertas simuladas quando a fila está vazia', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('pt'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: RadarScreen(
          role: PartnerRole.courier,
          locationRepository: _Location(),
          partnerId: 'authenticated-courier',
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('offer_empty')), findsOneWidget);
    expect(find.textContaining('Avenida Paulista'), findsNothing);
    expect(find.text('Aceitar'), findsNothing);
  });

  testWidgets('o motorista acompanha as fases e finaliza a corrida', (
    tester,
  ) async {
    const call = NearbyCall(
      id: 'curto',
      origin: 'Origem',
      destination: 'Destino',
      client: LatLng(-23.54, -46.62),
      dropoff: LatLng(-23.53, -46.61),
      distanceKm: 2,
      driverFare: 15,
    );
    final corridas = MemoryCorridaRepository();
    await corridas.requestRide(call: call);
    await corridas.acceptCall(
      corridas.current!.id,
      driver: const LatLng(-23.55, -46.63),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('pt'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ActiveRescueScreen(
          role: PartnerRole.driver,
          driver: const LatLng(-23.55, -46.63),
          call: call,
          corridaRepository: corridas,
          stepInterval: const Duration(milliseconds: 30),
          approachSteps: 1,
          clientSteps: 1,
          destinationSteps: 1,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Aguardando um Motoboy para resgate...'), findsOneWidget);
    expect(find.byKey(const Key('rescue_motoboy_marker')), findsNothing);

    await corridas.assignMotoboy(
      id: corridas.current!.id,
      motoboyId: 'authenticated-courier',
      motoboyNome: 'Carlos Souza',
      etaMinutos: 5,
      motoboy: const LatLng(-23.56, -46.64),
      rescueDistanceKm: 1.5,
      rescueFare: 5.40,
    );
    await tester.pump();

    expect(find.text('Motoboy a caminho do seu encontro'), findsOneWidget);
    expect(find.byIcon(Icons.two_wheeler), findsWidgets);
    expect(find.byIcon(Icons.person), findsWidgets);
    expect(find.text('Finalizar Corrida'), findsNothing);
    var markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    var trackedMotoboy = markerLayer.markers.firstWhere(
      (marker) => marker.key == const Key('rescue_motoboy_marker'),
    );
    expect(trackedMotoboy.point, const LatLng(-23.56, -46.64));

    corridas.pushMotoboyPosition(const LatLng(-23.57, -46.65));
    await tester.pump();
    markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    trackedMotoboy = markerLayer.markers.firstWhere(
      (marker) => marker.key == const Key('rescue_motoboy_marker'),
    );
    expect(trackedMotoboy.point, const LatLng(-23.57, -46.65));

    corridas.push(RideStatus.aCaminhoDoCliente);
    await tester.pump();
    await tester.pump();
    expect(find.text('A caminho do carro do cliente'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsWidgets);
    expect(find.byIcon(Icons.directions_car), findsNothing);

    corridas.push(RideStatus.conduzindoDestino);
    await tester.pump();
    await tester.pump();
    expect(find.text('Navegação até o destino'), findsOneWidget);
    expect(find.byKey(const Key('navigation_hint')), findsOneWidget);
    expect(find.byIcon(Icons.directions_car), findsWidgets);
    expect(find.text('Finalizar Corrida'), findsOneWidget);

    await tester.tap(find.byKey(const Key('advance_phase_button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Corrida concluída'), findsOneWidget);
    expect(corridas.advanced, [RideStatus.concluida]);
  });

  testWidgets('o motoboy avança as fases e grava o status', (tester) async {
    const call = NearbyCall(
      id: 'curto',
      origin: 'Origem',
      destination: 'Destino',
      client: LatLng(-23.54, -46.62),
      dropoff: LatLng(-23.53, -46.61),
      distanceKm: 2,
      driverFare: 15,
    );
    final corridas = MemoryCorridaRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('pt'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ActiveRescueScreen(
          role: PartnerRole.courier,
          driver: const LatLng(-23.55, -46.63),
          call: call,
          corridaRepository: corridas,
          stepInterval: const Duration(milliseconds: 30),
          approachSteps: 1,
          clientSteps: 1,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Indo ao encontro do motorista'), findsOneWidget);
    expect(find.text('Cheguei ao Motorista'), findsOneWidget);
    expect(find.byIcon(Icons.two_wheeler), findsWidgets);

    final approach = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines
        .single
        .points;
    expect(approach, hasLength(2));
    expect(
      approach.last.latitude,
      isNot(closeTo(call.client.latitude, 0.00001)),
    );

    await tester.tap(find.byKey(const Key('advance_phase_button')));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Levando o motorista até o carro do cliente'),
      findsOneWidget,
    );
    expect(find.text('Motorista Entregue no Cliente'), findsOneWidget);
    expect(corridas.advanced, [RideStatus.aCaminhoDoCliente]);
    final toClient = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines
        .single
        .points;
    expect(toClient.last.latitude, closeTo(call.client.latitude, 0.00001));
    expect(find.text('Navegação até o destino'), findsNothing);

    await tester.tap(find.byKey(const Key('advance_phase_button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('mission_complete_screen')), findsOneWidget);
    expect(find.text('Missão concluída'), findsOneWidget);
    expect(find.text('Navegação até o destino'), findsNothing);
    expect(corridas.advanced, [
      RideStatus.aCaminhoDoCliente,
      RideStatus.conduzindoDestino,
    ]);

    final screen = tester.widget<Scaffold>(
      find.byKey(const Key('mission_complete_screen')),
    );
    expect(screen.backgroundColor, AppTheme.graphite);
  });

  testWidgets('sem a tabela de corridas a fase segue e a mensagem é curta', (
    tester,
  ) async {
    const call = NearbyCall(
      id: 'curto',
      origin: 'Origem',
      destination: 'Destino',
      client: LatLng(-23.54, -46.62),
      dropoff: LatLng(-23.53, -46.61),
      distanceKm: 2,
      driverFare: 15,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('pt'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ActiveRescueScreen(
          role: PartnerRole.courier,
          driver: const LatLng(-23.55, -46.63),
          call: call,
          corridaRepository: _MissingCorridas(),
          stepInterval: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('corrida_sync_error')), findsOneWidget);
    expect(find.textContaining('PGRST205'), findsNothing);
    expect(find.textContaining('tabela de corridas'), findsOneWidget);

    await tester.tap(find.byKey(const Key('advance_phase_button')));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Levando o motorista até o carro do cliente'),
      findsOneWidget,
    );
  });
}

class _MissingCorridas implements CorridaRepository {
  @override
  Future<Corrida> requestRide({required NearbyCall call}) {
    throw CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );
  }

  @override
  Future<Corrida> acceptCall(String id, {required LatLng driver}) {
    throw CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );
  }

  @override
  Future<Corrida> advance(String id, RideStatus status) {
    throw CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );
  }

  @override
  Future<Corrida> open({
    required NearbyCall call,
    required PartnerRole role,
    required LatLng partner,
  }) {
    throw CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );
  }

  @override
  Stream<Corrida> watch(String id) => const Stream.empty();

  @override
  Future<Corrida> releaseToQueue(String id) {
    throw CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );
  }

  @override
  Future<void> reportIncident(IncidentReport report) {
    throw CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );
  }

  @override
  Future<List<RescueOffer>> loadOffers({required PartnerRole role}) async =>
      const [];

  @override
  Future<Corrida> assignMotoboy({
    required String id,
    required String motoboyId,
    required String motoboyNome,
    required int etaMinutos,
    required LatLng motoboy,
    required double rescueDistanceKm,
    required double rescueFare,
  }) {
    throw CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );
  }

  @override
  Stream<List<RescueOffer>> offers({required PartnerRole role}) =>
      const Stream.empty();

  @override
  Future<Corrida> beginBoardingValidation(
    String id, {
    String? token,
    String? reserveCode,
  }) {
    throw CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );
  }

  @override
  Future<Corrida?> activeAwaitingValidation() async => null;

  @override
  Future<Corrida> confirmBoarding(String scannedToken) {
    throw CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );
  }

  @override
  Future<Corrida> confirmBoardingWithReserveCode(String reserveCode) {
    throw CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );
  }
}
