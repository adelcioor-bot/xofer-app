import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/ride/presentation/ride_request_wait_screen.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/data/memory_corrida_repository.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/ride_status.dart';

void main() {
  testWidgets('a tela do cliente acompanha cada etapa da corrida', (
    tester,
  ) async {
    const call = NearbyCall(
      id: 'ride-wait-status',
      origin: 'Origem do cliente',
      destination: 'Destino final',
      client: LatLng(-23.54, -46.62),
      dropoff: LatLng(-23.53, -46.61),
      distanceKm: 2,
      driverFare: 15,
    );
    final repository = MemoryCorridaRepository();
    final corrida = await repository.requestRide(call: call);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('pt'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: RideRequestWaitScreen(
          call: call,
          corrida: corrida,
          repository: repository,
        ),
      ),
    );

    expect(
      find.text('Buscando prestadores para sua corrida...'),
      findsOneWidget,
    );

    repository.push(RideStatus.procurandoMotoboy);
    await tester.pump();
    expect(
      find.text(
        'Motorista encontrado. Aguardando um motoboy para o resgate...',
      ),
      findsOneWidget,
    );

    repository.push(RideStatus.motoboyACaminho);
    await tester.pump();
    expect(
      find.text('Um motoboy aceitou o resgate e está a caminho do motorista.'),
      findsOneWidget,
    );

    repository.push(RideStatus.aCaminhoDoCliente);
    await tester.pump();
    expect(
      find.text(
        'Motorista resgatado. A caminho do ponto de embarque do cliente.',
      ),
      findsOneWidget,
    );

    repository.push(RideStatus.conduzindoDestino);
    await tester.pump();
    expect(
      find.text('Motorista chegou ao cliente. Aguardando início da corrida.'),
      findsOneWidget,
    );

    repository.push(RideStatus.emAndamento);
    await tester.pump();
    expect(find.text('Sua corrida está em andamento.'), findsOneWidget);

    repository.push(RideStatus.concluida);
    await tester.pump();
    expect(find.text('Corrida concluída.'), findsOneWidget);
    expect(find.byKey(const Key('driver_rating_stars')), findsOneWidget);
    await tester.tap(find.byKey(const Key('driver_rating_star_5')));
    await tester.pump();
    expect(find.byIcon(Icons.star), findsNWidgets(5));
    await tester.ensureVisible(find.byKey(const Key('submit_driver_rating')));
    await tester.tap(find.byKey(const Key('submit_driver_rating')));
    await tester.pumpAndSettle();
    expect(repository.driverRatings[corrida.id], 5);
    expect(find.text('Obrigado por avaliar o motorista!'), findsOneWidget);
    expect(find.text('Voltar ao início'), findsOneWidget);
  });

  testWidgets('a avaliação concluída permite voltar para a tela inicial', (
    tester,
  ) async {
    const call = NearbyCall(
      id: 'ride-return-home',
      origin: 'Origem do cliente',
      destination: 'Destino final',
      client: LatLng(-23.54, -46.62),
      dropoff: LatLng(-23.53, -46.61),
      distanceKm: 2,
      driverFare: 15,
    );
    final repository = MemoryCorridaRepository();
    final corrida = await repository.requestRide(call: call);
    repository.push(RideStatus.concluida);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('pt'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open_completed_ride'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RideRequestWaitScreen(
                      call: call,
                      corrida: repository.current!,
                      repository: repository,
                    ),
                  ),
                ),
                child: const Text('Início'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_completed_ride')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('driver_rating_star_4')));
    await tester.tap(find.byKey(const Key('driver_rating_star_4')));
    await tester.pump();
    expect(find.byIcon(Icons.star), findsNWidgets(4));
    await tester.ensureVisible(find.byKey(const Key('submit_driver_rating')));
    await tester.tap(find.byKey(const Key('submit_driver_rating')));
    await tester.pumpAndSettle();
    expect(repository.driverRatings[corrida.id], 4);
    await tester.tap(find.byKey(const Key('return_home_after_ride')));
    await tester.pumpAndSettle();

    expect(find.text('Início'), findsOneWidget);
    expect(find.byKey(const Key('ride_request_wait_screen')), findsNothing);
    expect(repository.driverRatings[corrida.id], 4);
  });

  testWidgets('merchant vê progresso e retorna ao painel após solicitar', (
    tester,
  ) async {
    const call = NearbyCall(
      id: 'merchant-delivery-return',
      origin: 'Estabelecimento',
      destination: 'Destino do pedido',
      client: LatLng(-23.54, -46.62),
      dropoff: LatLng(-23.53, -46.61),
      distanceKm: 2,
      driverFare: 15,
    );
    final repository = MemoryCorridaRepository();
    final corrida = await repository.requestRide(
      call: call,
      requesterType: 'merchant',
      serviceType: 'delivery',
    );
    repository.push(RideStatus.motoboyACaminho);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open_merchant_ride'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RideRequestWaitScreen(
                      call: call,
                      corrida: repository.current!,
                      repository: repository,
                      merchantMode: true,
                      merchantServiceType: 'delivery',
                    ),
                  ),
                ),
                child: const Text('Painel'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_merchant_ride')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('merchant_ride_progress')), findsOneWidget);
    expect(find.text('Buscando motoboy'), findsOneWidget);
    expect(find.text('Motoboy a caminho da coleta'), findsOneWidget);

    expect(
      find.byKey(const Key('merchant_auto_return_message')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Painel'), findsOneWidget);
    expect(find.byKey(const Key('ride_request_wait_screen')), findsNothing);
    expect(corrida.id, repository.current!.id);
    expect(repository.current!.status, RideStatus.motoboyACaminho);
  });
}
