import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/ride_status.dart';

void main() {
  test('o motoboy só avança até entregar o motorista', () {
    expect(
      RescuePhaseMachine.next(RideStatus.motoboyACaminho, PartnerRole.courier),
      RideStatus.aCaminhoDoCliente,
    );
    expect(
      RescuePhaseMachine.actionLabel(
        RideStatus.motoboyACaminho,
        PartnerRole.courier,
      ),
      'Cheguei ao Motorista',
    );
    expect(
      RescuePhaseMachine.next(
        RideStatus.aCaminhoDoCliente,
        PartnerRole.courier,
      ),
      RideStatus.conduzindoDestino,
    );
    expect(
      RescuePhaseMachine.actionLabel(
        RideStatus.aCaminhoDoCliente,
        PartnerRole.courier,
      ),
      'Motorista Entregue no Cliente',
    );
    expect(
      RescuePhaseMachine.next(
        RideStatus.conduzindoDestino,
        PartnerRole.courier,
      ),
      isNull,
    );
  });

  test('o motorista só finaliza a navegação até o destino', () {
    expect(
      RescuePhaseMachine.next(RideStatus.motoboyACaminho, PartnerRole.driver),
      isNull,
    );
    expect(
      RescuePhaseMachine.next(RideStatus.aCaminhoDoCliente, PartnerRole.driver),
      isNull,
    );
    expect(
      RescuePhaseMachine.next(RideStatus.conduzindoDestino, PartnerRole.driver),
      RideStatus.concluida,
    );
    expect(
      RescuePhaseMachine.actionLabel(
        RideStatus.conduzindoDestino,
        PartnerRole.driver,
      ),
      'Finalizar Corrida',
    );
  });

  test('erro de tabela ausente não repete o json do supabase', () {
    final failure = CorridaFailure.fromRemote(
      code: 'PGRST205',
      message: 'Could not find the table public.corridas in the schema cache',
    );

    expect(failure.message, CorridaFailure.missingTableMessage);
    expect(failure.message.contains('PGRST205'), isFalse);
    expect(
      RideStatus.tryParse('motoboy_a_caminho'),
      RideStatus.motoboyACaminho,
    );

    final column = CorridaFailure.fromRemote(
      code: 'PGRST204',
      message: "Could not find the 'driver_label' column of 'corridas' in the schema cache",
    );
    expect(column.message.contains('driver_label'), isTrue);
    expect(column.message.contains('PGRST204'), isFalse);

    final status = CorridaFailure.fromRemote(
      message: 'invalid input value for enum status_corrida_enum: "procurando_motoboy"',
    );
    expect(status.message.contains('procurando_motoboy'), isTrue);

    final unknown = CorridaFailure.fromRemote(
      code: 'PGRST999',
      message: 'The server rejected requested_by',
      details: 'column does not exist',
      hint: 'Apply the latest corrida migration',
    );
    expect(unknown.message, contains('PGRST999'));
    expect(unknown.message, contains('column does not exist'));
    expect(unknown.message, contains('Apply the latest corrida migration'));
  });
}
