import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/ride/domain/boarding_confirmation.dart';
import 'package:xofer/features/ride/domain/boarding_token.dart';
import 'package:xofer/features/ride/domain/payment_method.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';
import 'package:xofer/features/ride/presentation/active_trip_screen.dart';
import 'package:xofer/features/ride/presentation/boarding_scanner.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/data/memory_corrida_repository.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/ride_status.dart';
import 'package:xofer/prof/presentation/active_rescue_screen.dart';

const _origin = Place(
  id: 'origin',
  label: 'Praça da Sé',
  description: 'Praça da Sé, São Paulo',
  latitude: -23.5505,
  longitude: -46.6333,
);

const _destination = Place(
  id: 'destination',
  label: 'Avenida Paulista',
  description: 'Avenida Paulista, São Paulo',
  latitude: -23.5614,
  longitude: -46.6558,
);

const _call = NearbyCall(
  id: 'curto',
  origin: 'Origem',
  destination: 'Destino',
  client: LatLng(-23.54, -46.62),
  dropoff: LatLng(-23.53, -46.61),
  distanceKm: 2,
  driverFare: 15,
);

class _FixedScanner implements BoardingScanner {
  _FixedScanner(this.code, {this.reserveCode = false});

  final String code;
  final bool reserveCode;
  String? lastReserveCodeError;

  @override
  Future<BoardingScanResult?> scan(
    BuildContext context, {
    required Future<String?> Function(String code) confirmReserveCode,
  }) async {
    if (!reserveCode) return BoardingScanResult.qr(code);
    lastReserveCodeError = await confirmReserveCode(code);
    if (lastReserveCodeError != null) return null;
    return BoardingScanResult.reserveCode(code);
  }
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('pt'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: home,
  );
}

