import 'package:latlong2/latlong.dart';
import 'package:xofer/features/places/domain/place.dart';

class RideQuote {
  const RideQuote({required this.distanceKm, required this.price});

  final double distanceKm;
  final double price;

  static const baseFare = 6.90;
  static const pricePerKm = 2.70;
  static const minimumFare = 12.0;

  factory RideQuote.between(Place origin, Place destination) {
    const distance = Distance();
    final kilometers = distance.as(
      LengthUnit.Kilometer,
      LatLng(origin.latitude, origin.longitude),
      LatLng(destination.latitude, destination.longitude),
    );
    final raw = baseFare + kilometers * pricePerKm;
    final charged = raw < minimumFare ? minimumFare : raw;
    return RideQuote(
      distanceKm: kilometers,
      price: (charged * 100).round() / 100,
    );
  }
}

String formatBrl(double value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    final remaining = whole.length - i;
    if (i > 0 && remaining % 3 == 0) buffer.write('.');
    buffer.write(whole[i]);
  }
  final sign = negative ? '-' : '';
  return '${sign}R\$ $buffer,${parts[1]}';
}

String formatKilometers(double kilometers) {
  return '${kilometers.toStringAsFixed(1).replaceAll('.', ',')} km';
}

String pixCopyPaste(RideQuote quote) {
  final cents = (quote.price * 100).round().toString().padLeft(4, '0');
  return '00020126580014br.gov.bcb.pix0136xofer@teste.xofer540$cents'
      '5802BR6304XOFR';
}
