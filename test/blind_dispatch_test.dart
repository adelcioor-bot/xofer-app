import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/location/domain/location_failure.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/location/domain/user_location.dart';
import 'package:xofer/prof/domain/dispatch_attempt.dart';
import 'package:xofer/prof/domain/dispatch_repository.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/presentation/blind_dispatch_screen.dart';
import 'package:xofer/prof/presentation/active_rescue_screen.dart';

class _Location implements LocationRepository {
  @override
  Future<UserLocation> currentLocation() async {
    return const UserLocation(latitude: -23.55, longitude: -46.63);
  }

  @override
  Future<void> openSettings(LocationFailureReason reason) async {}
}

class _DispatchRepository implements DispatchRepository {
  final StreamController<DispatchAttempt> attempts =
      StreamController<DispatchAttempt>.broadcast();
  final List<String> responses = [];
  final List<bool> availabilityChanges = [];
  final List<PartnerRole> watchedRoles = [];
  final List<PartnerRole> presenceRoles = [];
  NearbyCall? loadedCall;

  @override
  Stream<DispatchAttempt> watchAttempts({
    required String providerId,
    required PartnerRole role,
  }) {
    watchedRoles.add(role);
    return attempts.stream;
  }

  @override
  Future<MissionResponse> respondToMission({
    required String attemptId,
    required String providerId,
    required String response,
  }) async {
    responses.add('$attemptId:$providerId:$response');
    return MissionResponse(
      status: response,
      rideId: response == 'accepted' ? 'ride-1' : null,
    );
  }

  @override
  Future<NearbyCall> loadAcceptedRide(
    String rideId, {
    required PartnerRole role,
  }) async {
    return loadedCall = const NearbyCall(
      id: 'ride-call-1',
      origin: 'Origem confidencial',
      destination: 'Destino confidencial',
      client: LatLng(-23.55, -46.63),
      dropoff: LatLng(-23.56, -46.64),
      distanceKm: 3,
      driverFare: 20,
    );
  }

  @override
  Future<void> updatePresence({
    required PartnerRole role,
    required LatLng? location,
    required bool isAvailable,
  }) async {
    presenceRoles.add(role);
    availabilityChanges.add(isAvailable);
  }
}

