import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/features/ride/domain/boarding_token.dart';
import 'package:xofer/prof/data/make_penalty_webhook.dart';
import 'package:xofer/prof/domain/corrida.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/incident_report.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/penalty_webhook.dart';
import 'package:xofer/prof/domain/rescue_offer.dart';
import 'package:xofer/prof/domain/ride_status.dart';

class SupabaseCorridaRepository implements CorridaRepository {
  SupabaseCorridaRepository({this.client, PenaltyWebhook? penaltyWebhook})
    : penaltyWebhook = penaltyWebhook ?? MakePenaltyWebhook();

  final SupabaseClient? client;
  final PenaltyWebhook penaltyWebhook;

  SupabaseClient get _supabase => client ?? Supabase.instance.client;

  String get _userId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) {
      throw const CorridaFailure('Sessão expirada. Entre novamente.');
    }
    return id;
  }

  @override
  Future<Corrida> requestRide({required NearbyCall call}) async {
    try {
      final inserted = await _insertRow({
        'call_id': call.id,
        'status_corrida': RideStatus.buscandoPrestadores.wire,
        'origin': call.origin,
        'destination': call.destination,
        'origin_lat': call.client.latitude,
        'origin_lng': call.client.longitude,
        'dest_lat': call.dropoff.latitude,
        'dest_lng': call.dropoff.longitude,
        'valor_total': call.driverFare,
        'driver_fare': call.driverFare,
        'requested_by': _userId,
        'accepted_by': null,
        'accepted_role': null,
        'motoboy_id': null,
        'encerrada': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return Corrida.fromMap(inserted);
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      debugPrint('SupabaseCorridaRepository.requestRide failed: $error');
      throw CorridaFailure.fromRemote(
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      );
    } catch (error, stackTrace) {
      debugPrint('SupabaseCorridaRepository.requestRide failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw CorridaFailure(
        'Não foi possível criar a corrida (${error.runtimeType}). '
        'Verifique a conexão e confira o console para detalhes técnicos.',
      );
    }
  }

  @override
  Future<Corrida> acceptCall(String id, {required LatLng driver}) async {
    try {
      final updated = await _supabase
          .from('corridas')
          .update({
            'accepted_by': _userId,
            'accepted_role': PartnerRole.driver.wire,
            'status_corrida': RideStatus.procurandoMotoboy.wire,
            'partner_lat': driver.latitude,
            'partner_lng': driver.longitude,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .eq('status_corrida', RideStatus.buscandoPrestadores.wire)
          .isFilter('accepted_by', null)
          .isFilter('motoboy_id', null)
          .select()
          .maybeSingle();
      if (updated == null) {
        throw const CorridaFailure(
          'Esta chamada já foi aceita por outro parceiro.',
        );
      }
      return Corrida.fromMap(Map<String, dynamic>.from(updated));
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      debugPrint('SupabaseCorridaRepository._insertRow failed: $error');
      throw CorridaFailure.fromRemote(
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      );
    } catch (_) {
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }

  @override
  Future<Corrida> open({
    required NearbyCall call,
    required PartnerRole role,
    required LatLng partner,
  }) async {
    try {
      final existing = await _findOpen(call.id);
      if (existing != null) return existing;
      final inserted = await _insertRow({
        'call_id': call.id,
        'status_corrida': RideStatus.motoboyACaminho.wire,
        'origin': call.origin,
        'destination': call.destination,
        'origin_lat': call.client.latitude,
        'origin_lng': call.client.longitude,
        'dest_lat': call.dropoff.latitude,
        'dest_lng': call.dropoff.longitude,
        'partner_lat': partner.latitude,
        'partner_lng': partner.longitude,
        'driver_fare': call.driverFare,
        'accepted_by': _userId,
        'accepted_role': role.wire,
        'encerrada': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return Corrida.fromMap(inserted);
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      final failure = CorridaFailure(error.message);
      if (failure.isDuplicateKey) {
        final existing = await _findOpen(call.id);
        if (existing != null) return existing;
      }
      throw CorridaFailure.fromRemote(code: error.code, message: error.message);
    } catch (_) {
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }

  @override
  Future<List<RescueOffer>> loadOffers({required PartnerRole role}) =>
      _loadOffers(role);

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
    try {
      final userId = _userId;
      if (motoboyId != userId) {
        throw const CorridaFailure(
          'A sessão autenticada não corresponde ao motoboy selecionado.',
        );
      }
      final updated = await _updateRow(id, {
        'motoboy_id': userId,
        'accepted_by': userId,
        'accepted_role': PartnerRole.courier.wire,
        'motoboy_nome': motoboyNome,
        'eta_minutos': etaMinutos,
        'motoboy_lat': motoboy.latitude,
        'motoboy_lng': motoboy.longitude,
        'distancia_resgate_km': rescueDistanceKm,
        'ganho_resgate': rescueFare,
        'status_corrida': RideStatus.motoboyACaminho.wire,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onlyAwaitingMotoboy: true);
      return Corrida.fromMap(updated);
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(code: error.code, message: error.message);
    } catch (_) {
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }

  @override
  Future<Corrida> releaseToQueue(String id) async {
    try {
      final updated = await _updateRow(id, {
        'motoboy_id': null,
        'accepted_by': null,
        'accepted_role': null,
        'motoboy_nome': null,
        'eta_minutos': null,
        'motoboy_lat': null,
        'motoboy_lng': null,
        'status_corrida': RideStatus.buscandoPrestadores.wire,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return Corrida.fromMap(updated);
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(code: error.code, message: error.message);
    } catch (_) {
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }

  @override
  Future<void> reportIncident(IncidentReport report) async {
    try {
      final userId = _userId;
      final photoPath = await _uploadIncident(
        userId,
        report.corridaId,
        report.photoBytes,
      );
      final reportedAt = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('imprevistos').upsert({
        'corrida_id': report.corridaId,
        'motoboy_id': userId,
        'motivo': report.reason.wire,
        'penalizado': true,
        'foto_path': photoPath,
        'aceite_em': report.acceptedAt.toUtc().toIso8601String(),
        'reportado_em': reportedAt,
        'webhook_enviado': false,
      }, onConflict: 'corrida_id,motoboy_id');
      final sent = await penaltyWebhook.notifyPenalty({
        'corrida_id': report.corridaId,
        'motoboy_id': userId,
        'motivo': report.reason.wire,
        'penalizado': true,
        'foto_path': photoPath,
        'aceite_em': report.acceptedAt.toUtc().toIso8601String(),
        'reportado_em': reportedAt,
        'acao': 'debito_carteira_e_reduzir_score',
      });
      await _supabase
          .from('imprevistos')
          .update({'webhook_enviado': sent})
          .eq('corrida_id', report.corridaId)
          .eq('motoboy_id', userId);
      await releaseToQueue(report.corridaId);
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(code: error.code, message: error.message);
    } on StorageException catch (error) {
      throw CorridaFailure(error.message);
    } catch (_) {
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }

  Future<String> _uploadIncident(
    String userId,
    String corridaId,
    List<int> bytes,
  ) async {
    final path = '$userId/incidents/$corridaId.jpg';
    await _supabase.storage
        .from('provider-documents')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    return path;
  }

  @override
  Future<Corrida> beginBoardingValidation(
    String id, {
    String? token,
    String? reserveCode,
  }) async {
    final code = token ?? createBoardingToken(id);
    final fallbackCode = reserveCode ?? createReserveCode();
    try {
      final updated = await _updateRow(id, {
        'status_corrida': RideStatus.aguardandoValidacaoEmbarque.wire,
        'token_validacao': code,
        'codigo_reserva': fallbackCode,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return Corrida.fromMap(updated);
    } on CorridaFailure {
      rethrow;
    } catch (_) {
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }

  @override
  Future<Corrida?> activeAwaitingValidation() async {
    try {
      final rows = await _supabase
          .from('corridas')
          .select()
          .order('updated_at', ascending: false)
          .limit(30);
      for (final row in rows) {
        final data = Map<String, dynamic>.from(row);
        if (_closedRow(data)) continue;
        final corrida = Corrida.fromMap(data);
        if (corrida.status == RideStatus.aguardandoValidacaoEmbarque &&
            corrida.validationToken != null) {
          return corrida;
        }
      }
      return null;
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(code: error.code, message: error.message);
    } catch (_) {
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
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
    final code = reserveCode.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(code)) {
      throw const CorridaFailure(invalidBoardingReserveCodeMessage);
    }

    try {
      final row = await _supabase
          .from('corridas')
          .select()
          .eq('codigo_reserva', code)
          .eq('status_corrida', RideStatus.aguardandoValidacaoEmbarque.wire)
          .eq('encerrada', false)
          .maybeSingle();
      if (row == null) {
        throw const CorridaFailure(invalidBoardingReserveCodeMessage);
      }

      final active = Corrida.fromMap(Map<String, dynamic>.from(row));
      if (!reserveCodesMatch(code, active.reserveCode)) {
        throw const CorridaFailure(invalidBoardingReserveCodeMessage);
      }
      final updated = await _supabase
          .from('corridas')
          .update({
            'status_corrida': RideStatus.emAndamento.wire,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', active.id)
          .eq('status_corrida', RideStatus.aguardandoValidacaoEmbarque.wire)
          .eq('codigo_reserva', code)
          .eq('encerrada', false)
          .select()
          .maybeSingle();

      if (updated == null) {
        throw const CorridaFailure(invalidBoardingReserveCodeMessage);
      }
      return Corrida.fromMap(Map<String, dynamic>.from(updated));
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(code: error.code, message: error.message);
    } catch (_) {
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }

  @override
  Future<Corrida> advance(String id, RideStatus status) async {
    try {
      final updated = await _supabase
          .from('corridas')
          .update({
            'status_corrida': status.wire,
            'encerrada': status == RideStatus.concluida,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .select()
          .single();
      return Corrida.fromMap(updated);
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(code: error.code, message: error.message);
    } catch (_) {
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }

  @override
  Stream<Corrida> watch(String id) {
    final controller = StreamController<Corrida>();
    final channel = _supabase.channel('corrida:$id');
    Future<void> publishCurrent() async {
      try {
        final row = await _supabase
            .from('corridas')
            .select()
            .eq('id', id)
            .maybeSingle();
        if (row != null && !controller.isClosed) {
          controller.add(Corrida.fromMap(Map<String, dynamic>.from(row)));
        }
      } on PostgrestException catch (error) {
        if (!controller.isClosed) {
          controller.addError(
            CorridaFailure.fromRemote(code: error.code, message: error.message),
          );
        }
      } catch (_) {
        if (!controller.isClosed) {
          controller.addError(const CorridaFailure(CorridaFailure.syncMessage));
        }
      }
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'corridas',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: id,
          ),
          callback: (payload) {
            if (controller.isClosed) return;
            final record = payload.newRecord;
            if (record.isEmpty) return;
            try {
              controller.add(Corrida.fromMap(record));
            } on CorridaFailure catch (error) {
              if (!controller.isClosed) controller.addError(error);
            }
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(publishCurrent());
          } else if (status == RealtimeSubscribeStatus.channelError &&
              !controller.isClosed) {
            controller.addError(
              error is PostgrestException
                  ? CorridaFailure.fromRemote(
                      code: error.code,
                      message: error.message,
                    )
                  : const CorridaFailure(CorridaFailure.syncMessage),
            );
          }
        });
    controller.onCancel = () {
      _supabase.removeChannel(channel);
    };
    return controller.stream;
  }

  @override
  Stream<List<RescueOffer>> offers({required PartnerRole role}) {
    final controller = StreamController<List<RescueOffer>>();
    final channel = _supabase.channel('corridas-offers');
    Future<void> publish() async {
      try {
        final list = await _loadOffers(role);
        if (!controller.isClosed) controller.add(list);
      } catch (error) {
        if (!controller.isClosed) controller.addError(error);
      }
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'corridas',
          callback: (_) => publish(),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.channelError &&
              !controller.isClosed) {
            controller.addError(
              error is PostgrestException
                  ? CorridaFailure.fromRemote(
                      code: error.code,
                      message: error.message,
                    )
                  : const CorridaFailure(CorridaFailure.syncMessage),
            );
          }
        });
    controller.onListen = publish;
    controller.onCancel = () {
      _supabase.removeChannel(channel);
    };
    return controller.stream;
  }

  Future<List<RescueOffer>> _loadOffers(PartnerRole role) async {
    try {
      var query = _supabase
          .from('corridas')
          .select()
          .eq('encerrada', false)
          .isFilter('motoboy_id', null);
      if (role == PartnerRole.courier) {
        query = query
            .eq('status_corrida', RideStatus.procurandoMotoboy.wire)
            .not('accepted_by', 'is', null);
      } else {
        query = query
            .eq('status_corrida', RideStatus.buscandoPrestadores.wire)
            .isFilter('accepted_by', null);
      }
      final rows = await query;
      return [
        for (final row in rows)
          if (!_closedRow(Map<String, dynamic>.from(row)) &&
              _hasOfferCoordinates(Map<String, dynamic>.from(row), role))
            _offerFromRow(Map<String, dynamic>.from(row), role),
      ];
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(code: error.code, message: error.message);
    }
  }

  bool _hasOfferCoordinates(Map<String, dynamic> data, PartnerRole role) {
    final latitude = _double(
      role == PartnerRole.courier ? data['partner_lat'] : data['origin_lat'],
    );
    final longitude = _double(
      role == PartnerRole.courier ? data['partner_lng'] : data['origin_lng'],
    );
    return latitude != null && longitude != null;
  }

  RescueOffer _offerFromRow(Map<String, dynamic> data, PartnerRole role) {
    final corrida = Corrida.fromMap(data);
    final driverLatitude =
        _double(
          role == PartnerRole.courier
              ? data['partner_lat']
              : data['origin_lat'],
        ) ??
        0;
    final driverLongitude =
        _double(
          role == PartnerRole.courier
              ? data['partner_lng']
              : data['origin_lng'],
        ) ??
        0;
    final driver = LatLng(driverLatitude, driverLongitude);
    final call = NearbyCall(
      id: corrida.callId,
      origin: corrida.origin,
      destination: corrida.destination,
      client: LatLng(
        _double(data['origin_lat']) ?? driver.latitude,
        _double(data['origin_lng']) ?? driver.longitude,
      ),
      dropoff: LatLng(
        _double(data['dest_lat']) ?? driver.latitude,
        _double(data['dest_lng']) ?? driver.longitude,
      ),
      distanceKm: 0,
      driverFare: _double(data['driver_fare']) ?? 0,
    );
    return offerFromCorrida(corrida, call, driver);
  }

  Future<Corrida?> _findOpen(String callId) async {
    try {
      final rows = await _supabase
          .from('corridas')
          .select()
          .eq('call_id', callId);
      Corrida? chosen;
      for (final row in rows) {
        final data = Map<String, dynamic>.from(row);
        if (_closedRow(data)) continue;
        chosen = Corrida.fromMap(data);
      }
      return chosen;
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(code: error.code, message: error.message);
    }
  }

  bool _closedRow(Map<String, dynamic> data) {
    if (data['encerrada'] == true) return true;
    return RideStatus.tryParse('${data['status_corrida']}') ==
        RideStatus.concluida;
  }

  Future<Map<String, dynamic>> _insertRow(Map<String, dynamic> payload) async {
    try {
      final inserted = await _supabase
          .from('corridas')
          .insert(payload)
          .select()
          .single();
      return Map<String, dynamic>.from(inserted);
    } on PostgrestException catch (error) {
      debugPrint('SupabaseCorridaRepository._insertRow failed: $error');
      final failure = CorridaFailure('${error.code ?? ''} ${error.message}');
      final column = failure.missingColumn;
      if (column != null &&
          _optionalColumns.contains(column) &&
          payload.containsKey(column)) {
        return _insertRow(Map<String, dynamic>.from(payload)..remove(column));
      }
      throw CorridaFailure.fromRemote(
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      );
    }
  }

  Future<Map<String, dynamic>> _updateRow(
    String id,
    Map<String, dynamic> payload, {
    bool onlyAwaitingMotoboy = false,
  }) async {
    try {
      var query = _supabase.from('corridas').update(payload).eq('id', id);
      if (onlyAwaitingMotoboy && payload.containsKey('motoboy_id')) {
        query = query
            .eq('status_corrida', RideStatus.procurandoMotoboy.wire)
            .not('accepted_by', 'is', null)
            .isFilter('motoboy_id', null);
      }
      final updated = await query.select().maybeSingle();
      if (updated == null) {
        throw const CorridaFailure('Outro motoboy já aceitou este resgate.');
      }
      return Map<String, dynamic>.from(updated);
    } on PostgrestException catch (error) {
      final failure = CorridaFailure('${error.code ?? ''} ${error.message}');
      final column = failure.missingColumn;
      if (column != null &&
          _optionalColumns.contains(column) &&
          payload.containsKey(column)) {
        return _updateRow(
          id,
          Map<String, dynamic>.from(payload)..remove(column),
          onlyAwaitingMotoboy: onlyAwaitingMotoboy,
        );
      }
      throw CorridaFailure.fromRemote(code: error.code, message: error.message);
    }
  }
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  if (value == null) return null;
  return double.tryParse(value.toString());
}

const _optionalColumns = {
  'driver_label',
  'ganho_resgate',
  'distancia_resgate_km',
  'encerrada',
  'driver_fare',
  'accepted_role',
  'updated_at',
  'aceite_em',
  'motoboy_nome',
  'eta_minutos',
  'motoboy_lat',
  'motoboy_lng',
  'origin_lat',
  'origin_lng',
  'dest_lat',
  'dest_lng',
  'partner_lat',
  'partner_lng',
};