void main() {
  test('o token combina o id da corrida e só aceita o valor exato', () {
    final token = createBoardingToken('abcd-corrida');
    expect(token.startsWith('ABCD'), isTrue);
    expect(boardingTokensMatch(' $token ', token), isTrue);
    expect(boardingTokensMatch('outro', token), isFalse);
    expect(boardingTokensMatch('', token), isFalse);
  });

  testWidgets('o motorista gera o QR e a validação abre a navegação', (
    tester,
  ) async {
    final corridas = MemoryCorridaRepository();
    await corridas.requestRide(call: _call);
    await corridas.acceptCall(
      corridas.current!.id,
      driver: const LatLng(-23.55, -46.63),
    );
    await corridas.assignMotoboy(
      id: corridas.current!.id,
      motoboyId: 'authenticated-courier',
      motoboyNome: 'Carlos Souza',
      etaMinutos: 5,
      motoboy: const LatLng(-23.56, -46.64),
      rescueDistanceKm: 1.5,
      rescueFare: 5.40,
    );

    await tester.pumpWidget(
      _app(
        ActiveRescueScreen(
          role: PartnerRole.driver,
          driver: const LatLng(-23.55, -46.63),
          call: _call,
          corridaRepository: corridas,
          stepInterval: const Duration(hours: 1),
          approachSteps: 1,
          clientSteps: 1,
          destinationSteps: 1,
        ),
      ),
    );
    await tester.pump();

    corridas.push(RideStatus.aCaminhoDoCliente);
    await tester.pump();

    expect(find.text('Cheguei ao Ponto de Encontro'), findsOneWidget);
    await tester.tap(find.byKey(const Key('arrived_meeting_point_button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('boarding_qr_screen')), findsOneWidget);
    expect(find.text(boardingQrInstruction), findsOneWidget);
    expect(find.byKey(const Key('boarding_qr')), findsOneWidget);
    final screen = tester.widget<Scaffold>(
      find.byKey(const Key('boarding_qr_screen')),
    );
    expect(screen.backgroundColor, AppTheme.graphite);
    expect(corridas.current?.status, RideStatus.aguardandoValidacaoEmbarque);
    expect(corridas.current?.validationToken, isNotNull);
    expect(corridas.current?.reserveCode, matches(RegExp(r'^\d{4}$')));
    expect(
      find.text('Código Reserva: ${corridas.current?.reserveCode}'),
      findsOneWidget,
    );

    await corridas.confirmBoarding(corridas.current!.validationToken!);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('boarding_qr_screen')), findsNothing);
    expect(find.text('Navegação até o destino'), findsOneWidget);
    expect(corridas.current?.status, RideStatus.emAndamento);
  });

  testWidgets('QR diferente da corrida ativa é recusado', (tester) async {
    final corridas = await _waitingCorrida('TOKEN-CERTO', reserveCode: '9876');
    final quote = RideQuote.between(_origin, _destination);

    await tester.pumpWidget(
      _app(
        ActiveTripScreen(
          origin: _origin,
          destination: _destination,
          quote: quote,
          payment: PaymentMethod.pix,
          stepInterval: const Duration(hours: 1),
          pickupSteps: 2,
          rideSteps: 2,
          boarding: RepositoryBoardingConfirmation(corridas),
          scanner: _FixedScanner('TOKEN-ERRADO'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Escanear QR Code do Motorista'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan_driver_qr_button')));
    await tester.pump();
    await tester.pump();

    expect(find.text(invalidBoardingQrMessage), findsOneWidget);
    expect(find.text('Motorista a caminho do resgate'), findsOneWidget);
    expect(corridas.current?.status, RideStatus.aguardandoValidacaoEmbarque);

    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.byKey(const Key('invalid_qr_alert')), findsNothing);
  });

  testWidgets('o QR da corrida ativa libera a navegação', (tester) async {
    final corridas = await _waitingCorrida('TOKEN-CERTO', reserveCode: '1234');
    final quote = RideQuote.between(_origin, _destination);

    await tester.pumpWidget(
      _app(
        ActiveTripScreen(
          origin: _origin,
          destination: _destination,
          quote: quote,
          payment: PaymentMethod.pix,
          stepInterval: const Duration(hours: 1),
          pickupSteps: 2,
          rideSteps: 2,
          boarding: RepositoryBoardingConfirmation(corridas),
          scanner: _FixedScanner('TOKEN-CERTO'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('scan_driver_qr_button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('A caminho do destino'), findsOneWidget);
    expect(find.text('Escanear QR Code do Motorista'), findsNothing);
    expect(find.byIcon(Icons.directions_car), findsOneWidget);
    expect(corridas.current?.status, RideStatus.emAndamento);
  });

  test('código reserva incorreto não libera a corrida', () async {
    final corridas = await _waitingCorrida('TOKEN-CERTO', reserveCode: '9876');

    await expectLater(
      corridas.confirmBoardingWithReserveCode('0000'),
      throwsA(
        isA<CorridaFailure>().having(
          (error) => error.message,
          'message',
          invalidBoardingReserveCodeMessage,
        ),
      ),
    );
    expect(corridas.current?.status, RideStatus.aguardandoValidacaoEmbarque);
  });

  testWidgets('código reserva correto libera navegação do cliente', (
    tester,
  ) async {
    final corridas = await _waitingCorrida('TOKEN-CERTO');
    final reserveCode = corridas.current!.reserveCode!;
    final quote = RideQuote.between(_origin, _destination);

    await tester.pumpWidget(
      _app(
        ActiveTripScreen(
          origin: _origin,
          destination: _destination,
          quote: quote,
          payment: PaymentMethod.pix,
          stepInterval: const Duration(hours: 1),
          pickupSteps: 2,
          rideSteps: 2,
          boarding: RepositoryBoardingConfirmation(corridas),
          scanner: _FixedScanner(reserveCode, reserveCode: true),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('scan_driver_qr_button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('A caminho do destino'), findsOneWidget);
    expect(corridas.current?.status, RideStatus.emAndamento);
  });

  testWidgets('código reserva errado apresenta o erro esperado', (
    tester,
  ) async {
    final corridas = await _waitingCorrida('TOKEN-CERTO');
    final quote = RideQuote.between(_origin, _destination);
    final scanner = _FixedScanner('0000', reserveCode: true);

    await tester.pumpWidget(
      _app(
        ActiveTripScreen(
          origin: _origin,
          destination: _destination,
          quote: quote,
          payment: PaymentMethod.pix,
          stepInterval: const Duration(hours: 1),
          pickupSteps: 2,
          rideSteps: 2,
          boarding: RepositoryBoardingConfirmation(corridas),
          scanner: scanner,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('scan_driver_qr_button')));
    await tester.pump();
    await tester.pump();

    expect(scanner.lastReserveCodeError, invalidBoardingReserveCodeMessage);
    expect(corridas.current?.status, RideStatus.aguardandoValidacaoEmbarque);
    expect(find.text('Motorista a caminho do resgate'), findsOneWidget);
  });
}

Future<MemoryCorridaRepository> _waitingCorrida(
  String token, {
  String reserveCode = '1234',
}) async {
  final corridas = MemoryCorridaRepository();
  final created = await corridas.requestRide(call: _call);
  await corridas.beginBoardingValidation(
    created.id,
    token: token,
    reserveCode: reserveCode,
  );
  return corridas;
}
