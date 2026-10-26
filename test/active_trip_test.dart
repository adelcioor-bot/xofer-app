import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/ride/domain/payment_method.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';
import 'package:xofer/features/ride/presentation/active_trip_screen.dart';
import 'package:xofer/l10n/app_localizations.dart';

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

Future<void> _untilText(
  WidgetTester tester,
  Duration interval,
  String text,
) async {
  for (var i = 0; i < 8; i++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.pump(interval);
  }
  expect(find.text(text), findsOneWidget);
}

LatLng _vehicle(WidgetTester tester) {
  final layer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
  return layer.markers
      .firstWhere((marker) => marker.key == const Key('trip_vehicle_marker'))
      .point;
}

void main() {
  testWidgets('o carro vai ao encontro e depois ao destino', (tester) async {
    const interval = Duration(milliseconds: 40);
    final quote = RideQuote.between(_origin, _destination);

    await tester.pumpWidget(
      _wrap(
        ActiveTripScreen(
          origin: _origin,
          destination: _destination,
          quote: quote,
          payment: PaymentMethod.pix,
          stepInterval: interval,
          pickupSteps: 2,
          rideSteps: 2,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Motorista a caminho do resgate'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.directions_car), findsNothing);
    final start = _vehicle(tester);

    await tester.pump(const Duration(milliseconds: 20));
    final midway = _vehicle(tester);
    expect(midway.latitude, lessThan(start.latitude));
    expect(midway.latitude, greaterThan(_origin.latitude));

    await _untilText(tester, interval, 'A caminho do destino');
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byIcon(Icons.directions_car), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNothing);
    expect(_vehicle(tester).latitude, lessThan(_origin.latitude));

    await _untilText(tester, interval, 'Você chegou ao destino');
    final arrived = _vehicle(tester);
    expect(arrived.latitude, closeTo(_destination.latitude, 0.0002));
    expect(arrived.longitude, closeTo(_destination.longitude, 0.0002));

    final card = tester.widget<Material>(
      find.byKey(const Key('active_trip_screen')),
    );
    expect(card.color, AppTheme.graphiteSurface);
  });
}
