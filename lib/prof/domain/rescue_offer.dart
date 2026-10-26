import 'package:latlong2/latlong.dart';
import 'package:xofer/prof/domain/corrida.dart';
import 'package:xofer/prof/domain/nearby_call.dart';

class RescueOffer {
  const RescueOffer({
    required this.corridaId,
    required this.call,
    required this.driver,
    required this.driverLabel,
    required this.rescueDistanceKm,
    required this.rescueFare,
  });

  final String? corridaId;
  final NearbyCall call;
  final LatLng driver;
  final String driverLabel;
  final double rescueDistanceKm;
  final double rescueFare;

  String get queueKey => corridaId ?? call.id;

  RescueOffer forCourier(LatLng courier) {
    const distance = Distance();
    final kilometers = distance.as(LengthUnit.Kilometer, courier, driver);
    return RescueOffer(
      corridaId: corridaId,
      call: call,
      driver: driver,
      driverLabel: driverLabel,
      rescueDistanceKm: kilometers,
      rescueFare: rescuePayoutForDistance(kilometers),
    );
  }
}

double rescuePayoutForDistance(double distanceKm) {
  const baseFare = 6.90;
  const pricePerKm = 2.70;
  const minimumFare = 12.0;
  final rideFare = baseFare + distanceKm * pricePerKm;
  final fare = (rideFare < minimumFare ? minimumFare : rideFare) * 0.45;
  return (fare * 100).round() / 100;
}

int etaMinutesBetween(LatLng from, LatLng to) {
  const distance = Distance();
  final kilometers = distance.as(LengthUnit.Kilometer, from, to);
  final minutes = (kilometers / 30 * 60).round();
  if (minutes < 2) return 2;
  if (minutes > 25) return 25;
  return minutes;
}

String assignedMotoboyMessage(String name, int minutes) {
  final unit = minutes == 1 ? 'minuto' : 'minutos';
  return 'Motoboy $name aceitou seu resgate e chega em $minutes $unit';
}

RescueOffer offerFromCorrida(Corrida corrida, NearbyCall call, LatLng driver) {
  return RescueOffer(
    corridaId: corrida.id,
    call: call,
    driver: driver,
    driverLabel: 'Encontro com o motorista',
    rescueDistanceKm: corrida.rescueDistanceKm ?? 0,
    rescueFare: corrida.rescueFare ?? 0,
  );
}
