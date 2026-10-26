import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/data/make_penalty_webhook.dart';
import 'package:xofer/prof/data/memory_corrida_repository.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/incident_report.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/provider_account.dart';
import 'package:xofer/prof/domain/ride_status.dart';
import 'package:xofer/prof/presentation/active_rescue_screen.dart';

const _call = NearbyCall(
  id: 'curto',
  origin: 'Origem',
  destination: 'Destino',
  client: LatLng(-23.54, -46.62),
  dropoff: LatLng(-23.53, -46.61),
  distanceKm: 2,
  driverFare: 15,
);

class _Camera implements DocumentCapture {
  @override
  Future<CapturedDocument?> pick(DocumentSource source) async {
    return const CapturedDocument(name: 'via.jpg', bytes: [1, 2, 3]);
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

Future<void> _openRescue(WidgetTester tester, ActiveRescueScreen screen) async {
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => screen));
            },
            child: const Text('radar'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('radar'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('dentro de 3 minutos o imprevisto devolve a corrida sem multa', (
    tester,
  ) async {
    final corridas = MemoryCorridaRepository();
    final acceptedAt = DateTime.utc(2026, 10, 23, 12);

    await _openRescue(
      tester,
      ActiveRescueScreen(
        role: PartnerRole.courier,
        driver: const LatLng(-23.55, -46.63),
        call: _call,
        corridaRepository: corridas,
        motoboyId: 'motoboy-1',
        acceptedAt: acceptedAt,
        now: () => acceptedAt.add(const Duration(minutes: 2)),
        documentCapture: _Camera(),
        stepInterval: const Duration(hours: 1),
      ),
    );

    expect(find.text('Reportar Imprevisto'), findsOneWidget);
    expect(find.text('Cancelar'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('report_incident_button')));
    await tester.tap(find.byKey(const Key('report_incident_button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('radar'), findsOneWidget);
    expect(corridas.incidents, isEmpty);
    expect(corridas.released, isNotEmpty);
    expect(corridas.current?.status, RideStatus.buscandoPrestadores);
    expect(corridas.current?.motoboyId, isNull);
  });

  testWidgets('depois de 3 minutos a foto e o motivo são obrigatórios', (
    tester,
  ) async {
    final corridas = MemoryCorridaRepository();
    final acceptedAt = DateTime.utc(2026, 10, 23, 12);

    await _openRescue(
      tester,
      ActiveRescueScreen(
        role: PartnerRole.courier,
        driver: const LatLng(-23.55, -46.63),
        call: _call,
        corridaRepository: corridas,
        motoboyId: 'motoboy-1',
        acceptedAt: acceptedAt,
        now: () => acceptedAt.add(const Duration(minutes: 3, seconds: 1)),
        documentCapture: _Camera(),
        stepInterval: const Duration(hours: 1),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('report_incident_button')));
    await tester.tap(find.byKey(const Key('report_incident_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('incident_modal')), findsOneWidget);
    ElevatedButton confirm() => tester.widget<ElevatedButton>(
      find.byKey(const Key('confirm_incident_button')),
    );
    expect(confirm().onPressed, isNull);

    await tester.tap(
      find.byKey(const Key('incident_reason_problema_mecanico')),
    );
    await tester.pump();
    expect(confirm().onPressed, isNull);

    await tester.tap(find.byKey(const Key('incident_camera_button')));
    await tester.pump();
    expect(find.byKey(const Key('incident_photo_ready')), findsOneWidget);
    expect(confirm().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('confirm_incident_button')));
    await tester.pump();
    await tester.pump();

    expect(corridas.incidents, hasLength(1));
    expect(corridas.incidents.single.penalized, isTrue);
    expect(corridas.incidents.single.reason, IncidentReason.mechanical);
    expect(corridas.incidents.single.photoBytes, [1, 2, 3]);
    expect(corridas.current?.motoboyId, isNull);
    expect(find.text('radar'), findsOneWidget);
  });

  test('o webhook avisa o Make.com para debitar e reduzir o score', () async {
    Map<String, dynamic>? body;
    final webhook = MakePenaltyWebhook(
      url: 'https://hook.make.com/penalidade',
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('ok', 200);
      }),
    );

    final sent = await webhook.notifyPenalty({
      'acao': 'debito_carteira_e_reduzir_score',
      'motivo': 'problema_mecanico',
    });

    expect(sent, isTrue);
    expect(body?['acao'], 'debito_carteira_e_reduzir_score');
    expect(body?['motivo'], 'problema_mecanico');
  });
}
