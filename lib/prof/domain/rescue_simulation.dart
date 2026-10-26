import 'package:latlong2/latlong.dart';
import 'package:xofer/prof/domain/partner_role.dart';

enum RescueStage { motoboyToDriver, toClientCar, toDestination, finished }

class RescueSpan {
  const RescueSpan({required this.start, required this.end});

  final int start;
  final int end;
}

class RescueLeg {
  const RescueLeg({
    required this.from,
    required this.to,
    required this.steps,
    required this.stage,
  });

  final LatLng from;
  final LatLng to;
  final int steps;
  final RescueStage stage;
}

class RescueSimulation {
  const RescueSimulation({
    required this.role,
    required this.legs,
    required this.partner,
    required this.client,
    required this.dropoff,
    required this.motoboyStart,
  });

  final PartnerRole role;
  final List<RescueLeg> legs;
  final LatLng partner;
  final LatLng client;
  final LatLng dropoff;
  final LatLng motoboyStart;

  int get lastStep => legs.fold(0, (sum, leg) => sum + leg.steps);

  factory RescueSimulation.forRole({
    required PartnerRole role,
    required LatLng partner,
    required LatLng client,
    required LatLng dropoff,
    int approachSteps = 4,
    int clientSteps = 4,
    int destinationSteps = 6,
    LatLng? motoboyOrigin,
    LatLng? motoboyTarget,
  }) {
    if (role == PartnerRole.courier) {
      final driver = motoboyTarget ?? rescueLerp(partner, client, 0.35);
      return RescueSimulation(
        role: role,
        partner: driver,
        client: client,
        dropoff: dropoff,
        motoboyStart: partner,
        legs: [
          RescueLeg(
            from: partner,
            to: driver,
            steps: approachSteps,
            stage: RescueStage.motoboyToDriver,
          ),
          RescueLeg(
            from: driver,
            to: client,
            steps: clientSteps,
            stage: RescueStage.toClientCar,
          ),
        ],
      );
    }

    final motoboyStart =
        motoboyOrigin ??
        LatLng(partner.latitude - 0.012, partner.longitude + 0.008);
    return RescueSimulation(
      role: role,
      partner: partner,
      client: client,
      dropoff: dropoff,
      motoboyStart: motoboyStart,
      legs: [
        RescueLeg(
          from: motoboyStart,
          to: partner,
          steps: approachSteps,
          stage: RescueStage.motoboyToDriver,
        ),
        RescueLeg(
          from: partner,
          to: client,
          steps: clientSteps,
          stage: RescueStage.toClientCar,
        ),
        RescueLeg(
          from: client,
          to: dropoff,
          steps: destinationSteps,
          stage: RescueStage.toDestination,
        ),
      ],
    );
  }

  RescueSpan? spanFor(RescueStage stage) {
    var cursor = 0;
    for (final leg in legs) {
      final end = cursor + leg.steps;
      if (leg.stage == stage) return RescueSpan(start: cursor, end: end);
      cursor = end;
    }
    return null;
  }

  List<LatLng> pointsFor(RescueStage stage) {
    for (final leg in legs) {
      if (leg.stage == stage) return [leg.from, leg.to];
    }
    return routePoints;
  }

  RescueStage stageAt(int step) {
    if (step >= lastStep) return RescueStage.finished;
    var cursor = 0;
    for (final leg in legs) {
      if (step < cursor + leg.steps) return leg.stage;
      cursor += leg.steps;
    }
    return RescueStage.finished;
  }

  LatLng pointAt(int step) {
    if (legs.isEmpty) return partner;
    var cursor = 0;
    for (final leg in legs) {
      final end = cursor + leg.steps;
      if (step <= end) {
        final local = (step - cursor).clamp(0, leg.steps);
        final t = leg.steps == 0 ? 1.0 : local / leg.steps;
        return rescueLerp(leg.from, leg.to, t);
      }
      cursor = end;
    }
    return legs.last.to;
  }

  LatLng glide(int step, double t) {
    return rescueLerp(pointAt(step), pointAt(step + 1), t.clamp(0, 1));
  }

  List<LatLng> get routePoints {
    if (legs.isEmpty) return const [];
    return [legs.first.from, for (final leg in legs) leg.to];
  }
}

LatLng rescueLerp(LatLng from, LatLng to, double t) {
  return LatLng(
    from.latitude + (to.latitude - from.latitude) * t,
    from.longitude + (to.longitude - from.longitude) * t,
  );
}
