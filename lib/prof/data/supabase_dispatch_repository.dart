import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/dispatch_attempt.dart';
import 'package:xofer/prof/domain/dispatch_repository.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/partner_role.dart';

class SupabaseDispatchRepository implements DispatchRepository {
  SupabaseDispatchRepository({this.client});

  final SupabaseClient? client;

  SupabaseClient get _supabase => client ?? Supabase.instance.client;

  @override
  Stream<DispatchAttempt> watchAttempts({
    required String providerId,
    required PartnerRole role,
  }) {
    final controller = StreamController<DispatchAttempt>();
    final channel = _supabase.channel('dispatch-attempts:$providerId');

    void publish(Map<String, dynamic> row) {
      if (row['provider_id'] != providerId ||
          row['provider_role'] != role.wire) {
        return;
      }
      try {
        controller.add(DispatchAttempt.fromMap(row));
      } on FormatException catch (error, stackTrace) {
        debugPrint('Invalid dispatch attempt payload: $error');
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    Future<void> publishOpenAttempts() async {
      try {
        final rows = await _supabase
            .from('dispatch_attempts')
            .select('id, provider_id, provider_role, status, expires_at')
            .eq('provider_id', providerId)
            .eq('provider_role', role.wire)
            .eq('status', 'offered')
            .order('offered_at');
        if (controller.isClosed) return;
        for (final row in rows) {
          publish(Map<String, dynamic>.from(row));
        }
      } on PostgrestException catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(
            CorridaFailure.fromRemote(
              code: error.code,
              message: error.message,
              details: error.details,
              hint: error.hint,
            ),
            stackTrace,
          );
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dispatch_attempts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'provider_id',
            value: providerId,
          ),
          callback: (payload) {
            final row = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            if (row.isNotEmpty && !controller.isClosed) publish(row);
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(publishOpenAttempts());
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            if (!controller.isClosed) {
              controller.addError(
                error ?? StateError('Não foi possível conectar ao despacho.'),
              );
            }
          }
        });

    controller.onCancel = () {
      unawaited(_supabase.removeChannel(channel));
    };
    return controller.stream;
  }

  @override
  Future<MissionResponse> respondToMission({
    required String attemptId,
    required String providerId,
    required String response,
  }) async {
    try {
      final result = await _supabase.rpc(
        'rpc_respond_to_mission',
        params: {
          'p_attempt_id': attemptId,
          'p_provider_id': providerId,
          'p_response': response,
        },
      );
      if (result is! Map) {
        throw const CorridaFailure(
          'O servidor retornou uma resposta inválida para a missão.',
        );
      }
      final rideId = result['ride_id'];
      return MissionResponse(
        status: '${result['status'] ?? ''}',
        rideId: rideId is String ? rideId : null,
      );
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      );
    } catch (error, stackTrace) {
      debugPrint('SupabaseDispatchRepository.respondToMission failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }

  @override
  Future<NearbyCall> loadAcceptedRide(
    String rideId, {
    required PartnerRole role,
  }) async {
    try {
      final columns = role == PartnerRole.courier
          ? 'call_id, origin, destination, origin_lat, origin_lng, '
                'dest_lat, dest_lng, partner_lat, partner_lng, '
                'requester_type, service_type'
          : 'call_id, origin, destination, origin_lat, origin_lng, '
                'dest_lat, dest_lng, driver_fare, valor_total, '
                'requester_type, service_type';
      final row = await _supabase
          .from('corridas')
          .select(columns)
          .eq('id', rideId)
          .single();
      final originLat = _number(row['origin_lat']);
      final originLng = _number(row['origin_lng']);
      final meetingLat = _number(row['partner_lat']);
      final meetingLng = _number(row['partner_lng']);
      final merchantDelivery =
          row['requester_type'] == 'merchant' &&
          row['service_type'] == 'delivery';
      final destinationLat = role == PartnerRole.driver || merchantDelivery
          ? _number(row['dest_lat'])
          : originLat;
      final destinationLng = role == PartnerRole.driver || merchantDelivery
          ? _number(row['dest_lng'])
          : originLng;
      if (originLat == null ||
          originLng == null ||
          destinationLat == null ||
          destinationLng == null ||
          (role == PartnerRole.courier &&
              (meetingLat == null || meetingLng == null))) {
        throw const CorridaFailure(
          'A corrida aceita não contém uma localização válida para a missão.',
        );
      }
      return NearbyCall(
        id: '${row['call_id'] ?? rideId}',
        origin: '${row['origin'] ?? ''}',
        destination: role == PartnerRole.courier && !merchantDelivery
            ? '${row['origin'] ?? ''}'
            : '${row['destination'] ?? ''}',
        client: role == PartnerRole.courier && merchantDelivery
            ? LatLng(destinationLat, destinationLng)
            : LatLng(originLat, originLng),
        dropoff: LatLng(destinationLat, destinationLng),
        distanceKm: 0,
        driverFare: role == PartnerRole.driver
            ? _number(row['driver_fare'] ?? row['valor_total']) ?? 0
            : 0,
        meetingPoint: role == PartnerRole.courier
            ? LatLng(meetingLat!, meetingLng!)
            : null,
        requesterType: '${row['requester_type'] ?? 'customer'}',
        serviceType: '${row['service_type'] ?? 'rescue'}',
      );
    } on CorridaFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      );
    } catch (error, stackTrace) {
      debugPrint('SupabaseDispatchRepository.loadAcceptedRide failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }

  @override
  Future<void> updatePresence({
    required PartnerRole role,
    required LatLng? location,
    required bool isAvailable,
  }) async {
    try {
      await _supabase.rpc(
        'rpc_update_provider_presence',
        params: {
          'p_provider_role': role.wire,
          'p_lat': location?.latitude,
          'p_lng': location?.longitude,
          'p_is_available': isAvailable,
        },
      );
    } on PostgrestException catch (error) {
      throw CorridaFailure.fromRemote(
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      );
    } catch (error, stackTrace) {
      debugPrint('SupabaseDispatchRepository.updatePresence failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw const CorridaFailure(CorridaFailure.syncMessage);
    }
  }
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value == null) return null;
  return double.tryParse(value.toString());
}
