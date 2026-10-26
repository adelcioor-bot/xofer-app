import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/ride/presentation/ride_summary_screen.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/data/memory_corrida_repository.dart';
import 'package:xofer/prof/domain/ride_status.dart';

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
  testWidgets('solicita uma corrida e abre a tela real de espera', (
    tester,
  ) async {
    final corridas = MemoryCorridaRepository();
    await tester.pumpWidget(
      _wrap(
        RideSummaryScreen(
          origin: _origin,
          destination: _destination,
          corridaRepository: corridas,
        ),
      ),
    );

    expect(find.byKey(const Key('summary_origin')), findsOneWidget);
    expect(find.text('Praça da Sé, São Paulo'), findsOneWidget);
    expect(find.text('Avenida Paulista, São Paulo'), findsOneWidget);
    expect(find.byKey(const Key('ride_price')), findsOneWidget);
    expect(find.text('Visa •••• 4242'), findsOneWidget);
    expect(find.text('Confirmar Motorista + Resgate'), findsOneWidget);

    final price = tester.widget<Text>(find.byKey(const Key('ride_price')));
    expect(price.style?.fontWeight, FontWeight.w800);
    expect(price.data, startsWith('R\$'));

    await tester.tap(find.byKey(const Key('payment_pix')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('pix_copy_button')));
    await tester.pump();

    expect(find.byKey(const Key('pix_code')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pix_copy_button')));
    await tester.pump();

    expect(find.text('Código copiado'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('confirm_ride_button')));
    await tester.tap(find.byKey(const Key('confirm_ride_button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('ride_request_wait_screen')), findsOneWidget);
    expect(
      find.text('Buscando prestadores para sua corrida...'),
      findsOneWidget,
    );
    expect(corridas.current?.status, RideStatus.buscandoPrestadores);
    expect(corridas.current?.acceptedBy, isNull);
    expect(corridas.current?.motoboyId, isNull);

    await corridas.acceptCall(
      corridas.current!.id,
      driver: const LatLng(-23.55, -46.63),
    );
    await tester.pump();
    expect(
      find.text(
        'Motorista encontrado. Aguardando um motoboy para o resgate...',
      ),
      findsOneWidget,
    );
  });

  testWidgets('resumo se adapta a telas estreitas sem overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        const RideSummaryScreen(origin: _origin, destination: _destination),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
