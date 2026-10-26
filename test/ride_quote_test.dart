import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';

Place _place(double latitude, double longitude) {
  return Place(
    id: '$latitude,$longitude',
    label: 'Ponto',
    description: 'Ponto',
    latitude: latitude,
    longitude: longitude,
  );
}

void main() {
  test('aplica a tarifa mínima quando os pontos coincidem', () {
    final quote = RideQuote.between(_place(0, 0), _place(0, 0));

    expect(quote.distanceKm, 0);
    expect(quote.price, RideQuote.minimumFare);
    expect(formatBrl(quote.price), r'R$ 12,00');
  });

  test('o preço sobe com a distância e formata milhar', () {
    final quote = RideQuote.between(
      _place(-23.5505, -46.6333),
      _place(-23.2000, -45.9000),
    );

    expect(quote.distanceKm, greaterThan(20));
    expect(quote.price, greaterThan(RideQuote.minimumFare));
    expect(formatBrl(1234.5), r'R$ 1.234,50');
    expect(pixCopyPaste(quote), contains('br.gov.bcb.pix'));
  });
}
