import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/rescue_simulation.dart';

void main() {
  const partner = LatLng(-23.55, -46.63);
  const client = LatLng(-23.54, -46.62);
  const dropoff = LatLng(-23.53, -46.61);

  test('o motoboy encontra o motorista e para no carro do cliente', () {
    final simulation = RescueSimulation.forRole(
      role: PartnerRole.courier,
      partner: partner,
      client: client,
      dropoff: dropoff,
      approachSteps: 2,
      clientSteps: 2,
    );

    expect(simulation.stageAt(0), RescueStage.motoboyToDriver);
    expect(simulation.stageAt(2), RescueStage.toClientCar);
    expect(simulation.stageAt(4), RescueStage.finished);
    expect(simulation.pointAt(0).latitude, closeTo(partner.latitude, 0.000001));
    expect(
      simulation.pointAt(2).latitude,
      closeTo(simulation.partner.latitude, 0.000001),
    );
    expect(simulation.pointAt(4).latitude, closeTo(client.latitude, 0.000001));
    expect(simulation.routePoints, isNot(contains(dropoff)));
  });

  test('a rota inicial do resgate termina na posição real do motorista', () {
    const driver = LatLng(-23.56, -46.64);
    final simulation = RescueSimulation.forRole(
      role: PartnerRole.courier,
      partner: partner,
      client: client,
      dropoff: dropoff,
      approachSteps: 2,
      motoboyTarget: driver,
    );

    expect(simulation.pointAt(2), driver);
    expect(simulation.legs.first.to, driver);
  });

  test('o motorista vê o motoboy e depois conduz até o destino', () {
    final simulation = RescueSimulation.forRole(
      role: PartnerRole.driver,
      partner: partner,
      client: client,
      dropoff: dropoff,
      approachSteps: 2,
      clientSteps: 2,
      destinationSteps: 2,
    );

    expect(simulation.stageAt(0), RescueStage.motoboyToDriver);
    expect(simulation.pointAt(0), simulation.motoboyStart);
    expect(simulation.stageAt(2), RescueStage.toClientCar);
    expect(simulation.pointAt(2).latitude, closeTo(partner.latitude, 0.000001));
    expect(simulation.stageAt(4), RescueStage.toDestination);
    expect(simulation.pointAt(4).latitude, closeTo(client.latitude, 0.000001));
    expect(simulation.stageAt(6), RescueStage.finished);
    expect(simulation.pointAt(6).latitude, closeTo(dropoff.latitude, 0.000001));
  });
}
