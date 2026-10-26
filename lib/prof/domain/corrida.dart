import 'package:xofer/prof/domain/ride_status.dart';

class Corrida {
  const Corrida({
    required this.id,
    required this.callId,
    required this.status,
    required this.origin,
    required this.destination,
    this.motoboyId,
    this.acceptedBy,
    this.motoboyNome,
    this.etaMinutos,
    this.driverLabel,
    this.rescueFare,
    this.rescueDistanceKm,
    this.motoboyLatitude,
    this.motoboyLongitude,
    this.validationToken,
    this.reserveCode,
  });

  final String id;
  final String callId;
  final RideStatus status;
  final String origin;
  final String destination;
  final String? motoboyId;
  final String? acceptedBy;
  final String? motoboyNome;
  final int? etaMinutos;
  final String? driverLabel;
  final double? rescueFare;
  final double? rescueDistanceKm;
  final double? motoboyLatitude;
  final double? motoboyLongitude;
  final String? validationToken;
  final String? reserveCode;

  Corrida copyWith({
    RideStatus? status,
    String? motoboyId,
    String? acceptedBy,
    String? motoboyNome,
    int? etaMinutos,
    String? driverLabel,
    double? rescueFare,
    double? rescueDistanceKm,
    double? motoboyLatitude,
    double? motoboyLongitude,
    String? validationToken,
    String? reserveCode,
  }) {
    return Corrida(
      id: id,
      callId: callId,
      status: status ?? this.status,
      origin: origin,
      destination: destination,
      motoboyId: motoboyId ?? this.motoboyId,
      acceptedBy: acceptedBy ?? this.acceptedBy,
      motoboyNome: motoboyNome ?? this.motoboyNome,
      etaMinutos: etaMinutos ?? this.etaMinutos,
      driverLabel: driverLabel ?? this.driverLabel,
      rescueFare: rescueFare ?? this.rescueFare,
      rescueDistanceKm: rescueDistanceKm ?? this.rescueDistanceKm,
      motoboyLatitude: motoboyLatitude ?? this.motoboyLatitude,
      motoboyLongitude: motoboyLongitude ?? this.motoboyLongitude,
      validationToken: validationToken ?? this.validationToken,
      reserveCode: reserveCode ?? this.reserveCode,
    );
  }

  factory Corrida.fromMap(Map<String, dynamic> data) {
    final status =
        RideStatus.tryParse('${data['status_corrida']}') ??
        RideStatus.motoboyACaminho;
    return Corrida(
      id: '${data['id']}',
      callId: '${data['call_id']}',
      status: status,
      origin: '${data['origin'] ?? ''}',
      destination: '${data['destination'] ?? ''}',
      motoboyId: _text(data['motoboy_id']),
      acceptedBy: _text(data['accepted_by']),
      motoboyNome: _text(data['motoboy_nome']),
      etaMinutos: _asInt(data['eta_minutos']),
      driverLabel: _text(data['driver_label']),
      rescueFare: _asDouble(data['ganho_resgate']),
      rescueDistanceKm: _asDouble(data['distancia_resgate_km']),
      motoboyLatitude: _asDouble(data['motoboy_lat']),
      motoboyLongitude: _asDouble(data['motoboy_lng']),
      validationToken: _text(data['token_validacao']),
      reserveCode: _text(data['codigo_reserva']),
    );
  }
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
