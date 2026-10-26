import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:xofer/prof/domain/corrida.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/incident_report.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/rescue_offer.dart';
import 'package:xofer/features/ride/domain/boarding_token.dart';
import 'package:xofer/prof/domain/ride_status.dart';

class MemoryCorridaRepository implements CorridaRepository {
  MemoryCorridaRepository({this.openError});

  final CorridaFailure? openError;
  final List<RideStatus> advanced = [];
  final List<String> assignedMotoboys = [];
  final List<String> released = [];
  final List<String> acceptedDrivers = [];
  final List<IncidentReport> incidents = [];
  Corrida? current;
  NearbyCall? call;
  LatLng? driverPoint;

  @override
  Future<Corrida> requestRide({required NearbyCall call}) async {
    final error = openError;
    if (error != null) throw error;
    this.call = call;
    driverPoint = call.client;
    final created = Corrida(
      id: 'corrida-${call.id}',
      callId: call.id,
      status: RideStatus.buscandoPrestadores,
      origin: call.origin,
      destination: call.destination,
    );
    current = created;
    _emitOffers();
    return created;
  }

  @override
  Future<Corrida> acceptCall(String id, {required LatLng driver}) async {
    final existing = current;
    if (existing == null ||
        existing.id != id ||
        existing.status != RideStatus.buscandoPrestadores ||
        existing.acceptedBy != null) {
      throw const CorridaFailure(
        'Esta chamada já foi aceita por outro parceiro.',
      );
    }
    acceptedDrivers.add(id);
    driverPoint = driver;
    final next = existing.copyWith(
      status: RideStatus.procurandoMotoboy,
      acceptedBy: 'authenticated-driver',
    );
    current = next;
    if (!_updates.isClosed) _updates.add(next);
    _emitOffers();
    return next;
  }

  final StreamController<Corrida> _updates =
      StreamController<Corrida>.broadcast();
  final StreamController<List<RescueOffer>> _offerUpdates =
      StreamController<List<RescueOffer>>.broadcast();

  void push(RideStatus status) {
    final existing = current;
    if (existing == null) return;
    final next = existing.copyWith(status: status);
    current = next;
    if (!_updates.isClosed) _updates.add(next);
  }

  void pushMotoboyPosition(LatLng position) {
    final existing = current;
    if (existing == null || existing.motoboyId == null) return;
    final next = existing.copyWith(
      motoboyLatitude: position.latitude,
      motoboyLongitude: position.longitude,
    );
    current = next;
    if (!_updates.isClosed) _updates.add(next);
  }

  @override
  Future<Corrida> open({
    required NearbyCall call,
    required PartnerRole role,
    required LatLng partner,
  }) async {
    final error = openError;
    if (error != null) throw error;
    if (role.wire.isEmpty || partner.latitude.isNaN) {
      throw const CorridaFailure('Não foi possível abrir a corrida.');
    }
    final existing = current;
    if (existing != null &&
        existing.callId == call.id &&
        existing.status != RideStatus.concluida) {
      return existing;
    }
    final created = Corrida(
      id: 'corrida-${call.id}',
      callId: call.id,
      status: RideStatus.motoboyACaminho,
      origin: call.origin,
      destination: call.destination,
    );
    current = created;
    return created;
  }

  @override
  Future<List<RescueOffer>> loadOffers({required PartnerRole role}) async =>
      _openOffers(role);

  @override
  Future<Corrida> assignMotoboy({
    required String id,
    required String motoboyId,
    required String motoboyNome,
    required int etaMinutos,
    required LatLng motoboy,
    required double rescueDistanceKm,
    required double rescueFare,
  }) async {
    final existing = current;
    if (existing == null || existing.id != id) {
      throw const CorridaFailure('Corrida não encontrada.');
    }
    if (existing.status != RideStatus.procurandoMotoboy ||
        existing.acceptedBy == null) {
      throw const CorridaFailure('A corrida ainda não aguarda um motoboy.');
    }
    if (existing.motoboyId != null && existing.motoboyId != motoboyId) {
      throw const CorridaFailure('Outro motoboy já aceitou este resgate.');
    }
    if (motoboy.latitude.isNaN) {
      throw const CorridaFailure('Não foi possível vincular o motoboy.');
    }
    assignedMotoboys.add(motoboyId);
    final next = existing.copyWith(
      status: RideStatus.motoboyACaminho,
      motoboyId: motoboyId,
      acceptedBy: 'authenticated-courier',
      motoboyNome: motoboyNome,
      etaMinutos: etaMinutos,
      motoboyLatitude: motoboy.latitude,
      motoboyLongitude: motoboy.longitude,
      rescueDistanceKm: rescueDistanceKm,
      rescueFare: rescueFare,
    );
    current = next;
    if (!_updates.isClosed) _updates.add(next);
    _emitOffers();
    return next;
  }