void main() {
  testWidgets('oferta cega mostra somente título, timer e ações', (
    tester,
  ) async {
    final repository = _DispatchRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: BlindDispatchScreen(
          partnerId: 'driver-1',
          locationRepository: _Location(),
          corridaRepository: null,
          dispatchRepository: repository,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();

    repository.attempts.add(
      DispatchAttempt(
        id: 'attempt-1',
        providerRole: 'driver',
        status: 'offered',
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Novo Chamado Disponível'), findsOneWidget);
    expect(find.text(BlindMissionDialog.idleWarning), findsOneWidget);
    final timer = tester.widget<CircularProgressIndicator>(
      find.byKey(const Key('blind_mission_timer')),
    );
    expect(timer.color, AppTheme.amber);
    expect(find.text('Aceitar'), findsOneWidget);
    expect(find.text('Recusar'), findsOneWidget);
    expect(find.textContaining('Origem confidencial'), findsNothing);
    expect(find.textContaining('Destino confidencial'), findsNothing);
    expect(find.textContaining('20'), findsNothing);
    expect(find.byKey(const Key('blind_mission_countdown')), findsOneWidget);
    expect(repository.availabilityChanges, contains(true));
  });

  testWidgets('tentativa expirada não abre oferta para o motorista', (
    tester,
  ) async {
    final repository = _DispatchRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: BlindDispatchScreen(
          partnerId: 'driver-1',
          locationRepository: _Location(),
          corridaRepository: null,
          dispatchRepository: repository,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();

    repository.attempts.add(
      DispatchAttempt(
        id: 'expired-attempt',
        providerRole: 'driver',
        status: 'offered',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('blind_mission_dialog')), findsNothing);
  });

  testWidgets('aceitar chama a RPC e abre a corrida ativa', (tester) async {
    final repository = _DispatchRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: BlindDispatchScreen(
          partnerId: 'driver-1',
          locationRepository: _Location(),
          corridaRepository: null,
          dispatchRepository: repository,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();
    repository.attempts.add(
      DispatchAttempt(
        id: 'attempt-accepted',
        providerRole: 'driver',
        status: 'offered',
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('accept_mission')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.responses, ['attempt-accepted:driver-1:accepted']);
    expect(repository.loadedCall?.id, 'ride-call-1');
    expect(find.byKey(const Key('active_rescue_screen')), findsOneWidget);
  });

  testWidgets('recusar chama a RPC e fecha a oferta', (tester) async {
    final repository = _DispatchRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: BlindDispatchScreen(
          partnerId: 'driver-1',
          locationRepository: _Location(),
          corridaRepository: null,
          dispatchRepository: repository,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();
    repository.attempts.add(
      DispatchAttempt(
        id: 'attempt-declined',
        providerRole: 'driver',
        status: 'offered',
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('decline_mission')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(repository.responses, ['attempt-declined:driver-1:declined']);
    expect(find.byKey(const Key('blind_mission_dialog')), findsNothing);
    expect(find.byKey(const Key('blind_dispatch_screen')), findsOneWidget);
  });

  testWidgets('resgatador recebe despacho cego e abre a corrida como courier', (
    tester,
  ) async {
    final repository = _DispatchRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: BlindDispatchScreen(
          role: PartnerRole.courier,
          partnerId: 'courier-1',
          locationRepository: _Location(),
          corridaRepository: null,
          dispatchRepository: repository,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Área do resgatador'), findsOneWidget);
    expect(find.text('Aguardando nova missão'), findsOneWidget);
    expect(repository.watchedRoles, [PartnerRole.courier]);
    expect(repository.presenceRoles, contains(PartnerRole.courier));

    repository.attempts.add(
      DispatchAttempt(
        id: 'courier-attempt',
        providerRole: 'courier',
        status: 'offered',
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Novo Chamado Disponível'), findsOneWidget);
    expect(find.text(BlindMissionDialog.idleWarning), findsNothing);
    final timer = tester.widget<CircularProgressIndicator>(
      find.byKey(const Key('blind_mission_timer')),
    );
    expect(timer.color, AppTheme.amber);
    expect(find.text('Aceitar'), findsOneWidget);
    expect(find.text('Recusar'), findsOneWidget);
    expect(find.textContaining('Origem confidencial'), findsNothing);

    await tester.tap(find.byKey(const Key('accept_mission')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.responses, ['courier-attempt:courier-1:accepted']);
    expect(find.byKey(const Key('active_rescue_screen')), findsOneWidget);
    final activeScreen = tester.widget<ActiveRescueScreen>(
      find.byType(ActiveRescueScreen),
    );
    expect(activeScreen.role, PartnerRole.courier);
  });

  testWidgets('os 15 segundos finais ficam vermelhos', (tester) async {
    final repository = _DispatchRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: BlindDispatchScreen(
          partnerId: 'driver-1',
          locationRepository: _Location(),
          corridaRepository: null,
          dispatchRepository: repository,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();
    repository.attempts.add(
      DispatchAttempt(
        id: 'attempt-grace',
        providerRole: 'driver',
        status: 'offered',
        expiresAt: DateTime.now().add(const Duration(seconds: 15)),
      ),
    );
    await tester.pump();
    await tester.pump();

    final timer = tester.widget<CircularProgressIndicator>(
      find.byKey(const Key('blind_mission_timer')),
    );
    expect((timer.color!.a * 255).round(), isNot(255));
    expect(timer.color!.r, greaterThan(timer.color!.g));
    expect(find.text(BlindMissionDialog.idleWarning), findsOneWidget);
  });

  testWidgets('inatividade fecha o chamado e avisa que o saldo zerou', (
    tester,
  ) async {
    final repository = _DispatchRepository();
    final openedAt = DateTime.now();
    var clock = openedAt;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: BlindDispatchScreen(
          partnerId: 'driver-1',
          locationRepository: _Location(),
          corridaRepository: null,
          dispatchRepository: repository,
          onSignOut: () async {},
          now: () => clock,
        ),
      ),
    );
    await tester.pump();
    repository.attempts.add(
      DispatchAttempt(
        id: 'attempt-timeout',
        providerRole: 'driver',
        status: 'offered',
        expiresAt: openedAt.add(const Duration(seconds: 1)),
      ),
    );
    await tester.pump();
    await tester.pump();
    clock = openedAt.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('blind_mission_dialog')), findsNothing);
    expect(
      find.text('O saldo de espera foi zerado por inatividade.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('blind_dispatch_screen')), findsOneWidget);
  });
}
