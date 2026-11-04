import 'package:latlong2/latlong.dart';
import 'package:xofer/prof/domain/dispatch_attempt.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/partner_role.dart';

class MissionResponse {
  const MissionResponse({required this.status, this.rideId});

  final String status;
  final String? rideId;
}

abstract interface class DispatchRepository {
  Stream<DispatchAttempt> watchAttempts({
    required String providerId,
    required PartnerRole role,
  });

  Future<MissionResponse> respondToMission({
    required String attemptId,
    required String providerId,
    required String response,
  });

  Future<NearbyCall> loadAcceptedRide(
    String rideId, {
    required PartnerRole role,
  });

  Future<void> updatePresence({
    required PartnerRole role,
    required LatLng? location,
    required bool isAvailable,
  });
}