  @override
  Future<Corrida> releaseToQueue(String id) async {
    final existing = current;
    if (existing == null || existing.id != id) {
      throw const CorridaFailure('Corrida não encontrada.');
    }
    final next = Corrida(
      id: existing.id,
      callId: existing.callId,
      status: RideStatus.buscandoPrestadores,
      origin: existing.origin,
      destination: existing.destination,
      driverLabel: existing.driverLabel,
      rescueFare: existing.rescueFare,
    );
    current = next;
    released.add(id);
    if (!_updates.isClosed) _updates.add(next);
    _emitOffers();
    return next;
  }

  @override
  Future<void> reportIncident(IncidentReport report) async {
    incidents.add(report);
    await releaseToQueue(report.corridaId);
  }

  @override
  Future<Corrida> beginBoardingValidation(
    String id, {
    String? token,
    String? reserveCode,
  }) async {
    final existing = current;
    if (existing == null || existing.id != id) {
      throw const CorridaFailure('Corrida não encontrada.');
    }
    final code = token ?? createBoardingToken(id);
    final next = existing.copyWith(
      status: RideStatus.aguardandoValidacaoEmbarque,
      validationToken: code,
      reserveCode: reserveCode ?? createReserveCode(),
    );
    current = next;
    if (!_updates.isClosed) _updates.add(next);
    return next;
  }

  @override
  Future<Corrida?> activeAwaitingValidation() async {
    final existing = current;
    if (existing == null ||
        existing.status != RideStatus.aguardandoValidacaoEmbarque ||
        existing.validationToken == null) {
      return null;
    }
    return existing;
  }

  @override
  Future<Corrida> confirmBoarding(String scannedToken) async {
    final active = await activeAwaitingValidation();
    if (active == null ||
        !boardingTokensMatch(scannedToken, active.validationToken)) {
      throw const CorridaFailure(invalidBoardingQrMessage);
    }
    return advance(active.id, RideStatus.emAndamento);
  }

  @override
  Future<Corrida> confirmBoardingWithReserveCode(String reserveCode) async {
    final active = await activeAwaitingValidation();
    if (active == null || !reserveCodesMatch(reserveCode, active.reserveCode)) {
      throw const CorridaFailure(invalidBoardingReserveCodeMessage);
    }
    return advance(active.id, RideStatus.emAndamento);
  }

  @override
  Future<Corrida> advance(String id, RideStatus status) async {
    final existing = current;
    if (existing == null || existing.id != id) {
      throw const CorridaFailure('Corrida não encontrada.');
    }
    advanced.add(status);
    final next = existing.copyWith(status: status);
    current = next;
    if (!_updates.isClosed) _updates.add(next);
    return next;
  }

  @override
  Stream<Corrida> watch(String id) => _updates.stream;

  @override
  Stream<List<RescueOffer>> offers({required PartnerRole role}) =>
      _offerUpdates.stream.map((_) => _openOffers(role));

  List<RescueOffer> _openOffers(PartnerRole role) {
    final existing = current;
    final driver = driverPoint;
    final expectedStatus = role == PartnerRole.courier
        ? RideStatus.procurandoMotoboy
        : RideStatus.buscandoPrestadores;
    if (existing == null ||
        driver == null ||
        existing.motoboyId != null ||
        existing.status != expectedStatus ||
        (role == PartnerRole.driver && existing.acceptedBy != null) ||
        (role == PartnerRole.courier && existing.acceptedBy == null)) {
      return const [];
    }
    final source = call;
    if (source == null) return const [];
    return [offerFromCorrida(existing, source, driver)];
  }

  void _emitOffers() {
    if (!_offerUpdates.isClosed) _offerUpdates.add(const []);
  }
}
