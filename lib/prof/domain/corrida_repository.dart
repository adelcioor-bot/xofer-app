import 'package:latlong2/latlong.dart';
import 'package:xofer/prof/domain/corrida.dart';
import 'package:xofer/prof/domain/incident_report.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/rescue_offer.dart';
import 'package:xofer/prof/domain/ride_status.dart';

abstract class CorridaRepository {
  Future<Corrida> requestRide({required NearbyCall call});

  Future<Corrida> acceptCall(String id, {required LatLng driver});

  Future<Corrida> open({
    required NearbyCall call,
    required PartnerRole role,
    required LatLng partner,
  });

  Future<List<RescueOffer>> loadOffers({required PartnerRole role});

  Future<Corrida> assignMotoboy({
    required String id,
    required String motoboyId,
    required String motoboyNome,
    required int etaMinutos,
    required LatLng motoboy,
    required double rescueDistanceKm,
    required double rescueFare,
  });

  Future<Corrida> releaseToQueue(String id);

  Future<void> reportIncident(IncidentReport report);

  Future<Corrida> advance(String id, RideStatus status);

  Future<Corrida> beginBoardingValidation(
    String id, {
    String? token,
    String? reserveCode,
  });

  Future<Corrida?> activeAwaitingValidation();

  Future<Corrida> confirmBoarding(String scannedToken);

  Future<Corrida> confirmBoardingWithReserveCode(String reserveCode);

  Stream<Corrida> watch(String id);

  Stream<List<RescueOffer>> offers({required PartnerRole role});
}
